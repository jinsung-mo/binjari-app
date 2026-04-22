// services/location_service.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../config/app_config.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';


class LocationService {
  // Singleton pattern
  static final LocationService _instance = LocationService._internal();

  factory LocationService() {
    return _instance;
  }

  LocationService._internal();

  // Get current position
  Future<Position?> getCurrentPosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Check if location services are enabled
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled
      return Future.error('위치 서비스가 비활성화되어 있습니다');
    }

    // Check permission
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permissions are denied
        return Future.error('위치 권한이 거부되었습니다');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever
      return Future.error('위치 권한이 영구적으로 거부되었습니다. 설정에서 권한을 허용해주세요.');
    }

    // Permissions are granted, get position
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      return position;
    } catch (e) {
      return Future.error('위치를 가져오는 중 오류가 발생했습니다: $e');
    }
  }

  // Get address from position
  Future<String> getAddressFromPosition(Position position) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        return "${place.street}, ${place.subLocality}, ${place.locality}";
      } else {
        return "주소를 찾을 수 없습니다";
      }
    } catch (e) {
      return "주소 검색 중 오류 발생: $e";
    }
  }

  // getPositionFromAddress 메서드를 수정
  Future<LatLng?> getLatLngFromAddress(String address) async {
    try {
      List<Location> locations = await locationFromAddress(address);
      if (locations.isNotEmpty) {
        Location location = locations[0];
        return LatLng(location.latitude, location.longitude);
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  // Calculate distance between two positions
  double calculateDistance(double startLatitude, double startLongitude,
      double endLatitude, double endLongitude) {
    return Geolocator.distanceBetween(
      startLatitude,
      startLongitude,
      endLatitude,
      endLongitude,
    );
  }

  // Check if user is near campus
  bool isNearCampus(Position position, {double radius = 500}) {
    final campusLat = AppConfig.changwonUniversity['latitude'] as double;
    final campusLng = AppConfig.changwonUniversity['longitude'] as double;

    double distance = calculateDistance(
      position.latitude,
      position.longitude,
      campusLat,
      campusLng,
    );

    return distance <= radius; // Within radius meters
  }

  // Get nearest parking lot
  Map<String, dynamic>? getNearestParkingLot(Position position) {
    double minDistance = double.infinity;
    Map<String, dynamic>? nearestLot;

    AppConfig.parkingLocations.forEach((key, lot) {
      double distance = calculateDistance(
        position.latitude,
        position.longitude,
        lot['latitude'] as double,
        lot['longitude'] as double,
      );

      if (distance < minDistance) {
        minDistance = distance;
        nearestLot = {...lot, 'id': key, 'distance': minDistance};
      }
    });

    return nearestLot;
  }

  // Format distance for display
  String formatDistance(double distanceInMeters) {
    if (distanceInMeters < 1000) {
      return '${distanceInMeters.toStringAsFixed(0)}m';
    } else {
      return '${(distanceInMeters / 1000).toStringAsFixed(1)}km';
    }
  }
}