// screens/campus_map_screen.dart
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'dart:io' show Platform;
import '../services/parking_service.dart';
import '../services/location_service.dart';
import '../models/parking_model.dart';
import '../config/app_config.dart';
import '../screens/home_screen.dart';
import '../widgets/common_widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// Conditionally import Google Maps
import 'package:google_maps_flutter/google_maps_flutter.dart'
    if (dart.library.js_util) 'package:google_maps_flutter_web/google_maps_flutter_web.dart';

class CampusMapScreen extends StatefulWidget {
  const CampusMapScreen({Key? key}) : super(key: key);

  @override
  State<CampusMapScreen> createState() => _CampusMapScreenState();
}

class _CampusMapScreenState extends State<CampusMapScreen> {
  final ParkingService _parkingService = ParkingService();
  final LocationService _locationService = LocationService();
  final TextEditingController _searchController = TextEditingController();

  ParkingStatus? _parkingStatus;
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _refreshTimer;
  bool _isSearching = false;
  Position? _currentPosition;
  String _currentAddress = "현재 위치 찾는 중...";

  // 선택된 마커 및 정보 표시 관련 상태
  String? _selectedParkingLotId;
  bool _showMarkerInfo = false;

  // Google Maps related variables
  Completer<GoogleMapController> _controller = Completer();
  Set<Marker> _markers = {};
  Set<Polygon> _polygons = {};

  // 주차장 P 마커 아이콘
  BitmapDescriptor? _parkingIcon;

  // 창원대학교 위치 정보
  static const _changwonUniversityLat = 35.2456;
  static const _changwonUniversityLng = 128.6969;

  // 공과대학 55호관 주차장 좌표
  static const _engineering55BuildingLat = 35.241343;
  static const _engineering55BuildingLng = 128.695526;

  // Initial map position - 창원대학교 전체 캠퍼스가 보이도록 설정
  final CameraPosition _initialCameraPosition = CameraPosition(
    target: LatLng(_changwonUniversityLat, _changwonUniversityLng),
    zoom: 15.5, // 캠퍼스 전체가 보이는 줌 레벨
  );

  // 플랫폼 지원 확인
  bool get _isMapsSupported {
    return kIsWeb || Platform.isAndroid || Platform.isIOS;
  }

  @override
  void initState() {
    super.initState();
    print('CampusMapScreen initialized');

    // 지도 지원 확인
    if (_isMapsSupported) {
      print('Maps are supported on this platform');
    } else {
      print('Maps are NOT supported on this platform');
    }

    // 주차장 P 마커 아이콘 생성
    _createParkingIcon();

    // 초기 주차 상태 로드
    _loadParkingStatus();

    // 위치 권한 요청 및 현재 위치 가져오기
    _getCurrentLocation();

    // 주기적으로 주차 상태 갱신
    _refreshTimer = Timer.periodic(
      Duration(seconds: AppConfig.refreshInterval),
      (_) => _loadParkingStatus()
    );
  }

  // 주차장 P 마커 아이콘 생성 메서드
  Future<void> _createParkingIcon() async {
    try {
      // Canvas를 사용하여 P 마커 아이콘 생성
      final size = 75.0; // 크기를 절반으로 줄임 (150 -> 75)
      final pictureRecorder = ui.PictureRecorder();
      final canvas = Canvas(pictureRecorder);
      final radius = size / 2;

      // 원형 배경 (파란색)
      final backgroundPaint = Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(radius, radius), radius, backgroundPaint);

      // 테두리 (하얀색)
      final borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4; // 테두리 두께도 절반으로 줄임 (8 -> 4)
      canvas.drawCircle(Offset(radius, radius), radius - 2, borderPaint);

      // P 텍스트 그리기
      final textPainter = TextPainter(
        text: TextSpan(
          text: 'P',
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.65,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      // P 텍스트 중앙에 배치
      textPainter.paint(
        canvas,
        Offset(
          radius - textPainter.width / 2,
          radius - textPainter.height / 2,
        ),
      );

      // 이미지로 변환
      final picture = pictureRecorder.endRecording();
      final img = await picture.toImage(size.toInt(), size.toInt());
      final pngBytes = await img.toByteData(format: ui.ImageByteFormat.png);

      if (pngBytes != null) {
        final Uint8List bytes = Uint8List.view(pngBytes.buffer);
        _parkingIcon = BitmapDescriptor.fromBytes(bytes);

        // 아이콘이 생성되면 마커 업데이트
        if (_parkingStatus != null) {
          _updateMapMarkers();
        }
      }
    } catch (e) {
      print('Failed to create parking icon: $e');
      _parkingIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // 현재 위치 가져오기
  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled;
      LocationPermission permission;

      // 위치 서비스 활성화 여부 확인
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _currentAddress = "위치 서비스가 비활성화되어 있습니다";
        });
        return;
      }

      // 위치 권한 확인
      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _currentAddress = "위치 권한이 거부되었습니다";
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _currentAddress = "위치 권한이 영구적으로 거부되었습니다";
        });
        return;
      }

      // 현재 위치 가져오기
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high
      );
      setState(() {
        _currentPosition = position;
      });

      // 주소 가져오기
      _getAddressFromLatLng(position);

    } catch (e) {
      print('Error getting location: $e');
      setState(() {
        _currentAddress = "위치를 가져올 수 없습니다";
      });
    }
  }

  // 좌표에서 주소 가져오기
  Future<void> _getAddressFromLatLng(Position position) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        setState(() {
          _currentAddress =
              "${place.street}, ${place.subLocality}, ${place.locality}";
        });
      }
    } catch (e) {
      print('Error getting address: $e');
      setState(() {
        _currentAddress = "주소를 가져올 수 없습니다";
      });
    }
  }

  // 위치 검색 개선
  Future<void> _searchLocation(String query) async {
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
    });

    try {
      print('Searching for location: $query');

      // 검색어에 기본적으로 창원대학교를 포함
      String searchQuery = query;
      if (!query.toLowerCase().contains('창원대') &&
          !query.toLowerCase().contains('changwon univ')) {
        searchQuery = '창원대학교 $query';
      }

      print('Modified search query: $searchQuery');

      // 우선 내부 검색 시도 (설정된 건물 및 주차장)
      bool foundInBuildings = false;

      // 건물 이름으로 검색
      AppConfig.additionalBuildings.forEach((id, buildingInfo) {
        if (buildingInfo['name'].toString().toLowerCase().contains(query.toLowerCase())) {
          print('Found in buildings: ${buildingInfo['name']}');
          foundInBuildings = true;
          _moveToLocation(buildingInfo['latitude'], buildingInfo['longitude'], 18.0);
        }
      });

      // 주차장 이름으로 검색
      if (!foundInBuildings) {
        AppConfig.parkingLocations.forEach((id, lotInfo) {
          if (lotInfo['name'].toString().toLowerCase().contains(query.toLowerCase()) ||
              lotInfo['building'].toString().toLowerCase().contains(query.toLowerCase())) {
            print('Found in parking lots: ${lotInfo['name']}');
            foundInBuildings = true;
            _moveToLocation(lotInfo['latitude'], lotInfo['longitude'], 18.0);

            // 주차장 마커 정보창 표시
            if (_parkingStatus != null && _parkingStatus!.parkingLots.containsKey(id)) {
              setState(() {
                _selectedParkingLotId = id;
                _showMarkerInfo = true;
              });
            }
          }
        });
      }

      // 내부 검색에서 찾지 못한 경우 Geocoding API 사용
      if (!foundInBuildings) {
        print('Not found in internal database, using Geocoding API');
        List<Location> locations = await locationFromAddress(searchQuery);

        if (locations.isNotEmpty) {
          Location location = locations.first;
          print('Geocoding result: ${location.latitude}, ${location.longitude}');
          _moveToLocation(location.latitude, location.longitude, 18.0);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('검색 결과를 찾을 수 없습니다')),
          );
        }
      }
    } catch (e) {
      print('Error searching location: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('위치 검색 중 오류가 발생했습니다: $e')),
      );
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  // 지도 위치 이동 헬퍼 메서드
  Future<void> _moveToLocation(double latitude, double longitude, double zoom) async {
    if (_isMapsSupported) {
      final GoogleMapController controller = await _controller.future;
      controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(latitude, longitude),
          zoom,
        ),
      );
    }
  }

  // 주차 상태 로드
  Future<void> _loadParkingStatus() async {
    print('Loading parking status...');
    setState(() {
      _isLoading = _parkingStatus == null;
    });

    try {
      final status = await _parkingService.getParkingStatus();
      print('Parking status loaded successfully: ${status.totalSpaces} total spaces');

      setState(() {
        _parkingStatus = status;
        _isLoading = false;
        _errorMessage = null;
      });

      if (_isMapsSupported) {
        _updateMapMarkers();
      }
    } catch (e) {
      print('Error loading parking status: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  // 마커 업데이트 - 모든 주차장에 P 마커 표시, 55호관 주차장의 다각형 숨김
  void _updateMapMarkers() {
    print('Updating map markers...');
    if (_parkingStatus == null) {
      print('Cannot update markers: parking status is null');
      return;
    }

    // 임시 마커와 다각형 세트 생성
    Set<Marker> newMarkers = {};
    Set<Polygon> newPolygons = {};

    // 모든 주차장에 대해 처리 (AppConfig.parkingLocations)
    _parkingStatus!.parkingLots.forEach((lotId, lotStatus) {
      // 주차장 위치 정보 가져오기
      final lotInfo = AppConfig.parkingLocations[lotId];
      if (lotInfo == null) {
        print('Parking lot info not found for $lotId');
        return;
      }

      print('Processing parking lot: $lotId with occupancy rate: ${lotStatus.occupancyRate}%');

      // 모든 주차장에 P 마커 표시
      newMarkers.add(
        Marker(
          markerId: MarkerId(lotId),
          position: LatLng(lotInfo['latitude'], lotInfo['longitude']),
          icon: _parkingIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: InfoWindow(
            title: lotInfo['name'],
            snippet: "주차 가능: ${lotStatus.availableSpaces}/${lotStatus.totalSpaces}대",
          ),
          onTap: () {
            print('Marker tapped: $lotId');
            setState(() {
              _selectedParkingLotId = lotId;
              _showMarkerInfo = true;
            });
          },
        ),
      );

      // 주차장 다각형 영역 생성 (55호관 주차장 제외)
      if (lotId != 'parking_lot_A') { // 55호관 주차장(parking_lot_A)의 다각형은 표시하지 않음
        final polygonPoints = AppConfig.parkingPolygons[lotId];
        if (polygonPoints != null) {
          // 항상 파란색 사용 (주차장 표준 색상)
          Color polygonColor = Colors.blue.withOpacity(0.2);

          // LatLng 포인트 리스트 생성
          final List<LatLng> points = polygonPoints.map((point) =>
            LatLng(point['latitude']!, point['longitude']!)
          ).toList();

          // 다각형 추가
          newPolygons.add(
            Polygon(
              polygonId: PolygonId(lotId),
              points: points,
              fillColor: polygonColor,
              strokeColor: Colors.blue,
              strokeWidth: 2,
            ),
          );
        }
      }
    });

    // 대학 본부, 도서관, 53호관도 P 마커로 표시 (마커만 추가, 정보는 건물 정보 표시)
    // 이 건물들은 추가 건물이자 주차장이므로 P 마커로 표시
    AppConfig.additionalBuildings.forEach((buildingId, buildingInfo) {
      // additionalBuildings에 있는 건물의 위치에 P 마커 추가
      newMarkers.add(
        Marker(
          markerId: MarkerId(buildingId),
          position: LatLng(buildingInfo['latitude'], buildingInfo['longitude']),
          icon: _parkingIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: InfoWindow(
            title: buildingInfo['name'],
            snippet: buildingInfo['description'] ?? '',
          ),
        ),
      );
    });

    // 마커와 다각형 업데이트
    setState(() {
      _markers = newMarkers;
      _polygons = newPolygons;
      print('Updated ${_markers.length} markers and ${_polygons.length} polygons');
    });
  }

  // 주차장 상세 정보 표시
  void _showParkingLotDetails(String parkingLotId, ParkingLotStatus lotStatus) {
    print('Showing detailed bottom sheet for $parkingLotId');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 드래그 핸들
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

              // 주차장 아이콘과 이름
              Row(
                children: [
                  // P 아이콘 (원 안에 P)
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        'P',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 24,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),

                  // 주차장 이름
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${AppConfig.parkingLocations[parkingLotId]?['name'] ?? '주차장'}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${AppConfig.parkingLocations[parkingLotId]?['building'] ?? ''}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // 주차 상태 정보
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatusItem(
                    '주차 가능',
                    '${lotStatus.availableSpaces}대',
                    Colors.green,
                    Icons.check_circle,
                  ),
                  _buildStatusItem(
                    '점유 중',
                    '${lotStatus.occupiedSpaces}대',
                    Colors.red,
                    Icons.car_rental,
                  ),
                  _buildStatusItem(
                    '점유율',
                    '${lotStatus.occupancyRate.toStringAsFixed(1)}%',
                    _getStatusColor(lotStatus.occupancyRate),
                    Icons.pie_chart,
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // 상세 정보 버튼
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () {
                    // 바텀시트 닫고 홈 화면으로 이동
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => HomeScreen(
                          initialParkingLotId: parkingLotId,
                        ),
                      ),
                    );
                  },
                  child: Text('주차장 상세 정보 보기'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 상태 항목 생성 헬퍼 메서드
  Widget _buildStatusItem(String label, String value, Color color, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  // 점유율에 따른 색상 반환
  Color _getStatusColor(double occupancyRate) {
    if (occupancyRate > 80) {
      return Colors.red;
    } else if (occupancyRate > 50) {
      return Colors.orange;
    } else {
      return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('창원대학교 주차장 지도'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadParkingStatus,
            tooltip: '새로고침',
          ),
          IconButton(
            icon: Icon(Icons.list),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => HomeScreen()),
              );
            },
            tooltip: '주차장 목록',
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // 검색 바
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: '창원대학교 건물 또는 주차장 검색',
                    prefixIcon: Icon(Icons.search),
                    suffixIcon: _isSearching
                        ? Container(
                            width: 24,
                            height: 24,
                            padding: EdgeInsets.all(6),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            icon: Icon(Icons.send),
                            onPressed: () => _searchLocation(_searchController.text),
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onSubmitted: _searchLocation,
                ),
              ),

              // 현재 위치 정보
              if (_currentPosition != null || _currentAddress != "현재 위치 찾는 중...")
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.location_on, size: 16, color: Colors.grey),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _currentAddress,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

              // 지도
              Expanded(
                child: _isMapsSupported
                    ? GoogleMap(
                        mapType: MapType.normal,
                        initialCameraPosition: _initialCameraPosition,
                        markers: _markers,
                        polygons: _polygons,
                        onMapCreated: (GoogleMapController controller) {
                          print('Map created successfully');
                          _controller.complete(controller);

                          // 지도가 생성되면 마커 상태 업데이트
                          if (_parkingStatus != null) {
                            _updateMapMarkers();
                          } else {
                            print('Cannot update markers after map creation: parking status is null');
                          }
                        },
                        myLocationEnabled: true,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        mapToolbarEnabled: false,
                      )
                    : Center(
                        child: Text('현재 플랫폼에서는 지도가 지원되지 않습니다'),
                      ),
              ),
            ],
          ),

          // 말풍선 커스텀 UI - 마커가 선택된 경우에만 표시
          if (_showMarkerInfo && _selectedParkingLotId != null && _parkingStatus != null)
            _buildCustomInfoWindow(),

          // 로딩 인디케이터
          if (_isLoading)
            Container(
              color: Colors.black26,
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),

          // 에러 메시지
          if (_errorMessage != null)
            Container(
              color: Colors.black26,
              child: Center(
                child: Container(
                  padding: EdgeInsets.all(16),
                  margin: EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error, color: Colors.red, size: 48),
                      SizedBox(height: 16),
                      Text(
                        '데이터를 불러오는 중 오류가 발생했습니다',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      Text(_errorMessage!, textAlign: TextAlign.center),
                      SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadParkingStatus,
                        child: Text('다시 시도'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      // 플로팅 버튼
      floatingActionButton: _buildFloatingButtons(),
    );
  }

  // 커스텀 정보 창(말풍선) 위젯
  Widget _buildCustomInfoWindow() {
    final lotStatus = _parkingStatus!.parkingLots[_selectedParkingLotId!];
    if (lotStatus == null) return SizedBox.shrink();

    final lotInfo = AppConfig.parkingLocations[_selectedParkingLotId!];
    if (lotInfo == null) return SizedBox.shrink();

    // MediaQuery를 사용하여 화면 크기에 따라 위치 및 크기 조정
    final screenWidth = MediaQuery.of(context).size.width;
    final infoWindowWidth = screenWidth * 0.8 > 300 ? 300.0 : screenWidth * 0.8;

    return Positioned(
      // 화면 중앙에 배치 (고정 위치 대신)
      top: 250,
      left: (screenWidth - infoWindowWidth) / 2,
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          width: infoWindowWidth,
          padding: EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 주차장 이름 - 긴 텍스트 처리
              Text(
                lotInfo['name'],
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                overflow: TextOverflow.ellipsis, // 텍스트 오버플로우 처리
              ),
              SizedBox(height: 8),

              // 주차장 상태 - Row 배치 개선
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '가용: ${lotStatus.availableSpaces}대/${lotStatus.totalSpaces}대',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(lotStatus.occupancyRate),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${lotStatus.occupancyRate.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: 12),

              // 버튼 배치 개선
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _showMarkerInfo = false;
                    });
                    _showParkingLotDetails(_selectedParkingLotId!, lotStatus);
                  },
                  child: Text('상세 정보'),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),

              // 닫기 버튼
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      _showMarkerInfo = false;
                    });
                  },
                  child: Text('닫기'),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size(60, 30),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  // 플로팅 버튼
  Widget _buildFloatingButtons() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // 내 위치 버튼
        FloatingActionButton(
          heroTag: "location",
          child: const Icon(Icons.my_location),
          onPressed: () async {
            if (_currentPosition != null) {
              final controller = await _controller.future;
              controller.animateCamera(
                CameraUpdate.newLatLngZoom(
                  LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                  18
                ),
              );
            } else {
              _getCurrentLocation();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('현재 위치를 가져오는 중입니다...')),
              );
            }
          },
          tooltip: '내 위치',
        ),

        SizedBox(height: 16),

        // 55호관 주차장 버튼
        FloatingActionButton(
          heroTag: "parking",
          child: const Icon(Icons.local_parking),
          onPressed: () async {
            // 55호관 주차장으로 이동
            final controller = await _controller.future;
            controller.animateCamera(
              CameraUpdate.newLatLngZoom(
                LatLng(_engineering55BuildingLat, _engineering55BuildingLng),
                18
              ),
            );

            // 필요하다면 이 버튼으로 마커 정보도 표시
            if (_parkingStatus != null && _parkingStatus!.parkingLots.containsKey('parking_lot_A')) {
              setState(() {
                _selectedParkingLotId = 'parking_lot_A';
                _showMarkerInfo = true;
              });
            }
          },
          tooltip: '55호관 주차장',
        ),

        SizedBox(height: 16),

        // 캠퍼스 전체 보기 버튼
        FloatingActionButton(
          heroTag: "campus",
          child: const Icon(Icons.school),
          onPressed: () async {
            // 캠퍼스 전체 보기
            final controller = await _controller.future;
            controller.animateCamera(
              CameraUpdate.newLatLngZoom(
                LatLng(_changwonUniversityLat, _changwonUniversityLng),
                15.5
              ),
            );
            // 마커 정보 창 닫기
            setState(() {
              _showMarkerInfo = false;
            });
          },
          tooltip: '캠퍼스 전체 보기',
        ),
      ],
    );
  }
}