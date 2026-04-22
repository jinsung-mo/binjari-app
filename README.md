# 창원대학교 스마트 주차장 모니터링 서비스 - 빈자리 (Binjari)

창원대학교 캠퍼스 내 주차장의 실시간 현황을 모니터링하고, 사용자에게 빈자리 정보를 제공하는 스마트 주차장 시스템의 프론트엔드 어플리케이션입니다.

## 주요 기능

- 실시간 캠퍼스 맵: 창원대학교 캠퍼스 지도를 기반으로 각 주차장의 위치와 실시간 빈자리 상태를 시각적으로 확인합니다.
- 주차 통계: 기간별 주차장 이용률 및 통계 데이터를 차트로 시각화하여 제공합니다.
- 관리자 모드: 주차장 설정 변경, 시스템 구성 및 데이터 관리를 위한 관리 전용 인터페이스를 제공합니다.
- 멀티 플랫폼 지원: Flutter를 사용하여 Android, iOS, Web은 물론 Windows, macOS, Linux 데스크톱 환경을 모두 지원합니다.

## 프로젝트 구조

- lib/screens/: 홈, 캠퍼스 맵, 통계, 관리자 화면 등 주요 UI 구현
- lib/services/: 위치 서비스, 주차 데이터 API 호출, 관리자 설정 등 비즈니스 로직
- lib/models/: 주차장 구성 및 설정 데이터 모델
- lib/widgets/: 재사용 가능한 지도 위젯 및 공통 UI 컴포넌트

## 시작하기

### 필수 요구 사항
- Flutter SDK (Latest Stable)
- Dart SDK

### 설치 및 실행
1. 저장소를 클론합니다.
   ```bash
   git clone https://github.com/jinsung-mo/binjari-app.git
   ```
2. 패키지를 설치합니다.
   ```bash
   flutter pub get
   ```
3. 어플리케이션을 실행합니다.
   ```bash
   flutter run
   ```

## 기술 스택
- Framework: Flutter (Dart)
- State Management: Provider / StatefulWidget
- Visualization: CustomPainter (Bar Chart)
- Backend Integration: Python-based Detection Server

---
© 2024 Jinsung Mo. All rights reserved.
