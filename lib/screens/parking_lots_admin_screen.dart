// screens/parking_lots_admin_screen.dart
// 주차장 관리 화면

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../config/app_config.dart';
import '../models/parking_lot_config_model.dart';
import '../services/parking_lot_config_service.dart';
import '../utils/platform_util.dart';
import 'parking_lot_edit_screen.dart';

class ParkingLotsAdminScreen extends StatefulWidget {
  const ParkingLotsAdminScreen({Key? key}) : super(key: key);

  @override
  State<ParkingLotsAdminScreen> createState() => _ParkingLotsAdminScreenState();
}

class _ParkingLotsAdminScreenState extends State<ParkingLotsAdminScreen> {
  final ParkingLotConfigService _configService = ParkingLotConfigService();
  List<ParkingLotConfig> _parkingLots = [];
  bool _isLoading = true;
  String? _errorMessage;

  // GoogleMap 컨트롤러
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polygon> _polygons = {};

  // 지도 초기 위치 (창원대학교)
  final CameraPosition _initialCameraPosition = CameraPosition(
    target: LatLng(AppConfig.changwonUniversity['latitude'] as double,
                  AppConfig.changwonUniversity['longitude'] as double),
    zoom: 15.0,
  );

  @override
  void initState() {
    super.initState();
    _loadParkingLots();
  }

  // 주차장 목록 로드
  Future<void> _loadParkingLots() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final lots = await _configService.loadConfigurations();

      setState(() {
        _parkingLots = lots;
        _isLoading = false;
      });

      // 지도 마커 및 다각형 업데이트
      if (PlatformUtil.isMapsSupported) {
        _updateMapMarkersAndPolygons();
      }
    } catch (e) {
      setState(() {
        _errorMessage = '주차장 정보를 불러오는 중 오류가 발생했습니다: $e';
        _isLoading = false;
      });
    }
  }

  // 지도 마커 및 다각형 업데이트
  void _updateMapMarkersAndPolygons() {
    if (_mapController == null) return;

    setState(() {
      _markers.clear();
      _polygons.clear();

      for (var lot in _parkingLots) {
        // 마커 추가
        _markers.add(
          Marker(
            markerId: MarkerId(lot.id),
            position: LatLng(lot.latitude, lot.longitude),
            infoWindow: InfoWindow(
              title: lot.name,
              snippet: '${lot.building} (${lot.capacity}대 주차 가능)',
            ),
            onTap: () {
              _showParkingLotDetails(lot);
            },
          ),
        );

        // 주차 구역 다각형 추가
        if (lot.parkingSpaces.isNotEmpty) {
          for (int i = 0; i < lot.parkingSpaces.length; i++) {
            final points = lot.parkingSpaces[i];
            if (points.length >= 3) { // 다각형이 유효한지 확인
              _polygons.add(
                Polygon(
                  polygonId: PolygonId('${lot.id}_$i'),
                  points: points,
                  fillColor: Colors.blue.withOpacity(0.3),
                  strokeColor: Colors.blue,
                  strokeWidth: 2,
                ),
              );
            }
          }
        }
      }
    });
  }

  // 주차장 세부 정보 표시
  void _showParkingLotDetails(ParkingLotConfig lot) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          maxChildSize: 0.9,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drag handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 주차장 이름 및 건물 정보
                    Row(
                      children: [
                        const Icon(Icons.local_parking, size: 28, color: Colors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                lot.name,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                lot.building,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 주차장 정보
                    _buildInfoSection(
                      title: '주차장 정보',
                      items: [
                        _buildInfoItem('수용 대수', '${lot.capacity}대'),
                        _buildInfoItem('주차장 유형', lot.type == 'outdoor' ? '실외' : '실내'),
                        _buildInfoItem('장애인 주차', lot.hasDisabledSpaces ? '가능' : '없음'),
                        _buildInfoItem('운영 시간', lot.openHours),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // 좌표 정보
                    _buildInfoSection(
                      title: '위치 정보',
                      items: [
                        _buildInfoItem('위도', lot.latitude.toString()),
                        _buildInfoItem('경도', lot.longitude.toString()),
                      ],
                    ),

                    if (lot.videoSource.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildInfoSection(
                        title: '비디오 소스',
                        items: [
                          _buildInfoItem('비디오 경로', lot.videoSource),
                        ],
                      ),
                    ],

                    if (lot.description.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildInfoSection(
                        title: '설명',
                        child: Text(lot.description),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // 주차장 편집 및 삭제 버튼
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _editParkingLot(lot),
                            icon: const Icon(Icons.edit),
                            label: const Text('주차장 편집'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _deleteParkingLot(lot),
                            icon: const Icon(Icons.delete),
                            label: const Text('주차장 삭제'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // 정보 섹션 위젯
  Widget _buildInfoSection({
    required String title,
    List<Widget>? items,
    Widget? child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Divider(),
        if (items != null) ...items,
        if (child != null) child,
      ],
    );
  }

  // 정보 항목 위젯
  Widget _buildInfoItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 주차장 편집
  Future<void> _editParkingLot(ParkingLotConfig lot) async {
    Navigator.pop(context); // 바텀시트 닫기

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ParkingLotEditScreen(
          parkingLot: lot,
        ),
      ),
    );

    if (result == true) {
      _loadParkingLots();
    }
  }

  // 주차장 삭제
  Future<void> _deleteParkingLot(ParkingLotConfig lot) async {
    Navigator.pop(context); // 바텀시트 닫기

    // 삭제 확인 다이얼로그
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('주차장 삭제'),
        content: Text('정말로 "${lot.name}" 주차장을 삭제하시겠습니까?\n이 작업은 취소할 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    ) ?? false;

    if (confirmed) {
      setState(() {
        _isLoading = true;
      });

      try {
        final success = await _configService.removeLot(lot.id);

        if (success) {
          // 서버에도 삭제 요청 (오류가 나도 로컬에서는 삭제됨)
          try {
            await _configService.deleteConfigFromServer(lot.id);
          } catch (e) {
            print('서버에서 주차장 삭제 실패: $e');
          }

          _showSnackBar('주차장이 삭제되었습니다.');
          _loadParkingLots(); // 목록 새로고침
        } else {
          _showSnackBar('주차장 삭제에 실패했습니다.', isError: true);
          setState(() {
            _isLoading = false;
          });
        }
      } catch (e) {
        _showSnackBar('주차장 삭제 중 오류가 발생했습니다: $e', isError: true);
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // 새 주차장 추가
  void _addNewParkingLot() async {
    // 새 주차장의 ID 생성 (parking_lot_X 형식)
    int nextId = 1;

    while (_parkingLots.any((lot) => lot.id == 'parking_lot_${String.fromCharCode(64 + nextId)}')) {
      nextId++;
    }

    // 새 주차장 기본 설정
    final newLot = ParkingLotConfig(
      id: 'parking_lot_${String.fromCharCode(64 + nextId)}',
      name: '새 주차장',
      building: '추가 정보 필요',
      latitude: AppConfig.changwonUniversity['latitude'] as double,
      longitude: AppConfig.changwonUniversity['longitude'] as double,
      capacity: 10,
    );

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ParkingLotEditScreen(
          parkingLot: newLot,
          isNewLot: true,
        ),
      ),
    );

    if (result == true) {
      _loadParkingLots();
    }
  }

  // 스낵바 표시
  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('주차장 관리'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadParkingLots,
            tooltip: '새로고침',
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _addNewParkingLot,
        tooltip: '새 주차장 추가',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              '오류가 발생했습니다',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(_errorMessage!),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadParkingLots,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    if (_parkingLots.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.local_parking,
              size: 64,
              color: Colors.blue,
            ),
            const SizedBox(height: 16),
            Text(
              '등록된 주차장이 없습니다',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _addNewParkingLot,
              icon: const Icon(Icons.add),
              label: const Text('새 주차장 추가'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 지도 영역
        if (PlatformUtil.isMapsSupported) ...[
          Expanded(
            flex: 5,
            child: GoogleMap(
              initialCameraPosition: _initialCameraPosition,
              onMapCreated: (controller) {
                _mapController = controller;
                _updateMapMarkersAndPolygons();
              },
              markers: _markers,
              polygons: _polygons,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: true,
              mapToolbarEnabled: false,
            ),
          ),
        ],

        // 주차장 목록
        Expanded(
          flex: 4,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              children: [
                // 제목 영역
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.list, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text(
                        '주차장 목록 (${_parkingLots.length}개)',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                // 주차장 목록
                Expanded(
                  child: ListView.builder(
                    itemCount: _parkingLots.length,
                    itemBuilder: (context, index) {
                      final lot = _parkingLots[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: ListTile(
                          leading: const Icon(
                            Icons.local_parking,
                            color: Colors.blue,
                          ),
                          title: Text(lot.name),
                          subtitle: Text('${lot.building} (${lot.capacity}대)'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.orange),
                                onPressed: () => _editParkingLot(lot),
                                tooltip: '편집',
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteParkingLot(lot),
                                tooltip: '삭제',
                              ),
                            ],
                          ),
                          onTap: () {
                            if (_mapController != null) {
                              _mapController!.animateCamera(
                                CameraUpdate.newLatLngZoom(
                                  LatLng(lot.latitude, lot.longitude),
                                  17.0,
                                ),
                              );
                            }
                            _showParkingLotDetails(lot);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}