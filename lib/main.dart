import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'config/app_config.dart';
import 'screens/campus_map_screen.dart'; // Changed to map screen

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Platform verification
  if (!kIsWeb) {
    try {
      bool isMobileOrWeb = Platform.isAndroid || Platform.isIOS || kIsWeb;
      print('Running on ${Platform.operatingSystem}. Maps supported: $isMobileOrWeb');
    } catch (e) {
      print('Running on non-mobile platform. Maps may not be supported.');
    }
  } else {
    print('Running on web. Maps supported: true');
  }

  // Set status bar color
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '창원대학교 스마트 주차장 모니터링',
      theme: ThemeData(
        // App theme colors
        primaryColor: Color(AppConfig.primaryColorHex),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Color(AppConfig.primaryColorHex),
          secondary: Color(AppConfig.secondaryColorHex),
        ),
        // AppBar theme
        appBarTheme: AppBarTheme(
          backgroundColor: Color(AppConfig.primaryColorHex),
          foregroundColor: Colors.white,
          elevation: 2,
        ),
        // TabBar theme
        tabBarTheme: TabBarTheme(
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
        ),
        // Card theme
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        // Button theme
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(AppConfig.primaryColorHex),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        useMaterial3: true,
      ),
      home: const CampusMapScreen(), // Changed to start with map screen
      debugShowCheckedModeBanner: false,
    );
  }
}