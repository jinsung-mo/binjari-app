# BINJARI API 명세

Flask 서버 [`app_v1.py`](../app_v1.py)의 현재 라우트를 기준으로 작성했습니다. 기본 주소는 `http://localhost:5000`이며 실행 시 `--host`, `--port`로 변경할 수 있습니다.

## 공통 규칙

| 항목 | 규칙 |
| --- | --- |
| 형식 | 별도 표시가 없으면 요청·응답은 JSON |
| 관리자 인증 | 관리자 엔드포인트에 `X-Admin-Token: <ADMIN_TOKEN>` 헤더 필요 |
| 인증 실패 | 토큰이 없거나 다르면 `401`과 `{"error":"관리자 인증이 필요합니다"}` 반환 |
| 오류 형식 | 일반적으로 `{"error":"오류 내용"}`. 상태 코드는 엔드포인트별로 다름 |
| 주차장 ID | 기본 분석 대상은 `parking_lot_A`(55호관), `parking_lot_B`(도서관) |

`ADMIN_TOKEN`을 환경 변수로 지정하지 않으면 서버가 시작할 때 임시 토큰을 생성합니다. 아래 예시는 형식을 보여주기 위한 것이며 실제 주차 현황이 아닙니다.

## 엔드포인트 목록

| 구분 | 메서드·경로 | 인증 | 주요 응답 |
| --- | --- | --- | --- |
| 상태 확인 | `GET /api/health` | 없음 | 서버·모니터링 실행 상태 |
| 현재 현황 | `GET /api/status` | 없음 | 주차장별 주차면 상태·점유율 |
| 전체 통계 | `GET /api/statistics` | 없음 | 전체 분석 대상의 시간대별 점유율 |
| 주차장 통계 | `GET /api/statistics/<parking_lot_id>` | 없음 | 해당 주차장의 시간대별 점유율 |
| 입·출차 이력 | `GET /api/history` | 없음 | 기간·주차장별 입·출차 기록 |
| 영상 | `GET /api/stream/<parking_lot>` | 없음 | MJPEG 영상 스트림 |
| 주차장 목록 | `GET /api/parking_lots` | 없음 | DB에 등록된 주차장 메타데이터 |
| 토큰 확인 | `GET /api/auth/check` | 관리자 | `{"status":"ok"}` |
| 분석 제어 | `POST /api/start`, `POST /api/stop` | 관리자 | `started` / `stopped` |
| 주차장 메타데이터 | `POST /api/parking_lots`, `PUT·DELETE /api/parking_lots/<lot_id>` | 관리자 | 등록·수정·삭제 결과 |
| 영상 연결 주차장 | `POST /api/parking_lots/dynamic` | 관리자 | 분석 대상 추가 결과 |
| 주차면 좌표 | `POST /api/parking_lots/<lot_id>/coordinates` | 관리자 | 업로드한 주차면 수 |
| 운영 진단 | `GET /api/debug`, `GET /api/test_model` | 관리자 | 경로·DB 상태 / 모델 호출 결과 |

## 조회 API

### `GET /api/health`

서버 연결과 분석 실행 여부를 확인합니다.

```json
{"status":"ok","running":true,"parking_lots":["parking_lot_A","parking_lot_B"]}
```

`running`은 분석 시스템의 시작·중지 상태입니다. 서버가 응답한다는 사실과 실제 모델 추론이 정상이라는 사실은 구분해야 합니다.

### `GET /api/status`

응답은 **주차장 ID를 키로 하는 객체**입니다. 각 값에는 `total_spaces`, `occupied_spaces`, `available_spaces`, `occupancy_rate`, `spaces`가 들어갑니다.

```json
{
  "parking_lot_A": {
    "total_spaces": 20,
    "occupied_spaces": 1,
    "available_spaces": 19,
    "occupancy_rate": 5.0,
    "spaces": [{"id":"A1","status":"occupied","vehicle_type":"car"}]
  }
}
```

`spaces`에는 아직 판정 결과가 없는 면이 빠질 수 있습니다. 서버 라우트에는 주차장 필터 쿼리가 없으며, Flutter 클라이언트는 전체 응답에서 원하는 주차장을 선택합니다. [구현](../app_v1.py#L1412-L1434)

### `GET /api/statistics` · `GET /api/statistics/<parking_lot_id>`

전체 또는 한 주차장의 통계를 반환합니다. 응답의 핵심 필드는 다음과 같습니다.

| 필드 | 형식 | 의미 |
| --- | --- | --- |
| `current` | 객체 | 현재 시각·시간대, 점유율, 전체·점유·가용 면수, `is_live` |
| `hourly_data` | 배열(24개) | 시간(`hour`), 점유율, `has_data`, 출처(`source`), 샘플 수 |
| `recommendation` | 객체 또는 `null` | 향후 12시간 중 관측 데이터가 있는 최저 점유율 시간 |
| `time_periods` | 객체 | 아침·오후·저녁·밤 평균 점유율과 데이터 유무 |
| `data_coverage` | 객체 | 데이터가 있는 시간 수, 당일·최근 7일 시간 수 |
| `parking_lot_id`, `has_video` | 개별 주차장 응답 | 주차장 식별자와 영상 연결 여부 |

`hourly_data[].source`는 `live`, `today`, `week`, `null` 중 하나입니다. 기록이 없는 시간은 `has_data=false`, `formatted_rate="-"`이며 `occupancy_rate`는 화면 호환을 위해 `0.0`으로 전달됩니다. 따라서 **0.0만 보고 실제 점유율 0%로 해석하면 안 됩니다.** 추천할 시간대가 없으면 `recommendation=null`입니다. [집계 로직](../app_v1.py#L1602-L1689)

개별 주차장 ID가 영상 소스에는 없지만 좌표 목록에만 있으면 `has_video=false`와 메시지·주차면 수만 반환합니다. 존재하지 않는 ID는 `404`입니다.

### `GET /api/history`

| 쿼리 | 기본값 | 설명 |
| --- | --- | --- |
| `days` | `7` | 조회 기간. 정수로 읽은 뒤 1~365 사이로 제한 |
| `parking_lot` | 없음 | 특정 주차장 ID로 필터 |

응답은 `id`, `parking_lot`, `space_id`, `entry_time`, `exit_time`, `duration`, `duration_seconds`, `vehicle_type`을 가진 객체의 배열입니다. 아직 출차하지 않은 기록은 `exit_time`과 주차 시간이 `null`일 수 있습니다. [구현](../app_v1.py#L1734-L1790)

### `GET /api/stream/<parking_lot>`

`Content-Type: multipart/x-mixed-replace; boundary=frame`으로 MJPEG 프레임을 보냅니다. 주차장 ID가 영상 소스에 없으면 `404`입니다. 프레임 준비 전에는 대기 화면이 전송될 수 있습니다. [구현](../app_v1.py#L1885-L1946)

### `GET /api/parking_lots`

DB에 등록된 주차장 메타데이터 배열을 반환합니다. 객체에는 `id`, `name`, `building`, `latitude`, `longitude`, `capacity`, `type`, `hasDisabledSpaces`, `openHours`, `description`, `videoSource`, `parkingSpaces`가 들어갑니다. `parkingSpaces`는 **지도 위경도 다각형**입니다. 영상 속 픽셀 좌표는 별도 업로드 API로 관리합니다. 이 목록은 현재 분석 중인 영상 소스 목록과 동일한 개념이 아닙니다. [구현](../app_v1.py#L1949-L2007)

## 관리자 API

모든 요청에 `X-Admin-Token` 헤더가 필요합니다.

### 인증·분석 제어

| 요청 | 성공 응답 | 비고 |
| --- | --- | --- |
| `GET /api/auth/check` | `200 {"status":"ok"}` | 토큰 확인 |
| `POST /api/start` | `200 {"status":"started"}` | 모니터링 시작 |
| `POST /api/stop` | `200 {"status":"stopped"}` | 모니터링 중지 |

### 주차장 메타데이터 CRUD

`POST /api/parking_lots`의 필수 JSON 필드는 `id`, `name`, `building`, `latitude`, `longitude`, `capacity`입니다. 선택 필드는 `type`, `hasDisabledSpaces`, `openHours`, `description`, `videoSource`, `parkingSpaces`입니다. `parkingSpaces`는 각 다각형의 `[{"latitude": ..., "longitude": ...}, ...]` 목록입니다.

| 요청 | 성공 | 주요 오류·주의 |
| --- | --- | --- |
| `POST /api/parking_lots` | `201 {"id":"...","message":"..."}` | 필수 필드 누락 `400`, ID 중복 `409`. 메타데이터 등록만으로 분석 영상이 연결되지는 않음 |
| `PUT /api/parking_lots/<lot_id>` | `200 {"id":"...","message":"..."}` | ID 없음 `404`. 전달하지 않은 속성은 `null` 또는 기본값으로 갱신될 수 있으므로 전체 객체 전달 권장 |
| `DELETE /api/parking_lots/<lot_id>` | `200 {"id":"...","message":"..."}` | ID 없음 `404`. 기본 제공 주차장의 메타데이터 삭제는 영상 처리 중단과 별개 |

### 영상 연결 주차장 추가

`POST /api/parking_lots/dynamic`은 메타데이터와 **분석할 영상 소스**를 함께 등록합니다.

```json
{
  "id": "parking_lot_C",
  "name": "추가 주차장",
  "video_path": "sample.mp4",
  "coordinates": [
    {"id": "A1", "coords": [[10, 10], [100, 10], [100, 80], [10, 80]]}
  ]
}
```

필수 필드는 `id`, `name`, `video_path`입니다. `video_path`는 서버의 `VIDEOS_DIR` 안에 존재하는 파일 또는 `rtsp://`, `http://`, `https://` 스트림 URL이어야 합니다. `coordinates`는 비워 두고 나중에 업로드할 수 있습니다. 성공 시 `201`과 `parking_lot_id`, `total_spaces` 등을 반환하며, 필수 필드·영상 소스·좌표 오류는 `400`, 분석 대상 ID 중복은 `409`입니다. [구현](../app_v1.py#L2205-L2280)

### 영상 속 주차면 좌표 업로드

`POST /api/parking_lots/<lot_id>/coordinates`는 `multipart/form-data`의 `file` 필드를 받습니다. 확장자는 `.json`, `.txt`, `.csv`를 지원합니다.

- JSON: `[{"id":"A1","coords":[[10,10],[100,10],[100,80]]}]` 또는 `{"coordinates":[...]}`
- TXT/CSV: 주차면마다 한 줄씩 `A1,10,10,100,10,100,80`

각 주차면은 고유 ID와 최소 3개의 `(x, y)` 점이 필요합니다. 성공 시 `200`과 `total_spaces`를 반환하고 좌표는 DB에 저장됩니다. 주차장 없음 `404`, 파일 누락·형식·좌표 오류 `400`입니다. [구현](../app_v1.py#L2283-L2352)

### 운영 진단

`GET /api/debug`는 모델·영상·DB 경로와 테이블 수 등 운영 정보를 반환합니다. `GET /api/test_model`은 생성한 테스트 이미지로 **모델 호출 가능 여부**를 확인하며 실제 주차장 탐지 정확도를 측정하지 않습니다. 두 엔드포인트 모두 관리자 토큰이 필요합니다. [구현](../app_v1.py#L1816-L1881)

## 호출 예시

```bash
curl http://localhost:5000/api/health
curl http://localhost:5000/api/status
curl 'http://localhost:5000/api/history?days=7&parking_lot=parking_lot_A'
curl -X POST -H 'X-Admin-Token: <ADMIN_TOKEN>' http://localhost:5000/api/stop
```

기능 범위와 수용 기준은 [요구사항 명세](REQUIREMENTS.md)를 참고하세요.
