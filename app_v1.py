"""
대학교 주차장 관리 시스템 - 백엔드 (영상 표시 기능 추가)
YOLOv8를 활용한 차량 인식 및 관리 시스템 (개선된 버전)

날짜: 2025-05-10
"""

import os
import sys
import json
import hmac
import secrets
import time
import cv2
import numpy as np
import sqlite3
from datetime import datetime, timedelta
from functools import wraps
import threading
import argparse
import traceback
import logging
from flask import Flask, request, jsonify, g, Response
from flask_cors import CORS
from PIL import Image, ImageDraw, ImageFont

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler("parking_system.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger("ParkingSystem")

# 기본 디렉터리 설정
BASE_DIR = os.path.dirname(os.path.abspath(__file__))


# 유틸리티 함수: 여러 경로에서 파일 찾기
def find_file_in_paths(file_name, possible_paths):
    """여러 가능한 경로에서 파일 찾기"""
    for path in possible_paths:
        if path and os.path.exists(path):
            logger.info(f"파일을 찾았습니다: {path}")
            return path
    return None


def get_font_path():
    """시스템에 설치된 폰트 중 한글 지원 폰트 찾기 (Windows / macOS / Linux)"""
    font_paths = [os.getenv('FONT_PATH')]

    windir = os.environ.get('WINDIR')
    if windir:
        font_paths += [
            os.path.join(windir, 'Fonts', 'malgun.ttf'),  # 맑은 고딕
            os.path.join(windir, 'Fonts', 'gulim.ttc'),  # 굴림
            os.path.join(windir, 'Fonts', 'batang.ttc'),  # 바탕
        ]

    font_paths += [
        '/System/Library/Fonts/AppleSDGothicNeo.ttc',  # macOS
        '/System/Library/Fonts/Supplemental/AppleGothic.ttf',  # macOS
        '/usr/share/fonts/truetype/nanum/NanumGothic.ttf',  # Linux (fonts-nanum)
        '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',  # Linux (fonts-noto-cjk)
    ]

    for path in font_paths:
        if path and os.path.exists(path):
            return path

    # 폰트를 찾지 못했을 경우
    return None


# 폰트 로드는 비용이 크므로 크기별로 캐시
_FONT_PATH = get_font_path()
_FONT_CACHE = {}


def _get_font(font_size):
    if font_size not in _FONT_CACHE:
        font = None
        if _FONT_PATH:
            try:
                font = ImageFont.truetype(_FONT_PATH, font_size)
            except Exception:
                font = None
        _FONT_CACHE[font_size] = font or ImageFont.load_default()
    return _FONT_CACHE[font_size]


# 3. 한글 텍스트를 이미지에 표시하는 함수
def put_text_pil(img, text, position, font_size=16, color=(255, 255, 255), background=None):
    """PIL을 사용하여 한글 텍스트 표시"""
    # OpenCV 이미지를 PIL 이미지로 변환
    img_pil = Image.fromarray(cv2.cvtColor(img, cv2.COLOR_BGR2RGB))
    draw = ImageDraw.Draw(img_pil)

    # 폰트 설정
    font = _get_font(font_size)

    # 배경이 설정된 경우
    if background:
        # 텍스트 크기 계산
        text_size = draw.textbbox((0, 0), text, font=font)
        text_width = text_size[2] - text_size[0]
        text_height = text_size[3] - text_size[1]

        # 배경 사각형 그리기
        rect_position = (
            position[0],
            position[1],
            position[0] + text_width,
            position[1] + text_height
        )
        draw.rectangle(rect_position, fill=background)

    # 텍스트 그리기
    draw.text(position, text, font=font, fill=color)

    # PIL 이미지를 OpenCV 이미지로 다시 변환
    result = cv2.cvtColor(np.array(img_pil), cv2.COLOR_RGB2BGR)
    return result


# 모델 경로 설정 (MODEL_PATH 환경 변수가 최우선)
MODEL_PATHS = [
    os.getenv('MODEL_PATH'),
    os.path.join(BASE_DIR, 'models', 'best.pt'),
    os.path.join(BASE_DIR, 'models', 'best_seo.pt'),
    os.path.join(os.getcwd(), 'best(v8).pt'),
    os.path.join(os.getcwd(), 'models', 'best(v8).pt'),
    os.path.join(BASE_DIR, 'best(v8).pt'),
    os.path.join(BASE_DIR, '..', 'best(v8).pt'),
    os.path.join(BASE_DIR, '..', 'models', 'best(v8).pt')
]
MODEL_PATH = find_file_in_paths("best model", MODEL_PATHS) or os.path.join(BASE_DIR, 'models', 'best.pt')

# 비디오 파일 디렉터리 (동적 주차장 추가 시 이 디렉터리 안의 파일만 허용)
VIDEOS_DIR = os.getenv('VIDEOS_DIR', os.path.join(BASE_DIR, 'videos'))

# 비디오 소스 경로 설정
VIDEO_SOURCES = {}


def _generate_test_video(output_path, duration=10, fps=30):
    """테스트 컬러 비디오 생성 (실제 파일을 찾지 못한 경우 대체용)"""
    try:
        width, height = 640, 480
        fourcc = cv2.VideoWriter_fourcc(*'XVID')
        out = cv2.VideoWriter(output_path, fourcc, fps, (width, height))

        # 다양한 색상 패턴으로 테스트 프레임 생성
        frames = fps * duration
        for i in range(frames):
            # 배경 색상 설정 (시간에 따라 색조가 변함)
            hue = int((i / frames) * 180)  # 0-180 범위의 색조
            color_bg = np.zeros((height, width, 3), dtype=np.uint8)
            color_bg[:, :, 0] = hue  # 색조 설정
            color_bg[:, :, 1] = 200  # 채도 설정
            color_bg[:, :, 2] = 200  # 명도 설정
            frame = cv2.cvtColor(color_bg, cv2.COLOR_HSV2BGR)

            # 안내 텍스트 표시 (cv2.putText는 한글을 지원하지 않으므로 영문 사용)
            cv2.putText(frame, "TEST VIDEO - video file not found", (50, 50),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)
            cv2.putText(frame, "Check VIDEO_PATH_* settings", (50, 100),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)

            # 타임스탬프 표시
            cv2.putText(frame, f"frame: {i}/{frames}", (width - 200, height - 20),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2)

            out.write(frame)

        out.release()
        logger.info(f"테스트 비디오 생성 완료: {output_path}")
        return True
    except Exception as e:
        logger.error(f"테스트 비디오 생성 중 오류: {e}")
        return False


def setup_video_sources():
    """비디오 소스 경로 설정 및 유효성 검증"""
    # 주차장별 비디오 경로 후보 (우선순위 순서대로)
    video_paths = {
        'parking_lot_A': [  # 55호관 주차장
            os.getenv('VIDEO_PATH_A'),
            os.getenv('VIDEO_PATH'),  # 이전 버전 호환
            os.path.join(VIDEOS_DIR, 'parking_best.mp4'),
            os.path.join(VIDEOS_DIR, 'parking_lot_A.mp4'),
            os.path.join(os.getcwd(), 'parking_best.mp4'),
        ],
        'parking_lot_B': [  # 도서관 주차장
            os.getenv('VIDEO_PATH_B'),
            os.path.join(VIDEOS_DIR, 'library2.mp4'),
            os.path.join(VIDEOS_DIR, 'library.mp4'),
            os.path.join(VIDEOS_DIR, 'parking_lot_B.mp4'),
            os.path.join(os.getcwd(), 'library.mp4'),
        ]
    }

    # 비디오 파일 확장명 후보들
    video_extensions = ['.mp4', '.avi', '.mov', '.mkv']

    # 각 주차장별 유효한 첫 번째 경로 사용
    for parking_lot, paths in video_paths.items():
        found_path = find_file_in_paths(f"{parking_lot} video", paths)

        # 직접 경로에서 찾지 못한 경우, 다양한 확장자로 검색 시도
        if not found_path:
            for path in paths:
                if path:
                    base_path = os.path.splitext(path)[0]
                    for ext in video_extensions:
                        ext_path = base_path + ext
                        if os.path.exists(ext_path):
                            found_path = ext_path
                            logger.info(f"다른 확장자로 비디오 파일 발견: {ext_path}")
                            break
                if found_path:
                    break

        if found_path:
            VIDEO_SOURCES[parking_lot] = found_path
            logger.info(f"비디오 소스 '{parking_lot}'에 경로를 설정했습니다: {found_path}")
        else:
            logger.warning(f"경고: 비디오 소스 '{parking_lot}'의 모든 경로를 찾을 수 없습니다.")
            logger.info("테스트 컬러 영상을 생성합니다.")
            test_path = os.path.join(BASE_DIR, f'test_video_{parking_lot}.avi')
            _generate_test_video(test_path)
            VIDEO_SOURCES[parking_lot] = test_path


# 데이터베이스 경로
DB_PATH = os.getenv('DB_PATH', os.path.join(BASE_DIR, 'parking_system.db'))

# 점유율 기록 간격 (시간대별 통계는 이 샘플들의 평균)
OCCUPANCY_RECORD_INTERVAL = timedelta(minutes=5)

# B1 보정 규칙을 적용할 주차장 (55호관)
B1_CORRECTION_LOT = 'parking_lot_A'

# 주차 공간 좌표 (주차장 별 주차 공간 좌표 정의)
PARKING_SPACES = {
    'parking_lot_A': [  # 기존 55호관 주차장
        {"id": "A1", "coords": [(74, 104), (40, 200), (2, 204), (3, 105)]},
        {"id": "A2", "coords": [(75, 104), (153, 101), (124, 197), (43, 200)]},
        {"id": "A3", "coords": [(154, 101), (231, 97), (209, 195), (126, 198)]},
        {"id": "A4", "coords": [(231, 96), (312, 90), (299, 189), (210, 194)]},
        {"id": "A5", "coords": [(296, 188), (382, 190), (382, 91), (302, 91)]},
        {"id": "A6", "coords": [(380, 90), (458, 85), (470, 180), (381, 190)]},
        {"id": "A7", "coords": [(460, 86), (539, 81), (560, 183), (470, 186)]},
        {"id": "A8", "coords": [(539, 82), (620, 76), (652, 173), (560, 180)]},
        {"id": "A9", "coords": [(618, 75), (699, 72), (746, 169), (653, 177)]},
        {"id": "A10", "coords": [(700, 71), (782, 67), (843, 168), (747, 173)]},
        {"id": "A11", "coords": [(784, 68), (842, 166), (939, 166), (879, 64)]},
        {"id": "A12", "coords": [(882, 63), (938, 166), (966, 165), (966, 59)]},
        {"id": "B1", "coords": [(172, 379), (130, 585), (10, 585), (74, 381)]},
        {"id": "B2disabled", "coords": [(172, 380), (266, 376), (239, 581), (129, 585)]},
        {"id": "B3", "coords": [(303, 375), (412, 372), (417, 581), (289, 583)]},
        {"id": "B4", "coords": [(411, 371), (418, 576), (552, 580), (520, 370)]},
        {"id": "B5", "coords": [(519, 369), (551, 577), (686, 579), (631, 367)]},
        {"id": "B6", "coords": [(631, 367), (688, 579), (826, 574), (748, 363)]},
        {"id": "B7", "coords": [(747, 363), (824, 571), (966, 573), (867, 359)]},
        {"id": "B8", "coords": [(867, 358), (968, 572), (968, 355)]},  # 화면 가장자리에 걸친 칸이라 삼각형
    ],
    'parking_lot_B': [  # 새로 추가된 도서관 주차장
        {"id": "A1", "coords": [(95, 144), (46, 193), (0, 189), (1, 135)]},
        {"id": "A2", "coords": [(95, 144), (46, 193), (99, 197), (143, 147)]},
        {"id": "A3", "coords": [(145, 147), (99, 196), (153, 198), (191, 151)]},
        {"id": "A4", "coords": [(191, 149), (154, 198), (206, 200), (236, 152)]},
        {"id": "A5", "coords": [(289, 155), (259, 202), (206, 200), (237, 151)]},
        {"id": "A6", "coords": [(287, 154), (335, 156), (315, 207), (259, 203)]},
        {"id": "A7", "coords": [(333, 155), (385, 157), (366, 208), (314, 204)]},
        {"id": "A8", "coords": [(385, 157), (366, 209), (421, 212), (435, 160)]},
        {"id": "A9", "coords": [(473, 215), (482, 162), (433, 159), (419, 213)]},
        {"id": "A10", "coords": [(480, 160), (471, 215), (527, 217), (531, 163)]},
        {"id": "A11", "coords": [(530, 164), (525, 217), (578, 219), (578, 166)]},
        {"id": "A12", "coords": [(578, 165), (578, 219), (630, 221), (626, 167)]},
        {"id": "B1", "coords": [(1, 279), (64, 280), (10, 365), (-1, 365)]},
        {"id": "B2", "coords": [(142, 281), (64, 279), (9, 365), (83, 368)]},
        {"id": "B3", "coords": [(140, 281), (83, 367), (155, 370), (207, 284)]},
        {"id": "B4", "coords": [(206, 284), (154, 371), (224, 373), (263, 286)]},
        {"id": "B5", "coords": [(262, 285), (329, 288), (295, 376), (225, 373)]},
        {"id": "B6", "coords": [(329, 289), (394, 292), (369, 378), (295, 377)]},
        {"id": "B7", "coords": [(394, 291), (456, 295), (438, 380), (368, 376)]},
        {"id": "B8", "coords": [(456, 295), (518, 299), (509, 383), (440, 380)]},
        {"id": "B9", "coords": [(518, 299), (509, 383), (579, 385), (581, 302)]},
        {"id": "B10", "coords": [(581, 302), (579, 382), (649, 387), (640, 304)]},
        {"id": "C1", "coords": [(1, 409), (114, 411), (47, 542), (0, 541)]},
        {"id": "C2", "coords": [(114, 411), (46, 542), (135, 546), (193, 415)]},
        {"id": "C3", "coords": [(192, 415), (134, 545), (224, 551), (273, 417)]},
        {"id": "C4", "coords": [(272, 417), (224, 549), (315, 553), (351, 418)]},
        {"id": "C5", "coords": [(348, 419), (312, 555), (401, 557), (428, 423)]},
        {"id": "C6", "coords": [(427, 423), (399, 558), (492, 561), (503, 427)]},
        {"id": "C7", "coords": [(502, 426), (490, 560), (577, 562), (577, 430)]},
        {"id": "C8", "coords": [(576, 429), (576, 562), (661, 565), (652, 431)]},
        {"id": "D1", "coords": [(799, 233), (811, 261), (924, 260), (910, 232)]},
        {"id": "D2", "coords": [(826, 297), (845, 342), (973, 343), (947, 300)]},
        {"id": "D3", "coords": [(845, 341), (864, 391), (1004, 393), (971, 342)]},
        {"id": "D4electric", "coords": [(864, 391), (887, 449), (1030, 454), (1003, 393)]},
        {"id": "D5electric", "coords": [(886, 450), (930, 550), (1078, 555), (1028, 453)]},
        {"id": "D6disabled", "coords": [(930, 549), (981, 680), (1154, 684), (1078, 554)]},
    ]
}

# Flask 앱 설정
app = Flask(__name__)
CORS(app)  # 크로스 오리진 요청 허용


# 데이터베이스 유틸리티 함수
def get_db():
    """현재 요청에 대한 데이터베이스 연결 가져오기"""
    if 'db' not in g:
        g.db = sqlite3.connect(DB_PATH)
    return g.db


@app.teardown_appcontext
def close_db(e=None):
    """요청 종료 시 데이터베이스 연결 닫기"""
    db = g.pop('db', None)
    if db is not None:
        db.close()
        logger.debug("요청 컨텍스트에서 DB 연결 종료")


def init_db():
    """데이터베이스 스키마 초기화 (이전 버전 스키마 자동 마이그레이션 포함)"""
    with app.app_context():
        db = get_db()
        cursor = db.cursor()

        # 이전 버전은 parking_spaces의 기본 키가 주차면 ID뿐이라 주차장 간 ID(A1 등)가 충돌했음.
        # 현재 상태 캐시 테이블이므로 구 스키마면 삭제 후 재생성
        cursor.execute("PRAGMA table_info(parking_spaces)")
        columns = [row[1] for row in cursor.fetchall()]
        if columns and 'parking_lot' not in columns:
            logger.info("구 버전 parking_spaces 테이블을 새 스키마로 재생성합니다")
            cursor.execute("DROP TABLE parking_spaces")

        cursor.execute('''
        CREATE TABLE IF NOT EXISTS parking_spaces (
            parking_lot TEXT NOT NULL,
            id TEXT NOT NULL,
            status TEXT DEFAULT 'empty',
            last_updated TIMESTAMP,
            PRIMARY KEY (parking_lot, id)
        )
        ''')

        cursor.execute('''
        CREATE TABLE IF NOT EXISTS vehicles (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            parking_lot TEXT,
            parking_space_id TEXT,
            entry_time TIMESTAMP,
            exit_time TIMESTAMP,
            vehicle_type TEXT
        )
        ''')

        # 구 버전 vehicles 테이블에 parking_lot 컬럼 추가
        cursor.execute("PRAGMA table_info(vehicles)")
        if 'parking_lot' not in [row[1] for row in cursor.fetchall()]:
            cursor.execute("ALTER TABLE vehicles ADD COLUMN parking_lot TEXT")

        # 점유율 기록 테이블 (5분 간격 샘플)
        cursor.execute('''
        CREATE TABLE IF NOT EXISTS occupancy_rates (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            parking_lot TEXT,
            timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            hour INTEGER,
            occupancy_rate REAL
        )
        ''')

        # 주차장 설정 테이블
        cursor.execute('''
        CREATE TABLE IF NOT EXISTS parking_lots (
            id TEXT PRIMARY KEY,
            name TEXT,
            building TEXT,
            latitude REAL,
            longitude REAL,
            capacity INTEGER,
            type TEXT,
            has_disabled_spaces INTEGER,
            open_hours TEXT,
            description TEXT,
            video_source TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
        ''')

        # 주차장 지도 영역 좌표 (위경도 다각형)
        cursor.execute('''
        CREATE TABLE IF NOT EXISTS parking_spaces_coords (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            parking_lot_id TEXT,
            polygon_index INTEGER, 
            point_index INTEGER,
            latitude REAL,
            longitude REAL,
            FOREIGN KEY (parking_lot_id) REFERENCES parking_lots (id) ON DELETE CASCADE
        )
        ''')

        # 영상 내 주차면 다각형 좌표 (픽셀). 업로드/동적 추가한 좌표를 재시작 후에도 유지
        cursor.execute('''
        CREATE TABLE IF NOT EXISTS parking_space_polygons (
            parking_lot_id TEXT PRIMARY KEY,
            spaces_json TEXT NOT NULL,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
        ''')

        db.commit()
        logger.info("데이터베이스 초기화 완료")


def save_space_polygons(db, parking_lot_id, spaces):
    """주차면 픽셀 좌표를 DB에 저장"""
    db.execute(
        "INSERT OR REPLACE INTO parking_space_polygons (parking_lot_id, spaces_json, updated_at) "
        "VALUES (?, ?, CURRENT_TIMESTAMP)",
        (parking_lot_id, json.dumps(spaces))
    )


def load_persisted_parking_lots():
    """DB에 저장된 동적 주차장과 업로드된 주차면 좌표를 메모리 설정에 복원"""
    with app.app_context():
        db = get_db()
        cursor = db.cursor()

        cursor.execute("SELECT parking_lot_id, spaces_json FROM parking_space_polygons")
        for lot_id, spaces_json in cursor.fetchall():
            try:
                PARKING_SPACES[lot_id] = json.loads(spaces_json)
                logger.info(f"저장된 주차면 좌표 복원: {lot_id} ({len(PARKING_SPACES[lot_id])}개)")
            except ValueError:
                logger.error(f"주차면 좌표 파싱 실패: {lot_id}")

        # 동적 추가 API로 등록된 주차장(주차면 좌표 행이 있는 주차장)만 영상 처리 대상으로 복원
        cursor.execute('''
            SELECT l.id, l.video_source FROM parking_lots l
            JOIN parking_space_polygons p ON p.parking_lot_id = l.id
            WHERE l.video_source IS NOT NULL AND l.video_source != ''
        ''')
        for lot_id, video_source in cursor.fetchall():
            resolved = resolve_video_source(video_source)
            if lot_id not in VIDEO_SOURCES and resolved:
                VIDEO_SOURCES[lot_id] = resolved
                PARKING_SPACES.setdefault(lot_id, [])
                logger.info(f"동적 주차장 복원: {lot_id} -> {VIDEO_SOURCES[lot_id]}")


def resolve_video_source(video_source):
    """
    영상 소스 검증. 스트림 URL(rtsp/http)이거나 VIDEOS_DIR 안에 실제로 존재하는 파일만 허용.
    유효하면 사용할 경로(또는 URL)를, 아니면 None을 반환
    """
    if not video_source:
        return None
    if video_source.startswith(('rtsp://', 'http://', 'https://')):
        return video_source

    videos_dir = os.path.realpath(VIDEOS_DIR)
    candidate = video_source if os.path.isabs(video_source) else os.path.join(videos_dir, video_source)
    candidate = os.path.realpath(candidate)
    try:
        inside_videos_dir = os.path.commonpath([videos_dir, candidate]) == videos_dir
    except ValueError:  # Windows에서 드라이브가 다른 경우
        inside_videos_dir = False
    if not inside_videos_dir or not os.path.isfile(candidate):
        return None
    return candidate


class ParkingSystem:
    def __init__(self, show_video=True):
        """주차장 관리 시스템 초기화"""
        self.model = self._load_model()
        self.db_path = DB_PATH  # DB 경로 저장
        self.parking_status = {}  # 주차 공간 상태 저장
        self.video_threads = {}  # 비디오 처리 스레드 저장
        self.running = False
        self.frame_skip = 5  # 5프레임 중 1프레임만 추론 (연산량 80% 감소)
        self.status_lock = threading.RLock()  # 스레드 간 상태 공유용 락

        # 영상 표시 설정 (OpenCV GUI 호출은 모두 메인 스레드에서만 수행)
        self.show_video = show_video
        self.current_frames = {}  # 주차장별 현재 프레임 (스트림 API 및 화면 표시용)
        self.message_frames = set()  # 현재 프레임이 안내/오류 메시지 화면인 주차장
        self.display_width = 1024  # 화면 표시 너비
        self.display_height = 768  # 화면 표시 높이
        self.window_names = {}  # 주차장별 창 이름
        self.windows_enabled = show_video  # 'q'로 창을 닫아도 감지는 계속됨
        self.display_paused = False

        # 시간적 필터 및 상태 전이 모델 (주차장별)
        self.temporal_filters = {}
        self.state_machines = {}
        self.last_occupancy_record = {}  # 주차장별 마지막 점유율 기록 시각
        self.b1_empty_counters = {}  # 55호관 B1 보정용 연속 빈칸 카운터

    # ---------- 화면 표시 (메인 스레드 전용) ----------

    def _ensure_window(self, parking_lot):
        """주차장별 표시 창 생성 (이미 있으면 재사용)"""
        if parking_lot in self.window_names:
            return self.window_names[parking_lot]

        window_name = f"Parking Monitoring System - {parking_lot}"
        cv2.namedWindow(window_name, cv2.WINDOW_NORMAL)
        cv2.resizeWindow(window_name, self.display_width, self.display_height)
        self.window_names[parking_lot] = window_name
        logger.info(f"창 초기화 완료: {window_name}")
        return window_name

    def _close_windows(self):
        for window_name in self.window_names.values():
            try:
                cv2.destroyWindow(window_name)
            except cv2.error:
                pass
        self.window_names.clear()
        try:
            cv2.waitKey(1)  # 창 닫기 이벤트 처리
        except cv2.error:
            pass

    def update_display(self):
        """
        메인 스레드에서 주기적으로 호출. 각 주차장의 최신 프레임을 창에 그리고 키 입력을 처리.
        macOS 등 일부 플랫폼은 워커 스레드에서 GUI를 호출하면 크래시가 나므로 여기서만 처리한다.
        """
        if not self.show_video:
            return

        if self.windows_enabled and not self.display_paused:
            for parking_lot in list(VIDEO_SOURCES.keys()):
                frame = self.current_frames.get(parking_lot)
                if frame is None:
                    continue
                try:
                    if parking_lot in self.message_frames:
                        display = frame
                    else:
                        display = self._render_overlay(parking_lot, frame)
                    cv2.imshow(self._ensure_window(parking_lot), display)
                except cv2.error as e:
                    # GUI를 지원하지 않는 OpenCV 빌드(headless) 또는 디스플레이가 없는 환경
                    logger.warning(f"영상 창을 열 수 없어 화면 표시를 끕니다 (감지는 계속): {e}")
                    self.show_video = False
                    return
                except Exception as e:
                    logger.error(f"화면 표시 중 오류 발생: {e}")

        key = cv2.waitKey(1) & 0xFF
        if key != 255:
            self._handle_key_press(key)

    def cleanup(self):
        """명시적 리소스 정리 (프로그램 종료 전 호출용)"""
        if self.running:
            self.stop()
            logger.info("시스템 정리 중 실행 중지됨")

        if self.show_video:
            self._close_windows()
            try:
                cv2.destroyAllWindows()
            except cv2.error:
                pass

        logger.info("시스템 리소스 정리 완료")

    def _load_model(self):
        """
        YOLOv8 주차면 상태 모델 로드.
        이 모델은 space-empty(0) / space-occupied(1) 두 클래스로 학습된 커스텀 모델이다.
        COCO 기본 모델(yolov8n.pt)은 클래스 체계가 달라(0=person, 1=bicycle) 결과가 무의미하므로
        대체 모델로 사용하지 않고 명확한 오류로 종료한다.
        """
        if not os.path.exists(MODEL_PATH):
            raise FileNotFoundError(
                f"모델 파일을 찾을 수 없습니다: {MODEL_PATH}\n"
                f"학습된 가중치(.pt)를 models/best.pt 에 두거나 MODEL_PATH 환경 변수로 경로를 지정하세요."
            )

        try:
            from ultralytics import YOLO
        except ImportError as e:
            raise ImportError("ultralytics 패키지가 필요합니다: pip install -r requirements.txt") from e

        logger.info(f"모델 파일 크기: {os.path.getsize(MODEL_PATH) / (1024 * 1024):.2f} MB")
        model = YOLO(MODEL_PATH)
        logger.info(f"YOLOv8 모델 '{MODEL_PATH}'을 성공적으로 로드했습니다. 클래스: {getattr(model, 'names', None)}")
        return model

    def _handle_key_press(self, key):
        """키 입력 처리 (영상 창에서 입력)"""
        if key == ord('q'):
            # 창만 닫고 감지는 계속 실행
            logger.info("사용자가 'q' 키를 눌러 창을 닫습니다 (백그라운드 감지는 계속 실행)")
            self.windows_enabled = False
            self._close_windows()
        elif key == ord('p'):
            self.display_paused = not self.display_paused
            logger.info(f"화면 표시 {'일시 정지' if self.display_paused else '재개'}")
        elif key == ord('x'):
            logger.info("사용자가 'x' 키를 눌러 전체 시스템을 종료합니다")
            self.running = False

    def _set_message_frame(self, parking_lot, lines, color=(255, 255, 255)):
        """안내/오류 메시지 화면을 현재 프레임으로 설정"""
        frame = np.zeros((720, 1280, 3), dtype=np.uint8)
        for i, (text, size) in enumerate(lines):
            frame = put_text_pil(frame, text, (200, 200 + i * 100), size, color=color if i == 0 else (255, 255, 255))
        self.current_frames[parking_lot] = frame
        self.message_frames.add(parking_lot)

    def _process_video_file(self, parking_lot, video_path):
        """비디오 파일(또는 스트림) 처리 및 차량 감지. 워커 스레드에서 실행되며 GUI는 호출하지 않는다."""
        logger.info(f"비디오 처리 시작: {parking_lot}, 경로: {video_path}")

        self._set_message_frame(parking_lot, [
            (f"주차장 모니터링 시스템 - {parking_lot}", 30),
            (f"비디오 로드 중: {os.path.basename(str(video_path))}", 24),
            ("잠시만 기다려 주세요...", 24),
        ])

        is_stream = str(video_path).startswith(('rtsp://', 'http://', 'https://'))
        if not is_stream and not os.path.exists(video_path):
            logger.error(f"비디오 파일을 찾을 수 없음: {video_path}")
            self._set_message_frame(parking_lot, [
                ("오류: 비디오 파일을 찾을 수 없습니다", 26),
                (f"경로: {video_path}", 20),
            ], color=(0, 0, 255))
            return

        thread_db = None
        cap = None
        try:
            cap = cv2.VideoCapture(video_path)
            if not cap.isOpened():
                logger.error(f"비디오를 열 수 없음: {video_path}")
                self._set_message_frame(parking_lot, [
                    ("오류: 비디오를 열 수 없습니다", 26),
                    (f"경로: {video_path}", 20),
                ], color=(0, 0, 255))
                return

            # 비디오 정보 로깅
            frame_width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
            frame_height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
            fps = cap.get(cv2.CAP_PROP_FPS)
            frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
            logger.info(
                f"비디오 '{video_path}' 정보: 크기 {frame_width}x{frame_height}, "
                f"FPS {fps:.2f}, 총 프레임 수 {frame_count}"
            )

            # 스레드별 데이터베이스 연결
            thread_db = sqlite3.connect(self.db_path)
            read_frame_count = 0
            detect_count = 0
            start_time = time.time()

            while self.running and VIDEO_SOURCES.get(parking_lot) == video_path:
                try:
                    ret, frame = cap.read()

                    # 비디오 끝에 도달하면 처음부터 다시 재생 (루프 재생)
                    if not ret:
                        if is_stream:
                            logger.warning(f"스트림 프레임 수신 실패: {video_path}, 재시도합니다")
                            time.sleep(1)
                            continue
                        logger.info(f"비디오 '{video_path}' 끝에 도달하여 처음부터 다시 재생합니다.")
                        cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
                        continue

                    # 성능 향상을 위해 frame_skip 프레임마다 한 번만 추론
                    read_frame_count += 1
                    if read_frame_count % self.frame_skip != 0:
                        continue

                    # 차량 감지 수행 - 창 상태와 관계없이 항상 실행
                    self._detect_vehicles(frame, parking_lot, thread_db)
                    detect_count += 1

                    # 현재 프레임 저장 (화면 표시용 및 스트림 API용)
                    self.current_frames[parking_lot] = frame
                    self.message_frames.discard(parking_lot)

                    # 100번째 추론마다 로그 출력
                    if detect_count % 100 == 0:
                        elapsed_time = time.time() - start_time
                        fps_actual = detect_count / elapsed_time if elapsed_time > 0 else 0
                        with self.status_lock:
                            occupied_count = sum(1 for st in self.parking_status.get(parking_lot, {}).values()
                                                 if st.get("status") == "occupied")
                        space_count = len(PARKING_SPACES.get(parking_lot, []))
                        logger.info(
                            f"{parking_lot}: 추론 {detect_count}회, 초당 추론 {fps_actual:.2f}회, "
                            f"점유 {occupied_count}/{space_count}"
                        )

                    # CPU 사용량 감소를 위한 짧은 대기
                    time.sleep(0.01)

                except Exception as e:
                    logger.error(f"프레임 처리 중 오류 발생: {e}")
                    logger.error(traceback.format_exc())
                    time.sleep(0.5)

            logger.info(f"비디오 '{video_path}' 처리 종료")

        except Exception as e:
            logger.error(f"비디오 처리 중 치명적 오류 발생: {e}")
            logger.error(traceback.format_exc())
            self._set_message_frame(parking_lot, [
                (f"치명적 오류 발생: {str(e)[:50]}", 24),
                ("시스템을 재시작하세요", 24),
            ], color=(0, 0, 255))
        finally:
            if thread_db is not None:
                thread_db.close()
            if cap is not None:
                cap.release()

    def _render_overlay(self, parking_lot, frame):
        """감지 결과(주차면 다각형, 상태 정보 패널)를 그린 표시용 프레임 생성"""
        # 화면 크기에 맞게 조정
        display_frame = frame.copy()
        height, width = display_frame.shape[:2]

        # 비율 유지하면서 너비 조정
        display_height = int(height * self.display_width / width)
        display_frame = cv2.resize(display_frame, (self.display_width, display_height))

        # 주차 공간 상태 표시
        with self.status_lock:
            status = dict(self.parking_status.get(parking_lot, {}))
        if status:
            spaces = PARKING_SPACES.get(parking_lot, [])

            for space in spaces:
                space_id = space["id"]
                coords = np.array(space["coords"])

                # 비율에 맞게 좌표 조정
                scaled_coords = coords.copy()
                scaled_coords[:, 0] = coords[:, 0] * self.display_width / width
                scaled_coords[:, 1] = coords[:, 1] * display_height / height

                # 상태에 따른 색상 설정
                space_status = status.get(space_id, {}).get("status", "unknown")
                if space_status == "occupied":
                    color = (0, 0, 255)  # 빨간색 (BGR)
                    thickness = 3  # 두껍게 표시
                elif space_status == "empty":
                    color = (0, 255, 0)  # 녹색 (BGR)
                    thickness = 2
                else:
                    color = (128, 128, 128)  # 회색 (BGR)
                    thickness = 2

                # 다각형 그리기
                cv2.polylines(display_frame, [scaled_coords.astype(np.int32)], True, color, thickness)

                # 공간 ID 표시
                centroid = np.mean(scaled_coords, axis=0).astype(np.int32)
                # 배경 사각형 추가 (가독성 향상)
                text_size = cv2.getTextSize(space_id, cv2.FONT_HERSHEY_SIMPLEX, 0.6, 2)[0]
                cv2.rectangle(display_frame,
                              (centroid[0] - text_size[0] // 2 - 5, centroid[1] - text_size[1] // 2 - 5),
                              (centroid[0] + text_size[0] // 2 + 5, centroid[1] + text_size[1] // 2 + 5),
                              (0, 0, 0), -1)

                cv2.putText(
                    display_frame,
                    space_id,
                    (centroid[0] - text_size[0] // 2, centroid[1] + text_size[1] // 2),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.6,
                    (255, 255, 255),
                    2,
                    cv2.LINE_AA
                )

        # 정보 패널 추가 (화면 상단)
        info_panel_height = 60
        info_panel = np.zeros((info_panel_height, self.display_width, 3), dtype=np.uint8)

        # 전체 주차장 상태 정보 계산
        spaces = PARKING_SPACES.get(parking_lot, [])
        total_spaces = len(spaces)
        occupied_spaces = sum(1 for st in status.values() if st.get("status") == "occupied")
        available_spaces = total_spaces - occupied_spaces
        occupancy_rate = (occupied_spaces / total_spaces * 100) if total_spaces > 0 else 0

        # 상태 문구와 색상 설정
        if occupancy_rate > 80:
            status_text = "매우 혼잡"
            status_color = (0, 0, 255)  # 빨간색
        elif occupancy_rate > 50:
            status_text = "혼잡"
            status_color = (0, 165, 255)  # 주황색
        elif occupancy_rate > 30:
            status_text = "보통"
            status_color = (0, 255, 255)  # 노란색
        else:
            status_text = "여유"
            status_color = (0, 255, 0)  # 녹색

        # PIL로 정보 패널에 한글 텍스트 추가
        info_text = f"주차 가능: {available_spaces}/{total_spaces} | 점유율: {occupancy_rate:.1f}% | 상태: {status_text}"
        info_panel = put_text_pil(info_panel, info_text, (10, 20), 24, color=status_color)

        # 타임스탬프 표시
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        info_panel = put_text_pil(info_panel, timestamp, (self.display_width - 250, 20), 20, color=(255, 255, 255))

        # 정보 패널과 화면 합치기
        combined_frame = np.vstack((info_panel, display_frame))

        # 바닥 패널 추가 (키 안내)
        bottom_panel_height = 40
        bottom_panel = np.zeros((bottom_panel_height, self.display_width, 3), dtype=np.uint8)
        bottom_panel = put_text_pil(
            bottom_panel,
            "창 닫기(감지는 계속): 'q' | 일시정지: 'p' | 전체 종료: 'x'",
            (10, 15), 20, color=(200, 200, 200)
        )

        # 바닥 패널 추가
        final_frame = np.vstack((combined_frame, bottom_panel))

        return final_frame

    def _detect_vehicles(self, frame, parking_lot, db_conn):
        """
        이미지에서 주차 공간 상태 감지 및 업데이트
        (겹침 비율 × 신뢰도 점수 → 시간 필터 → 상태 전이 모델)
        """
        cursor = db_conn.cursor()

        # 원본 프레임 크기
        original_height, original_width = frame.shape[:2]

        # YOLOv8 주차 공간 감지 처리
        results = self.model(frame, conf=0.5)

        # YOLO 모델 실제 입력 크기
        model_width, model_height = 640, 448

        # 비율 계산 - 원본 프레임에서 모델 입력으로의 변환 비율
        width_ratio = original_width / model_width
        height_ratio = original_height / model_height

        # 감지된 객체 분류
        detected_occupied = []
        detected_empty = []

        # YOLO 감지 결과 바운딩 박스 처리
        if len(results) > 0 and hasattr(results[0], 'boxes'):
            boxes = results[0].boxes
            class_names = results[0].names if hasattr(results[0], 'names') else {0: "space-empty", 1: "space-occupied"}

            for box in boxes:
                try:
                    class_id = int(box.cls[0].item())
                    confidence = float(box.conf[0].item())
                    x1, y1, x2, y2 = map(int, box.xyxy[0].tolist())

                    # 모델 좌표계로 변환
                    model_x1, model_y1, model_x2, model_y2 = self._convert_to_model_coordinates(
                        [x1, y1, x2, y2],
                        width_ratio,
                        height_ratio
                    )

                    # 최소 크기 필터링 (노이즈 제거)
                    area = (x2 - x1) * (y2 - y1)
                    min_area = 100  # 최소 100 픽셀 면적

                    if area < min_area:
                        continue

                    if class_id == 1:  # space-occupied
                        detected_occupied.append((model_x1, model_y1, model_x2, model_y2, confidence))
                    elif class_id == 0:  # space-empty
                        detected_empty.append((model_x1, model_y1, model_x2, model_y2, confidence))
                except Exception as e:
                    logger.error(f"박스 처리 중 오류: {e}")
                    continue

        # 각 주차 공간에 대한 상태 확인
        spaces = PARKING_SPACES.get(parking_lot, [])
        occupied_spaces = {}
        current_time = datetime.now()

        if parking_lot not in self.temporal_filters:
            self.temporal_filters[parking_lot] = {}

        if parking_lot not in self.state_machines:
            self.state_machines[parking_lot] = {}

        # 주차 공간별 매핑 결과 저장 (IoU 기반 정렬용)
        space_mappings = {}

        # 1단계: 모든 주차 공간에 대해 객체 매핑 계산
        for space in spaces:
            space_id = space["id"]

            # 초기화
            space_mappings[space_id] = {
                "occupied_mappings": [],
                "empty_mappings": [],
                "space_area": 0
            }

            try:
                # 좌표 변환 및 유효성 검사
                original_coords, adjusted_coords = self._process_space_coordinates(
                    space["coords"],
                    original_width,
                    original_height,
                    width_ratio,
                    height_ratio,
                    model_width,
                    model_height
                )

                # 주차 공간 마스크 생성 (모델 크기에 맞게)
                space_mask = self._create_space_mask(adjusted_coords, model_width, model_height)
                space_area = np.count_nonzero(space_mask)
                space_mappings[space_id]["space_area"] = space_area

                # 'space-occupied' 클래스와 매핑 확인
                self._calculate_mappings(
                    space_id,
                    space_mask,
                    space_area,
                    detected_occupied,
                    space_mappings[space_id]["occupied_mappings"],
                    model_width,
                    model_height
                )

                # 'space-empty' 클래스와 매핑 확인
                self._calculate_mappings(
                    space_id,
                    space_mask,
                    space_area,
                    detected_empty,
                    space_mappings[space_id]["empty_mappings"],
                    model_width,
                    model_height
                )
            except Exception as e:
                logger.error(f"주차 공간 {space_id} 처리 중 오류: {e}")
                continue

        # 2단계: 스코어 기반 상태 결정
        for space_id, mapping in space_mappings.items():
            # 각 클래스별 최고 스코어 매핑 찾기
            occupied_score = max([m[3] for m in mapping["occupied_mappings"]], default=0)
            empty_score = max([m[3] for m in mapping["empty_mappings"]], default=0)

            # 55호관 B1은 카메라 가장자리에 걸쳐 차량이 잘려 보여 빈칸으로 오인되는 경우가 많아 별도 보정
            is_b1_space = parking_lot == B1_CORRECTION_LOT and space_id == "B1"

            # 점유 객체 가중치 적용
            occupancy_boost = 1.3  # 기본 점유 가중치

            if is_b1_space:
                # B1은 점유 상태를 선호하도록 가중치 상향
                occupancy_boost = 2.5
                # 모델이 전혀 감지하지 못해도 최소 0.4 점수 부여
                occupied_score = max(occupied_score, 0.4)
                # 비어있음 감지 신뢰도 40% 감소
                empty_score *= 0.6
                logger.debug(f"B1 공간 특별 처리: 점유={occupied_score:.2f}, 빈공간={empty_score:.2f}, 가중치={occupancy_boost}")

            # 시간적 필터 초기화
            if space_id not in self.temporal_filters[parking_lot]:
                if is_b1_space:
                    self.temporal_filters[parking_lot][space_id] = self.TemporalFilter(
                        history_length=25,
                        occupancy_threshold=0.40,  # 더 쉽게 점유 상태로 판단
                        confidence_decay=0.98  # 과거 판정을 더 오래 반영
                    )
                else:
                    self.temporal_filters[parking_lot][space_id] = self._create_temporal_filter()

            adjusted_occupied_score = occupied_score * occupancy_boost

            # 현재 프레임 상태 결정
            if adjusted_occupied_score > empty_score and occupied_score > 0:
                current_frame_status = "occupied"
                confidence_score = occupied_score
            else:
                current_frame_status = "empty"
                confidence_score = empty_score

            # B1: 빈칸 판정은 매우 높은 신뢰도(0.85 이상)일 때만 인정
            if is_b1_space and current_frame_status == "empty" and empty_score < 0.85:
                current_frame_status = "occupied"
                confidence_score = max(occupied_score, 0.5)
                logger.debug(f"B1 공간 상태 오버라이드: 빈공간→점유 (신뢰도 부족: {empty_score:.2f})")

            # 시간적 필터링 적용
            filtered_status, filtered_confidence = self.temporal_filters[parking_lot][space_id].update(
                space_id, current_frame_status, confidence_score
            )

            # 상태 머신 초기화 및 적용
            if space_id not in self.state_machines[parking_lot]:
                if is_b1_space:
                    self.state_machines[parking_lot][space_id] = self.ParkingSpaceStateMachine(
                        empty_to_occupied_threshold=1,  # 더 쉽게 점유 상태로 전환
                        occupied_to_empty_threshold=15,  # 더 어렵게 빈 상태로 전환
                        confidence_threshold=0.5
                    )
                else:
                    self.state_machines[parking_lot][space_id] = self._create_state_machine()

            # 상태 머신 업데이트 (시간적 필터링 결과 기반)
            final_status, is_state_changed = self.state_machines[parking_lot][space_id].update(
                space_id, filtered_status, filtered_confidence
            )

            # B1: 상태 머신이 빈칸으로 판정해도 20회 연속일 때만 실제 빈칸으로 인정
            if is_b1_space:
                if final_status == "empty":
                    self.b1_empty_counters[parking_lot] = self.b1_empty_counters.get(parking_lot, 0) + 1
                    if self.b1_empty_counters[parking_lot] < 20:
                        final_status = "occupied"
                        is_state_changed = False
                        logger.debug(f"B1 공간 수동 오버라이드: empty→occupied "
                                     f"(카운터: {self.b1_empty_counters[parking_lot]}/20)")
                else:
                    self.b1_empty_counters[parking_lot] = 0

            # 결과 기록
            occupied_spaces[space_id] = {
                "status": final_status,
                "vehicle_type": "car" if final_status == "occupied" else None,
                "confidence": filtered_confidence
            }

            # 상태가 변경된 경우만 데이터베이스 업데이트
            if is_state_changed:
                self._update_space_status_in_db(cursor, parking_lot, space_id, final_status, current_time, db_conn)

        # 주차장 상태 업데이트
        with self.status_lock:
            self.parking_status[parking_lot] = occupied_spaces

        # 전체 주차장 점유율을 5분 간격으로 DB에 기록 (시간대별 통계의 원천 데이터)
        total_spaces = len(spaces)
        if total_spaces > 0:
            last_record = self.last_occupancy_record.get(parking_lot)
            if last_record is None or current_time - last_record >= OCCUPANCY_RECORD_INTERVAL:
                occupied_count = sum(1 for st in occupied_spaces.values() if st["status"] == "occupied")
                self._record_occupancy_rate(parking_lot, (occupied_count / total_spaces) * 100, db_conn)
                self.last_occupancy_record[parking_lot] = current_time

        return occupied_spaces

    # 좌표 변환 유틸리티 함수
    def _convert_to_model_coordinates(self, coords, width_ratio, height_ratio):
        """원본 좌표를 모델 좌표계로 변환"""
        if isinstance(coords[0], (list, tuple)):
            # 폴리곤 좌표 변환
            return np.array([
                [int(x / width_ratio), int(y / height_ratio)]
                for x, y in coords
            ])
        else:
            # 바운딩 박스 좌표 변환 [x1, y1, x2, y2]
            return [
                int(coords[0] / width_ratio),
                int(coords[1] / height_ratio),
                int(coords[2] / width_ratio),
                int(coords[3] / height_ratio)
            ]

    def _process_space_coordinates(self, coords, original_width, original_height,
                                  width_ratio, height_ratio, model_width, model_height):
        """주차 공간 좌표 처리: 변환 및 유효성 검사를 통합"""
        # 원본 좌표가 이미지 범위를 벗어나지 않도록 보장
        original_coords = np.array([
            [max(0, min(x, original_width - 1)), max(0, min(y, original_height - 1))]
            for x, y in coords
        ])

        # 원본 주차 공간 좌표를 모델 입력 크기에 맞게 조정
        adjusted_coords = np.array([
            [int(x / width_ratio), int(y / height_ratio)]
            for x, y in original_coords
        ])

        # 모델 좌표가 모델 크기를 벗어나지 않도록 보장
        adjusted_coords = np.array([
            [max(0, min(x, model_width - 1)), max(0, min(y, model_height - 1))]
            for x, y in adjusted_coords
        ])

        return original_coords, adjusted_coords

    def _create_space_mask(self, coords, width, height):
        """좌표로부터 공간 마스크 생성"""
        mask = np.zeros((height, width), dtype=np.uint8)
        cv2.fillPoly(mask, [coords.astype(np.int32)], 255)
        return mask

    def _calculate_mappings(self, space_id, space_mask, space_area,
                          detected_objects, mappings_list, model_width, model_height):
        """객체와 주차 공간 간의 매핑 계산"""
        MIN_OVERLAP_RATIO = 0.05  # 최소 5% 이상 겹침

        for i, (x1, y1, x2, y2, confidence) in enumerate(detected_objects):
            # 벡터화된 접근 방식으로 교차 영역 계산
            box_mask = np.zeros((model_height, model_width), dtype=np.uint8)
            cv2.rectangle(box_mask, (x1, y1), (x2, y2), 255, -1)

            # 두 마스크의 교차 영역 계산
            intersection = cv2.bitwise_and(space_mask, box_mask)
            intersection_area = np.count_nonzero(intersection)

            # IoU 및 겹침 비율 계산
            if space_area > 0:
                # 주차 공간 대비 겹침 비율
                overlap_ratio = intersection_area / space_area

                if overlap_ratio > MIN_OVERLAP_RATIO:
                    # 겹침 비율과 신뢰도를 고려한 스코어 계산
                    score = overlap_ratio * confidence
                    mappings_list.append((i, overlap_ratio, confidence, score))

    def _record_occupancy_rate(self, parking_lot, occupancy_rate, db_conn):
        """
        주차장 점유율 샘플을 DB에 기록 (5분 간격으로 호출됨).
        시간대별 통계는 같은 시간대 샘플들의 평균으로 계산한다.
        """
        try:
            current_time = datetime.now()
            db_conn.execute(
                "INSERT INTO occupancy_rates (parking_lot, timestamp, hour, occupancy_rate) VALUES (?, ?, ?, ?)",
                (parking_lot, current_time.strftime("%Y-%m-%d %H:%M:%S"), current_time.hour, occupancy_rate)
            )
            db_conn.commit()
        except Exception as e:
            logger.error(f"점유율 기록 중 오류 발생: {e}")
            logger.error(traceback.format_exc())

    def _update_space_status_in_db(self, cursor, parking_lot, space_id, current_status, current_time, db_conn):
        """주차 공간 상태 및 입출차 기록 데이터베이스 업데이트"""
        try:
            timestamp = current_time.strftime("%Y-%m-%d %H:%M:%S")
            cursor.execute(
                "SELECT status FROM parking_spaces WHERE parking_lot = ? AND id = ?",
                (parking_lot, space_id)
            )
            row = cursor.fetchone()
            previous_status = row[0] if row else "unknown"

            if previous_status == current_status:
                return False

            logger.info(f"주차 공간 {parking_lot}/{space_id} 상태 변경: {previous_status} -> {current_status}")
            cursor.execute(
                "INSERT OR REPLACE INTO parking_spaces (parking_lot, id, status, last_updated) VALUES (?, ?, ?, ?)",
                (parking_lot, space_id, current_status, timestamp)
            )

            # 점유됨으로 바뀌면 입차 기록 (최초 감지 시 이전 상태가 unknown인 경우 포함)
            if current_status == "occupied":
                cursor.execute(
                    "SELECT id FROM vehicles WHERE parking_lot = ? AND parking_space_id = ? AND exit_time IS NULL",
                    (parking_lot, space_id)
                )
                if not cursor.fetchone():
                    cursor.execute(
                        "INSERT INTO vehicles (parking_lot, parking_space_id, entry_time, vehicle_type) "
                        "VALUES (?, ?, ?, ?)",
                        (parking_lot, space_id, timestamp, "car")
                    )
                    logger.info(f"차량 입차 기록: {parking_lot}/{space_id}, 시간 {timestamp}")

            # 점유됨 -> 비어있음으로 바뀌면 출차 기록
            elif current_status == "empty" and previous_status == "occupied":
                cursor.execute(
                    "UPDATE vehicles SET exit_time = ? "
                    "WHERE parking_lot = ? AND parking_space_id = ? AND exit_time IS NULL",
                    (timestamp, parking_lot, space_id)
                )

            db_conn.commit()
            return True

        except Exception as e:
            logger.error(f"주차 공간 상태 업데이트 중 오류 발생: {e}")
            logger.error(traceback.format_exc())
            db_conn.rollback()

        return False

    # 시간적 필터 및 상태 머신 클래스 구현
    def _create_temporal_filter(self):
        """시간적 필터링을 위한 클래스 인스턴스 생성"""
        # 개선: 더 안정적인 파라미터로 조정
        return self.TemporalFilter(
            history_length=10,  # 5→10 프레임으로 증가
            occupancy_threshold=0.7,  # 0.6→0.7로 증가
            confidence_decay=0.9  # 0.8→0.9로 증가
        )

    def _create_state_machine(self):
        """상태 전이 모델을 위한 클래스 인스턴스 생성"""
        # 개선: 상태 전이 임계값 강화
        return self.ParkingSpaceStateMachine(
            empty_to_occupied_threshold=5,  # 3→5로 증가
            occupied_to_empty_threshold=8,  # 3→8로 증가
            confidence_threshold=0.7  # 0.6→0.7로 증가
        )

    # 시간적 필터링을 위한 클래스
    class TemporalFilter:
        def __init__(self, history_length=5, occupancy_threshold=0.6, confidence_decay=0.8):
            """
            시간적 필터링을 위한 클래스

            Args:
                history_length: 유지할 이전 프레임 수
                occupancy_threshold: 점유 상태로 판단할 임계값 (0-1 사이)
                confidence_decay: 이전 프레임 가중치 감소 계수
            """
            self.history_length = history_length
            self.occupancy_threshold = occupancy_threshold
            self.confidence_decay = confidence_decay
            self.space_history = {}  # 각 주차 공간의 상태 이력

        def update(self, space_id, current_status, confidence):
            """
            주차 공간 상태 업데이트 및 필터링된 상태 반환

            Args:
                space_id: 주차 공간 식별자
                current_status: 현재 프레임에서의 상태 ('occupied' 또는 'empty')
                confidence: 현재 프레임 상태의 신뢰도 (0-1 사이)

            Returns:
                filtered_status: 필터링된 상태 ('occupied' 또는 'empty')
                filtered_confidence: 필터링된 신뢰도
            """
            # 공간에 대한 이력이 없으면 초기화
            if space_id not in self.space_history:
                self.space_history[space_id] = []

            # 현재 상태를 이력에 추가
            status_value = 1.0 if current_status == 'occupied' else 0.0
            self.space_history[space_id].append((status_value, confidence))

            # 이력 길이 제한
            if len(self.space_history[space_id]) > self.history_length:
                self.space_history[space_id].pop(0)

            # 가중 평균 계산
            weighted_sum = 0
            total_weight = 0

            for i, (status, conf) in enumerate(self.space_history[space_id]):
                # 더 최근 프레임에 더 높은 가중치 부여
                weight = conf * (self.confidence_decay ** (len(self.space_history[space_id]) - i - 1))
                weighted_sum += status * weight
                total_weight += weight

            # 평균 점유율 계산
            average_occupancy = weighted_sum / total_weight if total_weight > 0 else 0.5

            # 최종 상태 결정
            filtered_status = 'occupied' if average_occupancy >= self.occupancy_threshold else 'empty'
            filtered_confidence = average_occupancy if filtered_status == 'occupied' else (1 - average_occupancy)

            return filtered_status, filtered_confidence

    # 상태 전이 모델 클래스
    class ParkingSpaceStateMachine:
        """
        주차 공간 상태 변화를 모델링하는 상태 기계
        이 클래스는 상태 전이에 제약을 두어 일시적인 오탐을 필터링합니다.
        """

        # 상태 정의
        STATE_EMPTY = "empty"
        STATE_OCCUPIED = "occupied"
        STATE_TRANSITION_TO_EMPTY = "transition_to_empty"
        STATE_TRANSITION_TO_OCCUPIED = "transition_to_occupied"

        def __init__(self,
                     empty_to_occupied_threshold=3,
                     occupied_to_empty_threshold=3,
                     confidence_threshold=0.6):
            """
            Args:
                empty_to_occupied_threshold: 빈 상태에서 점유 상태로 전환하기 위한 연속 프레임 수
                occupied_to_empty_threshold: 점유 상태에서 빈 상태로 전환하기 위한 연속 프레임 수
                confidence_threshold: 상태 전환을 고려하기 위한 최소 신뢰도
            """
            self.empty_to_occupied_threshold = empty_to_occupied_threshold
            self.occupied_to_empty_threshold = occupied_to_empty_threshold
            self.confidence_threshold = confidence_threshold

            # 공간별 상태 정보
            self.space_states = {}

        def update(self, space_id, detected_status, confidence):
            """
            주차 공간 상태 업데이트 및 필터링된 상태 반환

            Args:
                space_id: 주차 공간 ID
                detected_status: 현재 프레임에서 감지된 상태 ('occupied' 또는 'empty')
                confidence: 감지 신뢰도

            Returns:
                (filtered_status, is_state_changed): 필터링된 상태와 상태 변경 여부
            """
            # 공간 상태 초기화 (필요한 경우)
            if space_id not in self.space_states:
                self.space_states[space_id] = {
                    'current_state': self.STATE_EMPTY,  # 기본값은 빈 상태
                    'consecutive_occupied': 0,  # 연속으로 점유 감지된 프레임 수
                    'consecutive_empty': 0,  # 연속으로 빈 상태로 감지된 프레임 수
                    'last_stable_state': self.STATE_EMPTY,  # 마지막 안정 상태
                    'last_confidence': 0.0  # 마지막 신뢰도
                }

            # 현재 상태 가져오기
            state_info = self.space_states[space_id]
            current_state = state_info['current_state']
            is_state_changed = False

            # 신뢰도가 임계값 이상인 경우에만 상태 업데이트 고려
            if confidence >= self.confidence_threshold:
                if detected_status == self.STATE_OCCUPIED:
                    state_info['consecutive_occupied'] += 1
                    state_info['consecutive_empty'] = 0
                else:  # empty
                    state_info['consecutive_empty'] += 1
                    state_info['consecutive_occupied'] = 0

            # 상태 전이 로직
            if current_state == self.STATE_EMPTY:
                if state_info['consecutive_occupied'] >= self.empty_to_occupied_threshold:
                    # 빈 상태 -> 점유 상태 전환
                    state_info['current_state'] = self.STATE_OCCUPIED
                    state_info['last_stable_state'] = self.STATE_OCCUPIED
                    is_state_changed = True
                    # 카운터 재설정
                    state_info['consecutive_occupied'] = 0

            elif current_state == self.STATE_OCCUPIED:
                if state_info['consecutive_empty'] >= self.occupied_to_empty_threshold:
                    # 점유 상태 -> 빈 상태 전환
                    state_info['current_state'] = self.STATE_EMPTY
                    state_info['last_stable_state'] = self.STATE_EMPTY
                    is_state_changed = True
                    # 카운터 재설정
                    state_info['consecutive_empty'] = 0

            # 전환 상태 처리
            elif current_state == self.STATE_TRANSITION_TO_OCCUPIED:
                if state_info['consecutive_occupied'] >= self.empty_to_occupied_threshold:
                    state_info['current_state'] = self.STATE_OCCUPIED
                    state_info['last_stable_state'] = self.STATE_OCCUPIED
                    is_state_changed = True
                elif state_info['consecutive_empty'] >= self.occupied_to_empty_threshold:
                    state_info['current_state'] = self.STATE_EMPTY
                    # 전환 취소

            elif current_state == self.STATE_TRANSITION_TO_EMPTY:
                if state_info['consecutive_empty'] >= self.occupied_to_empty_threshold:
                    state_info['current_state'] = self.STATE_EMPTY
                    state_info['last_stable_state'] = self.STATE_EMPTY
                    is_state_changed = True
                elif state_info['consecutive_occupied'] >= self.empty_to_occupied_threshold:
                    state_info['current_state'] = self.STATE_OCCUPIED
                    # 전환 취소

            # 신뢰도 업데이트
            state_info['last_confidence'] = confidence

            return state_info['current_state'], is_state_changed

    def get_parking_status(self):
        """주차장별 현재 상태 정보 반환"""
        status_result = {}

        with self.status_lock:
            snapshot = {lot: dict(spaces) for lot, spaces in self.parking_status.items()}

        for parking_lot in VIDEO_SOURCES.keys():
            spaces = snapshot.get(parking_lot, {})
            total_spaces = len(PARKING_SPACES.get(parking_lot, []))
            occupied_spaces = sum(1 for st in spaces.values() if st["status"] == "occupied")

            status_result[parking_lot] = {
                "total_spaces": total_spaces,
                "occupied_spaces": occupied_spaces,
                "available_spaces": total_spaces - occupied_spaces,
                "occupancy_rate": round((occupied_spaces / total_spaces) * 100, 2) if total_spaces > 0 else 0,
                "spaces": [
                    {"id": space_id, "status": info["status"], "vehicle_type": info["vehicle_type"]}
                    for space_id, info in spaces.items()
                ]
            }

        return status_result

    def _start_lot_thread(self, parking_lot, source):
        thread = threading.Thread(
            target=self._process_video_file,
            args=(parking_lot, source),
            name=f"video-{parking_lot}",
            daemon=True
        )
        self.video_threads[parking_lot] = thread
        thread.start()
        logger.info(f"비디오 '{parking_lot}' 처리 스레드 시작")

    def start(self):
        """모든 비디오 소스에서 차량 감지 시작"""
        if self.running:
            logger.info("이미 실행 중입니다")
            return

        self.running = True
        for parking_lot, source in VIDEO_SOURCES.items():
            self._start_lot_thread(parking_lot, source)

    def stop(self, timeout=10):
        """차량 감지 중지 (처리 스레드가 실제로 종료될 때까지 대기)"""
        if not self.running:
            logger.info("이미 중지되었습니다")
            return

        self.running = False
        for parking_lot, thread in list(self.video_threads.items()):
            if thread is not threading.current_thread():
                thread.join(timeout=timeout)
            if thread.is_alive():
                logger.warning(f"스레드가 제한 시간 내에 종료되지 않았습니다: {parking_lot}")
        self.video_threads.clear()
        logger.info("주차장 모니터링 중지됨")

    def add_parking_lot(self, parking_lot_id, video_source, parking_spaces=None):
        """
        새 주차장 추가. 실행 중이면 해당 주차장 처리 스레드만 새로 시작한다.

        Returns:
            bool: 성공 여부
        """
        if parking_lot_id in VIDEO_SOURCES:
            logger.warning(f"이미 존재하는 주차장 ID: {parking_lot_id}")
            return False

        logger.info(f"새 주차장 추가: {parking_lot_id}, 소스: {video_source}")
        VIDEO_SOURCES[parking_lot_id] = video_source
        PARKING_SPACES[parking_lot_id] = parking_spaces or []
        self.temporal_filters.pop(parking_lot_id, None)
        self.state_machines.pop(parking_lot_id, None)

        if self.running:
            self._start_lot_thread(parking_lot_id, video_source)
        return True

    def reset_lot_state(self, parking_lot_id):
        """주차면 좌표가 바뀐 주차장의 필터/상태 초기화"""
        self.temporal_filters.pop(parking_lot_id, None)
        self.state_machines.pop(parking_lot_id, None)
        with self.status_lock:
            self.parking_status.pop(parking_lot_id, None)


# ---------- 관리자 인증 ----------

# 관리자 API 토큰. 환경 변수로 지정하지 않으면 서버 시작 시 임의 토큰을 생성해 로그에 출력한다.
ADMIN_TOKEN = os.getenv('ADMIN_TOKEN')

# 기본 제공 주차장 (삭제 API로 영상 처리를 중단하지 않음)
BUILTIN_LOTS = ('parking_lot_A', 'parking_lot_B')


def require_admin(f):
    """X-Admin-Token 헤더가 관리자 토큰과 일치해야 호출 가능한 엔드포인트"""
    @wraps(f)
    def wrapper(*args, **kwargs):
        token = request.headers.get('X-Admin-Token', '')
        if not ADMIN_TOKEN or not hmac.compare_digest(token.encode(), ADMIN_TOKEN.encode()):
            return jsonify({"error": "관리자 인증이 필요합니다"}), 401
        return f(*args, **kwargs)
    return wrapper


def _valid_lot_id(lot_id):
    return isinstance(lot_id, str) and 0 < len(lot_id) <= 64 and all(c.isalnum() or c in '_-' for c in lot_id)


def normalize_spaces(spaces):
    """주차면 좌표 목록 검증: [{"id": str, "coords": [[x, y], ...(3점 이상)]}, ...]"""
    if not isinstance(spaces, list):
        raise ValueError("좌표는 리스트여야 합니다")
    normalized = []
    seen = set()
    for space in spaces:
        if not isinstance(space, dict) or not isinstance(space.get('id'), str) or not space['id']:
            raise ValueError("각 주차면은 문자열 id를 가져야 합니다")
        coords = space.get('coords')
        if not isinstance(coords, list) or len(coords) < 3:
            raise ValueError(f"주차면 '{space['id']}'의 좌표는 3개 이상의 점이어야 합니다")
        points = []
        for point in coords:
            if not isinstance(point, (list, tuple)) or len(point) != 2:
                raise ValueError(f"주차면 '{space['id']}'의 좌표 형식이 올바르지 않습니다")
            points.append([int(point[0]), int(point[1])])
        if space['id'] in seen:
            raise ValueError(f"주차면 ID '{space['id']}'가 중복되었습니다")
        seen.add(space['id'])
        normalized.append({"id": space['id'], "coords": points})
    return normalized


# ---------- 공개 엔드포인트 ----------

@app.route('/api/health', methods=['GET'])
def health():
    """가벼운 서버 상태 확인 (앱의 연결 확인용)"""
    return jsonify({
        "status": "ok",
        "running": parking_system.running,
        "parking_lots": list(VIDEO_SOURCES.keys())
    })


@app.route('/api/auth/check', methods=['GET'])
@require_admin
def auth_check():
    """관리자 토큰 확인"""
    return jsonify({"status": "ok"})


@app.route('/api/status', methods=['GET'])
def get_status():
    """현재 주차장 상태 반환"""
    try:
        return jsonify(parking_system.get_parking_status())
    except Exception as e:
        logger.error(f"API 오류 발생: /api/status - {e}")
        return jsonify({"error": "주차장 상태를 가져오는 중 오류가 발생했습니다"}), 500


TIME_PERIODS = {
    "morning": {"start": 6, "end": 11, "label": "아침 (06:00-11:59)"},
    "afternoon": {"start": 12, "end": 17, "label": "오후 (12:00-17:59)"},
    "evening": {"start": 18, "end": 21, "label": "저녁 (18:00-21:59)"},
    "night": {"start": 22, "end": 5, "label": "밤 (22:00-05:59)"}
}


def _hourly_averages(cursor, lot_ids, period_condition):
    """시간대별 평균 점유율과 샘플 수 조회"""
    placeholders = ','.join('?' for _ in lot_ids)
    cursor.execute(
        f"""
        SELECT hour, AVG(occupancy_rate), COUNT(*)
        FROM occupancy_rates
        WHERE parking_lot IN ({placeholders}) AND {period_condition}
        GROUP BY hour
        """,
        tuple(lot_ids)
    )
    return {row[0]: (row[1], row[2]) for row in cursor.fetchall()}


def build_statistics(lot_ids):
    """
    DB에 누적된 5분 간격 점유율 샘플로 시간대별 통계를 계산한다.
    각 시간대는 당일 평균을 우선 사용하고, 없으면 최근 7일 평균을 사용한다.
    데이터가 없는 시간대는 임의 값으로 채우지 않고 has_data=false로 표시한다.
    """
    cursor = get_db().cursor()
    current_time = datetime.now()
    current_hour = current_time.hour

    # 현재 상태 (실시간)
    current_status = parking_system.get_parking_status()
    total_spaces = sum(current_status[lot]['total_spaces'] for lot in lot_ids if lot in current_status)
    current_occupied = sum(current_status[lot]['occupied_spaces'] for lot in lot_ids if lot in current_status)
    has_live_data = parking_system.running and any(
        current_status.get(lot, {}).get('spaces') for lot in lot_ids
    )
    current_occupancy_rate = round((current_occupied / total_spaces) * 100, 1) if total_spaces > 0 else 0.0

    today = _hourly_averages(cursor, lot_ids, "date(timestamp) = date('now', 'localtime')")
    week = _hourly_averages(cursor, lot_ids, "timestamp >= datetime('now', 'localtime', '-7 days')")

    hourly = {}
    for hour in range(24):
        if hour == current_hour and has_live_data:
            rate, source, samples = current_occupancy_rate, "live", None
        elif hour in today:
            rate, source, samples = today[hour][0], "today", today[hour][1]
        elif hour in week:
            rate, source, samples = week[hour][0], "week", week[hour][1]
        else:
            rate, source, samples = None, None, 0
        hourly[hour] = {"rate": None if rate is None else round(rate, 1), "source": source, "samples": samples}

    hourly_data_list = [{
        "hour": hour,
        "formatted_time": f"{hour:02d}:00",
        "occupancy_rate": hourly[hour]["rate"] if hourly[hour]["rate"] is not None else 0.0,
        "formatted_rate": f"{round(hourly[hour]['rate'])}%" if hourly[hour]["rate"] is not None else "-",
        "has_data": hourly[hour]["rate"] is not None,
        "source": hourly[hour]["source"],
        "sample_count": hourly[hour]["samples"],
        "is_current": hour == current_hour
    } for hour in range(24)]

    # 추천 시간: 향후 12시간 중 데이터가 있는 시간대에서 점유율이 가장 낮은 시간
    recommendation = None
    for offset in range(1, 13):
        check_hour = (current_hour + offset) % 24
        rate = hourly[check_hour]["rate"]
        if rate is not None and (recommendation is None or rate < recommendation["occupancy_rate"]):
            recommendation = {
                "best_hour": check_hour,
                "formatted_time": f"{check_hour:02d}:00",
                "occupancy_rate": rate,
                "formatted_rate": f"{round(rate)}%"
            }

    # 시간대 구분 (아침, 오후, 저녁, 밤) 평균
    period_rates = {}
    for period_name, info in TIME_PERIODS.items():
        if info["start"] <= info["end"]:
            period_hours = range(info["start"], info["end"] + 1)
        else:  # 밤처럼 날짜를 넘어가는 경우
            period_hours = list(range(info["start"], 24)) + list(range(0, info["end"] + 1))
        rates = [hourly[h]["rate"] for h in period_hours if hourly[h]["rate"] is not None]
        avg_rate = round(sum(rates) / len(rates), 1) if rates else None
        period_rates[period_name] = {
            "label": info["label"],
            "avg_rate": avg_rate if avg_rate is not None else 0.0,
            "formatted_rate": f"{avg_rate}%" if avg_rate is not None else "-",
            "has_data": avg_rate is not None
        }

    return {
        "current": {
            "time": current_time.strftime("%H:%M"),
            "hour": current_hour,
            "occupancy_rate": current_occupancy_rate,
            "formatted_rate": f"{current_occupancy_rate}%",
            "total_spaces": total_spaces,
            "occupied_spaces": current_occupied,
            "available_spaces": total_spaces - current_occupied,
            "is_live": has_live_data
        },
        "hourly_data": hourly_data_list,
        "recommendation": recommendation,
        "time_periods": period_rates,
        "data_coverage": {
            "hours_with_data": sum(1 for h in hourly.values() if h["rate"] is not None),
            "today_hours": len(today),
            "week_hours": len(week)
        }
    }


@app.route('/api/statistics', methods=['GET'])
def get_statistics():
    """전체 주차장 통계 (시간대별 점유율과 추천 시간)"""
    try:
        return jsonify(build_statistics(list(VIDEO_SOURCES.keys())))
    except Exception as e:
        logger.error(f"통계 정보 조회 중 오류 발생: {e}")
        logger.error(traceback.format_exc())
        return jsonify({"error": "통계 정보를 가져오는 중 오류가 발생했습니다"}), 500


@app.route('/api/statistics/<parking_lot_id>', methods=['GET'])
def get_parking_lot_statistics(parking_lot_id):
    """특정 주차장의 통계 정보 반환"""
    try:
        if parking_lot_id not in VIDEO_SOURCES:
            if parking_lot_id not in PARKING_SPACES:
                return jsonify({"error": f"주차장 '{parking_lot_id}'를 찾을 수 없습니다"}), 404
            # 좌표만 있고 영상이 연결되지 않은 주차장
            return jsonify({
                "parking_lot_id": parking_lot_id,
                "has_video": False,
                "message": "아직 영상이 연결되지 않은 주차장입니다",
                "total_spaces": len(PARKING_SPACES.get(parking_lot_id, [])),
            })

        stats = build_statistics([parking_lot_id])
        stats.update({"parking_lot_id": parking_lot_id, "has_video": True})
        return jsonify(stats)

    except Exception as e:
        logger.error(f"주차장 '{parking_lot_id}' 통계 조회 중 오류: {e}")
        logger.error(traceback.format_exc())
        return jsonify({"error": "통계 정보를 가져오는 중 오류가 발생했습니다"}), 500


@app.route('/api/history', methods=['GET'])
def get_history():
    """주차 이력 반환 (days: 조회 기간, parking_lot: 주차장 필터)"""
    try:
        days = max(1, min(request.args.get('days', default=7, type=int), 365))
        parking_lot = request.args.get('parking_lot')

        query = """
            SELECT id, parking_lot, parking_space_id, entry_time, exit_time, vehicle_type
            FROM vehicles
            WHERE entry_time >= datetime('now', 'localtime', ?)
        """
        params = [f'-{days} days']
        if parking_lot:
            query += " AND parking_lot = ?"
            params.append(parking_lot)
        query += " ORDER BY entry_time DESC"

        cursor = get_db().cursor()
        cursor.execute(query, params)

        history = []
        for vehicle_id, lot_id, space_id, entry_time, exit_time, vehicle_type in cursor.fetchall():
            duration = None
            duration_seconds = None

            if entry_time and exit_time:
                try:
                    entry_dt = datetime.fromisoformat(str(entry_time).replace(' ', 'T'))
                    exit_dt = datetime.fromisoformat(str(exit_time).replace(' ', 'T'))
                    duration_seconds = (exit_dt - entry_dt).total_seconds()

                    if duration_seconds < 0:
                        duration = "오류: 음수 시간"
                        logger.warning(f"음수 주차 시간 감지: 차량 ID {vehicle_id}, 주차 공간 {space_id}")
                    elif duration_seconds > 86400:  # 24시간 초과
                        duration = f"{int(duration_seconds // 86400)}일 {int((duration_seconds % 86400) // 3600)}시간"
                    else:
                        hours = int(duration_seconds // 3600)
                        minutes = int((duration_seconds % 3600) // 60)
                        duration = f"{hours}시간 {minutes}분"
                except ValueError as e:
                    duration = "시간 형식 오류"
                    logger.error(f"주차 시간 계산 오류: {e}, 입차: {entry_time}, 출차: {exit_time}")

            history.append({
                "id": vehicle_id,
                "parking_lot": lot_id,
                "space_id": space_id,
                "entry_time": entry_time,
                "exit_time": exit_time,
                "duration": duration,
                "duration_seconds": duration_seconds,
                "vehicle_type": vehicle_type
            })

        return jsonify(history)

    except Exception as e:
        logger.error(f"주차 이력 조회 중 오류 발생: {e}")
        logger.error(traceback.format_exc())
        return jsonify({"error": "주차 이력을 가져오는 중 오류가 발생했습니다"}), 500


# ---------- 관리자 엔드포인트 ----------

@app.route('/api/start', methods=['POST'])
@require_admin
def start_system():
    """시스템 시작"""
    parking_system.start()
    return jsonify({"status": "started"})


@app.route('/api/stop', methods=['POST'])
@require_admin
def stop_system():
    """시스템 중지"""
    parking_system.stop()
    return jsonify({"status": "stopped"})


@app.route('/api/debug', methods=['GET'])
@require_admin
def debug_info():
    """시스템 디버그 정보 반환"""
    model_info = {
        "path": MODEL_PATH,
        "exists": os.path.exists(MODEL_PATH),
        "size": os.path.getsize(MODEL_PATH) if os.path.exists(MODEL_PATH) else None
    }

    video_info = {}
    for name, path in VIDEO_SOURCES.items():
        video_info[name] = {
            "path": path,
            "exists": os.path.exists(path),
            "size": os.path.getsize(path) if os.path.exists(path) else None
        }

    db_info = {}
    try:
        cursor = get_db().cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
        tables = [table[0] for table in cursor.fetchall()]
        db_info = {
            "path": DB_PATH,
            "exists": os.path.exists(DB_PATH),
            "size": os.path.getsize(DB_PATH) if os.path.exists(DB_PATH) else None,
            "tables": tables
        }
        for table in tables:
            cursor.execute(f'SELECT COUNT(*) FROM "{table}"')
            db_info[f"{table}_count"] = cursor.fetchone()[0]
    except Exception as e:
        db_info["error"] = str(e)

    return jsonify({
        "model": model_info,
        "videos": video_info,
        "database": db_info,
        "running": parking_system.running,
        "threads": list(parking_system.video_threads.keys())
    })


@app.route('/api/test_model', methods=['GET'])
@require_admin
def test_model():
    """모델 동작 확인"""
    try:
        test_img = np.zeros((640, 640, 3), dtype=np.uint8)
        cv2.rectangle(test_img, (100, 100), (300, 400), (0, 255, 0), 3)
        results = parking_system.model(test_img)

        return jsonify({
            "status": "success",
            "model_info": {
                "path": MODEL_PATH,
                "task": getattr(parking_system.model, 'task', "unknown"),
                "names": getattr(parking_system.model, 'names', None),
            },
            "detection_count": len(results[0]) if results else 0
        })
    except Exception as e:
        logger.error(f"모델 테스트 실패: {e}")
        logger.error(traceback.format_exc())
        return jsonify({"status": "error", "error": "모델 테스트 중 오류가 발생했습니다"}), 500


# 비디오 스트림 API 엔드포인트
@app.route('/api/stream/<parking_lot>', methods=['GET'])
def stream_video(parking_lot):
    """주차장 비디오 스트림 (MJPEG 포맷)"""
    logger.info(f"스트림 요청 수신: {parking_lot}")

    # 주차장 ID 확인
    if parking_lot not in VIDEO_SOURCES:
        return jsonify({"error": f"주차장 '{parking_lot}'이 존재하지 않습니다"}), 404

    # 현재 프레임이 없는 경우에도 처리
    if parking_lot not in parking_system.current_frames:
        logger.warning(f"주차장 '{parking_lot}'의 현재 프레임이 없습니다. 더미 프레임을 생성합니다.")
        # 더미 프레임 생성
        dummy_frame = np.zeros((480, 640, 3), dtype=np.uint8)
        cv2.putText(dummy_frame, f"Waiting for video: {parking_lot}", (50, 240),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)
        parking_system.current_frames[parking_lot] = dummy_frame

    def generate():
        logger.info(f"스트림 생성기 시작: {parking_lot}")
        while True:
            try:
                if not parking_system.running:
                    logger.info(f"시스템이 중지되어 스트림 종료: {parking_lot}")
                    break

                # 현재 프레임 가져오기 (없으면 더미 프레임 생성)
                if parking_lot in parking_system.current_frames:
                    frame = parking_system.current_frames[parking_lot].copy()
                else:
                    logger.warning(f"프레임 누락: {parking_lot}")
                    frame = np.zeros((480, 640, 3), dtype=np.uint8)
                    cv2.putText(frame, "No video frame available", (50, 240),
                                cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)

                # 화면 크기에 맞게 조정
                height, width = frame.shape[:2]
                max_width = 800  # 최대 너비
                if width > max_width:
                    ratio = max_width / width
                    frame = cv2.resize(frame, (max_width, int(height * ratio)))

                # 이미지를 JPEG로 인코딩
                ret, jpeg = cv2.imencode('.jpg', frame, [int(cv2.IMWRITE_JPEG_QUALITY), 70])
                if not ret:
                    logger.warning("JPEG 인코딩 실패")
                    continue

                # MJPEG 스트림 형식으로 출력
                yield (b'--frame\r\n'
                       b'Content-Type: image/jpeg\r\n\r\n' + jpeg.tobytes() + b'\r\n')

                # 프레임 레이트 조절 (15 FPS)
                time.sleep(1 / 15)

            except Exception as e:
                logger.error(f"스트림 생성 중 오류: {e}")
                time.sleep(0.5)  # 오류 발생 시 짧은 대기

    logger.info(f"스트림 응답 반환: {parking_lot}")
    return Response(generate(),
                    mimetype='multipart/x-mixed-replace; boundary=frame')


@app.route('/api/parking_lots', methods=['GET'])
def get_parking_lots():
    """등록된 주차장 목록 반환"""
    try:
        db = get_db()
        cursor = db.cursor()

        # 주차장 기본 정보 조회
        cursor.execute('''
        SELECT id, name, building, latitude, longitude, capacity, 
               type, has_disabled_spaces, open_hours, description, video_source
        FROM parking_lots
        ORDER BY name
        ''')

        lots = []
        for row in cursor.fetchall():
            lot_id, name, building, latitude, longitude, capacity, type_, has_disabled, open_hours, description, video_source = row

            # 주차 구역 좌표 조회
            cursor.execute('''
            SELECT polygon_index, point_index, latitude, longitude 
            FROM parking_spaces_coords 
            WHERE parking_lot_id = ? 
            ORDER BY polygon_index, point_index
            ''', (lot_id,))

            # 다각형 좌표 구성
            polygons = {}
            for p_row in cursor.fetchall():
                poly_idx, point_idx, lat, lng = p_row
                if poly_idx not in polygons:
                    polygons[poly_idx] = []
                polygons[poly_idx].append({"latitude": lat, "longitude": lng})

            # 주차장 정보 구성
            lot = {
                "id": lot_id,
                "name": name,
                "building": building,
                "latitude": latitude,
                "longitude": longitude,
                "capacity": capacity,
                "type": type_,
                "hasDisabledSpaces": bool(has_disabled),
                "openHours": open_hours,
                "description": description,
                "videoSource": video_source,
                "parkingSpaces": list(polygons.values())  # 다각형 목록으로 변환
            }

            lots.append(lot)

        return jsonify(lots)

    except Exception as e:
        logger.error(f"주차장 목록 조회 중 오류 발생: {e}")
        logger.error(traceback.format_exc())
        return jsonify({"error": str(e)}), 500


@app.route('/api/parking_lots', methods=['POST'])
@require_admin
def add_parking_lot():
    """새 주차장 추가"""
    try:
        if not request.json:
            return jsonify({"error": "요청 본문이 JSON 형식이어야 합니다"}), 400

        lot_data = request.json

        # 필수 필드 검증
        required_fields = ['id', 'name', 'building', 'latitude', 'longitude', 'capacity']
        for field in required_fields:
            if field not in lot_data:
                return jsonify({"error": f"필수 필드 '{field}'가 누락되었습니다"}), 400

        db = get_db()
        cursor = db.cursor()

        # 이미 존재하는 ID인지 확인
        cursor.execute('SELECT id FROM parking_lots WHERE id = ?', (lot_data['id'],))
        if cursor.fetchone():
            return jsonify({"error": f"ID '{lot_data['id']}'가 이미 사용 중입니다"}), 409

        # 주차장 기본 정보 삽입
        cursor.execute('''
        INSERT INTO parking_lots (
            id, name, building, latitude, longitude, capacity, 
            type, has_disabled_spaces, open_hours, description, video_source
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            lot_data['id'],
            lot_data['name'],
            lot_data['building'],
            lot_data['latitude'],
            lot_data['longitude'],
            lot_data['capacity'],
            lot_data.get('type', 'outdoor'),
            1 if lot_data.get('hasDisabledSpaces', False) else 0,
            lot_data.get('openHours', '24시간'),
            lot_data.get('description', ''),
            lot_data.get('videoSource', '')
        ))

        # 주차 구역 좌표 삽입
        if 'parkingSpaces' in lot_data and isinstance(lot_data['parkingSpaces'], list):
            for poly_idx, polygon in enumerate(lot_data['parkingSpaces']):
                for point_idx, point in enumerate(polygon):
                    if 'latitude' in point and 'longitude' in point:
                        cursor.execute('''
                        INSERT INTO parking_spaces_coords (
                            parking_lot_id, polygon_index, point_index, latitude, longitude
                        ) VALUES (?, ?, ?, ?, ?)
                        ''', (
                            lot_data['id'],
                            poly_idx,
                            point_idx,
                            point['latitude'],
                            point['longitude']
                        ))

        db.commit()

        # 새로운 주차장 정보 반환
        return jsonify({
            "id": lot_data['id'],
            "message": "주차장이 성공적으로 추가되었습니다"
        }), 201

    except Exception as e:
        logger.error(f"주차장 추가 중 오류 발생: {e}")
        logger.error(traceback.format_exc())
        return jsonify({"error": str(e)}), 500


@app.route('/api/parking_lots/<lot_id>', methods=['PUT'])
@require_admin
def update_parking_lot(lot_id):
    """주차장 정보 업데이트"""
    try:
        if not request.json:
            return jsonify({"error": "요청 본문이 JSON 형식이어야 합니다"}), 400

        lot_data = request.json

        db = get_db()
        cursor = db.cursor()

        # 주차장 존재 여부 확인
        cursor.execute('SELECT id FROM parking_lots WHERE id = ?', (lot_id,))
        if not cursor.fetchone():
            return jsonify({"error": f"ID '{lot_id}'인 주차장을 찾을 수 없습니다"}), 404

        # 주차장 기본 정보 업데이트
        cursor.execute('''
        UPDATE parking_lots SET
            name = ?,
            building = ?,
            latitude = ?,
            longitude = ?,
            capacity = ?,
            type = ?,
            has_disabled_spaces = ?,
            open_hours = ?,
            description = ?,
            video_source = ?,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
        ''', (
            lot_data.get('name'),
            lot_data.get('building'),
            lot_data.get('latitude'),
            lot_data.get('longitude'),
            lot_data.get('capacity'),
            lot_data.get('type', 'outdoor'),
            1 if lot_data.get('hasDisabledSpaces', False) else 0,
            lot_data.get('openHours', '24시간'),
            lot_data.get('description', ''),
            lot_data.get('videoSource', ''),
            lot_id
        ))

        # 기존 주차 구역 좌표 삭제
        cursor.execute('DELETE FROM parking_spaces_coords WHERE parking_lot_id = ?', (lot_id,))

        # 새 주차 구역 좌표 삽입
        if 'parkingSpaces' in lot_data and isinstance(lot_data['parkingSpaces'], list):
            for poly_idx, polygon in enumerate(lot_data['parkingSpaces']):
                for point_idx, point in enumerate(polygon):
                    if 'latitude' in point and 'longitude' in point:
                        cursor.execute('''
                        INSERT INTO parking_spaces_coords (
                            parking_lot_id, polygon_index, point_index, latitude, longitude
                        ) VALUES (?, ?, ?, ?, ?)
                        ''', (
                            lot_id,
                            poly_idx,
                            point_idx,
                            point['latitude'],
                            point['longitude']
                        ))

        db.commit()

        return jsonify({
            "id": lot_id,
            "message": "주차장 정보가 성공적으로 업데이트되었습니다"
        })

    except Exception as e:
        logger.error(f"주차장 업데이트 중 오류 발생: {e}")
        logger.error(traceback.format_exc())
        return jsonify({"error": str(e)}), 500


@app.route('/api/parking_lots/<lot_id>', methods=['DELETE'])
@require_admin
def delete_parking_lot(lot_id):
    """주차장 삭제"""
    try:
        db = get_db()
        cursor = db.cursor()

        # 주차장 존재 여부 확인
        cursor.execute('SELECT id FROM parking_lots WHERE id = ?', (lot_id,))
        if not cursor.fetchone():
            return jsonify({"error": f"ID '{lot_id}'인 주차장을 찾을 수 없습니다"}), 404

        # 주차 구역 좌표 삭제 (외래 키 제약 조건이 있는 경우 자동으로 삭제됨)
        cursor.execute('DELETE FROM parking_spaces_coords WHERE parking_lot_id = ?', (lot_id,))

        # 주차장 삭제
        cursor.execute('DELETE FROM parking_lots WHERE id = ?', (lot_id,))

        # 동적으로 추가한 주차장이면 영상 처리도 중단 (처리 루프가 VIDEO_SOURCES에서 빠진 것을 감지하고 종료)
        if lot_id not in BUILTIN_LOTS:
            cursor.execute('DELETE FROM parking_space_polygons WHERE parking_lot_id = ?', (lot_id,))
            VIDEO_SOURCES.pop(lot_id, None)
            PARKING_SPACES.pop(lot_id, None)
            parking_system.reset_lot_state(lot_id)

        db.commit()

        return jsonify({
            "id": lot_id,
            "message": "주차장이 성공적으로 삭제되었습니다"
        })

    except Exception as e:
        logger.error(f"주차장 삭제 중 오류 발생: {e}")
        logger.error(traceback.format_exc())
        return jsonify({"error": str(e)}), 500


# 동적 주차장 관리
@app.route('/api/parking_lots/dynamic', methods=['POST'])
@require_admin
def add_dynamic_parking_lot():
    """
    영상이 연결된 주차장을 동적으로 추가.
    video_path는 VIDEOS_DIR 안의 파일 또는 rtsp/http 스트림 URL만 허용한다.
    coordinates는 비워 두고 나중에 좌표 파일 업로드 API로 설정할 수 있다.
    """
    try:
        lot_data = request.get_json(silent=True)
        if not lot_data:
            return jsonify({"error": "요청 본문이 JSON 형식이어야 합니다"}), 400

        for field in ['id', 'name', 'video_path']:
            if field not in lot_data:
                return jsonify({"error": f"필수 필드 '{field}'가 누락되었습니다"}), 400

        parking_lot_id = lot_data['id']
        if not _valid_lot_id(parking_lot_id):
            return jsonify({"error": "주차장 ID는 영문, 숫자, '_', '-'로 이루어진 64자 이하 문자열이어야 합니다"}), 400

        if parking_lot_id in VIDEO_SOURCES:
            return jsonify({"error": f"주차장 ID '{parking_lot_id}'가 이미 존재합니다"}), 409

        video_source = resolve_video_source(lot_data['video_path'])
        if not video_source:
            return jsonify({
                "error": "영상 소스를 사용할 수 없습니다. 서버의 videos 디렉터리 안에 있는 파일 이름 또는 "
                         "rtsp/http 스트림 주소를 입력하세요"
            }), 400

        try:
            coordinates = normalize_spaces(lot_data.get('coordinates') or [])
        except ValueError as e:
            return jsonify({"error": str(e)}), 400

        db = get_db()
        db.execute('''
        INSERT INTO parking_lots (
            id, name, building, latitude, longitude, capacity,
            type, has_disabled_spaces, open_hours, description, video_source
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            name = excluded.name,
            video_source = excluded.video_source,
            capacity = excluded.capacity,
            updated_at = CURRENT_TIMESTAMP
        ''', (
            parking_lot_id,
            lot_data.get('name', f'주차장 {parking_lot_id}'),
            lot_data.get('building', ''),
            lot_data.get('latitude', 0.0),
            lot_data.get('longitude', 0.0),
            len(coordinates),
            lot_data.get('type', 'outdoor'),
            1 if lot_data.get('hasDisabledSpaces', False) else 0,
            lot_data.get('openHours', '24시간'),
            lot_data.get('description', ''),
            video_source
        ))
        save_space_polygons(db, parking_lot_id, coordinates)
        db.commit()

        parking_system.add_parking_lot(parking_lot_id, video_source, coordinates)

        return jsonify({
            "status": "success",
            "message": f"주차장 '{parking_lot_id}'가 성공적으로 추가되었습니다",
            "parking_lot_id": parking_lot_id,
            "total_spaces": len(coordinates)
        }), 201

    except Exception as e:
        logger.error(f"동적 주차장 추가 중 오류 발생: {e}")
        logger.error(traceback.format_exc())
        return jsonify({"error": "주차장 추가 중 오류가 발생했습니다"}), 500


def parse_coordinates_file(file_ext, content):
    """좌표 파일 파싱. JSON: {"coordinates": [...]}, TXT/CSV: 'A1,x1,y1,x2,y2,...' 한 줄에 한 주차면"""
    if file_ext == '.json':
        data = json.loads(content)
        if isinstance(data, list):
            return normalize_spaces(data)
        return normalize_spaces(data.get('coordinates', data.get('parking_spaces', [])))

    spaces = []
    for line_no, line in enumerate(content.splitlines(), start=1):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        parts = [part.strip() for part in line.split(',')]
        if len(parts) < 7 or len(parts) % 2 == 0:
            raise ValueError(f"{line_no}번째 줄: 'ID,x1,y1,x2,y2,x3,y3[,...]' 형식이어야 합니다")
        try:
            values = [int(float(v)) for v in parts[1:]]
        except ValueError:
            raise ValueError(f"{line_no}번째 줄: 좌표는 숫자여야 합니다")
        spaces.append({"id": parts[0], "coords": [[values[i], values[i + 1]] for i in range(0, len(values), 2)]})
    return normalize_spaces(spaces)


@app.route('/api/parking_lots/<lot_id>/coordinates', methods=['POST'])
@require_admin
def upload_coordinates_file(lot_id):
    """주차면 좌표 파일 업로드 (TXT, CSV, JSON 형식 지원). 업로드한 좌표는 DB에 저장되어 재시작 후에도 유지된다"""
    try:
        if lot_id not in VIDEO_SOURCES and lot_id not in PARKING_SPACES:
            return jsonify({"error": f"주차장 '{lot_id}'를 찾을 수 없습니다"}), 404

        if 'file' not in request.files:
            return jsonify({"error": "파일이 업로드되지 않았습니다"}), 400

        file = request.files['file']
        if file.filename == '':
            return jsonify({"error": "파일이 선택되지 않았습니다"}), 400

        file_ext = os.path.splitext(file.filename)[1].lower()
        if file_ext not in {'.txt', '.csv', '.json'}:
            return jsonify({"error": "지원되는 파일 형식: .txt, .csv, .json"}), 400

        try:
            coordinates = parse_coordinates_file(file_ext, file.read().decode('utf-8'))
        except (ValueError, UnicodeDecodeError) as e:
            return jsonify({"error": f"좌표 파일을 해석할 수 없습니다: {e}"}), 400

        if not coordinates:
            return jsonify({"error": "유효한 좌표를 찾을 수 없습니다"}), 400

        db = get_db()
        save_space_polygons(db, lot_id, coordinates)
        db.execute("UPDATE parking_lots SET capacity = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
                   (len(coordinates), lot_id))
        db.commit()

        PARKING_SPACES[lot_id] = coordinates
        parking_system.reset_lot_state(lot_id)

        return jsonify({
            "status": "success",
            "message": f"주차장 '{lot_id}'의 좌표가 업데이트되었습니다",
            "total_spaces": len(coordinates)
        })

    except Exception as e:
        logger.error(f"좌표 파일 업로드 중 오류 발생: {e}")
        logger.error(traceback.format_exc())
        return jsonify({"error": "좌표 파일 업로드 중 오류가 발생했습니다"}), 500


def _console_exit_requested():
    """Windows 콘솔에서 'x' 키 입력 확인 (다른 OS에서는 Ctrl+C 사용)"""
    if os.name != 'nt':
        return False
    import msvcrt
    return msvcrt.kbhit() and msvcrt.getch() == b'x'


def main():
    """메인 함수"""
    global ADMIN_TOKEN, parking_system

    parser = argparse.ArgumentParser(description='대학교 주차장 관리 시스템')
    parser.add_argument('--host', type=str, default='0.0.0.0', help='호스트 IP')
    parser.add_argument('--port', type=int, default=5000, help='포트 번호')
    parser.add_argument('--debug', action='store_true', help='디버그 모드 활성화')
    parser.add_argument('--frame-skip', type=int, default=5, help='추론할 프레임 간격 (기본 5: 5프레임 중 1프레임 추론)')
    parser.add_argument('--log-level', type=str, default='INFO',
                        choices=['DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL'],
                        help='로그 레벨 설정')
    parser.add_argument('--show-video', action='store_true', help='영상 표시 활성화 (기본값, 이전 버전 호환용)')
    parser.add_argument('--no-video', action='store_true', help='영상 표시 비활성화 (서버/헤드리스 환경)')
    args = parser.parse_args()

    logger.setLevel(getattr(logging, args.log_level))

    if args.frame_skip < 1:
        parser.error('--frame-skip은 1 이상이어야 합니다')

    if not ADMIN_TOKEN:
        ADMIN_TOKEN = secrets.token_urlsafe(16)
        logger.warning(f"ADMIN_TOKEN 환경 변수가 없어 임시 관리자 토큰을 생성했습니다: {ADMIN_TOKEN}")

    # 데이터베이스 초기화 및 설정 로드
    init_db()
    setup_video_sources()
    load_persisted_parking_lots()

    show_video = not args.no_video

    try:
        parking_system = ParkingSystem(show_video=show_video)
    except (FileNotFoundError, ImportError) as e:
        logger.error(str(e))
        sys.exit(1)

    parking_system.frame_skip = args.frame_skip

    logger.info("주차장 관리 시스템 시작 중...")
    logger.info(f"모델 경로: {MODEL_PATH}")
    logger.info(f"비디오 소스: {VIDEO_SOURCES}")
    logger.info(f"영상 표시: {'활성화' if show_video else '비활성화'}, 프레임 간격: {args.frame_skip}")

    parking_system.start()

    # Flask는 별도 스레드에서 실행하고, 메인 스레드는 화면 표시(OpenCV GUI)와 종료 신호를 담당
    server_thread = threading.Thread(
        target=lambda: app.run(host=args.host, port=args.port, debug=args.debug, threaded=True, use_reloader=False),
        daemon=True
    )
    server_thread.start()

    try:
        while parking_system.running:
            if parking_system.show_video:
                parking_system.update_display()
                time.sleep(0.03)
            else:
                time.sleep(0.5)

            if _console_exit_requested():
                logger.info("사용자가 콘솔에서 'x' 키를 눌러 종료합니다")
                break
    except KeyboardInterrupt:
        logger.info("키보드 인터럽트로 프로그램 종료")
    finally:
        logger.info("프로그램 종료 중...")
        parking_system.cleanup()
        logger.info("시스템 정리 완료")


if __name__ == "__main__":
    main()
