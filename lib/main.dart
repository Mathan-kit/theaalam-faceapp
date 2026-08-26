import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/face_recognition_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('auth_token');
  
  runApp(FaceAttendanceApp(token: token));
}

class FaceAttendanceApp extends StatelessWidget {
  final String? token;
  const FaceAttendanceApp({super.key, this.token});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ABN',
      theme: AppTheme.theme,
      home: token != null && token!.isNotEmpty 
          ? FaceRecognitionScreen(token: token!) 
          : const LoginScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
