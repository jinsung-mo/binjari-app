import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_config.dart';
import '../services/parking_service.dart';
import '../services/admin_settings_service.dart';
import '../models/admin_settings_model.dart';
import '../utils/platform_util.dart';
import '../widgets/common_widgets.dart';
import 'parking_lots_admin_screen.dart';

// 플랫폼별 임포트
import 'package:flutter/foundation.dart' show kIsWeb;

// 조건부 임포트 (Windows에서도 작동하도록)
// 실제 사용 시에는 이 패키지들이 필요합니다
//import 'package:file_picker/file_picker.dart';
//import 'package:clipboard/clipboard.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  final ParkingService _parkingService = ParkingService();
  final AdminSettingsService _adminSettingsService = AdminSettingsService();
  late TabController _tabController;

  // 상태 변수
  bool _isLoading = false;
  String? _errorMessage;
  bool _isSystemRunning = false;
  bool _isPasswordDialogOpen = false;
  bool _isModelUploading = false;
  bool _isVideoUploading = false;

  // 설정 상태
  late AdminSettings _settings;

  // 컨트롤러
  final TextEditingController _apiUrlController = TextEditingController();
  final TextEditingController _modelPathController = TextEditingController();
  final TextEditingController _videoPathController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this); // 탭 개수 4개로 변경
    _loadSettings();
    _checkSystemStatus();
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    _modelPathController.dispose();
    _videoPathController.dispose();
    _passwordController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // 설정 로드
  Future<void> _loadSettings() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final settings = await _adminSettingsService.getSettings();

      setState(() {
        _settings = settings;
        _apiUrlController.text = settings.apiUrl;
        _modelPathController.text = settings.modelPath;
        _videoPathController.text = settings.videoPath;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '설정을 불러오는 중 오류가 발생했습니다: $e';
        _isLoading = false;
      });
    }
  }

  // 시스템 상태 확인
  Future<void> _checkSystemStatus() async {
    try {
      // 향후 서버 API 연결 시 실제 상태를 가져오도록 수정
      setState(() {
        _isSystemRunning = true;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '시스템 상태를 확인하는 중 오류가 발생했습니다: $e';
      });
    }
  }

  // 시스템 시작
  Future<void> _startSystem() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final result = await _parkingService.startSystem();

      setState(() {
        _isSystemRunning = result;
        _isLoading = false;
      });

      // 알림 표시
      if (result) {
        _showSnackBar('시스템이 성공적으로 시작되었습니다');
      } else {
        _showSnackBar('시스템 시작에 실패했습니다', isError: true);
      }
    } catch (e) {
      setState(() {
        _errorMessage = '시스템 시작 중 오류가 발생했습니다: $e';
        _isLoading = false;
      });
      _showSnackBar('시스템 시작 중 오류가 발생했습니다: $e', isError: true);
    }
  }

  // 시스템 중지
  Future<void> _stopSystem() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final result = await _parkingService.stopSystem();

      setState(() {
        _isSystemRunning = !result;
        _isLoading = false;
      });

      // 알림 표시
      if (result) {
        _showSnackBar('시스템이 성공적으로 중지되었습니다');
      } else {
        _showSnackBar('시스템 중지에 실패했습니다', isError: true);
      }
    } catch (e) {
      setState(() {
        _errorMessage = '시스템 중지 중 오류가 발생했습니다: $e';
        _isLoading = false;
      });
      _showSnackBar('시스템 중지 중 오류가 발생했습니다: $e', isError: true);
    }
  }

  // RTSP 스트림 설정 (새로 추가된 기능)
  Future<void> _configureRtspStream() async {
    // Show dialog for RTSP configuration
    final TextEditingController rtspUrlController = TextEditingController();

    bool? result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('RTSP 스트림 설정'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('CCTV 스트림 URL을 입력하세요:'),
            const SizedBox(height: 16),
            TextField(
              controller: rtspUrlController,
              decoration: const InputDecoration(
                labelText: 'RTSP URL',
                hintText: 'rtsp://username:password@ip_address:port/stream',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('설정'),
          ),
        ],
      ),
    );

    if (result == true && rtspUrlController.text.isNotEmpty) {
      setState(() {
        _videoPathController.text = rtspUrlController.text;
      });
      _showSnackBar('RTSP 스트림 URL이 설정되었습니다');
    }
  }

  // 모델 파일 선택 (Windows에서는 임시로 비활성화)
  Future<void> _selectModelFile() async {
    // Windows에서는 수동 입력 안내만 제공
    _showSnackBar('현재 플랫폼에서는 직접 모델 경로를 입력해 주세요', isError: false);

    // 클립보드 붙여넣기 대화상자 표시
    _showTextInputDialog(
      '모델 파일 경로 입력',
      '모델 파일 경로를 입력하세요(.pt 확장자)',
      _modelPathController,
    );

    // 실제로 파일 선택기를 사용하려면 아래 코드를 활성화하세요
    /*
    if (PlatformUtil.isFilePickerSupported) {
      try {
        setState(() {
          _isModelUploading = true;
        });

        // 파일 선택기 사용 코드
        // ...

        setState(() {
          _isModelUploading = false;
        });
      } catch (e) {
        _showSnackBar('파일 선택 중 오류가 발생했습니다: $e', isError: true);
        setState(() {
          _isModelUploading = false;
        });
      }
    }
    */
  }

  // 비디오 파일 선택 (Windows에서는 임시로 비활성화)
  Future<void> _selectVideoFile() async {
    // Windows에서는 수동 입력 안내만 제공
    _showSnackBar('현재 플랫폼에서는 직접 비디오 경로를 입력해 주세요', isError: false);

    // 클립보드 붙여넣기 대화상자 표시
    _showTextInputDialog(
      '비디오 파일 경로 입력',
      '비디오 파일 경로를 입력하세요(.mp4, .avi 등)',
      _videoPathController,
    );

    // 실제로 파일 선택기를 사용하려면 아래 코드를 활성화하세요
    /*
    if (PlatformUtil.isFilePickerSupported) {
      try {
        setState(() {
          _isVideoUploading = true;
        });

        // 파일 선택기 사용 코드
        // ...

        setState(() {
          _isVideoUploading = false;
        });
      } catch (e) {
        _showSnackBar('파일 선택 중 오류가 발생했습니다: $e', isError: true);
        setState(() {
          _isVideoUploading = false;
        });
      }
    }
    */
  }

  // 설정 저장
  Future<void> _saveSettings() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // 패스워드 확인
      if (_isPasswordDialogOpen) return;

      // 비밀번호 확인 다이얼로그 표시
      _showPasswordDialog();
    } catch (e) {
      setState(() {
        _errorMessage = '설정 저장 중 오류가 발생했습니다: $e';
        _isLoading = false;
      });
      _showSnackBar('설정 저장 중 오류가 발생했습니다: $e', isError: true);
    }
  }

  // 실제 설정 저장 구현
  Future<void> _saveSettingsWithPassword(String password) async {
    try {
      // 비밀번호 검증 (실제로는 서버에서 해야 함)
      if (password != '1234') {
        _showSnackBar('잘못된 비밀번호입니다', isError: true);
        return;
      }

      // 설정 업데이트
      final updatedSettings = AdminSettings(
        apiUrl: _apiUrlController.text,
        modelPath: _modelPathController.text,
        videoPath: _videoPathController.text,
        lastUpdated: DateTime.now(),
      );

      await _adminSettingsService.saveSettings(updatedSettings);

      setState(() {
        _settings = updatedSettings;
        _isLoading = false;
      });

      _showSnackBar('설정이 성공적으로 저장되었습니다');
    } catch (e) {
      setState(() {
        _errorMessage = '설정 저장 중 오류가 발생했습니다: $e';
        _isLoading = false;
      });
      _showSnackBar('설정 저장 중 오류가 발생했습니다: $e', isError: true);
    }
  }

  // 설정 초기화
  Future<void> _resetSettings() async {
    try {
      setState(() {
        _isLoading = true;
      });

      await _adminSettingsService.resetSettings();
      await _loadSettings();

      _showSnackBar('설정이 초기화되었습니다');
    } catch (e) {
      setState(() {
        _errorMessage = '설정 초기화 중 오류가 발생했습니다: $e';
        _isLoading = false;
      });
      _showSnackBar('설정 초기화 중 오류가 발생했습니다: $e', isError: true);
    }
  }

  // 비밀번호 확인 다이얼로그
  void _showPasswordDialog() {
    setState(() {
      _isPasswordDialogOpen = true;
      _passwordController.text = '';
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('관리자 인증'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('설정을 변경하려면 관리자 비밀번호를 입력하세요'),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: '비밀번호',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _isPasswordDialogOpen = false;
                  _isLoading = false;
                });
              },
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _isPasswordDialogOpen = false;
                });
                _saveSettingsWithPassword(_passwordController.text);
              },
              child: const Text('확인'),
            ),
          ],
        );
      },
    );
  }

  // 텍스트 입력 다이얼로그 (Windows 등 파일 선택기 미지원 플랫폼용)
  void _showTextInputDialog(String title, String message, TextEditingController controller) {
    final TextEditingController tempController = TextEditingController(text: controller.text);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message),
              const SizedBox(height: 16),
              TextField(
                controller: tempController,
                decoration: const InputDecoration(
                  labelText: '경로',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              if (PlatformUtil.isDesktop)
                TextButton.icon(
                  icon: const Icon(Icons.content_paste),
                  label: const Text('직접 입력하세요'),
                  onPressed: () {
                    // 클립보드 기능이 없으므로 그냥 안내만 제공
                    // 실제로는 클립보드 기능을 사용해야 함
                  },
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  controller.text = tempController.text;
                });
              },
              child: const Text('확인'),
            ),
          ],
        );
      },
    );
  }

  // 스낵바 표시
  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('관리자 설정'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '시스템 제어'),
            Tab(text: 'API 설정'),
            Tab(text: '파일 관리'),
            Tab(text: '주차장 관리'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildSystemControlTab(),
                _buildApiSettingsTab(),
                _buildFileManagementTab(),
                _buildParkingLotsTab(),
              ],
            ),
    );
  }

  // 주차장 관리 탭
  Widget _buildParkingLotsTab() {
    return const ParkingLotsAdminScreen();
  }

  // 시스템 제어 탭
  Widget _buildSystemControlTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '시스템 상태',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(
                        _isSystemRunning ? Icons.check_circle : Icons.error,
                        color: _isSystemRunning ? Colors.green : Colors.red,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isSystemRunning ? '실행 중' : '중지됨',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _isSystemRunning ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('시스템 시작'),
                          onPressed: _isSystemRunning ? null : _startSystem,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.stop),
                          label: const Text('시스템 중지'),
                          onPressed: _isSystemRunning ? _stopSystem : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '시스템 정보',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow('앱 버전', AppConfig.appVersion),
                  _buildInfoRow('서버 URL', _settings.apiUrl),
                  _buildInfoRow('플랫폼', PlatformUtil.platformName),
                  _buildInfoRow('마지막 업데이트', _formatDateTime(_settings.lastUpdated)),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '기능 지원 상태',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildFeatureStatusRow(
                    '지도 기능',
                    PlatformUtil.isMapsSupported,
                    '현재 플랫폼에서 지도 기능을 ${PlatformUtil.isMapsSupported ? '사용할 수 있습니다' : '사용할 수 없습니다'}',
                  ),
                  _buildFeatureStatusRow(
                    '차트 기능',
                    PlatformUtil.isChartSupported,
                    '현재 플랫폼에서 차트 기능을 ${PlatformUtil.isChartSupported ? '사용할 수 있습니다' : '사용할 수 없습니다'}',
                  ),
                  _buildFeatureStatusRow(
                    '파일 선택 기능',
                    PlatformUtil.isFilePickerSupported,
                    '현재 플랫폼에서 파일 선택 기능을 ${PlatformUtil.isFilePickerSupported ? '사용할 수 있습니다' : '사용할 수 없습니다'}',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // API 설정 탭
  Widget _buildApiSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'API 설정',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 16),

          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '서버 연결 설정',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _apiUrlController,
                    decoration: const InputDecoration(
                      labelText: 'API URL',
                      hintText: 'http://localhost:5000',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.link),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '서버 API URL을 설정합니다. 기본값은 http://localhost:5000 입니다.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'API 설정 관리',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '마지막 업데이트: ${_formatDateTime(_settings.lastUpdated)}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: const Text('설정 초기화'),
                          onPressed: _resetSettings,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.save),
                          label: const Text('설정 저장'),
                          onPressed: _saveSettings,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 파일 관리 탭
  Widget _buildFileManagementTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '파일 관리',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 16),

          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'YOLO 모델 경로',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _modelPathController,
                    decoration: const InputDecoration(
                      labelText: '모델 파일 경로',
                      hintText: '/path/to/model.pt',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.model_training),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'YOLOv8 모델 파일(.pt)의 경로를 설정합니다.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: _isModelUploading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.upload_file),
                      label: Text(_isModelUploading ? '업로드 중...' : '모델 파일 선택'),
                      onPressed: _isModelUploading ? null : _selectModelFile,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '비디오 소스 설정',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _videoPathController,
                    decoration: const InputDecoration(
                      labelText: '비디오 파일 경로 또는 RTSP URL',
                      hintText: '/path/to/video.mp4 또는 rtsp://...',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.videocam),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '주차장 영상 파일(.mp4, .avi 등) 또는 RTSP 스트림 URL을 설정합니다.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: _isVideoUploading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.upload_file),
                          label: Text(_isVideoUploading ? '업로드 중...' : '비디오 파일 선택'),
                          onPressed: _isVideoUploading ? null : _selectVideoFile,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.camera),
                          label: const Text('RTSP 스트림 설정'),
                          onPressed: _configureRtspStream,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          Card(
            elevation: 4,
            color: Colors.yellow.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info, color: Colors.orange),
                      SizedBox(width: 8),
                      Text(
                        '파일 선택 제한 안내',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                  '현재 플랫폼(${PlatformUtil.platformName})에서는 파일 선택기 기능이 제한됩니다. '
                    '파일 경로를 직접 입력해 주세요.',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.save),
              label: const Text('설정 저장'),
              onPressed: _saveSettings,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 정보 행 위젯
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // 기능 지원 상태 행 위젯
  Widget _buildFeatureStatusRow(String feature, bool isSupported, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isSupported ? Icons.check_circle : Icons.cancel,
            color: isSupported ? Colors.green : Colors.red,
            size: 24,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  feature,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 날짜 형식화
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}/${dateTime.month}/${dateTime.day} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}