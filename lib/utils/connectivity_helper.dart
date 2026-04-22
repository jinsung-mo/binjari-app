// utils/connectivity_helper.dart
// 네트워크 연결 상태 관리 및 서버 상태 확인 도우미 클래스

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; // 패키지 추가 필요
import '../config/app_config.dart';
import 'package:http/http.dart' as http;

class ConnectivityHelper {
  // 싱글톤 패턴 구현
  static final ConnectivityHelper _instance = ConnectivityHelper._internal();
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  bool _isConnected = true;
  bool _isServerAvailable = false;

  // 연결 상태 변경 콜백
  Function(bool)? onConnectivityChanged;
  Function(bool)? onServerAvailabilityChanged;

  // 싱글톤 접근자
  factory ConnectivityHelper() {
    return _instance;
  }

  ConnectivityHelper._internal();

  // 현재 연결 상태
  bool get isConnected => _isConnected;
  bool get isServerAvailable => _isServerAvailable;

  // 초기화 및 설정
  void initialize() {
    // 초기 연결 상태 확인
    _checkConnectivity();

    // 연결 상태 변경 모니터링
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);

    // 초기 서버 상태 확인
    _checkServerAvailability();
  }

  // 리소스 정리
  void dispose() {
    _connectivitySubscription?.cancel();
  }

  // 연결 상태 확인
  Future<void> _checkConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      _updateConnectionStatus(result);
    } catch (e) {
      print('연결 상태 확인 중 오류: $e');
      _isConnected = false;
      onConnectivityChanged?.call(false);
    }
  }

  // 연결 상태 업데이트 처리
  void _updateConnectionStatus(ConnectivityResult result) {
    bool previousState = _isConnected;
    _isConnected = result != ConnectivityResult.none;

    // 상태가 변경된 경우에만 콜백 호출
    if (previousState != _isConnected) {
      print('네트워크 연결 상태 변경: $_isConnected');
      onConnectivityChanged?.call(_isConnected);

      // 연결이 복구된 경우 서버 상태도 확인
      if (_isConnected) {
        _checkServerAvailability();
      } else {
        // 연결이 끊어진 경우 서버도 사용 불가로 설정
        _isServerAvailable = false;
        onServerAvailabilityChanged?.call(false);
      }
    }
  }

  // 서버 상태 확인
  Future<bool> _checkServerAvailability() async {
    if (!_isConnected) {
      _isServerAvailable = false;
      return false;
    }

    try {
      // 디버그 엔드포인트로 빠른 확인
      final response = await http.get(
        Uri.parse(AppConfig.debugEndpoint),
      ).timeout(const Duration(seconds: 5));

      bool previousState = _isServerAvailable;
      _isServerAvailable = response.statusCode == 200;

      // 상태가 변경된 경우에만 콜백 호출
      if (previousState != _isServerAvailable) {
        print('서버 가용성 변경: $_isServerAvailable');
        onServerAvailabilityChanged?.call(_isServerAvailable);
      }

      return _isServerAvailable;
    } catch (e) {
      print('서버 상태 확인 중 오류: $e');
      _isServerAvailable = false;
      onServerAvailabilityChanged?.call(false);
      return false;
    }
  }

  // 수동으로 서버 상태 확인 (UI에서 호출용)
  Future<bool> checkServerAvailability() {
    return _checkServerAvailability();
  }

  // 연결 상태 스낵바 표시 유틸리티
  static void showConnectivitySnackBar(BuildContext context, bool isConnected) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isConnected
              ? '네트워크에 연결되었습니다.'
              : '네트워크 연결이 끊어졌습니다. 연결을 확인해 주세요.',
        ),
        backgroundColor: isConnected ? Colors.green : Colors.red,
        duration: const Duration(seconds: 3),
        action: isConnected
            ? null
            : SnackBarAction(
                label: '설정',
                textColor: Colors.white,
                onPressed: () {
                  // 네트워크 설정 화면으로 이동 (옵션)
                },
              ),
      ),
    );
  }

  // 서버 상태 스낵바 표시 유틸리티
  static void showServerStatusSnackBar(BuildContext context, bool isAvailable) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isAvailable
              ? '주차장 서버에 연결되었습니다.'
              : '주차장 서버에 연결할 수 없습니다. 서버 상태를 확인해 주세요.',
        ),
        backgroundColor: isAvailable ? Colors.green : Colors.orange,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}