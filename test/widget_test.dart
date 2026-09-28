import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:parking_app_0413/models/parking_model.dart';
import 'package:parking_app_0413/widgets/parking_lot_view.dart';

void main() {
  group('ParkingSpace', () {
    test('특수 주차면 ID를 구분한다', () {
      expect(ParkingSpace(id: 'D6disabled', status: 'empty').isDisabledSpace, isTrue);
      expect(ParkingSpace(id: 'B2disabled', status: 'empty').number, '2');
      // C구역 일반 주차면은 장애인 전용이 아니다
      expect(ParkingSpace(id: 'C1', status: 'empty').isDisabledSpace, isFalse);
    });

    test('주차면 번호를 추출한다', () {
      expect(RectangularParkingPainter.spaceIndex('A10'), 10);
      expect(RectangularParkingPainter.spaceIndex('D4electric'), 4);
      expect(RectangularParkingPainter.spaceIndex('D6disabled'), 6);
    });
  });

  group('ParkingStatus', () {
    final status = ParkingStatus.fromJson({
      'parking_lot_B': {
        'total_spaces': 3,
        'occupied_spaces': 1,
        'available_spaces': 2,
        'occupancy_rate': 33.3,
        'spaces': [
          {'id': 'C1', 'status': 'occupied', 'vehicle_type': 'car'},
          {'id': 'C2', 'status': 'empty'},
          {'id': 'D6disabled', 'status': 'empty'},
        ],
      },
    });

    test('장애인 전용 주차면만 집계한다', () {
      expect(status.totalDisabledSpaces, 1);
      expect(status.disabledAvailableSpaces, 1);
      expect(status.totalAvailableSpaces, 2);
    });
  });

  group('ParkingStatistics', () {
    test('데이터가 없는 시간대와 추천 없음 응답을 해석한다', () {
      final statistics = ParkingStatistics.fromJson({
        'current': {'time': '09:00', 'hour': 9, 'occupancy_rate': 40.0, 'is_live': true},
        'hourly_data': [
          {'hour': 9, 'formatted_time': '09:00', 'occupancy_rate': 40.0, 'formatted_rate': '40%',
           'has_data': true, 'source': 'live', 'is_current': true},
          {'hour': 10, 'formatted_time': '10:00', 'occupancy_rate': 0.0, 'formatted_rate': '-',
           'has_data': false, 'source': null, 'is_current': false},
        ],
        'recommendation': null,
        'time_periods': {
          'morning': {'label': '아침', 'avg_rate': 40.0, 'formatted_rate': '40.0%', 'has_data': true},
        },
      });

      expect(statistics.current.isLive, isTrue);
      expect(statistics.getHourData(10)!.hasData, isFalse);
      expect(statistics.recommendation.hasData, isFalse);
      expect(statistics.timePeriods['morning']!.hasData, isTrue);
    });
  });

  testWidgets('주차장 도면이 모든 구역의 주차면을 그린다', (WidgetTester tester) async {
    final lotStatus = ParkingLotStatus.fromJson({
      'total_spaces': 3,
      'occupied_spaces': 1,
      'available_spaces': 2,
      'occupancy_rate': 33.3,
      'spaces': [
        {'id': 'A1', 'status': 'occupied'},
        {'id': 'D4electric', 'status': 'empty'},
        {'id': 'D6disabled', 'status': 'empty'},
      ],
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ParkingLotView(parkingLotId: 'parking_lot_B', parkingLotStatus: lotStatus),
        ),
      ),
    ));

    expect(find.text('도서관 주차장'), findsOneWidget);
    expect(find.text('장애인 전용'), findsOneWidget);
    expect(find.text('전기차 전용'), findsOneWidget);
  });
}
