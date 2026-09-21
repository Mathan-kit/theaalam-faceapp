import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'screens/face_recognition_screen.dart';

import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final savedToken = prefs.getString('auth_token') ?? '';
  runApp(FaceAttendanceApp(token: savedToken));
}

class FaceAttendanceApp extends StatelessWidget {
  final String? token;
  const FaceAttendanceApp({super.key, this.token});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'The Aalam Attendance',
      theme: AppTheme.theme,
      home: FaceRecognitionScreen(token: token ?? ''),
      debugShowCheckedModeBanner: false,
    );
  }
}
