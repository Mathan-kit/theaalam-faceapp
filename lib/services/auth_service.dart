import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  String? _cachedToken;

  String get safeBaseUrl {
    return ApiConfig.baseUrl.endsWith('/') ? ApiConfig.baseUrl : '${ApiConfig.baseUrl}/';
  }

  Future<String> getValidToken() async {
    if (_cachedToken != null && _cachedToken!.isNotEmpty) {
      return _cachedToken!;
    }

    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString('auth_token');
    if (savedToken != null && savedToken.isNotEmpty) {
      _cachedToken = savedToken;
      return savedToken;
    }

    return '';
  }

  Future<String?> login(String username, String password) async {
    try {
      final url = '${safeBaseUrl}admin_login?user_name=$username&user_pwd=$password';
      debugPrint('AuthService: Login request to $url');

      final response = await http.post(
        Uri.parse(url),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final resData = jsonDecode(response.body);
        final token = resData['token'] as String? ?? '';
        final adminName = resData['name']?.toString() ?? resData['user_name']?.toString() ?? username;
        final adminRole = resData['role']?.toString() ?? resData['designation']?.toString() ?? 'System Admin';

        if (token.isNotEmpty) {
          _cachedToken = token;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('auth_token', token);
          await prefs.setString('admin_name', adminName);
          await prefs.setString('admin_role', adminRole);
          debugPrint('AuthService: Successfully authenticated.');
          return token;
        }
      }
    } catch (e) {
      debugPrint('AuthService: Login failed: $e');
    }
    return null;
  }

  Future<String?> getAdminName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('admin_name');
  }

  Future<String?> getAdminRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('admin_role');
  }

  Future<bool> isLoggedIn() async {
    final token = await getValidToken();
    return token.isNotEmpty;
  }

  Future<void> logout() async {
    _cachedToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('admin_name');
    await prefs.remove('admin_role');
  }
}
