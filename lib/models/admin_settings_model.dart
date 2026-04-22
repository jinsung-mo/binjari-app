// 관리자 설정 모델
class AdminSettings {
  final String apiUrl;
  final String modelPath;
  final String videoPath;
  final DateTime lastUpdated;

  AdminSettings({
    required this.apiUrl,
    required this.modelPath,
    required this.videoPath,
    required this.lastUpdated,
  });

  // 기본 설정으로 생성
  factory AdminSettings.defaultSettings() {
    return AdminSettings(
      apiUrl: 'http://localhost:5000',
      modelPath: 'C:\\Users\\user\\Desktop\\Flutter\\server\\models\\best_seo.pt',
      videoPath: 'C:\\Users\\user\\Desktop\\Flutter\\parking_best.mp4',
      lastUpdated: DateTime.now(),
    );
  }

  // JSON에서 생성
  factory AdminSettings.fromJson(Map<String, dynamic> json) {
    return AdminSettings(
      apiUrl: json['apiUrl'] ?? 'http://localhost:5000',
      modelPath: json['modelPath'] ?? '',
      videoPath: json['videoPath'] ?? '',
      lastUpdated: json['lastUpdated'] != null
          ? DateTime.parse(json['lastUpdated'])
          : DateTime.now(),
    );
  }

  // JSON으로 변환
  Map<String, dynamic> toJson() {
    return {
      'apiUrl': apiUrl,
      'modelPath': modelPath,
      'videoPath': videoPath,
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }

  // 설정 복사 with 패턴
  AdminSettings copyWith({
    String? apiUrl,
    String? modelPath,
    String? videoPath,
    DateTime? lastUpdated,
  }) {
    return AdminSettings(
      apiUrl: apiUrl ?? this.apiUrl,
      modelPath: modelPath ?? this.modelPath,
      videoPath: videoPath ?? this.videoPath,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}