// services/parking_lot_config_service.dart
// 주차장 설정 관리 서비스

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../models/parking_lot_config_model.dart';
import '../config/app_config.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class ParkingLotConfigService {
  // SharedPreferences 키
  static const String _configsKey = 'parking_lot_configs';

  // 관리자용 싱글톤 인스턴스
  static final ParkingLotConfigService _instance = ParkingLotConfigService._internal();

  factory ParkingLotConfigService() {
    return _instance;
  }

  ParkingLotConfigService._internal();

  final ParkingLotConfigManager _manager = ParkingLotConfigManager();

  // 설정 로드
  Future<List<ParkingLotConfig>> loadConfigurations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configsJson = prefs.getString(_configsKey);

      if (configsJson != null && configsJson.isNotEmpty) {
        _manager.fromJson(configsJson);
      } else {
        // 설정이 없는 경우 AppConfig에서 기본 설정 생성
        _initializeFromAppConfig();
      }

      return _manager.configurations;
    } catch (e) {
      print('주차장 설정 로드 오류: $e');
      return [];
    }
  }

  // 설정 저장
  Future<bool> saveConfigurations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(_configsKey, _manager.toJson());
    } catch (e) {
      print('주차장 설정 저장 오류: $e');
      return false;
    }
  }

  // 주차장 추가/수정
  Future<bool> addOrUpdateLot(ParkingLotConfig config) async {
    try {
      _manager.addOrUpdate(config);
      return await saveConfigurations();
    } catch (e) {
      print('주차장 추가/수정 오류: $e');
      return false;
    }
  }

  // 주차장 삭제
  Future<bool> removeLot(String id) async {
    try {
      bool removed = _manager.remove(id);
      if (removed) {
        return await saveConfigurations();
      }
      return false;
    } catch (e) {
      print('주차장 삭제 오류: $e');
      return false;
    }
  }

  // 특정 주차장 가져오기
  ParkingLotConfig? getLotById(String id) {
    return _manager.getLotById(id);
  }

  // 현재 모든 설정 가져오기
  List<ParkingLotConfig> get configurations => _manager.configurations;

  // AppConfig에서 초기 설정 로드
  void _initializeFromAppConfig() {
    try {
      // AppConfig.parkingLocations에서 주차장 정보 불러오기
      AppConfig.parkingLocations.forEach((key, lotInfo) {
        // 다각형 정보 가져오기
        List<List<LatLng>> parkingSpaces = [];
        final polygons = AppConfig.parkingPolygons[key];

        if (polygons != null) {
          List<LatLng> points = [];
          for (var point in polygons) {
            points.add(LatLng(
              point['latitude'] as double,
              point['longitude'] as double,
            ));
          }
          parkingSpaces.add(points);
        }

        // ParkingLotConfig 객체 생성
        final config = ParkingLotConfig(
          id: key,
          name: lotInfo['name'] as String,
          building: lotInfo['building'] as String,
          latitude: lotInfo['latitude'] as double,
          longitude: lotInfo['longitude'] as double,
          capacity: lotInfo['capacity'] as int,
          type: lotInfo['type'] as String? ?? 'outdoor',
          hasDisabledSpaces: lotInfo['hasDisabledSpaces'] as bool? ?? false,
          openHours: lotInfo['openHours'] as String? ?? '24시간',
          description: lotInfo['description'] as String? ?? '',
          videoSource: '', // 비디오 소스는 기본 설정 없음
          parkingSpaces: parkingSpaces,
        );

        _manager.addOrUpdate(config);
      });
    } catch (e) {
      print('AppConfig에서 주차장 설정 초기화 오류: $e');
    }
  }

  // 백엔드 서버에 주차장 설정 등록
  Future<bool> uploadConfigToServer(ParkingLotConfig config) async {
    try {
      final apiUrl = '${AppConfig.baseUrl}/api/parking_lots';

      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(config.toJson()),
      ).timeout(Duration(seconds: AppConfig.connectionTimeout));

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('서버에 주차장 설정 업로드 오류: $e');
      return false;
    }
  }

  // 백엔드 서버에서 주차장 설정 삭제
  Future<bool> deleteConfigFromServer(String id) async {
    try {
      final apiUrl = '${AppConfig.baseUrl}/api/parking_lots/$id';

      final response = await http.delete(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
      ).timeout(Duration(seconds: AppConfig.connectionTimeout));

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('서버에서 주차장 설정 삭제 오류: $e');
      return false;
    }
  }

  // 백엔드 서버에서 모든 주차장 설정 가져오기
  Future<List<ParkingLotConfig>> fetchAllFromServer() async {
    try {
      final apiUrl = '${AppConfig.baseUrl}/api/parking_lots';

      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
      ).timeout(Duration(seconds: AppConfig.connectionTimeout));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        List<dynamic> jsonList = jsonDecode(response.body);
        List<ParkingLotConfig> configs = jsonList
            .map((json) => ParkingLotConfig.fromJson(json))
            .toList();

        // 로컬 설정 업데이트
        configs.forEach((config) => _manager.addOrUpdate(config));
        await saveConfigurations();

        return configs;
      }

      return [];
    } catch (e) {
      print('서버에서 주차장 설정 가져오기 오류: $e');
      return [];
    }
  }
}