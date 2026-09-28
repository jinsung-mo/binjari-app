"""
영상 파일에 YOLO 탐지 결과를 그려 새 영상으로 저장하는 단독 스크립트

사용 예:
    python detect.py --model models/best.pt --video videos/library2.mp4 --output library_detect.mp4
"""
import argparse
import os
import sys

import cv2
from ultralytics import YOLO

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

parser = argparse.ArgumentParser(description='영상 YOLO 탐지 결과 저장')
parser.add_argument('--model', default=os.getenv('MODEL_PATH', os.path.join(BASE_DIR, 'models', 'best.pt')),
                    help='YOLO 가중치 경로 (기본: models/best.pt 또는 MODEL_PATH 환경 변수)')
parser.add_argument('--video', default=os.path.join(BASE_DIR, 'videos', 'library2.mp4'), help='입력 영상 경로')
parser.add_argument('--output', default='detect_result.mp4', help='결과 영상 저장 경로')
parser.add_argument('--play', action='store_true', help='저장 후 결과 영상 재생')
args = parser.parse_args()

model_path = args.model
video_path = args.video
output_path = args.output

# 파일 존재 확인
if not os.path.exists(model_path):
    print(f"모델 파일을 찾을 수 없습니다: {model_path}")
    sys.exit(1)

if not os.path.exists(video_path):
    print(f"동영상 파일을 찾을 수 없습니다: {video_path}")
    sys.exit(1)

# YOLO 모델 로드
print("YOLO 모델을 로드하는 중...")
model = YOLO(model_path)

# 동영상 파일 읽기
cap = cv2.VideoCapture(video_path)

# 동영상 정보 가져오기
fps = int(cap.get(cv2.CAP_PROP_FPS))
width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

print(f"동영상 정보: {width}x{height}, {fps} FPS, 총 {total_frames} 프레임")

# 출력 동영상 설정
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter(output_path, fourcc, fps, (width, height))

frame_count = 0

print("동영상 detection을 시작합니다...")

while True:
    ret, frame = cap.read()

    if not ret:
        break

    frame_count += 1

    # YOLO로 detection 수행
    results = model(frame)

    # detection 결과를 프레임에 그리기
    annotated_frame = results[0].plot()

    # 결과 프레임을 출력 파일에 쓰기
    out.write(annotated_frame)

    # 진행률 표시
    if frame_count % 30 == 0:
        progress = (frame_count / total_frames) * 100 if total_frames > 0 else 0
        print(f"진행률: {progress:.1f}% ({frame_count}/{total_frames})")

# 리소스 해제
cap.release()
out.release()
cv2.destroyAllWindows()

print(f"\nDetection 완료! 결과 동영상이 저장되었습니다: {output_path}")

# 선택사항: 결과 동영상 재생
if args.play:
    cap_result = cv2.VideoCapture(output_path)

    print("\n동영상을 재생합니다. 'q'를 눌러 종료하세요.")

    while True:
        ret, frame = cap_result.read()

        if not ret:
            break

        # 화면 크기에 맞게 조정 (선택사항)
        height_display = 600
        width_display = int(frame.shape[1] * (height_display / frame.shape[0]))
        frame_resized = cv2.resize(frame, (width_display, height_display))

        cv2.imshow('Detection Result', frame_resized)

        if cv2.waitKey(1) & 0xFF == ord('q'):
            break

    cap_result.release()
    cv2.destroyAllWindows()