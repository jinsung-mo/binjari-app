// config/app_config.dart
// 앱 설정 (API URL 등) - 다중 주차장 지원 및 동적 관리 기능 추가

class AppConfig {
  // API 베이스 URL - 환경에 맞게 주석 해제하여 사용
  //static String baseUrl = 'http://10.0.2.2:5000'; // Android 에뮬레이터용
  // static String baseUrl = 'http://localhost:5000';  // iOS 시뮬레이터용
  // static String baseUrl = 'http://127.0.0.1:5000'; // 로컬 테스트용
  static String baseUrl = 'http://10.100.142.97:5000'; // 특정 IP 서버용

  // API 엔드포인트
  static String statusEndpoint = '$baseUrl/api/status';
  static String statisticsEndpoint = '$baseUrl/api/statistics';
  static String historyEndpoint = '$baseUrl/api/history';
  static String startSystemEndpoint = '$baseUrl/api/start';
  static String stopSystemEndpoint = '$baseUrl/api/stop';
  static String debugEndpoint = '$baseUrl/api/debug';
  static String parkingLotsEndpoint = '$baseUrl/api/parking_lots';
  static String dynamicParkingLotsEndpoint = '$baseUrl/api/parking_lots/dynamic'; // 동적 추가
  static String uploadCoordinatesEndpoint = '$baseUrl/api/parking_lots'; // 좌표 업로드

  // Google Maps API 키
  static String googleMapsApiKey = 'AIzaSyBqClpv6rBxd0zPxDkk-HuJFGERzNbsQAU';

  // 앱 테마 색상
  static const primaryColorHex = 0xFF1976D2; // 파란색 계열
  static const secondaryColorHex = 0xFF4CAF50; // 녹색 계열

  // 앱 버전
  static const appVersion = '1.1.0'; // 버전 업데이트

  // 주차장 새로고침 간격 (초)
  static const refreshInterval = 10;

  // 연결 설정
  static const connectionTimeout = 15; // 연결 타임아웃 (초)
  static const receiveTimeout = 15; // 수신 타임아웃 (초)
  static const maxRetries = 3; // 최대 재시도 횟수

  // 창원대학교 위치 정보
  static const changwonUniversity = {
    'name': '창원대학교',
    'latitude': 35.2456,
    'longitude': 128.6969,
    'address': '경남 창원시 의창구 창원대학로 20',
  };

  // 주차장 위치 정보 - 도서관 추가 및 확장 가능한 구조
  static const Map<String, Map<String, dynamic>> parkingLocations = {
    'parking_lot_A': {
      'name': '55호관 주차장',
      'building': '공과대학 55호관',
      'latitude': 35.241343,
      'longitude': 128.695526,
      'capacity': 20,
      'type': 'outdoor',
      'hasDisabledSpaces': true,
      'openHours': '24시간',
      'description': '공과대학 55호관 앞 주차장으로, 학생 및 교직원을 위한 공용 주차장입니다.',
      'hasVideo': true,
      'status': 'active',
      'videoWidth': 1444,
      'videoHeight': 973,
    },
    'parking_lot_B': {
      'name': '도서관 주차장',
      'building': '중앙도서관',
      'latitude': 35.245288,
      'longitude': 128.690894,
      'capacity': 37, // A1-A12 (12개) + B1-B10 (10개) + C1-C8 (8개) + D1-D7 (7개)
      'type': 'outdoor',
      'hasDisabledSpaces': true,
      'openHours': '06:00 - 23:00',
      'description': '중앙도서관 옆에 위치한 주차장으로, 전기차 및 장애인 전용 주차 공간을 포함합니다.',
      'hasVideo': true,
      'status': 'active',
      'videoWidth': 1170,
      'videoHeight': 694,
      'specialSpaces': {
        'electric': ['D4electric', 'D5electric'], // 전기차 전용
        'disabled': ['D6disabled', 'D7disabled'], // 장애인 전용
      }
    },
    'parking_lot_C': {
      'name': '대학본부 주차장',
      'building': '대학본부',
      'latitude': 35.245381,
      'longitude': 128.692272,
      'capacity': 30,
      'type': 'outdoor',
      'hasDisabledSpaces': true,
      'openHours': '24시간',
      'description': '대학 본부 근처에 위치한 주차장으로, 주로 교직원과 방문객을 위한 주차장입니다.',
      'hasVideo': false, // 아직 영상이 연결되지 않음
      'status': 'no_video',
      'videoWidth': 640,
      'videoHeight': 480,
    },
    'parking_lot_D': {
      'name': '53호관 주차장',
      'building': '공과대학 53호관',
      'latitude': 35.240980,
      'longitude': 128.698414,
      'capacity': 18,
      'type': 'outdoor',
      'hasDisabledSpaces': true,
      'openHours': '24시간',
      'description': '공과대학 53호관 근처 주차장으로, 학생 및 교직원을 위한 공용 주차장입니다.',
      'hasVideo': false, // 아직 영상이 연결되지 않음
      'status': 'no_video',
      'videoWidth': 640,
      'videoHeight': 480,
    },
  };

  // 주차장 영역 좌표 (다각형 형태로 표시할 때 사용) - 도서관 추가
  static const Map<String, List<Map<String, double>>> parkingPolygons = {
    'parking_lot_A': [
      {'latitude': 35.241243, 'longitude': 128.695426}, // 좌하단
      {'latitude': 35.241243, 'longitude': 128.695626}, // 우하단
      {'latitude': 35.241443, 'longitude': 128.695626}, // 우상단
      {'latitude': 35.241443, 'longitude': 128.695426}, // 좌상단
    ],
    'parking_lot_B': [
      {'latitude': 35.245188, 'longitude': 128.690794}, // 도서관 주차장 다각형
      {'latitude': 35.245188, 'longitude': 128.690994},
      {'latitude': 35.245388, 'longitude': 128.690994},
      {'latitude': 35.245388, 'longitude': 128.690794},
    ],
    'parking_lot_C': [
      {'latitude': 35.245281, 'longitude': 128.692172}, // 본관 주차장 다각형
      {'latitude': 35.245281, 'longitude': 128.692372},
      {'latitude': 35.245481, 'longitude': 128.692372},
      {'latitude': 35.245481, 'longitude': 128.692172},
    ],
    'parking_lot_D': [
      {'latitude': 35.240880, 'longitude': 128.698314}, // 53호관 주차장 다각형
      {'latitude': 35.240880, 'longitude': 128.698514},
      {'latitude': 35.241080, 'longitude': 128.698514},
      {'latitude': 35.241080, 'longitude': 128.698314},
    ],
  };

  // 주차장별 영상 정보 - 도서관 추가
  static const Map<String, Map<String, dynamic>> videoInfo = {
    'parking_lot_A': {
      'hasVideo': true,
      'width': 1444,
      'height': 973,
      'streamUrl': '/api/stream/parking_lot_A',
    },
    'parking_lot_B': {
      'hasVideo': true,
      'width': 1170,
      'height': 694,
      'streamUrl': '/api/stream/parking_lot_B',
    },
    'parking_lot_C': {
      'hasVideo': false,
      'width': 640,
      'height': 480,
      'streamUrl': null,
    },
    'parking_lot_D': {
      'hasVideo': false,
      'width': 640,
      'height': 480,
      'streamUrl': null,
    },
  };

  // 주차장 이름 매핑 (한글) - 도서관 추가
  static const Map<String, String> parkingLotNames = {
    'parking_lot_A': '55호관 주차장',
    'parking_lot_B': '도서관 주차장',
    'parking_lot_C': '대학본부 주차장',
    'parking_lot_D': '53호관 주차장',
  };

  // 특수 공간 식별 헬퍼 메서드 - 전기차 지원 추가
  static String getSpaceType(String spaceId) {
    if (spaceId.toLowerCase().contains('disabled')) {
      return 'disabled';
    } else if (spaceId.toLowerCase().contains('electric')) {
      return 'electric';
    } else {
      return 'normal';
    }
  }

  // 특수 주차 공간 유형 - 전기차 추가
  static const Map<String, Map<String, dynamic>> specialSpaceTypes = {
    'electric': {
      'name': '전기차 전용',
      'color': 0xFFFFEB3B, // 노란색
      'icon': 'electric_car',
      'description': '전기차 전용 주차 구역',
    },
    'disabled': {
      'name': '장애인 전용',
      'color': 0xFF2196F3, // 파란색
      'icon': 'accessible',
      'description': '장애인 전용 주차 구역',
    },
    'normal': {
      'name': '일반',
      'color': 0xFF4CAF50, // 녹색
      'icon': 'local_parking',
      'description': '일반 주차 구역',
    },
  };

  // 주차장 우선순위 (표시 순서) - 도서관 우선순위 상향
  static const List<String> parkingLotPriority = [
    'parking_lot_A', // 55호관 (영상 있음)
    'parking_lot_B', // 도서관 (영상 있음)
    'parking_lot_C', // 대학본부 (영상 없음)
    'parking_lot_D', // 53호관 (영상 없음)
  ];

  // 동적 주차장 관리를 위한 메소드들
  static Map<String, dynamic> _dynamicParkingLots = {};

  // 동적으로 주차장 추가
  static void addDynamicParkingLot(String id, Map<String, dynamic> lotData) {
    _dynamicParkingLots[id] = lotData;
  }

  // 동적 주차장 제거
  static void removeDynamicParkingLot(String id) {
    _dynamicParkingLots.remove(id);
  }

  // 모든 주차장 정보 반환 (정적 + 동적)
  static Map<String, Map<String, dynamic>> getAllParkingLots() {
    final allLots = Map<String, Map<String, dynamic>>.from(parkingLocations);
    allLots.addAll(_dynamicParkingLots);
    return allLots;
  }

  // 활성화된 주차장 목록 반환 (영상이 있는 주차장) - 도서관 포함
  static List<String> getActiveParkingLots() {
    final allLots = getAllParkingLots();
    return allLots.entries
        .where((entry) => entry.value['hasVideo'] == true)
        .map((entry) => entry.key)
        .toList();
  }

  // 영상이 없는 주차장 목록 반환
  static List<String> getInactiveParkingLots() {
    final allLots = getAllParkingLots();
    return allLots.entries
        .where((entry) => entry.value['hasVideo'] != true)
        .map((entry) => entry.key)
        .toList();
  }

  // 주차장 정보 가져오기 (동적 주차장 포함)
  static Map<String, dynamic>? getParkingLotInfo(String parkingLotId) {
    final allLots = getAllParkingLots();
    return allLots[parkingLotId];
  }

  // API 엔드포인트 헬퍼 메서드들 - 주차장별 통계 지원
  static String getStatisticsEndpoint({String? parkingLotId}) {
    if (parkingLotId != null) {
      return '$statisticsEndpoint/$parkingLotId';
    }
    return statisticsEndpoint;
  }

  static String getDynamicParkingLotEndpoint() {
    return dynamicParkingLotsEndpoint;
  }

  static String getCoordinatesUploadEndpoint(String parkingLotId) {
    return '$uploadCoordinatesEndpoint/$parkingLotId/coordinates';
  }

  // 새 주차장 추가를 위한 기본 템플릿 - 향상된 버전
  static Map<String, dynamic> getNewParkingLotTemplate(String id) {
    return {
      'id': id,
      'name': '새 주차장',
      'building': '건물명 입력 필요',
      'latitude': changwonUniversity['latitude'],
      'longitude': changwonUniversity['longitude'],
      'capacity': 10,
      'type': 'outdoor',
      'hasDisabledSpaces': false,
      'hasElectricSpaces': false, // 전기차 공간 지원
      'openHours': '24시간',
      'description': '주차장 설명을 입력하세요',
      'hasVideo': false,
      'status': 'no_video',
      'videoWidth': 640,
      'videoHeight': 480,
      'coordinates': [], // 주차 공간 좌표
      'videoSource': '', // 비디오 소스 경로
      'specialSpaces': {
        'electric': [],
        'disabled': [],
      }
    };
  }

  // 파일 업로드 지원 형식
  static const List<String> supportedCoordinateFormats = [
    '.txt', '.json', '.csv'
  ];

  // 좌표 파일 예시 형식
  static const String coordinateFileExample = '''
  // JSON 형식 예시:
  {
    "coordinates": [
      {"id": "A1", "coords": [[74, 104], [40, 200], [2, 204], [3, 105]]},
      {"id": "A2", "coords": [[75, 104], [153, 101], [124, 197], [43, 200]]}
    ]
  }
  
  // TXT 형식 예시:
  A1,74,104,40,200,2,204,3,105
  A2,75,104,153,101,124,197,43,200
  ''';

  // 동적 주차장 추가 검증
  static Map<String, String> validateDynamicParkingLot(Map<String, dynamic> lotData) {
    Map<String, String> errors = {};

    // 기본 검증
    final basicErrors = validateParkingLotConfig(lotData);
    errors.addAll(basicErrors);

    // 비디오 파일 경로 검증
    if (lotData['videoSource'] == null || lotData['videoSource'].toString().isEmpty) {
      errors['videoSource'] = '비디오 파일 경로는 필수입니다';
    }

    // 좌표 데이터 검증
    if (lotData['coordinates'] == null ||
        (lotData['coordinates'] as List).isEmpty) {
      errors['coordinates'] = '주차 공간 좌표 데이터는 필수입니다';
    }

    return errors;
  }