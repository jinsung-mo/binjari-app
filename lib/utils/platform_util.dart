import 'dart:io' as io;
import 'package:flutter/foundation.dart' show kIsWeb;

class PlatformUtil {
  // 현재 플랫폼이 Android 또는 iOS인지 확인
  static bool get isMobile {
    if (kIsWeb) return false;
    try {
      return io.Platform.isAndroid || io.Platform.isIOS;
    } catch (e) {
      return false;
    }
  }

  // 현재 플랫폼이 Windows, macOS 또는 Linux인지 확인
  static bool get isDesktop {
    if (kIsWeb) return false;
    try {
      return io.Platform.isWindows || io.Platform.isMacOS || io.Platform.isLinux;
    } catch (e) {
      return false;
    }
  }

  // 현재 플랫폼이 웹인지 확인
  static bool get isWeb {
    return kIsWeb;
  }

  // 현재 플랫폼이 Windows인지 확인
  static bool get isWindows {
    if (kIsWeb) return false;
    try {
      return io.Platform.isWindows;
    } catch (e) {
      return false;
    }
  }

  // 현재 플랫폼이 macOS인지 확인
  static bool get isMacOS {
    if (kIsWeb) return false;
    try {
      return io.Platform.isMacOS;
    } catch (e) {
      return false;
    }
  }

  // 현재 플랫폼이 Linux인지 확인
  static bool get isLinux {
    if (kIsWeb) return false;
    try {
      return io.Platform.isLinux;
    } catch (e) {
      return false;
    }
  }

  // 차트 지원 여부 확인
  static bool get isChartSupported {
    return kIsWeb || isMobile || isMacOS;
  }

  // 파일 선택 지원 여부 확인
  static bool get isFilePickerSupported {
    return kIsWeb || isMobile || isMacOS;
  }

  // 지도 지원 여부 확인
  static bool get isMapsSupported {
    return kIsWeb || isMobile;
  }

  // 현재 플랫폼 이름 반환
  static String get platformName {
    if (kIsWeb) return 'Web';
    try {
      if (io.Platform.isAndroid) return 'Android';
      if (io.Platform.isIOS) return 'iOS';
      if (io.Platform.isWindows) return 'Windows';
      if (io.Platform.isMacOS) return 'macOS';
      if (io.Platform.isLinux) return 'Linux';
      if (io.Platform.isFuchsia) return 'Fuchsia';
      return 'Unknown';
    } catch (e) {
      return 'Unknown';
    }
  }
}