// screens/home_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../models/parking_model.dart';
import '../services/parking_service.dart';
import '../services/location_service.dart';
import '../widgets/common_widgets.dart';
import '../widgets/parking_lot_view.dart';
import 'statistics_screen.dart';
import 'admin_screen.dart';
import 'campus_map_screen.dart';

class HomeScreen extends StatefulWidget {
  final String? initialParkingLotId;

  const HomeScreen({super.key, this.initialParkingLotId});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ParkingService _parkingService = ParkingService();
  final LocationService _locationService = LocationService();

  // State variables
  ParkingStatus? _parkingStatus;
  String? _errorMessage;
  bool _isLoading = true;
  bool _isRefreshing = false;
  DateTime? _lastUpdated;
  String? _selectedParkingLotId;

  // Auto-refresh timer
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();

    // Set initially selected parking lot if provided
    _selectedParkingLotId = widget.initialParkingLotId;

    // Load initial data
    _fetchParkingStatus();

    // Set up auto-refresh timer
    _refreshTimer = Timer.periodic(
      Duration(seconds: AppConfig.refreshInterval),
      (_) => _refreshData()
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // Fetch parking status data
  Future<void> _fetchParkingStatus() async {
    if (_isRefreshing) return;

    setState(() {
      _isLoading = _parkingStatus == null;
      _isRefreshing = _parkingStatus != null;
      _errorMessage = null;
    });

    try {
      final status = await _parkingService.getParkingStatus();

      setState(() {
        _parkingStatus = status;
        _isLoading = false;
        _isRefreshing = false;
        _lastUpdated = DateTime.now();
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  // Refresh data (user-initiated)
  Future<void> _refreshData() async {
    await _fetchParkingStatus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('상세정보'),
        actions: [
          // Map button
          IconButton(
            icon: const Icon(Icons.map),
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const CampusMapScreen(),
                ),
              );
            },
            tooltip: '캠퍼스 지도',
          ),
          RefreshAction(
            onRefresh: _refreshData,
            isLoading: _isRefreshing,
          ),
          IconButton(
            icon: const Icon(Icons.insert_chart),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const StatisticsScreen(),
                ),
              );
            },
            tooltip: '통계',
          ),
          // Admin settings menu
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'admin') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AdminScreen(),
                  ),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'admin',
                child: Row(
                  children: [
                    Icon(Icons.admin_panel_settings),
                    SizedBox(width: 8),
                    Text('관리자 설정'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  // Build screen body
  Widget _buildBody() {
    if (_isLoading) {
      return const LoadingWidget(message: '주차장 정보를 불러오는 중...');
    }

    if (_errorMessage != null) {
      return CommonErrorWidget(
        message: _errorMessage!,
        onRetry: _fetchParkingStatus,
      );
    }

    return _buildParkingStatusView();
  }

  // Build parking status view
  Widget _buildParkingStatusView() {
    final status = _parkingStatus!;

    return RefreshIndicator(
      onRefresh: _refreshData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Last updated time
            if (_lastUpdated != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 0),
                child: Text(
                  '마지막 업데이트: ${_formatDateTime(_lastUpdated!)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ),

            // Campus map shortcut card
            Card(
              margin: const EdgeInsets.all(16.0),
              child: InkWell(
                onTap: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const CampusMapScreen()),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(Icons.map, size: 48, color: Theme.of(context).primaryColor),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '캠퍼스 지도 보기',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Text(
                              '전체 주차장 현황을 지도에서 확인하세요',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios),
                    ],
                  ),
                ),
              ),
            ),

            // Parking lot selector tabs
            _buildParkingLotTabs(status),

            // Main info cards grid
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // 화면 너비에 따라 열 개수 및 비율 조정
                  int crossAxisCount = constraints.maxWidth > 360 ? 2 : 1;
                  double childAspectRatio = constraints.maxWidth > 360 ? 1.5 : 2.0;

                  return GridView.count(
                    crossAxisCount: crossAxisCount,
                    childAspectRatio: childAspectRatio,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    children: [
                      // Total available spaces
                      InfoCard(
                        title: '주차 가능',
                        value: '${status.totalAvailableSpaces}대',
                        icon: Icons.local_parking,
                        color: Colors.green,
                      ),

                      // Occupancy rate
                      InfoCard(
                        title: '점유율',
                        value: '${status.overallOccupancyRate.toStringAsFixed(1)}%',
                        icon: Icons.pie_chart,
                        color: _getOccupancyColor(status.overallOccupancyRate),
                      ),

                      // Disabled parking spaces
                      InfoCard(
                        title: '장애인 주차',
                        value: '${status.disabledAvailableSpaces}대',
                        icon: Icons.accessible,
                        color: Colors.blue,
                      ),

                      // Total parking spaces
                      InfoCard(
                        title: '전체 주차',
                        value: '${status.totalSpaces}대',
                        icon: Icons.grid_view,
                      ),
                    ],
                  );
                }
              ),
            ),

            const Divider(height: 32),

            // Occupancy visualization
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Center(
                child: OccupancyIndicator(
                  occupancyRate: status.overallOccupancyRate,
                  size: 180,
                ),
              ),
            ),

            const Divider(height: 32),

            // Selected parking lot details
            _buildSelectedParkingLotView(status),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // Build parking lot selector tabs - 개선된 버전
  Widget _buildParkingLotTabs(ParkingStatus status) {
    // 모든 주차장 목록
    final List<Map<String, String>> allParkingLots = [
      {'id': 'parking_lot_A', 'name': '55호관 주차장'},
      {'id': 'parking_lot_B', 'name': '도서관 주차장'},
      {'id': 'parking_lot_C', 'name': '대학본부 주차장'},
      {'id': 'parking_lot_D', 'name': '53호관 주차장'},
    ];

    return Container(
      height: 60,
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: allParkingLots.length,
        itemBuilder: (context, index) {
          final lotInfo = allParkingLots[index];
          final lotId = lotInfo['id']!;
          final lotName = lotInfo['name']!;

          // 현재 시스템에 등록된 주차장인지 확인
          final lotStatus = status.parkingLots[lotId];

          final isSelected = _selectedParkingLotId == lotId ||
                        (_selectedParkingLotId == null && index == 0);

          if (_selectedParkingLotId == null && index == 0) {
            _selectedParkingLotId = lotId;
          }

          // 선택 가능 여부 (데이터가 있는 주차장만 선택 가능)
          final isEnabled = lotStatus != null;

          // 사용 가능한 공간에 맞게 탭 너비 조정 (고정 너비 대신 유연하게)
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: InkWell(
              onTap: isEnabled ? () {
                setState(() {
                  _selectedParkingLotId = lotId;
                });
              } : null,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                // 고정 패딩 대신 텍스트 크기에 맞게 조정
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(context).primaryColor
                      : isEnabled ? Colors.grey.shade200 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: !isEnabled
                      ? Border.all(color: Colors.grey.shade300)
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      lotName,
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : isEnabled ? Colors.black : Colors.grey,
                        fontWeight: FontWeight.bold,
                        fontSize: 12, // 폰트 크기 축소
                      ),
                    ),
                    if (lotStatus != null)
                      Text(
                        '${lotStatus.availableSpaces}/${lotStatus.totalSpaces}',
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : _getOccupancyColor(lotStatus.occupancyRate),
                          fontSize: 10, // 폰트 크기 축소
                        ),
                      )
                    else
                      Text(
                        '데이터 없음',
                        style: TextStyle(
                          color: isSelected ? Colors.white70 : Colors.grey,
                          fontSize: 9, // 폰트 크기 축소
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Build selected parking lot view
  Widget _buildSelectedParkingLotView(ParkingStatus status) {
    if (_selectedParkingLotId == null) return const SizedBox();

    final lotStatus = status.parkingLots[_selectedParkingLotId];
    if (lotStatus == null) return const SizedBox();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 4,
      child: ParkingLotView(
        parkingLotId: _selectedParkingLotId!,
        parkingLotStatus: lotStatus,
      ),
    );
  }

  // Get color based on occupancy rate
  Color _getOccupancyColor(double occupancyRate) {
    if (occupancyRate < 50) {
      return Colors.green;
    } else if (occupancyRate < 80) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }

  // Format date and time
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}/${dateTime.month}/${dateTime.day} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}

// Error widget
class CommonErrorWidget extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const CommonErrorWidget({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline,
            color: Colors.red,
            size: 60,
          ),
          const SizedBox(height: 16),
          Text(
            '오류가 발생했습니다',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(message),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRetry,
            child: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }
}