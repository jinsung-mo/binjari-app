// widgets/parking_lot_view.dart
import 'package:flutter/material.dart';
import '../models/parking_model.dart';
import '../config/app_config.dart';

class ParkingLotView extends StatelessWidget {
  final String parkingLotId;
  final ParkingLotStatus parkingLotStatus;
  final int? videoWidth;
  final int? videoHeight;

  const ParkingLotView({
    super.key,
    required this.parkingLotId,
    required this.parkingLotStatus,
    this.videoWidth,
    this.videoHeight,
  });

  @override
  Widget build(BuildContext context) {
    // 주차장별 비디오 크기 가져오기
    final lotInfo = AppConfig.getParkingLotInfo(parkingLotId);
    final actualVideoWidth = videoWidth ?? lotInfo?['videoWidth'] ?? 1444;
    final actualVideoHeight = videoHeight ?? lotInfo?['videoHeight'] ?? 973;

    // 주차 공간을 구역별로 분리
    final Map<String, List<ParkingSpace>> spacesBySection = _groupSpacesBySection();

    // 특별 주차 공간 확인
    final hasElectricSpaces = spacesBySection.entries.any((entry) =>
        entry.value.any((space) => space.id.toLowerCase().contains('electric')));
    final hasDisabledSpaces = spacesBySection.entries.any((entry) =>
        entry.value.any((space) => space.isDisabledSpace));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 주차장 제목 및 요약 정보 - 개선된 헤더
        _buildEnhancedHeader(),

        // 주차장 시각화 영역
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          width: double.infinity,
          height: MediaQuery.of(context).size.width * actualVideoHeight / actualVideoWidth,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CustomPaint(
              size: Size(
                double.infinity,
                MediaQuery.of(context).size.width * actualVideoHeight / actualVideoWidth
              ),
              painter: _getPainterForParkingLot(
                parkingLotId,
                spacesBySection,
                actualVideoWidth,
                actualVideoHeight,
              ),
            ),
          ),
        ),

        // 색상 범례 - 주차장별 특별 공간 포함
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              _buildLegendItem(Colors.red, '주차 중'),
              _buildLegendItem(Colors.green, '주차 가능'),
              if (hasDisabledSpaces)
                _buildLegendItem(Colors.blue, '장애인 전용'),
              if (hasElectricSpaces)
                _buildLegendItem(Colors.yellow[700]!, '전기차 전용'),
            ],
          ),
        ),

        // 구역별 상세 정보 (도서관의 경우 A, B, C, D 구역 표시)
        if (parkingLotId == 'parking_lot_B')
          _buildLibrarySectionDetails(spacesBySection),
      ],
    );
  }

  // 개선된 헤더 - 주차장별 특별 정보 표시
  Widget _buildEnhancedHeader() {
    final lotInfo = AppConfig.getParkingLotInfo(parkingLotId);
    final lotName = AppConfig.getParkingLotName(parkingLotId);

    // 주차장별 아이콘
    IconData lotIcon;
    Color lotIconColor;

    switch (parkingLotId) {
      case 'parking_lot_A':
        lotIcon = Icons.engineering;
        lotIconColor = Colors.blue;
        break;
      case 'parking_lot_B':
        lotIcon = Icons.library_books;
        lotIconColor = Colors.purple;
        break;
      case 'parking_lot_C':
        lotIcon = Icons.business;
        lotIconColor = Colors.orange;
        break;
      case 'parking_lot_D':
        lotIcon = Icons.science;
        lotIconColor = Colors.green;
        break;
      default:
        lotIcon = Icons.local_parking;
        lotIconColor = Colors.grey;
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            children: [
              // 주차장 아이콘
              Icon(
                lotIcon,
                color: lotIconColor,
                size: 32,
              ),
              const SizedBox(width: 12),

              // 주차장 정보
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lotName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      lotInfo?['building'] ?? '',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),

              // 주차 현황 요약
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.car_rental, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        '${parkingLotStatus.availableSpaces}/${parkingLotStatus.totalSpaces}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${parkingLotStatus.occupancyRate.toStringAsFixed(1)}% 점유',
                    style: TextStyle(
                      fontSize: 12,
                      color: _getOccupancyColor(parkingLotStatus.occupancyRate),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // 도서관 특별 공간 정보 표시
          if (parkingLotId == 'parking_lot_B') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Container(
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
                        const Expanded(
                          child: Text(
                            '전기차 전용 2구역 (D4, D5)',
                            style: TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
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
                        const Expanded(
                          child: Text(
                            '장애인 전용 1구역 (D6)',
                            style: TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // 구역별로 주차 공간 그룹핑
  Map<String, List<ParkingSpace>> _groupSpacesBySection() {
    final Map<String, List<ParkingSpace>> spacesBySection = {};

    for (var space in parkingLotStatus.spaces) {
      final section = space.section;
      if (!spacesBySection.containsKey(section)) {
        spacesBySection[section] = [];
      }
      spacesBySection[section]!.add(space);
    }

    // 각 섹션을 ID 순으로 정렬
    spacesBySection.forEach((key, value) {
      value.sort((a, b) => a.id.compareTo(b.id));
    });

    return spacesBySection;
  }

  // 주차장별 페인터 반환
  CustomPainter _getPainterForParkingLot(
    String parkingLotId,
    Map<String, List<ParkingSpace>> spacesBySection,
    int videoWidth,
    int videoHeight,
  ) {
    // 모든 주차장에 대해 통합된 직사각형 페인터 사용
    return RectangularParkingPainter(
      aSpaces: spacesBySection['A'] ?? [],
      bSpaces: spacesBySection['B'] ?? [],
      cSpaces: spacesBySection['C'] ?? [],
      dSpaces: spacesBySection['D'] ?? [],
    );
  }

  // 도서관 구역별 상세 정보
  Widget _buildLibrarySectionDetails(Map<String, List<ParkingSpace>> spacesBySection) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '구역별 주차 현황',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          // A, B, C, D 구역 정보
          Row(
            children: [
              Expanded(child: _buildSectionCard('A', spacesBySection['A'] ?? [], '일반 구역')),
              const SizedBox(width: 8),
              Expanded(child: _buildSectionCard('B', spacesBySection['B'] ?? [], '일반 구역')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildSectionCard('C', spacesBySection['C'] ?? [], '일반 구역')),
              const SizedBox(width: 8),
              Expanded(child: _buildSectionCard('D', spacesBySection['D'] ?? [], '특별 구역')),
            ],
          ),
        ],
      ),
    );
  }

  // 구역 카드
  Widget _buildSectionCard(String section, List<ParkingSpace> spaces, String description) {
    final occupiedCount = spaces.where((space) => space.isOccupied).length;
    final totalCount = spaces.length;
    final availableCount = totalCount - occupiedCount;
    final occupancyRate = totalCount > 0 ? (occupiedCount / totalCount) * 100 : 0.0;

    // D구역의 특별 공간 카운트
    int electricCount = 0;
    int disabledCount = 0;
    if (section == 'D') {
      electricCount = spaces.where((space) => space.id.contains('electric')).length;
      disabledCount = spaces.where((space) => space.id.contains('disabled')).length;
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$section구역',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getOccupancyColor(occupancyRate).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${occupancyRate.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 12,
                      color: _getOccupancyColor(occupancyRate),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '가능: $availableCount',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.green,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '점유: $occupiedCount',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            // D구역 특별 공간 정보
            if (section == 'D' && (electricCount > 0 || disabledCount > 0)) ...[
              const SizedBox(height: 8),
              if (electricCount > 0)
                Row(
                  children: [
                    Icon(Icons.electric_car, size: 12, color: Colors.yellow[700]),
                    const SizedBox(width: 4),
                    Text(
                      '전기차: $electricCount개',
                      style: const TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              if (disabledCount > 0)
                Row(
                  children: [
                    Icon(Icons.accessible, size: 12, color: Colors.blue[700]),
                    const SizedBox(width: 4),
                    Text(
                      '장애인: $disabledCount개',
                      style: const TextStyle(fontSize: 10),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  // 범례 항목
  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 4),
        Text(label),
      ],
    );
  }

  // 점유율에 따른 색상 반환
  Color _getOccupancyColor(double occupancyRate) {
    if (occupancyRate > 80) {
      return Colors.red;
    } else if (occupancyRate > 50) {
      return Colors.orange;
    } else {
      return Colors.green;
    }
  }
}

// 통합된 직사각형 주차장 페인터
// 구역(A~D)마다 한 줄씩, 주차면 번호 순서대로 칸을 배치해 캔버스 크기에 맞게 그린다.
class RectangularParkingPainter extends CustomPainter {
  final List<ParkingSpace> aSpaces;
  final List<ParkingSpace> bSpaces;
  final List<ParkingSpace> cSpaces;
  final List<ParkingSpace> dSpaces;

  RectangularParkingPainter({
    required this.aSpaces,
    required this.bSpaces,
    this.cSpaces = const [],
    this.dSpaces = const [],
  });

  // 'D4electric', 'B2disabled', 'A10' 등에서 번호 추출
  static int spaceIndex(String id) {
    final match = RegExp(r'^[A-Za-z](\d+)').firstMatch(id);
    return match != null ? int.parse(match.group(1)!) : 0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 배경 그리기
    final backgroundPaint = Paint()..color = Colors.grey.shade200;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), backgroundPaint);

    final rows = [aSpaces, bSpaces, cSpaces, dSpaces].where((spaces) => spaces.isNotEmpty).toList();
    if (rows.isEmpty) return;

    final rowHeight = size.height / rows.length;
    for (int row = 0; row < rows.length; row++) {
      _drawParkingSection(canvas, rows[row], size.width, row * rowHeight, rowHeight);
    }
  }

  void _drawParkingSection(
    Canvas canvas,
    List<ParkingSpace> spaces,
    double width,
    double top,
    double rowHeight,
  ) {
    // 칸 수: 가장 큰 번호 기준 (번호가 빠진 칸은 빈 자리로 남김)
    final maxIndex = spaces.map((space) => spaceIndex(space.id)).fold<int>(0, (a, b) => a > b ? a : b);
    final columns = maxIndex > 0 ? maxIndex : spaces.length;
    final columnWidth = width / columns;

    for (int i = 0; i < spaces.length; i++) {
      final space = spaces[i];
      final bool isOccupied = space.isOccupied;
      final bool isElectric = space.id.toLowerCase().contains('electric');
      final bool isDisabled = space.isDisabledSpace;

      // 주차 공간 색상
      Color fillColor;
      if (isElectric) {
        fillColor = isOccupied ? Colors.orange.shade800 : Colors.yellow.shade600;
      } else if (isDisabled) {
        fillColor = isOccupied ? Colors.red.shade800 : Colors.blue;
      } else {
        fillColor = isOccupied ? Colors.red : Colors.green;
      }

      final fillPaint = Paint()
        ..color = fillColor.withOpacity(0.7)
        ..style = PaintingStyle.fill;

      final strokePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      final index = spaceIndex(space.id);
      final column = index > 0 ? index - 1 : i;
      final rect = Rect.fromLTWH(
        column * columnWidth + columnWidth * 0.05,
        top + rowHeight * 0.1,
        columnWidth * 0.9,
        rowHeight * 0.8,
      );

      canvas.drawRect(rect, fillPaint);
      canvas.drawRect(rect, strokePaint);

      // 주차 공간 ID 표시
      _drawParkingId(canvas, space.id, rect, isElectric, isDisabled);
    }
  }

  void _drawParkingId(Canvas canvas, String id, Rect rect, bool isElectric, bool isDisabled) {
    // ID 텍스트 단순화
    String displayId = id;
    if (id.contains('electric')) {
      displayId = id.replaceAll('electric', 'E');
    } else if (id.contains('disabled')) {
      displayId = id.replaceAll('disabled', 'D');
    }

    // 텍스트 색상
    Color textColor = Colors.white;
    if (isElectric) textColor = Colors.black;

    final textStyle = TextStyle(
      color: textColor,
      fontSize: 14,
      fontWeight: FontWeight.bold,
      shadows: [
        Shadow(
          blurRadius: 2,
          color: Colors.black,
          offset: const Offset(1, 1),
        ),
      ],
    );

    final textSpan = TextSpan(text: displayId, style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        rect.center.dx - textPainter.width / 2,
        rect.center.dy - textPainter.height / 2,
      ),
    );

    // 특별 주차 공간 아이콘 표시
    if (isElectric) {
      _drawIcon(canvas, '⚡',
        Offset(rect.center.dx, rect.center.dy - 20), 12, Colors.black);
    } else if (isDisabled) {
      _drawIcon(canvas, '♿',
        Offset(rect.center.dx, rect.center.dy - 20), 12, Colors.white);
    }
  }

  void _drawIcon(Canvas canvas, String icon, Offset position, double fontSize, Color color) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: icon,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        position.dx - textPainter.width / 2,
        position.dy - textPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
