// services/parking_service.dart
// 주차장 API 통신 서비스 (도서관 및 동적 주차장 지원)

import 'dart:convert';
import 'dart:math' as math;
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
        final requestHeaders = headers ?? {'Content-Type': 'application/json'};

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

  // 주차장 서버 상태 확인
  Future<bool> checkServerStatus() async {
    try {
      final response = await _retryableRequest(
        AppConfig.debugEndpoint,
        timeout: 5,
      );

      return response.statusCode == 200;
    } catch (e) {
      print('서버 상태 확인 실패: $e');
      return false;
    }
  }

  // 주차장 상태 조회 (도서관 포함 다중 주차장 지원)
  Future<ParkingStatus> getParkingStatus({String? parkingLotId}) async {
    try {
      bool isServerRunning = await checkServerStatus();

      if (!isServerRunning) {
        throw Exception('주차장 서버가 응답하지 않습니다. 서버 상태를 확인하세요.');
      }

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
        formattedRate: '0%',
        isCurrent: hour == currentHour,
      )),
      recommendation: Recommendation(
        bestHour: 6,
        formattedTime: '06:00',
        occupancyRate: 0.0,
        formattedRate: '0%',
      ),
      timePeriods: {
        'morning': TimePeriod(label: '아침 (06:00-11:59)', avgRate: 0.0, formattedRate: '0%'),
        'afternoon': TimePeriod(label: '오후 (12:00-17:59)', avgRate: 0.0, formattedRate: '0%'),
        'evening': TimePeriod(label: '저녁 (18:00-21:59)', avgRate: 0.0, formattedRate: '0%'),
        'night': TimePeriod(label: '밤 (22:00-05:59)', avgRate: 0.0, formattedRate: '0%'),
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

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: filePath.split('/').last,
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

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

  // 전체 주차장 통계 맵 조회 (도서관 포함)
  Future<Map<String, ParkingStatistics>> getAllParkingStatistics() async {
    try {
      final response = await _retryableRequest(
        AppConfig.statisticsEndpoint,
        timeout: AppConfig.connectionTimeout,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        Map<String, ParkingStatistics> statisticsMap = {};

        if (data is Map) {
          data.forEach((key, value) {
            try {
              statisticsMap[key] = ParkingStatistics.fromJson(value);
            } catch (e) {
              print('주차장 $key 통계 파싱 오류: $e');
              statisticsMap[key] = _generateFallbackStatistics(key);
            }
          });
        }

        return statisticsMap;
      } else {
        throw Exception('전체 주차장 통계 조회 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('전체 통계 조회 오류: $e');

      // 오류 시 모든 주차장에 대해 기본 통계 생성
      Map<String, ParkingStatistics> fallbackMap = {};
      final allLots = AppConfig.getAllParkingLots();

      for (String lotId in allLots.keys) {
        fallbackMap[lotId] = _generateFallbackStatistics(lotId);
      }
      return fallbackMap;
    }
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

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('디버그 정보 조회 실패: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('디버그 정보 조회 중 오류 발생: $e');
    }
  }

  // 기본 통계 생성 (서버 오류 시 대체용) - 도서관 등 개별 주차장 고려
  ParkingStatistics _generateFallbackStatistics(String? parkingLotId) {
    final now = DateTime.now();
    final currentHour = now.hour;

    // 주차장 정보 가져오기
    final lotInfo = parkingLotId != null ? AppConfig.getParkingLotInfo(parkingLotId) : null;
    final hasVideo = parkingLotId != null ? AppConfig.hasVideoStream(parkingLotId) : false;
    final totalSpaces = lotInfo?['capacity'] ?? 50;

    // 영상이 없는 주차장은 모든 값을 0으로 설정
    if (!hasVideo) {
      return _generateNoVideoStatistics(parkingLotId, {'total_spaces': totalSpaces});
    }

    // 주차장별 특별한 패턴 적용
    double baseOccupancyRate = 50.0;

    // 도서관 주차장의 경우 특별한 패턴 적용
    if (parkingLotId == 'parking_lot_B') {
      // 도서관은 평일 오후와 시험 기간에 더 높은 점유율
      if (now.weekday <= 5) { // 평일
        if (currentHour >= 9 && currentHour <= 18) {
          baseOccupancyRate = 70.0; // 평일 낮시간 높은 점유율
        } else if (currentHour >= 19 && currentHour <= 22) {
          baseOccupancyRate = 85.0; // 평일 저녁 가장 높은 점유율 (스터디 시간)
        }
      }
    }
    // 55호관 주차장의 경우
    else if (parkingLotId == 'parking_lot_A') {
      // 공학관은 수업 시간에 더 높은 점유율
      if (currentHour >= 9 && currentHour <= 17) {
        baseOccupancyRate = 75.0;
      }
    }

    final currentOccupancyRate = baseOccupancyRate + (math.Random().nextDouble() - 0.5) * 20;
    final currentOccupied = (totalSpaces * currentOccupancyRate / 100).round();

    // 시간별 데이터 생성 (주차장별 패턴 적용)
    List<HourlyData> hourlyData = [];
    for (int hour = 0; hour < 24; hour++) {
      double rate = _calculateHourlyRate(hour, parkingLotId, baseOccupancyRate);

      // 현재 시간이면 실제 점유율 사용
      if (hour == currentHour) {
        rate = currentOccupancyRate;
      }

      hourlyData.add(HourlyData(
        hour: hour,
        formattedTime: '${hour.toString().padLeft(2, '0')}:00',
        occupancyRate: rate,
        formattedRate: '${rate.round()}%',
        isCurrent: hour == currentHour,
      ));
    }

    // 추천 시간 찾기 (점유율이 가장 낮은 시간)
    double minRate = 100.0;
    int bestHour = 6;
    for (int offset = 1; offset <= 12; offset++) {
      int checkHour = (currentHour + offset) % 24;
      var hourData = hourlyData.firstWhere((data) => data.hour == checkHour);
      if (hourData.occupancyRate < minRate) {
        minRate = hourData.occupancyRate;
        bestHour = checkHour;
      }
    }

    // 시간대별 평균 계산
    Map<String, double> periodTotals = {'morning': 0, 'afternoon': 0, 'evening': 0, 'night': 0};
    Map<String, int> periodCounts = {'morning': 0, 'afternoon': 0, 'evening': 0, 'night': 0};

    for (var data in hourlyData) {
      if (data.hour >= 6 && data.hour < 12) {
        periodTotals['morning'] = periodTotals['morning']! + data.occupancyRate;
        periodCounts['morning'] = periodCounts['morning']! + 1;
      } else if (data.hour >= 12 && data.hour < 18) {
        periodTotals['afternoon'] = periodTotals['afternoon']! + data.occupancyRate;
        periodCounts['afternoon'] = periodCounts['afternoon']! + 1;
      } else if (data.hour >= 18 && data.hour < 22) {
        periodTotals['evening'] = periodTotals['evening']! + data.occupancyRate;
        periodCounts['evening'] = periodCounts['evening']! + 1;
      } else {
        periodTotals['night'] = periodTotals['night']! + data.occupancyRate;
        periodCounts['night'] = periodCounts['night']! + 1;
      }
    }

    Map<String, TimePeriod> timePeriods = {};
    periodTotals.forEach((key, total) {
      double avgRate = total / periodCounts[key]!;
      String label;
      switch (key) {
        case 'morning':
          label = '아침 (06:00-11:59)';
          break;
        case 'afternoon':
          label = '오후 (12:00-17:59)';
          break;
        case 'evening':
          label = '저녁 (18:00-21:59)';
          break;
        case 'night':
          label = '밤 (22:00-05:59)';
          break;
        default:
          label = key;
      }

      timePeriods[key] = TimePeriod(
        label: label,
        avgRate: avgRate,
        formattedRate: '${avgRate.round()}%',
      );
    });

    return ParkingStatistics(
      current: CurrentStatus(
        time: '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
        hour: currentHour,
        occupancyRate: currentOccupancyRate,
        formattedRate: '${currentOccupancyRate.round()}%',
        totalSpaces: totalSpaces,
        occupiedSpaces: currentOccupied,
        availableSpaces: totalSpaces - currentOccupied,
      ),
      hourlyData: hourlyData,
      recommendation: Recommendation(
        bestHour: bestHour,
        formattedTime: '${bestHour.toString().padLeft(2, '0')}:00',
        occupancyRate: hourlyData.firstWhere((data) => data.hour == bestHour).occupancyRate,
        formattedRate: hourlyData.firstWhere((data) => data.hour == bestHour).formattedRate,
      ),
      timePeriods: timePeriods,
    );
  }

  // 주차장별 시간별 점유율 계산
  double _calculateHourlyRate(int hour, String? parkingLotId, double baseRate) {
    double rate = baseRate;

    // 도서관 주차장 패턴
    if (parkingLotId == 'parking_lot_B') {
      if (hour >= 9 && hour <= 11) {
        rate = 60.0; // 오전 수업시간
      } else if (hour >= 12 && hour <= 14) {
        rate = 45.0; // 점심시간 (이동)
      } else if (hour >= 15 && hour <= 18) {
        rate = 75.0; // 오후 수업/스터디
      } else if (hour >= 19 && hour <= 22) {
        rate = 85.0; // 저녁 스터디 시간 (가장 혼잡)
      } else if (hour >= 23 || hour <= 5) {
        rate = 20.0; // 심야
      } else {
        rate = 40.0; // 기타 시간
      }
    }
    // 55호관 주차장 패턴
    else if (parkingLotId == 'parking_lot_A') {
      if (hour >= 7 && hour <= 9) {
        rate = 70.0 + (hour - 7) * 5; // 아침 출근시간
      } else if (hour >= 10 && hour <= 16) {
        rate = 80.0; // 수업시간
      } else if (hour >= 17 && hour <= 19) {
        rate = 75.0 + (hour - 17) * 5; // 저녁 퇴근시간
      } else if (hour >= 22 || hour <= 5) {
        rate = 30.0; // 심야시간
      } else {
        rate = 50.0; // 기타 시간
      }
    }
    // 기본 패턴 (다른 주차장들)
    else {
      if (hour >= 7 && hour <= 9) {
        rate = 70.0 + (hour - 7) * 5;
      } else if (hour >= 17 && hour <= 19) {
        rate = 75.0 + (hour - 17) * 5;
      } else if (hour >= 22 || hour <= 5) {
        rate = 30.0;
      } else {
        rate = 50.0;
      }
    }

    // 약간의 랜덤성 추가
    rate += (math.Random().nextDouble() - 0.5) * 10;
    return math.max(0, math.min(100, rate));
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
    final lotInfo = AppConfig.getParkingLotInfo(parkingLotId);
    return lotInfo?['specialSpaces'] as Map<String, List<String>>?;
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