// screens/error_handling_screen.dart
// 오류 처리 및 서버 연결 문제 해결 화면

import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../services/parking_service.dart';
import '../utils/connectivity_helper.dart';

class ErrorHandlingScreen extends StatefulWidget {
  final String errorMessage;
  final Function onRetry;

  const ErrorHandlingScreen({
    Key? key,
    required this.errorMessage,
    required this.onRetry,
  }) : super(key: key);

  @override
  State<ErrorHandlingScreen> createState() => _ErrorHandlingScreenState();
}

class _ErrorHandlingScreenState extends State<ErrorHandlingScreen> {
  bool _isCheckingServer = false;
  bool _isStartingServer = false;
  String _statusMessage = '';
  bool _isServerAvailable = false;
  final ConnectivityHelper _connectivityHelper = ConnectivityHelper();
  final ParkingService _parkingService = ParkingService();

  @override
  void initState() {
    super.initState();
    _checkServerStatus();
  }

  // 서버 상태 확인
  Future<void> _checkServerStatus() async {
    setState(() {
      _isCheckingServer = true;
      _statusMessage = '서버 상태 확인 중...';
    });

    try {
      bool isAvailable = await _connectivityHelper.checkServerAvailability();

      setState(() {
        _isServerAvailable = isAvailable;
        _statusMessage = isAvailable
            ? '서버가 실행 중입니다. 다시 시도해 보세요.'
            : '서버에 연결할 수 없습니다. 서버를 시작하시겠습니까?';
        _isCheckingServer = false;
      });
    } catch (e) {
      setState(() {
        _isServerAvailable = false;
        _statusMessage = '서버 상태 확인 중 오류가 발생했습니다: $e';
        _isCheckingServer = false;
      });
    }
  }

  // 서버 시작 시도
  Future<void> _startServer() async {
    setState(() {
      _isStartingServer = true;
      _statusMessage = '서버 시작 중...';
    });

    try {
      bool started = await _parkingService.startSystem();

      setState(() {
        _isStartingServer = false;
        _statusMessage = started
            ? '서버가 성공적으로 시작되었습니다. 다시 시도해 보세요.'
            : '서버를 시작하지 못했습니다. 관리자에게 문의하세요.';

        // 서버가 시작되었으면 잠시 후 다시 시도
        if (started) {
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              widget.onRetry();
            }
          });
        }
      });
    } catch (e) {
      setState(() {
        _isStartingServer = false;
        _statusMessage = '서버 시작 중 오류가 발생했습니다: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('연결 오류'),
        backgroundColor: Colors.red,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 80,
              ),
              const SizedBox(height: 24),
              Text(
                '연결 오류가 발생했습니다',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                widget.errorMessage,
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Text(
                _statusMessage,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _isServerAvailable ? Colors.green : Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // 서버 상태 확인 버튼
              ElevatedButton.icon(
                onPressed: _isCheckingServer ? null : _checkServerStatus,
                icon: _isCheckingServer
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.refresh),
                label: Text(_isCheckingServer ? '확인 중...' : '서버 상태 확인'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 서버 시작 버튼
              if (!_isServerAvailable && !_isCheckingServer)
                ElevatedButton.icon(
                  onPressed: _isStartingServer ? null : _startServer,
                  icon: _isStartingServer
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(_isStartingServer ? '시작 중...' : '서버 시작'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 16),

              // 다시 시도 버튼
              ElevatedButton.icon(
                onPressed: _isCheckingServer || _isStartingServer
                    ? null
                    : () => widget.onRetry(),
                icon: const Icon(Icons.replay),
                label: const Text('다시 시도'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // 문제 해결 정보
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '오류 해결 방법:',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('1. 서버 상태를 확인하세요.'),
                    const Text('2. 네트워크 연결을 확인하세요.'),
                    const Text('3. app_config.dart의 서버 IP 주소 설정을 확인하세요.'),
                    const Text('4. 서버가 실행 중인지 확인하세요.'),
                    const Text('5. 문제가 지속되면 서버를 다시 시작해 보세요.'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}