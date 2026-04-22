// models/parking_model.dart
// 주차장 관련 데이터 모델

class ParkingStatus {
  final Map<String, ParkingLotStatus> parkingLots;

  ParkingStatus({required this.parkingLots});

  factory ParkingStatus.fromJson(Map<String, dynamic> json) {
    Map<String, ParkingLotStatus> lots = {};

    json.forEach((key, value) {
      lots[key] = ParkingLotStatus.fromJson(value);
    });

    return ParkingStatus(parkingLots: lots);
  }

  // 모든 주차장의 가용 공간 합계
  int get totalAvailableSpaces {
    return parkingLots.values.fold(0, (sum, lot) => sum + lot.availableSpaces);
  }

  // 모든 주차장의 전체 공간 합계
  int get totalSpaces {
    return parkingLots.values.fold(0, (sum, lot) => sum + lot.totalSpaces);
  }

  // 장애인 주차 가능 공간 수 (ID가 'C'로 시작하거나 'disabled'를 포함하는 빈 공간)
  int get disabledAvailableSpaces {
    int count = 0;
    parkingLots.values.forEach((lot) {
      lot.spaces.forEach((space) {
        if ((space.id.startsWith('C') || space.id.contains('disabled')) && space.status == 'empty') {
          count++;
        }
      });
    });
    return count;
  }

  // 전체 장애인 주차 공간 수도 함께 수정
  int get totalDisabledSpaces {
    int count = 0;
    parkingLots.values.forEach((lot) {
      lot.spaces.forEach((space) {
        if (space.id.startsWith('C') || space.id.contains('disabled')) {
          count++;
        }
      });
    });
    return count;
  }

  // 전체 주차장 점유율
  double get overallOccupancyRate {
    if (totalSpaces == 0) return 0;
    return ((totalSpaces - totalAvailableSpaces) / totalSpaces) * 100;
  }
}

class ParkingLotStatus {
  final int totalSpaces;
  final int occupiedSpaces;
  final int availableSpaces;
  final double occupancyRate;
  final List<ParkingSpace> spaces;

  ParkingLotStatus({
    required this.totalSpaces,
    required this.occupiedSpaces,
    required this.availableSpaces,
    required this.occupancyRate,
    required this.spaces,
  });

  factory ParkingLotStatus.fromJson(Map<String, dynamic> json) {
    List<ParkingSpace> spacesList = [];
    if (json['spaces'] != null) {
      spacesList =
          (json['spaces'] as List)
              .map((space) => ParkingSpace.fromJson(space))
              .toList();
    }

    return ParkingLotStatus(
      totalSpaces: json['total_spaces'] ?? 0,
      occupiedSpaces: json['occupied_spaces'] ?? 0,
      availableSpaces: json['available_spaces'] ?? 0,
      occupancyRate: (json['occupancy_rate'] ?? 0).toDouble(),
      spaces: spacesList,
    );
  }
}

class ParkingSpace {
  final String id;
  final String status;
  final String? vehicleType;

  ParkingSpace({
    required this.id,
    required this.status,
    this.vehicleType,
  });

  factory ParkingSpace.fromJson(Map<String, dynamic> json) {
    return ParkingSpace(
      id: json['id'] ?? '',
      status: json['status'] ?? 'unknown',
      vehicleType: json['vehicle_type'],
    );
  }

  // 상태 검사를 위한 편의 메소드 추가
  bool get isOccupied => status.toLowerCase() == 'occupied';
  bool get isEmpty => status.toLowerCase() == 'empty';

  // 주차 공간의 구역(A, B, C 등) 반환
  String get section {
    if (id.isEmpty) return '';
    return id.substring(0, 1);
  }

  // 주차 공간의 번호 반환 - 수정 버전
  String get number {
    if (id.length <= 1) return '';

    // B2disabled와 같은 특수 ID 처리
    if (id.contains("disabled")) {
      // disabled를 제외하고 숫자 부분만 반환
      return id.substring(1, id.indexOf("disabled"));
    }

    // 기본 동작: 첫 글자 이후의 모든 텍스트를 번호로 사용
    return id.substring(1);
  }

  // 장애인 주차 공간 여부 - 수정 버전
  bool get isDisabledSpace {
    return section == 'C' || id.contains("disabled");
  }
}

class ParkingHistory {
  final String spaceId;
  final DateTime entryTime;
  final DateTime? exitTime;
  final String? duration;
  final String? vehicleType;

  ParkingHistory({
    required this.spaceId,
    required this.entryTime,
    this.exitTime,
    this.duration,
    this.vehicleType,
  });

  factory ParkingHistory.fromJson(Map<String, dynamic> json) {
    return ParkingHistory(
      spaceId: json['space_id'] ?? '',
      entryTime: DateTime.parse(
        json['entry_time'] ?? DateTime.now().toString(),
      ),
      exitTime:
          json['exit_time'] != null ? DateTime.parse(json['exit_time']) : null,
      duration: json['duration'],
      vehicleType: json['vehicle_type'],
    );
  }
}

// ==================== 새로운 통계 모델 시작 ====================

// 개선된 주차장 통계 모델
class ParkingStatistics {
  final CurrentStatus current;
  final List<HourlyData> hourlyData;
  final Recommendation recommendation;
  final Map<String, TimePeriod> timePeriods;

  ParkingStatistics({
    required this.current,
    required this.hourlyData,
    required this.recommendation,
    required this.timePeriods,
  });

  factory ParkingStatistics.fromJson(Map<String, dynamic> json) {
    // 현재 상태 처리
    final current = CurrentStatus.fromJson(json['current'] ?? {});

    // 시간별 데이터 처리
    final List<HourlyData> hourlyData = [];
    if (json['hourly_data'] != null) {
      for (var item in json['hourly_data']) {
        hourlyData.add(HourlyData.fromJson(item));
      }
    }

    // 추천 정보 처리
    final recommendation = Recommendation.fromJson(json['recommendation'] ?? {});

    // 시간대별 정보 처리
    final Map<String, TimePeriod> timePeriods = {};
    if (json['time_periods'] != null) {
      json['time_periods'].forEach((key, value) {
        timePeriods[key] = TimePeriod.fromJson(value);
      });
    }

    return ParkingStatistics(
      current: current,
      hourlyData: hourlyData,
      recommendation: recommendation,
      timePeriods: timePeriods,
    );
  }

  // 특정 시간대의 점유율 데이터 가져오기
  HourlyData? getHourData(int hour) {
    try {
      return hourlyData.firstWhere((data) => data.hour == hour);
    } catch (e) {
      return null;
    }
  }

  // 특정 시간대의 데이터가 있는지 확인
  bool hasHourData(int hour) {
    return hourlyData.any((data) => data.hour == hour);
  }

  // 현재 시간 기준으로 정렬된 시간별 데이터 가져오기
  List<HourlyData> getSortedHourlyData() {
    final currentHour = current.hour;
    final sorted = List<HourlyData>.from(hourlyData);

    sorted.sort((a, b) {
      final adjustedHourA = (a.hour - currentHour + 24) % 24;
      final adjustedHourB = (b.hour - currentHour + 24) % 24;
      return adjustedHourA.compareTo(adjustedHourB);
    });

    return sorted;
  }
}

// 현재 주차장 상태
class CurrentStatus {
  final String time;
  final int hour;
  final double occupancyRate;
  final String formattedRate;
  final int totalSpaces;
  final int occupiedSpaces;
  final int availableSpaces;

  CurrentStatus({
    required this.time,
    required this.hour,
    required this.occupancyRate,
    required this.formattedRate,
    required this.totalSpaces,
    required this.occupiedSpaces,
    required this.availableSpaces,
  });

  factory CurrentStatus.fromJson(Map<String, dynamic> json) {
    return CurrentStatus(
      time: json['time'] ?? '00:00',
      hour: json['hour'] ?? 0,
      occupancyRate: (json['occupancy_rate'] ?? 0).toDouble(),
      formattedRate: json['formatted_rate'] ?? '0%',
      totalSpaces: json['total_spaces'] ?? 0,
      occupiedSpaces: json['occupied_spaces'] ?? 0,
      availableSpaces: json['available_spaces'] ?? 0,
    );
  }
}

// 시간별 데이터
class HourlyData {
  final int hour;
  final String formattedTime;
  final double occupancyRate;
  final String formattedRate;
  final bool isCurrent;

  HourlyData({
    required this.hour,
    required this.formattedTime,
    required this.occupancyRate,
    required this.formattedRate,
    required this.isCurrent,
  });

  factory HourlyData.fromJson(Map<String, dynamic> json) {
    return HourlyData(
      hour: json['hour'] ?? 0,
      formattedTime: json['formatted_time'] ?? '00:00',
      occupancyRate: (json['occupancy_rate'] ?? 0).toDouble(),
      formattedRate: json['formatted_rate'] ?? '0%',
      isCurrent: json['is_current'] ?? false,
    );
  }
}

// 추천 정보
class Recommendation {
  final int bestHour;
  final String formattedTime;
  final double occupancyRate;
  final String formattedRate;

  Recommendation({
    required this.bestHour,
    required this.formattedTime,
    required this.occupancyRate,
    required this.formattedRate,
  });

  factory Recommendation.fromJson(Map<String, dynamic> json) {
    return Recommendation(
      bestHour: json['best_hour'] ?? 0,
      formattedTime: json['formatted_time'] ?? '00:00',
      occupancyRate: (json['occupancy_rate'] ?? 0).toDouble(),
      formattedRate: json['formatted_rate'] ?? '0%',
    );
  }
}

// 시간대 정보 (아침, 오후, 저녁, 밤)
class TimePeriod {
  final String label;
  final double avgRate;
  final String formattedRate;

  TimePeriod({
    required this.label,
    required this.avgRate,
    required this.formattedRate,
  });

  factory TimePeriod.fromJson(Map<String, dynamic> json) {
    return TimePeriod(
      label: json['label'] ?? '',
      avgRate: (json['avg_rate'] ?? 0).toDouble(),
      formattedRate: json['formatted_rate'] ?? '0%',
    );
  }
}

// 이전 통계 모델과의 호환성을 위한 클래스들 (필요한 경우)
class AvgParkingDuration {
  final double minutes;
  final double hours;

  AvgParkingDuration({required this.minutes, required this.hours});

  factory AvgParkingDuration.fromJson(Map<String, dynamic> json) {
    return AvgParkingDuration(
      minutes: (json['minutes'] ?? 0).toDouble(),
      hours: (json['hours'] ?? 0).toDouble(),
    );
  }

  String get formatted {
    int hrs = hours.floor();
    int mins = (minutes % 60).round();
    return '$hrs시간 $mins분';
  }
}