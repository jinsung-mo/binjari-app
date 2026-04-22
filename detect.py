import cv2
from ultralytics import YOLO
import os

# 경로 설정
model_path = r"C:\Users\user\Desktop\Flutter\final.pt"
video_path = r"C:\Users\user\Desktop\Flutter\parking_best.mp4"
output_path = r"C:\Users\user\Desktop\Flutter\library_detect.mp4"

# 파일 존재 확인
if not os.path.exists(model_path):
    print(f"모델 파일을 찾을 수 없습니다: {model_path}")
    exit()

if not os.path.exists(video_path):
    print(f"동영상 파일을 찾을 수 없습니다: {video_path}")
    exit()

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
        progress = (frame_count / total_frames) * 100
        print(f"진행률: {progress:.1f}% ({frame_count}/{total_frames})")

# 리소스 해제
cap.release()
out.release()
cv2.destroyAllWindows()

print(f"\nDetection 완료! 결과 동영상이 저장되었습니다: {output_path}")

# 선택사항: 결과 동영상 재생
play_result = input("\n결과 동영상을 바로 재생하시겠습니까? (y/n): ")
if play_result.lower() == 'y':
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