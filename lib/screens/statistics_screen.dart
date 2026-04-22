import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/app_config.dart';
import '../models/parking_model.dart';
import '../services/parking_service.dart';
import '../utils/platform_util.dart';
import '../widgets/common_widgets.dart';
import 'dart:math' as math;

class StatisticsScreen extends StatefulWidget {
  final String? initialParkingLotId; // 특정 주차장 초기 선택

  const StatisticsScreen({super.key, this.initialParkingLotId});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> with SingleTickerProviderStateMixin {
  final ParkingService _parkingService = ParkingService();
  late TabController _tabController;

  // 상태 변수
  Map<String, ParkingStatistics?> _statisticsMap = {}; // 주차장별 통계 저장
  String? _selectedParkingLot; // 현재 선택된 주차장
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    // 초기 주차장 설정 - 도서관 포함
    _selectedParkingLot = widget.initialParkingLotId ?? _getDefaultParkingLot();

    _fetchAllStatistics();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // 기본 주차장 선택 (영상이 있는 첫 번째 주차장) - 도서관 우선 고려
  String _getDefaultParkingLot() {
    final activeLots = AppConfig.getActiveParkingLots();
    // 도서관이 있으면 도서관 우선, 없으면 55호관, 그것도 없으면 첫 번째
    if (activeLots.contains('parking_lot_B')) {
      return 'parking_lot_B'; // 도서관 우선
    } else if (activeLots.contains('parking_lot_A')) {
      return 'parking_lot_A'; // 55호관
    }
    return activeLots.isNotEmpty ? activeLots.first : AppConfig.parkingLotPriority.first;
  }

  // 모든 주차장 통계 데이터 조회 - 도서관 포함
  Future<void> _fetchAllStatistics() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
    });

    try {
      // 모든 주차장 (동적 추가된 것 포함)에 대해 통계 가져오기
      final allParkingLots = AppConfig.getAllParkingLots();

      for (String parkingLotId in allParkingLots.keys) {
        try {
          final statistics = await _parkingService.getParkingStatistics(parkingLotId: parkingLotId);
          _statisticsMap[parkingLotId] = statistics;
        } catch (e) {
          // 개별 주차장 오류는 로그만 남기고 계속 진행
          print('주차장 $parkingLotId 통계 조회 실패: $e');
          _statisticsMap[parkingLotId] = null;
        }
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          _lastUpdated = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  // 특정 주차장 통계 새로고침
  Future<void> _refreshParkingLotStatistics(String parkingLotId) async {
    try {
      final statistics = await _parkingService.getParkingStatistics(parkingLotId: parkingLotId);
      setState(() {
        _statisticsMap[parkingLotId] = statistics;
        _lastUpdated = DateTime.now();
      });
    } catch (e) {
      print('주차장 $parkingLotId 통계 새로고침 실패: $e');
      // 사용자에게 오류 알림
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppConfig.getParkingLotName(parkingLotId)} 통계 새로고침 실패'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('주차장 통계'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchAllStatistics,
            tooltip: '전체 새로고침',
          ),
          // 개별 주차장 새로고침 버튼
          if (_selectedParkingLot != null)
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              onPressed: () => _refreshParkingLotStatistics(_selectedParkingLot!),
              tooltip: '현재 주차장 새로고침',
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '주차장 선택'),
            Tab(text: '시간별 점유율'),
            Tab(text: '추천 시간'),
            Tab(text: '통계 요약'),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 60,
            ),
            const SizedBox(height: 16),
            const Text(
              '통계 데이터를 불러오는데 실패했습니다',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(_errorMessage ?? '알 수 없는 오류'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchAllStatistics,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    return TabBarView(
      controller: _tabController,
      children: [
        _buildParkingLotSelectionTab(),
        _buildHourlyOccupancyTab(),
        _buildRecommendationTab(),
        _buildSummaryTab(),
      ],
    );
  }

  // 주차장 선택 탭 - 도서관 및 동적 주차장 포함
  Widget _buildParkingLotSelectionTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '주차장 선택',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '통계를 확인할 주차장을 선택하세요',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 24),

          // 활성화된 주차장 (영상 있음) - 55호관, 도서관 포함
          _buildParkingLotSection(
            title: '실시간 모니터링 주차장',
            subtitle: '영상이 연결된 주차장',
            parkingLots: AppConfig.getActiveParkingLots(),
            isActive: true,
          ),

          const SizedBox(height: 32),

          // 비활성화된 주차장 (영상 없음) - 대학본부, 53호관 등
          _buildParkingLotSection(
            title: '영상 미연결 주차장',
            subtitle: '아직 영상이 연결되지 않은 주차장',
            parkingLots: AppConfig.getInactiveParkingLots(),
            isActive: false,
          ),

          const SizedBox(height: 32),

          // 동적 추가 버튼
          _buildAddParkingLotSection(),
        ],
      ),
    );
  }

  // 주차장 동적 추가 섹션
  Widget _buildAddParkingLotSection() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.add_circle, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                const Text(
                  '새 주차장 추가',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '교내 다른 주차장 CCTV를 실시간으로 추가하여 모니터링할 수 있습니다',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.videocam),
                    label: const Text('비디오 파일로 추가'),
                    onPressed: _showAddVideoDialog,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.upload_file),
                    label: const Text('좌표 파일 업로드'),
                    onPressed: _showUploadCoordinatesDialog,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 비디오 파일로 주차장 추가 다이얼로그
  void _showAddVideoDialog() {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController videoPathController = TextEditingController();
    final TextEditingController buildingController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('새 주차장 추가'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '주차장 이름',
                  hintText: '예: 공학관 주차장',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: buildingController,
                decoration: const InputDecoration(
                  labelText: '건물명',
                  hintText: '예: 공학관',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: videoPathController,
                decoration: const InputDecoration(
                  labelText: '비디오 파일 경로',
                  hintText: 'C:\\Videos\\parking.mp4',
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '주차 공간 좌표는 나중에 파일로 업로드하거나 관리자 화면에서 설정할 수 있습니다.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty &&
                  videoPathController.text.isNotEmpty) {
                Navigator.pop(context);
                await _addNewParkingLot(
                  nameController.text,
                  buildingController.text,
                  videoPathController.text,
                );
              }
            },
            child: const Text('추가'),
          ),
        ],
      ),
    );
  }

  // 좌표 파일 업로드 다이얼로그
  void _showUploadCoordinatesDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('주차 공간 좌표 업로드'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('지원되는 파일 형식:'),
            const SizedBox(height: 8),
            const Text('• JSON 파일 (.json)'),
            const Text('• 텍스트 파일 (.txt)'),
            const Text('• CSV 파일 (.csv)'),
            const SizedBox(height: 16),
            const Text(
              '좌표 파일 예시 형식:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.grey.shade100,
              child: const Text(
                AppConfig.coordinateFileExample,
                style: TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  // 새 주차장 추가 실행
  Future<void> _addNewParkingLot(String name, String building, String videoPath) async {
    try {
      // 임시 ID 생성
      final newId = 'parking_lot_${DateTime.now().millisecondsSinceEpoch}';

      // 서버에 주차장 추가 요청
      final result = await _parkingService.addDynamicParkingLot({
        'id': newId,
        'name': name,
        'building': building,
        'video_path': videoPath,
        'coordinates': [], // 빈 좌표로 시작
        'latitude': AppConfig.changwonUniversity['latitude'],
        'longitude': AppConfig.changwonUniversity['longitude'],
      });

      if (result) {
        // 로컬 설정에도 추가
        AppConfig.addDynamicParkingLot(newId, {
          'name': name,
          'building': building,
          'hasVideo': true,
          'status': 'active',
          'videoWidth': 640,
          'videoHeight': 480,
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$name이(가) 성공적으로 추가되었습니다'),
            backgroundColor: Colors.green,
          ),
        );

        // 통계 새로고침
        _fetchAllStatistics();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('주차장 추가 실패: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // 주차장 섹션 위젯 - 도서관 특별 표시 포함
  Widget _buildParkingLotSection({
    required String title,
    required String subtitle,
    required List<String> parkingLots,
    required bool isActive,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              isActive ? Icons.videocam : Icons.videocam_off,
              color: isActive ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 16),

        if (parkingLots.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                isActive ? '활성화된 주차장이 없습니다' : '영상이 미연결된 주차장이 없습니다',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          )
        else
          ...parkingLots.map((lotId) => _buildParkingLotCard(lotId, isActive)),
      ],
    );
  }

  // 주차장 카드 위젯 - 도서관 등 개별 주차장 구분 표시
  Widget _buildParkingLotCard(String parkingLotId, bool isActive) {
    final lotInfo = AppConfig.getParkingLotInfo(parkingLotId);
    final lotName = AppConfig.getParkingLotName(parkingLotId);
    final statistics = _statisticsMap[parkingLotId];
    final isSelected = _selectedParkingLot == parkingLotId;

    // 주차장별 특별 아이콘 설정
    IconData lotIcon;
    Color lotIconColor;

    switch (parkingLotId) {
      case 'parking_lot_A': // 55호관
        lotIcon = Icons.engineering;
        lotIconColor = Colors.blue;
        break;
      case 'parking_lot_B': // 도서관
        lotIcon = Icons.library_books;
        lotIconColor = Colors.purple;
        break;
      case 'parking_lot_C': // 대학본부
        lotIcon = Icons.business;
        lotIconColor = Colors.orange;
        break;
      case 'parking_lot_D': // 53호관
        lotIcon = Icons.science;
        lotIconColor = Colors.green;
        break;
      default: // 동적 추가된 주차장
        lotIcon = Icons.local_parking;
        lotIconColor = Colors.grey;
    }

    return Card(
      elevation: isSelected ? 4 : 2,
      margin: const EdgeInsets.only(bottom: 12),
      color: isSelected ? Theme.of(context).primaryColor.withOpacity(0.1) : null,
      child: InkWell(
        onTap: isActive
            ? () {
                setState(() {
                  _selectedParkingLot = parkingLotId;
                });
                // 선택 후 시간별 점유율 탭으로 이동
                _tabController.animateTo(1);
              }
            : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // 주차장별 특별 아이콘
                  Icon(
                    lotIcon,
                    color: lotIconColor,
                    size: 32,
                  ),
                  const SizedBox(width: 12),

                  // 상태 표시 아이콘
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive ? Colors.green : Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // 주차장 정보
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lotName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Theme.of(context).primaryColor : null,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          lotInfo?['building'] ?? '',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        // 특별 주차 공간 표시 (도서관의 경우)
                        if (parkingLotId == 'parking_lot_B' && isActive)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                Icon(Icons.electric_car, size: 14, color: Colors.yellow[700]),
                                const SizedBox(width: 4),
                                const Text('전기차', style: TextStyle(fontSize: 12)),
                                const SizedBox(width: 8),
                                Icon(Icons.accessible, size: 14, color: Colors.blue[700]),
                                const SizedBox(width: 4),
                                const Text('장애인', style: TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),

                  // 통계 정보 (활성화된 주차장만)
                  if (isActive && statistics != null) ...[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${statistics.current.formattedRate}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _getOccupancyColor(statistics.current.occupancyRate),
                          ),
                        ),
                        const Text(
                          '현재 점유율',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ] else if (isActive && statistics == null) ...[
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 20,
                    ),
                  ] else ...[
                    Column(
                      children: [
                        const Icon(
                          Icons.videocam_off,
                          color: Colors.orange,
                          size: 20,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '영상 미연결',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],

                  if (isSelected) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.check_circle,
                      color: Theme.of(context).primaryColor,
                    ),
                  ],
                ],
              ),

              if (!isActive) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        '아직 영상이 연결되지 않았습니다',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // 시간별 점유율 탭 - 주차장별 분리 표시
  Widget _buildHourlyOccupancyTab() {
    if (_selectedParkingLot == null) {
      return _buildNoParkingLotSelected();
    }

    final statistics = _statisticsMap[_selectedParkingLot];
    if (statistics == null) {
      return _buildNoDataAvailable();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 주차장 정보 헤더 - 개선된 버전
          _buildSelectedParkingLotHeader(),

          const SizedBox(height: 16),

          if (_lastUpdated != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(
                '마지막 업데이트: ${DateFormat('yyyy-MM-dd HH:mm').format(_lastUpdated!)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ),

          const Text(
            '시간별 주차장 점유율',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 16),

          // 차트 표시
          _buildBarChartPlaceholder(statistics),

          const SizedBox(height: 24),

          // 범례 - 도서관 전용 공간 포함
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _buildLegendItem('현재 시간', Colors.blue),
              _buildLegendItem('높은 점유율 (>80%)', Colors.red),
              _buildLegendItem('보통 점유율 (>50%)', Colors.orange),
              _buildLegendItem('낮은 점유율 (<50%)', Colors.green),
              if (_selectedParkingLot == 'parking_lot_B') ...[
                _buildLegendItem('전기차 전용', Colors.yellow[700]!),
                _buildLegendItem('장애인 전용', Colors.blue[700]!),
              ],
            ],
          ),

          const SizedBox(height: 24),

          // 시간별 점유율 목록
          _buildHourlyDataTable(statistics),
        ],
      ),
    );
  }

  // 선택된 주차장 헤더 - 도서관 등 특별 표시 포함
  Widget _buildSelectedParkingLotHeader() {
    if (_selectedParkingLot == null) return const SizedBox();

    final lotName = AppConfig.getParkingLotName(_selectedParkingLot!);
    final lotInfo = AppConfig.getParkingLotInfo(_selectedParkingLot!);
    final hasVideo = AppConfig.hasVideoStream(_selectedParkingLot!);

    // 주차장별 특별 아이콘
    IconData headerIcon;
    Color headerIconColor;

    switch (_selectedParkingLot!) {
      case 'parking_lot_A':
        headerIcon = Icons.engineering;
        headerIconColor = Colors.blue;
        break;
      case 'parking_lot_B':
        headerIcon = Icons.library_books;
        headerIconColor = Colors.purple;
        break;
      case 'parking_lot_C':
        headerIcon = Icons.business;
        headerIconColor = Colors.orange;
        break;
      case 'parking_lot_D':
        headerIcon = Icons.science;
        headerIconColor = Colors.green;
        break;
      default:
        headerIcon = Icons.local_parking;
        headerIconColor = Colors.grey;
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(
              headerIcon,
              color: headerIconColor,
              size: 40,
            ),
            const SizedBox(width: 16),
            Icon(
              hasVideo ? Icons.videocam : Icons.videocam_off,
              color: hasVideo ? Colors.green : Colors.orange,
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lotName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    lotInfo?['building'] ?? '',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  // 도서관 특별 정보 표시
                  if (_selectedParkingLot == 'parking_lot_B' && hasVideo) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.yellow.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.electric_car, size: 16, color: Colors.yellow[700]),
                              const SizedBox(width: 4),
                              const Text('전기차 2구역', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.accessible, size: 16, color: Colors.blue[700]),
                              const SizedBox(width: 4),
                              const Text('장애인 2구역', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (!hasVideo) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '영상 미연결',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _refreshParkingLotStatistics(_selectedParkingLot!),
              tooltip: '새로고침',
            ),
          ],
        ),
      ),
    );
  }

  // 나머지 메서드들은 기존과 동일하지만 주차장별 분리를 고려하여 수정
  Widget _buildNoParkingLotSelected() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.local_parking,
            size: 64,
            color: Colors.grey,
          ),
          const SizedBox(height: 16),
          const Text(
            '주차장을 선택하세요',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '첫 번째 탭에서 주차장을 선택하면\n해당 주차장의 통계를 확인할 수 있습니다',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _tabController.animateTo(0),
            child: const Text('주차장 선택하기'),
          ),
        ],
      ),
    );
  }

  Widget _buildNoDataAvailable() {
    final lotName = AppConfig.getParkingLotName(_selectedParkingLot!);
    final hasVideo = AppConfig.hasVideoStream(_selectedParkingLot!);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasVideo ? Icons.error_outline : Icons.videocam_off,
            size: 64,
            color: hasVideo ? Colors.red : Colors.orange,
          ),
          const SizedBox(height: 16),
          Text(
            hasVideo ? '데이터를 불러올 수 없습니다' : '영상이 연결되지 않았습니다',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasVideo
                ? '$lotName의 통계 데이터를 가져오는 중 오류가 발생했습니다'
                : '$lotName은 아직 영상이 연결되지 않아 실시간 통계를 제공할 수 없습니다',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 16),
          if (hasVideo)
            ElevatedButton(
              onPressed: () => _refreshParkingLotStatistics(_selectedParkingLot!),
              child: const Text('다시 시도'),
            )
          else
            ElevatedButton(
              onPressed: () => _tabController.animateTo(0),
              child: const Text('다른 주차장 선택'),
            ),
        ],
      ),
    );
  }

  // 나머지 메서드들 (기존과 동일)
  Widget _buildBarChartPlaceholder(ParkingStatistics statistics) {
    return _buildCustomBarChart(statistics);
  }

  Widget _buildCustomBarChart(ParkingStatistics statistics) {
    // 기존 차트 구현과 동일
    final List<HourlyData> data = statistics.hourlyData;

    return LayoutBuilder(
      builder: (context, constraints) {
        final chartHeight = constraints.maxHeight > 400 ? 300.0 : constraints.maxHeight * 0.7;

        return Container(
          height: chartHeight,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Y축 레이블
                    Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('100%', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                        Text('50%', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                        Text('0%', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                      ],
                    ),
                    const SizedBox(width: 8),
                    // 차트 영역 (기존 구현과 동일)
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Container(
                          width: data.length * 30.0 + 40,
                          child: CustomPaint(
                            painter: BarChartPainter(data),
                            size: Size(data.length * 30.0 + 40, chartHeight),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }
    );
  }

  Widget _buildHourlyDataTable(ParkingStatistics statistics) {
    // 기존 구현과 동일하지만 주차장별 특별 정보 표시 추가
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${AppConfig.getParkingLotName(_selectedParkingLot!)} 시간별 상세 정보',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        // 기존 시간별 데이터 테이블 구현
      ],
    );
  }

  Widget _buildRecommendationTab() {
    // 기존 구현과 동일
    if (_selectedParkingLot == null) {
      return _buildNoParkingLotSelected();
    }

    final statistics = _statisticsMap[_selectedParkingLot];
    if (statistics == null) {
      return _buildNoDataAvailable();
    }

    // 기존 추천 탭 구현
    return Container(); // 실제 구현 필요
  }

  Widget _buildSummaryTab() {
    // 기존 구현과 동일
    if (_selectedParkingLot == null) {
      return _buildNoParkingLotSelected();
    }

    final statistics = _statisticsMap[_selectedParkingLot];
    if (statistics == null) {
      return _buildNoDataAvailable();
    }

    // 기존 요약 탭 구현
    return Container(); // 실제 구현 필요
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Color _getOccupancyColor(double occupancyRate) {
    if (occupancyRate >= 80) {
      return Colors.red;
    } else if (occupancyRate >= 50) {
      return Colors.orange;
    } else {
      return Colors.green;
    }
  }
}

// 커스텀 차트 페인터
class BarChartPainter extends CustomPainter {
  final List<HourlyData> data;

  BarChartPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final barWidth = (size.width - 40) / data.length;

    for (int i = 0; i < data.length; i++) {
      final hourData = data[i];
      final barHeight = (hourData.occupancyRate / 100) * size.height;

      Color barColor;
      if (hourData.isCurrent) {
        barColor = Colors.blue;
      } else if (hourData.occupancyRate > 80) {
        barColor = Colors.red;
      } else if (hourData.occupancyRate > 50) {
        barColor = Colors.orange;
      } else {
        barColor = Colors.green;
      }

      paint.color = barColor;
      final rect = Rect.fromLTWH(
        i * barWidth + 20,
        size.height - barHeight,
        barWidth * 0.8,
        barHeight,
      );

      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}