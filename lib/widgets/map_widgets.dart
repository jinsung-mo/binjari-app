// widgets/map_widgets.dart
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/parking_model.dart';
import '../config/app_config.dart';

/// Custom widgets and helper functions for the map screen

// Create map markers from parking status
Set<Marker> createParkingMarkers({
  required ParkingStatus parkingStatus,
  required Function(String) onMarkerTap,
  required Map<String, BitmapDescriptor> markerIcons,
}) {
  final Set<Marker> markers = {};

  parkingStatus.parkingLots.forEach((key, lotStatus) {
    // Get parking location information
    final lotInfo = AppConfig.parkingLocations[key];
    if (lotInfo == null) return;

    // Set marker based on occupancy rate
    final occupancyRate = lotStatus.occupancyRate;
    String congestionLevel;
    BitmapDescriptor markerIcon;

    if (occupancyRate > 80) {
      congestionLevel = '혼잡';
      markerIcon = markerIcons['red'] ??
                  BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
    } else if (occupancyRate > 50) {
      congestionLevel = '보통';
      markerIcon = markerIcons['orange'] ??
                  BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
    } else {
      congestionLevel = '여유';
      markerIcon = markerIcons['green'] ??
                  BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
    }

    // Add parking lot marker
    markers.add(
      Marker(
        markerId: MarkerId(key),
        position: LatLng(lotInfo['latitude'], lotInfo['longitude']),
        infoWindow: InfoWindow(
          title: lotInfo['name'],
          snippet: '가용: ${lotStatus.availableSpaces}대 / 총 ${lotStatus.totalSpaces}대 (${congestionLevel})',
        ),
        onTap: () {
          onMarkerTap(key);
        },
        icon: markerIcon,
      ),
    );
  });

  return markers;
}

// Create map polygons from parking status
Set<Polygon> createParkingPolygons({
  required ParkingStatus parkingStatus,
}) {
  final Set<Polygon> polygons = {};

  parkingStatus.parkingLots.forEach((key, lotStatus) {
    // Get polygon points
    final polygonPoints = AppConfig.parkingPolygons[key];
    if (polygonPoints == null) return;

    // Set color based on occupancy rate
    final occupancyRate = lotStatus.occupancyRate;
    Color polygonColor;

    if (occupancyRate > 80) {
      polygonColor = Colors.red.withOpacity(0.4);
    } else if (occupancyRate > 50) {
      polygonColor = Colors.orange.withOpacity(0.4);
    } else {
      polygonColor = Colors.green.withOpacity(0.4);
    }

    // Create list of LatLng points
    final List<LatLng> points = polygonPoints.map((point) =>
      LatLng(point['latitude']!, point['longitude']!)
    ).toList();

    // Add polygon
    polygons.add(
      Polygon(
        polygonId: PolygonId(key),
        points: points,
        fillColor: polygonColor,
        strokeColor: Colors.black,
        strokeWidth: 2,
      ),
    );
  });

  return polygons;
}

// Bottom sheet showing parking details
class ParkingDetailBottomSheet extends StatelessWidget {
  final String parkingLotId;
  final ParkingLotStatus status;
  final VoidCallback onViewDetails;

  const ParkingDetailBottomSheet({
    Key? key,
    required this.parkingLotId,
    required this.status,
    required this.onViewDetails,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final lotInfo = AppConfig.parkingLocations[parkingLotId];
    if (lotInfo == null) return const SizedBox();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle indicator
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

          // Parking lot name and building
          Text(
            lotInfo['name'],
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            lotInfo['building'],
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),

          const SizedBox(height: 16),

          // Parking status information
          Row(
            children: [
              Expanded(
                child: _buildInfoCard(
                  context,
                  '${status.availableSpaces}',
                  '주차 가능',
                  Colors.green,
                  Icons.local_parking,
                ),
              ),
              Expanded(
                child: _buildInfoCard(
                  context,
                  '${status.occupiedSpaces}',
                  '주차 중',
                  Colors.red,
                  Icons.directions_car,
                ),
              ),
              Expanded(
                child: _buildInfoCard(
                  context,
                  '${status.occupancyRate.toStringAsFixed(1)}%',
                  '점유율',
                  _getStatusColor(status.occupancyRate),
                  Icons.pie_chart,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Additional information
          _buildInfoRow('운영 시간', lotInfo['openHours'] ?? '24시간'),
          if (lotInfo['hasDisabledSpaces'] == true)
            _buildInfoRow('장애인 주차', '가능', icon: Icons.accessible),
          _buildInfoRow('주차장 타입', lotInfo['type'] == 'outdoor' ? '실외' : '실내'),

          const SizedBox(height: 16),

          // View details button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onViewDetails,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text('상세 정보 보기'),
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to build info cards
  Widget _buildInfoCard(
    BuildContext context,
    String value,
    String label,
    Color color,
    IconData icon,
  ) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 4),
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
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to build info rows
  Widget _buildInfoRow(String label, String value, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: Colors.grey),
            const SizedBox(width: 8),
          ],
          Text(
            '$label: ',
            style: TextStyle(
              color: Colors.grey.shade700,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // Get status color based on occupancy rate
  Color _getStatusColor(double occupancyRate) {
    if (occupancyRate > 80) {
      return Colors.red;
    } else if (occupancyRate > 50) {
      return Colors.orange;
    } else {
      return Colors.green;
    }
  }
}

// Search bar widget for map screen
class MapSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final Function(String) onSearch;
  final bool isSearching;
  final VoidCallback onClear;

  const MapSearchBar({
    Key? key,
    required this.controller,
    required this.onSearch,
    required this.isSearching,
    required this.onClear,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(Icons.search, color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: '창원대학교 건물 또는 주차장 검색',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 16),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: onSearch,
              ),
            ),
            if (controller.text.isNotEmpty)
              IconButton(
                icon: Icon(Icons.clear),
                onPressed: onClear,
              )
            else if (isSearching)
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                icon: Icon(Icons.send),
                onPressed: () => onSearch(controller.text),
              ),
          ],
        ),
      ),
    );
  }
}