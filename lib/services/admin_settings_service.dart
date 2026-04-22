import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/admin_settings_model.dart';

class AdminSettingsService {
  // SharedPreferences 키
  static const String _settingsKey = 'admin_settings';

  // 설정 가져오기
  Future<AdminSettings> getSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString(_settingsKey);

      if (settingsJson != null) {
        // 저장된 설정이 있으면 파싱하여 반환
        return AdminSettings.fromJson(json.decode(settingsJson));
      } else {
        // 저장된 설정이 없으면 기본 설정 반환
        return AdminSettings.defaultSettings();
      }
    } catch (e) {
      // 오류 발생 시 기본 설정 반환
      print('설정을 가져오는 중 오류 발생: $e');
      return AdminSettings.defaultSettings();
    }
  }

  // 설정 저장하기
  Future<bool> saveSettings(AdminSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = json.encode(settings.toJson());

      return await prefs.setString(_settingsKey, settingsJson);
    } catch (e) {
      print('설정을 저장하는 중 오류 발생: $e');
      return false;
    }
  }

  // 설정 초기화하기
  Future<bool> resetSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 설정 삭제
      if (prefs.containsKey(_settingsKey)) {
        await prefs.remove(_settingsKey);
      }

      // 기본 설정 저장
      final defaultSettings = AdminSettings.defaultSettings();
      final settingsJson = json.encode(defaultSettings.toJson());

      return await prefs.setString(_settingsKey, settingsJson);
    } catch (e) {
      print('설정을 초기화하는 중 오류 발생: $e');
      return false;
    }
  }
}