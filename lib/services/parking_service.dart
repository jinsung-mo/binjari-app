// services/parking_service.dart
// 주차장 API 통신 서비스 (도서관 및 동적 주차장 지원)

import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/parking_model.dart';

class ParkingService {
  // 싱글톤 패턴 구현
  static final ParkingService _instance = ParkingService._internal();

  factory ParkingService() {
    return _instance;
  }

  ParkingService._internal();

  // 재시도 로직이 포함된 HTTP 요청 함수
  Future<http.Response> _retryableRequest(
    String url, {
    String method = 'GET',
    Map<String, String>? headers,
    String? body,
    int maxRetries = AppConfig.maxRetries,
    int timeout = AppConfig.connectionTimeout,
  }) async {
    int attempts = 0;

    while (attempts < maxRetries) {
      attempts++;
      try {
        http.Response response;

        final uri = Uri.parse(url);
        final requestHeaders = headers ?? AppConfig.jsonHeaders;

        if (method == 'GET') {
          response = await http.get(uri, headers: requestHeaders)
              .timeout(Duration(seconds: timeout));
        } else if (method == 'POST') {
          response = await http.post(uri, headers: requestHeaders, body: body)
              .timeout(Duration(seconds: timeout));
        } else if (method == 'PUT') {
          response = await http.put(uri, headers: requestHeaders, body: body)
              .timeout(Duration(seconds: timeout));
        } else if (method == 'DELETE') {
          response = await http.delete(uri, headers: requestHeaders)
              .timeout(Duration(seconds: timeout));
        } else {
          throw Exception('지원하지 않는 HTTP 메서드: $method');
        }

        return response;
      } catch (e) {
        print('HTTP 요청 실패 ($attempts/$maxRetries): $e');

        if (attempts >= maxRetries) {
          rethrow;
        }

        await Future.delayed(Duration(milliseconds: 500 * attempts));
      }
    }

    throw Exception('예상치 못한 오류');
  }

  // 주차장 서버 상태 확인 (가벼운 헬스체크 엔드포인트 사용)
  Future<bool> checkServerStatus() async {
    return (await getServerHealth()) != null;
  }

  // 서버 헬스체크 정보 (응답이 없으면 null). running: 감지 시스템 실행 여부
  Future<Map<String, dynamic>?> getServerHealth() async {
    try {
      final response = await _retryableRequest(
        AppConfig.healthEndpoint,
        timeout: 5,
        maxRetries: 1,
      );
      if (response.statusCode != 200) return null;
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      print('서버 상태 확인 실패: $e');
      return null;
    }
  }

  // 관리자 토큰 확인. 유효하면 이후 요청에 토큰을 포함하도록 저장
  Future<bool> verifyAdminToken(String token) async {
    try {
      final response = await _retryableRequest(
        AppConfig.authCheckEndpoint,
        headers: {'X-Admin-Token': token},
        timeout: 5,
        maxRetries: 1,
      );
      if (response.statusCode == 200) {
        AppConfig.adminToken = token;
        return true;
      }
      return false;
    } catch (e) {
      throw Exception('서버에 연결할 수 없습니다: $e');
    }
  }

  // 관리자 전용 API 응답 확인 (401이면 토큰 초기화)
  void _checkAuthorized(http.Response response) {
    if (response.statusCode == 401) {
      AppConfig.adminToken = null;
      throw Exception('관리자 인증이 필요합니다. 관리자 화면에서 관리자 토큰을 입력하세요.');
    }
  }

  // 주차장 상태 조회 (도서관 포함 다중 주차장 지원)
  Future<ParkingStatus> getParkingStatus({String? parkingLotId}) async {
    try {
      String endpoint = AppConfig.statusEndpoint;
      if (parkingLotId != null) {
        endpoint += '?parking_lot=$parkingLotId';
      }

      final response = await _retryableRequest(
        endpoint,
        timeout: AppConfig.connectionTimeout,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // 특정 주차장 요청인 경우 해당 주차장만 반환
        if (parkingLotId != null && data.containsKey(parkingLotId)) {
          return ParkingStatus.fromJson({parkingLotId: data[parkingLotId]});
        }

        return ParkingStatus.fromJson(data);
      } else {
        throw Exception('주차장 상태 조회 실패: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('주차장 상태 조회 중 오류 상세 정보: $e');
      throw Exception('주차장 상태 조회 중 오류 발생: $e');
    }
  }

  // 주차장 통계 조회 (개별 주차장별 지원 - 도서관 포함)
  Future<ParkingStatistics> getParkingStatistics({String? parkingLotId}) async {
    try {
      String endpoint = AppConfig.getStatisticsEndpoint(parkingLotId: parkingLotId);

      final response = await _retryableRequest(
        endpoint,
        timeout: AppConfig.connectionTimeout,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // 영상이 없는 주차장에 대한 특별 처리
        if (data['has_video'] == false) {
          return _generateNoVideoStatistics(parkingLotId, data);
        }

        return ParkingStatistics.fromJson(data);
      } else {
        throw Exception('주차장 통계 조회 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('통계 조회 오류: $e');

      // 서버에서 통계를 가져올 수 없는 경우 기본 통계 생성
      return _generateFallbackStatistics(parkingLotId);
    }
  }

  // 영상이 없는 주차장을 위한 통계 생성
  ParkingStatistics _generateNoVideoStatistics(String? parkingLotId, Map<String, dynamic> data) {
    final now = DateTime.now();
    final currentHour = now.hour;
    final totalSpaces = data['total_spaces'] ?? 20;

    // 영상 미연결 주차장은 모든 값을 0으로 설정
    return ParkingStatistics(
      current: CurrentStatus(
        time: '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
        hour: currentHour,
        occupancyRate: 0.0,
        formattedRate: '0%',
        totalSpaces: totalSpaces,
        occupiedSpaces: 0,
        availableSpaces: totalSpaces,
      ),
      hourlyData: List.generate(24, (hour) => HourlyData(
        hour: hour,
        formattedTime: '${hour.toString().padLeft(2, '0')}:00',
        occupancyRate: 0.0,
        formattedRate: '-',
        isCurrent: hour == currentHour,
        hasData: false,
      )),
      recommendation: Recommendation.none(),
      timePeriods: {
        'morning': TimePeriod(label: '아침 (06:00-11:59)', avgRate: 0.0, formattedRate: '-', hasData: false),
        'afternoon': TimePeriod(label: '오후 (12:00-17:59)', avgRate: 0.0, formattedRate: '-', hasData: false),
        'evening': TimePeriod(label: '저녁 (18:00-21:59)', avgRate: 0.0, formattedRate: '-', hasData: false),
        'night': TimePeriod(label: '밤 (22:00-05:59)', avgRate: 0.0, formattedRate: '-', hasData: false),
      },
    );
  }

  // 동적 주차장 추가
  Future<bool> addDynamicParkingLot(Map<String, dynamic> parkingLotData) async {
    try {
      final response = await _retryableRequest(
        AppConfig.getDynamicParkingLotEndpoint(),
        method: 'POST',
        body: json.encode(parkingLotData),
      );
      _checkAuthorized(response);

      if (response.statusCode == 201) {
        return true;
      } else {
        final responseData = json.decode(response.body);
        throw Exception(responseData['error'] ?? '동적 주차장 추가 실패');
      }
    } catch (e) {
      print('동적 주차장 추가 오류: $e');
      throw Exception('동적 주차장 추가 중 오류 발생: $e');
    }
  }

  // 좌표 파일 업로드
  Future<bool> uploadCoordinatesFile(String parkingLotId, String filePath, List<int> fileBytes) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(AppConfig.getCoordinatesUploadEndpoint(parkingLotId)),
      );

      if (AppConfig.adminToken != null) {
        request.headers['X-Admin-Token'] = AppConfig.adminToken!;
      }

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: filePath.split('/').last,
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      _checkAuthorized(response);

      if (response.statusCode == 200) {
        return true;
      } else {
        final responseData = json.decode(response.body);
        throw Exception(responseData['error'] ?? '좌표 파일 업로드 실패');
      }
    } catch (e) {
      print('좌표 파일 업로드 오류: $e');
      throw Exception('좌표 파일 업로드 중 오류 발생: $e');
    }
  }

  // 전체 주차장 통계 맵 조회 (주차장별 통계 API를 각각 호출)
  Future<Map<String, ParkingStatistics>> getAllParkingStatistics() async {
    final Map<String, ParkingStatistics> statisticsMap = {};
    for (final lotId in AppConfig.getAllParkingLots().keys) {
      statisticsMap[lotId] = await getParkingStatistics(parkingLotId: lotId);
    }
    return statisticsMap;
  }

  // 주차 이력 조회 (주차장별 지원)
  Future<List<ParkingHistory>> getParkingHistory({
    int days = 7,
    String? parkingLotId,
  }) async {
    try {
      String endpoint = AppConfig.getHistoryEndpoint(
        parkingLotId: parkingLotId,
        days: days,
      );

      final response = await _retryableRequest(
        endpoint,
        timeout: AppConfig.connectionTimeout,
      );

      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        return data.map((item) => ParkingHistory.fromJson(item)).toList();
      } else {
        throw Exception('주차 이력 조회 실패: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('주차 이력 조회 중 오류 발생: $e');
    }
  }

  // 주차장 목록 조회 (동적 주차장 포함)
  Future<List<Map<String, dynamic>>> getParkingLots() async {
    try {
      final response = await _retryableRequest(
        AppConfig.parkingLotsEndpoint,
        timeout: AppConfig.connectionTimeout,
      );

      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else {
        throw Exception('주차장 목록 조회 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('주차장 목록 조회 오류: $e');

      // 오류 시 로컬 설정에서 주차장 목록 반환
      return _getLocalParkingLots();
    }
  }

  // 새 주차장 추가
  Future<bool> addParkingLot(Map<String, dynamic> parkingLotData) async {
    try {
      // 클라이언트 측 유효성 검사
      final errors = AppConfig.validateParkingLotConfig(parkingLotData);
      if (errors.isNotEmpty) {
        throw Exception('유효성 검사 실패: ${errors.values.join(', ')}');
      }

      final response = await _retryableRequest(
        AppConfig.parkingLotsEndpoint,
        method: 'POST',
        body: json.encode(parkingLotData),
      );
      _checkAuthorized(response);

      if (response.statusCode == 201) {
        return true;
      } else {
        final responseData = json.decode(response.body);
        throw Exception(responseData['error'] ?? '주차장 추가 실패');
      }
    } catch (e) {
      print('주차장 추가 오류: $e');
      throw Exception('주차장 추가 중 오류 발생: $e');
    }
  }

  // 주차장 정보 업데이트
  Future<bool> updateParkingLot(String parkingLotId, Map<String, dynamic> parkingLotData) async {
    try {
      final errors = AppConfig.validateParkingLotConfig(parkingLotData);
      if (errors.isNotEmpty) {
        throw Exception('유효성 검사 실패: ${errors.values.join(', ')}');
      }

      final response = await _retryableRequest(
        '${AppConfig.parkingLotsEndpoint}/$parkingLotId',
        method: 'PUT',
        body: json.encode(parkingLotData),
      );
      _checkAuthorized(response);

      if (response.statusCode == 200) {
        return true;
      } else {
        final responseData = json.decode(response.body);
        throw Exception(responseData['error'] ?? '주차장 업데이트 실패');
      }
    } catch (e) {
      print('주차장 업데이트 오류: $e');
      throw Exception('주차장 업데이트 중 오류 발생: $e');
    }
  }

  // 주차장 삭제
  Future<bool> deleteParkingLot(String parkingLotId) async {
    try {
      final response = await _retryableRequest(
        '${AppConfig.parkingLotsEndpoint}/$parkingLotId',
        method: 'DELETE',
      );
      _checkAuthorized(response);

      if (response.statusCode == 200) {
        return true;
      } else {
        final responseData = json.decode(response.body);
        throw Exception(responseData['error'] ?? '주차장 삭제 실패');
      }
    } catch (e) {
      print('주차장 삭제 오류: $e');
      throw Exception('주차장 삭제 중 오류 발생: $e');
    }
  }

  // 시스템 시작
  Future<bool> startSystem() async {
    try {
      final response = await _retryableRequest(
        AppConfig.startSystemEndpoint,
        method: 'POST',
        timeout: AppConfig.connectionTimeout,
      );
      _checkAuthorized(response);

      return response.statusCode == 200;
    } catch (e) {
      throw Exception('시스템 시작 중 오류 발생: $e');
    }
  }

  // 시스템 중지
  Future<bool> stopSystem() async {
    try {
      final response = await _retryableRequest(
        AppConfig.stopSystemEndpoint,
        method: 'POST',
        timeout: AppConfig.connectionTimeout,
      );
      _checkAuthorized(response);

      return response.statusCode == 200;
    } catch (e) {
      throw Exception('시스템 중지 중 오류 발생: $e');
    }
  }

  // 서버 디버그 정보 조회
  Future<Map<String, dynamic>> getDebugInfo() async {
    try {
      final response = await _retryableRequest(
        AppConfig.debugEndpoint,
        timeout: AppConfig.connectionTimeout,
      );
      _checkAuthorized(response);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('디버그 정보 조회 실패: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('디버그 정보 조회 중 오류 발생: $e');
    }
  }

  // 서버에서 통계를 가져오지 못했을 때의 대체 통계.
  // 임의 값으로 채우면 실측 데이터처럼 보이므로 모든 시간대를 '데이터 없음'으로 표시한다.
  ParkingStatistics _generateFallbackStatistics(String? parkingLotId) {
    final lotInfo = parkingLotId != null ? AppConfig.getParkingLotInfo(parkingLotId) : null;
    return _generateNoVideoStatistics(parkingLotId, {'total_spaces': lotInfo?['capacity'] ?? 0});
  }

  // 로컬 주차장 목록 반환 (서버 오류 시 대체용) - 도서관 포함
  List<Map<String, dynamic>> _getLocalParkingLots() {
    List<Map<String, dynamic>> lots = [];

    final allLots = AppConfig.getAllParkingLots();
    allLots.forEach((lotId, lotInfo) {
      lots.add({
        'id': lotId,
        'name': lotInfo['name'],
        'building': lotInfo['building'],
        'latitude': lotInfo['latitude'],
        'longitude': lotInfo['longitude'],
        'capacity': lotInfo['capacity'],
        'type': lotInfo['type'],
        'hasDisabledSpaces': lotInfo['hasDisabledSpaces'],
        'openHours': lotInfo['openHours'],
        'description': lotInfo['description'],
        'hasVideo': lotInfo['hasVideo'],
        'status': lotInfo['status'],
        'coordinates': [], // 좌표 데이터는 복잡하므로 빈 배열로 설정
        'videoSource': AppConfig.hasVideoStream(lotId) ? AppConfig.getStreamEndpoint(lotId) : '',
      });
    });

    return lots;
  }

  // 주차장 상태 검증
  bool validateParkingLotId(String? parkingLotId) {
    if (parkingLotId == null) return true;
    return AppConfig.isValidParkingLot(parkingLotId);
  }

  // 주차장 이름 가져오기 (동적 주차장 포함)
  String getParkingLotName(String parkingLotId) {
    return AppConfig.getParkingLotName(parkingLotId);
  }

  // 주차장 영상 스트림 URL 가져오기
  String? getStreamUrl(String parkingLotId) {
    if (!AppConfig.hasVideoStream(parkingLotId)) {
      return null;
    }
    return AppConfig.getStreamEndpoint(parkingLotId);
  }

  // 활성화된 주차장 목록 가져오기 (도서관 포함)
  List<String> getActiveParkingLots() {
    return AppConfig.getActiveParkingLots();
  }

  // 비활성화된 주차장 목록 가져오기
  List<String> getInactiveParkingLots() {
    return AppConfig.getInactiveParkingLots();
  }

  // 주차장별 특별 정보 가져오기 (전기차, 장애인 주차 등)
  Map<String, List<String>>? getSpecialSpaces(String parkingLotId) {
    final specialSpaces = AppConfig.getParkingLotInfo(parkingLotId)?['specialSpaces'];
    if (specialSpaces is! Map) return null;
    return specialSpaces.map((key, value) => MapEntry(key.toString(), List<String>.from(value as List)));
  }

  // 주차장이 특별 주차 공간을 가지고 있는지 확인
  bool hasElectricSpaces(String parkingLotId) {
    final specialSpaces = getSpecialSpaces(parkingLotId);
    return specialSpaces?.containsKey('electric') ?? false;
  }

  bool hasDisabledSpaces(String parkingLotId) {
    final specialSpaces = getSpecialSpaces(parkingLotId);
    return specialSpaces?.containsKey('disabled') ?? false;
  }
}