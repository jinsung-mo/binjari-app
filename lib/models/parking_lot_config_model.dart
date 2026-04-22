// models/parking_lot_config_model.dart
// 주차장 설정 관련 데이터 모델

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class ParkingLotConfig {
  final String id;
  final String name;
  final String building;
  final double latitude;
  final double longitude;
  final int capacity;
  final String type;
  final bool hasDisabledSpaces;
  final String openHours;
  final String description;
  final String videoSource;
  final List<List<LatLng>> parkingSpaces; // 각 주차 구역의 좌표 목록

  ParkingLotConfig({
    required this.id,
    required this.name,
    required this.building,
    required this.latitude,
    required this.longitude,
    required this.capacity,
    this.type = 'outdoor',
    this.hasDisabledSpaces = false,
    this.openHours = '24시간',
    this.description = '',
    this.videoSource = '',
    this.parkingSpaces = const [],
  });

  // JSON에서 생성
  factory ParkingLotConfig.fromJson(Map<String, dynamic> json) {
    // 주차 구역 좌표 파싱
    List<List<LatLng>> spaces = [];
    if (json['parkingSpaces'] != null) {
      for (var polygon in json['parkingSpaces']) {
        List<LatLng> points = [];
        for (var point in polygon) {
          points.add(LatLng(point['latitude'], point['longitude']));
        }
        spaces.add(points);
      }
    }

    return ParkingLotConfig(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      building: json['building'] ?? '',
      latitude: json['latitude'] ?? 0.0,
      longitude: json['longitude'] ?? 0.0,
      capacity: json['capacity'] ?? 0,
      type: json['type'] ?? 'outdoor',
      hasDisabledSpaces: json['hasDisabledSpaces'] ?? false,
      openHours: json['openHours'] ?? '24시간',
      description: json['description'] ?? '',
      videoSource: json['videoSource'] ?? '',
      parkingSpaces: spaces,
    );
  }

  // JSON으로 변환
  Map<String, dynamic> toJson() {
    // 주차 구역 좌표 변환
    List<List<Map<String, double>>> spacesJson = [];
    for (var polygon in parkingSpaces) {
      List<Map<String, double>> points = [];
      for (var point in polygon) {
        points.add({
          'latitude': point.latitude,
          'longitude': point.longitude,
        });
      }
      spacesJson.add(points);
    }

    return {
      'id': id,
      'name': name,
      'building': building,
      'latitude': latitude,
      'longitude': longitude,
      'capacity': capacity,
      'type': type,
      'hasDisabledSpaces': hasDisabledSpaces,
      'openHours': openHours,
      'description': description,
      'videoSource': videoSource,
      'parkingSpaces': spacesJson,
    };
  }

  // 복사본 생성 with 패턴
  ParkingLotConfig copyWith({
    String? id,
    String? name,
    String? building,
    double? latitude,
    double? longitude,
    int? capacity,
    String? type,
    bool? hasDisabledSpaces,
    String? openHours,
    String? description,
    String? videoSource,
    List<List<LatLng>>? parkingSpaces,
  }) {
    return ParkingLotConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      building: building ?? this.building,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      capacity: capacity ?? this.capacity,
      type: type ?? this.type,
      hasDisabledSpaces: hasDisabledSpaces ?? this.hasDisabledSpaces,
      openHours: openHours ?? this.openHours,
      description: description ?? this.description,
      videoSource: videoSource ?? this.videoSource,
      parkingSpaces: parkingSpaces ?? this.parkingSpaces,
    );
  }

  // AppConfig에 저장할 수 있는 형태로 변환
  Map<String, dynamic> toAppConfigFormat() {
    // parkingLocations 형식
    final locationData = {
      'name': name,
      'building': building,
      'latitude': latitude,
      'longitude': longitude,
      'capacity': capacity,
      'type': type,
      'hasDisabledSpaces': hasDisabledSpaces,
      'openHours': openHours,
      'description': description,
    };

    // parkingPolygons 형식
    List<Map<String, double>> polygonPoints = [];
    if (parkingSpaces.isNotEmpty && parkingSpaces[0].isNotEmpty) {
      // 첫 번째 주차 구역 사용 (간소화)
      for (var point in parkingSpaces[0]) {
        polygonPoints.add({
          'latitude': point.latitude,
          'longitude': point.longitude,
        });
      }
    } else {
      // 기본 사각형 생성 (중심점 기준)
      final offset = 0.0001; // 약 10-20m
      polygonPoints = [
        {'latitude': latitude - offset, 'longitude': longitude - offset},
        {'latitude': latitude - offset, 'longitude': longitude + offset},
        {'latitude': latitude + offset, 'longitude': longitude + offset},
        {'latitude': latitude + offset, 'longitude': longitude - offset},
      ];
    }

    return {
      'locationData': locationData,
      'polygonData': polygonPoints,
    };
  }
}

// 주차장 설정 관리 클래스
class ParkingLotConfigManager {
  List<ParkingLotConfig> _configs = [];

  List<ParkingLotConfig> get configurations => _configs;

  // 현재 설정 목록에서 주차장 가져오기
  ParkingLotConfig? getLotById(String id) {
    try {
      return _configs.firstWhere((lot) => lot.id == id);
    } catch (e) {
      return null;
    }
  }

  // 새 주차장 추가/업데이트
  void addOrUpdate(ParkingLotConfig config) {
    int index = _configs.indexWhere((lot) => lot.id == config.id);
    if (index >= 0) {
      _configs[index] = config;
    } else {
      _configs.add(config);
    }
  }

  // 주차장 삭제
  bool remove(String id) {
    int initialLength = _configs.length;
    _configs.removeWhere((lot) => lot.id == id);
    return _configs.length < initialLength;
  }

  // JSON으로 변환
  String toJson() {
    List<Map<String, dynamic>> jsonList = _configs.map((config) => config.toJson()).toList();
    return jsonEncode(jsonList);
  }

  // JSON에서 불러오기
  void fromJson(String jsonString) {
    try {
      List<dynamic> jsonList = jsonDecode(jsonString);
      _configs = jsonList.map((json) => ParkingLotConfig.fromJson(json)).toList();
    } catch (e) {
      print('주차장 설정 불러오기 오류: $e');
      _configs = [];
    }
  }
}