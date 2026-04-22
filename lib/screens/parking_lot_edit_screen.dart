// screens/parking_lot_edit_screen.dart
// 주차장 추가/편집 화면

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../config/app_config.dart';
import '../models/parking_lot_config_model.dart';
import '../services/parking_lot_config_service.dart';
import '../utils/platform_util.dart';

class ParkingLotEditScreen extends StatefulWidget {
  final ParkingLotConfig parkingLot;
  final bool isNewLot;

  const ParkingLotEditScreen({
    Key? key,
    required this.parkingLot,
    this.isNewLot = false,
  }) : super(key: key);

  @override
  State<ParkingLotEditScreen> createState() => _ParkingLotEditScreenState();
}

class _ParkingLotEditScreenState extends State<ParkingLotEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final ParkingLotConfigService _configService = ParkingLotConfigService();

  // 폼 컨트롤러
  late TextEditingController _nameController;
  late TextEditingController _buildingController;
  late TextEditingController _latitudeController;
  late TextEditingController _longitudeController;
  late TextEditingController _capacityController;
  late TextEditingController _openHoursController;
  late TextEditingController _descriptionController;
  late TextEditingController _videoSourceController;

  // 폼 상태
  String _parkingType = 'outdoor';
  bool _hasDisabledSpaces = false;

  // 주차장 좌표 상태
  List<List<LatLng>> _parkingSpaces = [];
  bool _isDrawingPolygon = false;
  List<LatLng> _currentPolygon = [];

  // 지도 상태
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polygon> _polygons = {};
  LatLng? _selectedLocation;

  // 지도 초기 위치
  late CameraPosition _initialCameraPosition;

  // 로딩 상태
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    // 폼 컨트롤러 초기화
    _nameController = TextEditingController(text: widget.parkingLot.name);
    _buildingController = TextEditingController(text: widget.parkingLot.building);
    _latitudeController = TextEditingController(text: widget.parkingLot.latitude.toString());
    _longitudeController = TextEditingController(text: widget.parkingLot.longitude.toString());
    _capacityController = TextEditingController(text: widget.parkingLot.capacity.toString());
    _openHoursController = TextEditingController(text: widget.parkingLot.openHours);
    _descriptionController = TextEditingController(text: widget.parkingLot.description);
    _videoSourceController = TextEditingController(text: widget.parkingLot.videoSource);

    // 폼 상태 초기화
    _parkingType = widget.parkingLot.type;
    _hasDisabledSpaces = widget.parkingLot.hasDisabledSpaces;

    // 주차장 좌표 초기화
    _parkingSpaces = List.from(widget.parkingLot.parkingSpaces);

    // 지도 초기 위치 설정
    _initialCameraPosition = CameraPosition(
      target: LatLng(widget.parkingLot.latitude, widget.parkingLot.longitude),
      zoom: 17.0,
    );

    // 선택된 위치 초기화
    _selectedLocation = LatLng(widget.parkingLot.latitude, widget.parkingLot.longitude);

    // 마커 초기화
    _updateMapMarkers();
  }

  @override
  void dispose() {
    // 폼 컨트롤러 정리
    _nameController.dispose();
    _buildingController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _capacityController.dispose();
    _openHoursController.dispose();
    _descriptionController.dispose();
    _videoSourceController.dispose();

    super.dispose();
  }

  // 마커 및 다각형 업데이트
  void _updateMapMarkers() {
    setState(() {
      _markers.clear();

      // 주차장 위치 마커 추가
      if (_selectedLocation != null) {
        _markers.add(
          Marker(
            markerId: const MarkerId('parking_location'),
            position: _selectedLocation!,
            draggable: true,
            onDragEnd: (newPosition) {
              setState(() {
                _selectedLocation = newPosition;
                _latitudeController.text = newPosition.latitude.toString();
                _longitudeController.text = newPosition.longitude.toString();
              });
            },
          ),
        );
      }

      // 다각형 업데이트
      _updatePolygons();
    });
  }

  // 다각형 업데이트
  void _updatePolygons() {
    setState(() {
      _polygons.clear();

      // 저장된 주차 구역 다각형 추가
      for (int i = 0; i < _parkingSpaces.length; i++) {
        if (_parkingSpaces[i].length >= 3) {
          _polygons.add(
            Polygon(
              polygonId: PolygonId('space_$i'),
              points: _parkingSpaces[i],
              fillColor: Colors.blue.withOpacity(0.3),
              strokeColor: Colors.blue,
              strokeWidth: 2,
            ),
          );
        }
      }

      // 현재 그리는 중인 다각형 추가
      if (_isDrawingPolygon && _currentPolygon.isNotEmpty) {
        _polygons.add(
          Polygon(
            polygonId: const PolygonId('current_drawing'),
            points: _currentPolygon,
            fillColor: Colors.green.withOpacity(0.3),
            strokeColor: Colors.green,
            strokeWidth: 2,
          ),
        );
      }
    });
  }

  // 좌표 선택
  void _selectLocation(LatLng position) {
    if (_isDrawingPolygon) {
      // 다각형 그리기 모드에서는 점 추가
      setState(() {
        _currentPolygon.add(position);
        _updatePolygons();
      });
    } else {
      // 일반 모드에서는 주차장 위치 변경
      setState(() {
        _selectedLocation = position;
        _latitudeController.text = position.latitude.toString();
        _longitudeController.text = position.longitude.toString();
        _updateMapMarkers();
      });
    }
  }

  // 다각형 그리기 시작
  void _startDrawingPolygon() {
    setState(() {
      _isDrawingPolygon = true;
      _currentPolygon = [];
    });

    _showInformationDialog(
      '주차 구역 그리기',
      '지도를 탭하여 주차 구역의 모서리 점을 추가하세요.\n'
      '최소 3개 이상의 점이 필요합니다.\n'
      '완료되면 완료 버튼을 누르세요.',
    );
  }

  // 다각형 그리기 완료
  void _finishDrawingPolygon() {
    if (_currentPolygon.length < 3) {
      _showSnackBar('주차 구역에는 최소 3개 이상의 점이 필요합니다.', isError: true);
      return;
    }

    setState(() {
      // 다각형 닫기 (첫 번째 점 추가)
      if (_currentPolygon.first.latitude != _currentPolygon.last.latitude ||
          _currentPolygon.first.longitude != _currentPolygon.last.longitude) {
        _currentPolygon.add(_currentPolygon.first);
      }

      // 주차 구역 목록에 추가
      _parkingSpaces.add(List.from(_currentPolygon));

      // 그리기 모드 종료
      _isDrawingPolygon = false;
      _currentPolygon = [];

      // 다각형 업데이트
      _updatePolygons();
    });

    _showSnackBar('주차 구역이 추가되었습니다.');
  }

  // 다각형 그리기 취소
  void _cancelDrawingPolygon() {
    setState(() {
      _isDrawingPolygon = false;
      _currentPolygon = [];
      _updatePolygons();
    });
  }

  // 주차 구역 삭제
  void _deleteParkingSpace(int index) {
    setState(() {
      _parkingSpaces.removeAt(index);
      _updatePolygons();
    });

    _showSnackBar('주차 구역이 삭제되었습니다.');
  }

  // 폼 저장
  Future<void> _saveForm() async {
    if (_formKey.currentState?.validate() != true) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // 업데이트된 주차장 설정 생성
      final updatedLot = ParkingLotConfig(
        id: widget.parkingLot.id,
        name: _nameController.text,
        building: _buildingController.text,
        latitude: double.parse(_latitudeController.text),
        longitude: double.parse(_longitudeController.text),
        capacity: int.parse(_capacityController.text),
        type: _parkingType,
        hasDisabledSpaces: _hasDisabledSpaces,
        openHours: _openHoursController.text,
        description: _descriptionController.text,
        videoSource: _videoSourceController.text,
        parkingSpaces: _parkingSpaces,
      );

      // 주차장 설정 저장
      final success = await _configService.addOrUpdateLot(updatedLot);

      if (success) {
        // 서버에도 업로드 시도 (오류가 나도 로컬에는 저장)
        try {
          await _configService.uploadConfigToServer(updatedLot);
        } catch (e) {
          print('서버에 주차장 설정 업로드 실패: $e');
        }

        _showSnackBar(widget.isNewLot ? '주차장이 추가되었습니다.' : '주차장이 업데이트되었습니다.');

        if (mounted) {
          Navigator.pop(context, true); // 성공 결과 반환
        }
      } else {
        throw Exception('주차장 설정 저장 실패');
      }
    } catch (e) {
      _showSnackBar('저장 중 오류가 발생했습니다: $e', isError: true);
      setState(() {
        _isSaving = false;
      });
    }
  }

  // 정보 다이얼로그 표시
  void _showInformationDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
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
        title: Text(widget.isNewLot ? '새 주차장 추가' : '주차장 편집'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _isSaving ? null : _saveForm,
            tooltip: '저장',
          ),
        ],
      ),
      body: _isSaving
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          // 지도 영역 (지도 지원이 있는 플랫폼에서만 표시)
          if (PlatformUtil.isMapsSupported) ...[
            Expanded(
              flex: 6,
              child: Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: _initialCameraPosition,
                    onMapCreated: (controller) {
                      _mapController = controller;
                      _updateMapMarkers();
                    },
                    markers: _markers,
                    polygons: _polygons,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: true,
                    mapToolbarEnabled: false,
                    onTap: _selectLocation,
                  ),

                  // 다각형 그리기 모드 컨트롤
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (_isDrawingPolygon) ...[
                          FloatingActionButton.small(
                            heroTag: 'finishDrawing',
                            onPressed: _finishDrawingPolygon,
                            backgroundColor: Colors.green,
                            child: const Icon(Icons.check),
                            tooltip: '완료',
                          ),
                          const SizedBox(height: 8),
                          FloatingActionButton.small(
                            heroTag: 'cancelDrawing',
                            onPressed: _cancelDrawingPolygon,
                            backgroundColor: Colors.red,
                            child: const Icon(Icons.clear),
                            tooltip: '취소',
                          ),
                          const SizedBox(height: 8),
                        ] else ...[
                          FloatingActionButton.small(
                            heroTag: 'drawPolygon',
                            onPressed: _startDrawingPolygon,
                            backgroundColor: Colors.blue,
                            child: const Icon(Icons.edit),
                            tooltip: '주차 구역 그리기',
                          ),
                        ],
                        const SizedBox(height: 8),
                        FloatingActionButton.small(
                          heroTag: 'myLocation',
                          onPressed: () {
                            if (_mapController != null && _selectedLocation != null) {
                              _mapController!.animateCamera(
                                CameraUpdate.newLatLngZoom(
                                  _selectedLocation!,
                                  17.0,
                                ),
                              );
                            }
                          },
                          backgroundColor: Colors.blue,
                          child: const Icon(Icons.my_location),
                          tooltip: '주차장 위치로',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          // 폼 입력 영역
          Expanded(
            flex: PlatformUtil.isMapsSupported ? 8 : 1,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 기본 정보 카드
                  Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '기본 정보',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),

                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: '주차장 이름',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.local_parking),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return '주차장 이름을 입력하세요';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          TextFormField(
                            controller: _buildingController,
                            decoration: const InputDecoration(
                              labelText: '건물 정보',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.business),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return '건물 정보를 입력하세요';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _capacityController,
                                  decoration: const InputDecoration(
                                    labelText: '수용 대수',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.directions_car),
                                  ),
                                  keyboardType: TextInputType.number,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return '수용 대수를 입력하세요';
                                    }
                                    if (int.tryParse(value) == null || int.parse(value) <= 0) {
                                      return '유효한 숫자를 입력하세요';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextFormField(
                                  controller: _openHoursController,
                                  decoration: const InputDecoration(
                                    labelText: '운영 시간',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.access_time),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 위치 정보 카드
                  Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '위치 정보',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 이전 Row 위젯을 LayoutBuilder로 교체
                          LayoutBuilder(
                            builder: (context, constraints) {
                              // 화면이 좁을 때는 Column으로 배치
                              if (constraints.maxWidth < 600) {
                                return Column(
                                  children: [
                                    TextFormField(
                                      controller: _latitudeController,
                                      decoration: const InputDecoration(
                                        labelText: '위도',
                                        border: OutlineInputBorder(),
                                        prefixIcon: Icon(Icons.location_on),
                                      ),
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return '위도를 입력하세요';
                                        }
                                        if (double.tryParse(value) == null) {
                                          return '유효한 숫자를 입력하세요';
                                        }
                                        return null;
                                      },
                                      onChanged: (value) {
                                        if (double.tryParse(value) != null && _longitudeController.text.isNotEmpty) {
                                          setState(() {
                                            _selectedLocation = LatLng(
                                              double.parse(value),
                                              double.parse(_longitudeController.text),
                                            );
                                            _updateMapMarkers();
                                          });
                                        }
                                      },
                                    ),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                      controller: _longitudeController,
                                      decoration: const InputDecoration(
                                        labelText: '경도',
                                        border: OutlineInputBorder(),
                                        prefixIcon: Icon(Icons.location_on),
                                      ),
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return '경도를 입력하세요';
                                        }
                                        if (double.tryParse(value) == null) {
                                          return '유효한 숫자를 입력하세요';
                                        }
                                        return null;
                                      },
                                      onChanged: (value) {
                                        if (double.tryParse(value) != null && _latitudeController.text.isNotEmpty) {
                                          setState(() {
                                            _selectedLocation = LatLng(
                                              double.parse(_latitudeController.text),
                                              double.parse(value),
                                            );
                                            _updateMapMarkers();
                                          });
                                        }
                                      },
                                    ),
                                  ],
                                );
                              } else {
                                // 화면이 넓을 때는, 원래대로 Row로 배치
                                return Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _latitudeController,
                                        decoration: const InputDecoration(
                                          labelText: '위도',
                                          border: OutlineInputBorder(),
                                          prefixIcon: Icon(Icons.location_on),
                                        ),
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        validator: (value) {
                                          if (value == null || value.isEmpty) {
                                            return '위도를 입력하세요';
                                          }
                                          if (double.tryParse(value) == null) {
                                            return '유효한 숫자를 입력하세요';
                                          }
                                          return null;
                                        },
                                        onChanged: (value) {
                                          if (double.tryParse(value) != null && _longitudeController.text.isNotEmpty) {
                                            setState(() {
                                              _selectedLocation = LatLng(
                                                double.parse(value),
                                                double.parse(_longitudeController.text),
                                              );
                                              _updateMapMarkers();
                                            });
                                          }
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _longitudeController,
                                        decoration: const InputDecoration(
                                          labelText: '경도',
                                          border: OutlineInputBorder(),
                                          prefixIcon: Icon(Icons.location_on),
                                        ),
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        validator: (value) {
                                          if (value == null || value.isEmpty) {
                                            return '경도를 입력하세요';
                                          }
                                          if (double.tryParse(value) == null) {
                                            return '유효한 숫자를 입력하세요';
                                          }
                                          return null;
                                        },
                                        onChanged: (value) {
                                          if (double.tryParse(value) != null && _latitudeController.text.isNotEmpty) {
                                            setState(() {
                                              _selectedLocation = LatLng(
                                                double.parse(_latitudeController.text),
                                                double.parse(value),
                                              );
                                              _updateMapMarkers();
                                            });
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                );
                              }
                            },
                          ),

                          if (!PlatformUtil.isMapsSupported) ...[
                            const SizedBox(height: 16),
                            const Text(
                              '현재 플랫폼에서는 지도가 지원되지 않아 좌표를 직접 입력해야 합니다.',
                              style: TextStyle(
                                color: Colors.orange,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // 주차장 설정 카드
                  Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '주차장 설정',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 주차장 유형
                          DropdownButtonFormField<String>(
                            value: _parkingType,
                            decoration: const InputDecoration(
                              labelText: '주차장 유형',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.category),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'outdoor',
                                child: Text('실외 주차장'),
                              ),
                              DropdownMenuItem(
                                value: 'indoor',
                                child: Text('실내 주차장'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _parkingType = value;
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 16),

                          // 장애인 주차 공간
                          SwitchListTile(
                            title: const Text('장애인 주차 공간'),
                            subtitle: const Text('장애인 전용 주차 공간이 있는지 여부'),
                            value: _hasDisabledSpaces,
                            onChanged: (value) {
                              setState(() {
                                _hasDisabledSpaces = value;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 비디오 소스 카드
                  Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '비디오 소스',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),

                          TextFormField(
                            controller: _videoSourceController,
                            decoration: const InputDecoration(
                              labelText: '비디오 파일 경로 또는 RTSP 스트림 URL',
                              hintText: 'C:/videos/parking.mp4 또는 rtsp://...',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.videocam),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '주차장 영상 파일(.mp4, .avi 등) 또는 RTSP 스트림 URL을 입력하세요.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 설명 카드
                  Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '설명',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),

                          TextFormField(
                            controller: _descriptionController,
                            decoration: const InputDecoration(
                              labelText: '주차장 설명',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.description),
                            ),
                            maxLines: 3,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 주차 구역 목록
                  Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '주차 구역',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (!PlatformUtil.isMapsSupported)
                                TextButton.icon(
                                  icon: const Icon(Icons.add),
                                  label: const Text('구역 추가'),
                                  onPressed: () {
                                    _showInformationDialog(
                                      '주차 구역 추가',
                                      '현재 플랫폼에서는 지도 기능이 지원되지 않아 주차 구역을 추가할 수 없습니다.\n'
                                      '모바일 또는 웹 플랫폼에서 이 기능을 사용하세요.',
                                    );
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Divider(),

                          if (_parkingSpaces.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text(
                                '정의된 주차 구역이 없습니다. "주차 구역 그리기" 버튼을 사용하여 지도에서 주차 구역을 추가하세요.',
                                style: TextStyle(
                                  fontStyle: FontStyle.italic,
                                  color: Colors.grey,
                                ),
                              ),
                            )
                          else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _parkingSpaces.length,
                              itemBuilder: (context, index) {
                                final pointCount = _parkingSpaces[index].length;
                                return ListTile(
                                  leading: const Icon(Icons.crop_square, color: Colors.blue),
                                  title: Text('주차 구역 ${index + 1}'),
                                  subtitle: Text('점 개수: $pointCount'),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => _deleteParkingSpace(index),
                                    tooltip: '구역 삭제',
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}