// widgets/common_widgets.dart
// 재사용 가능한 공통 위젯

import 'package:flutter/material.dart';
import '../config/app_config.dart';

// 정보 카드 위젯 (주차 가능 수, 점유율 등)
class InfoCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color? color;

  const InfoCard({
    Key? key,
    required this.title,
    required this.value,
    required this.icon,
    this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),  // 패딩 축소 (16 -> 12)
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: color ?? Theme.of(context).primaryColor,
              size: 28,  // 아이콘 크기 축소 (32 -> 28)
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,  // 폰트 크기 축소 (14 -> 13)
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,  // 텍스트 오버플로우 처리 추가
              maxLines: 1,  // 한 줄로 제한
            ),
          ],
        ),
      ),
    );
  }
}

// 로딩 위젯
class LoadingWidget extends StatelessWidget {
  final String message;

  const LoadingWidget({
    super.key,
    this.message = '로딩 중...',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(message),
        ],
      ),
    );
  }
}

// 오류 위젯 (ErrorWidget -> CustomErrorWidget으로 이름 변경)
class ErrorWidget extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const ErrorWidget({
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

// 주차장 통계 카드
class StatisticsCard extends StatelessWidget {
  final String title;
  final Widget child;

  const StatisticsCard({
    super.key,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

// 주차장 점유율 원형 지시자
class OccupancyIndicator extends StatelessWidget {
  final double occupancyRate;
  final double size;

  const OccupancyIndicator({
    super.key,
    required this.occupancyRate,
    this.size = 150,
  });

  @override
  Widget build(BuildContext context) {
    Color indicatorColor;

    // 점유율에 따라 색상 결정
    if (occupancyRate < 50) {
      indicatorColor = Colors.green;
    } else if (occupancyRate < 80) {
      indicatorColor = Colors.orange;
    } else {
      indicatorColor = Colors.red;
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: occupancyRate / 100,
              strokeWidth: 10,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(indicatorColor),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${occupancyRate.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: size / 6,
                  fontWeight: FontWeight.bold,
                  color: indicatorColor,
                ),
              ),
              Text(
                '점유율',
                style: TextStyle(
                  fontSize: size / 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// 새로고침 앱바 액션
class RefreshAction extends StatelessWidget {
  final VoidCallback onRefresh;
  final bool isLoading;

  const RefreshAction({
    super.key,
    required this.onRefresh,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : const Icon(Icons.refresh),
      onPressed: isLoading ? null : onRefresh,
      tooltip: '새로고침',
    );
  }
}
