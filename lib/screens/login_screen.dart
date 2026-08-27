import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../config/api_config.dart';
import '../theme/app_colors.dart';
import 'face_recognition_screen.dart';
import 'register_face_screen.dart';
import '../utils/toast_util.dart';

class LoginScreen extends StatefulWidget {
  final String? reauthorizeStaffName;
  final String? reauthorizeStaffCode;
  final bool isModal;

  const LoginScreen({
    super.key,
    this.reauthorizeStaffName,
    this.reauthorizeStaffCode,
    this.isModal = false,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    
    debugPrint('--- Login / Re-authorization Clicked ---');
    debugPrint('Username: $username');

    if (username.isEmpty || password.isEmpty) {
      ToastUtil.showError(context, 'Please enter admin username and password.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final url = '${ApiConfig.baseUrl}admin_login?user_name=$username&user_pwd=$password';
      debugPrint('Sending POST request to: $url');

      final response = await http.post(
        Uri.parse(url),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      setState(() => _isLoading = false);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final resData = jsonDecode(response.body);
        final message = resData['message'] ?? (widget.reauthorizeStaffName != null ? 'Authorization successful' : 'Login successful');
        
        if (mounted) {
          ToastUtil.showSuccess(context, message);
        }
        
        final token = resData['token'] as String? ?? '';
        final adminName = resData['name']?.toString() ?? resData['user_name']?.toString() ?? username;
        final adminRole = resData['role']?.toString() ?? resData['designation']?.toString() ?? 'System Admin';
        
        if (token.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('auth_token', token);
          await prefs.setString('admin_name', adminName);
          await prefs.setString('admin_role', adminRole);
        }
        
        if (!mounted) return;
        if (widget.reauthorizeStaffName != null) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => RegisterFaceScreen(
                employeeName: widget.reauthorizeStaffName,
                empCode: widget.reauthorizeStaffCode,
              ),
            ),
          );
        } else if (widget.isModal || Navigator.canPop(context)) {
          Navigator.pop(context, token);
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => FaceRecognitionScreen(token: token)),
          );
        }
      } else {
        String errorMessage = 'Authorization Failed';
        try {
          final resData = jsonDecode(response.body);
          if (resData['message'] != null) {
            errorMessage = resData['message'];
          } else if (resData['error'] != null) {
            errorMessage = resData['error'];
          }
        } catch (_) {}

        if (mounted) {
          ToastUtil.showError(context, errorMessage);
        }
      }
    } catch (e) {
      debugPrint('--- API Request Exception: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ToastUtil.showError(context, 'Network Error: $e');
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isReauth = widget.reauthorizeStaffName != null;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Fixed Clean Background Image without Cambridge branding
          Image.asset(
            'assets/images/loginbackground.png',
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (context, error, stackTrace) => Container(
              color: AppColors.background,
            ),
          ),

          // Scrollable content
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: EdgeInsets.only(
                    left: 28.0,
                    right: 28.0,
                    top: 16.0,
                    bottom: bottomInset > 0 ? bottomInset + 16.0 : 16.0,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 32.0,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Optional back button if navigated from Staff Screen
                          if (Navigator.canPop(context))
                            Align(
                              alignment: Alignment.centerLeft,
                              child: IconButton(
                                icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF111827)),
                                onPressed: () => Navigator.pop(context),
                              ),
                            )
                          else
                            const SizedBox(height: 10),

                          // 1. Top Logo
                          Center(
                            child: Image.asset(
                              'assets/images/logo.png',
                              width: 82,
                              height: 82,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) => Container(
                                width: 82,
                                height: 82,
                                decoration: const BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.school_rounded,
                                  color: Colors.white,
                                  size: 40,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          // 2. Title & Subtitle
                          Text(
                            isReauth ? 'Re-Authorize Staff' : 'The Aalam School',
                            style: GoogleFonts.outfit(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF111827),
                              letterSpacing: -0.4,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),

                          Text(
                            isReauth
                                ? 'Admin verification for ${widget.reauthorizeStaffName}'
                                : 'Attendance Portal',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isReauth ? AppColors.accent : AppColors.primary,
                              letterSpacing: 0.2,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),

                          // 3. Username Input
                          TextField(
                            controller: _usernameController,
                            textInputAction: TextInputAction.next,
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              color: const Color(0xFF111827),
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Admin Username',
                              hintStyle: GoogleFonts.outfit(
                                fontSize: 14,
                                color: const Color(0xFF9CA3AF),
                                fontWeight: FontWeight.w500,
                              ),
                              prefixIcon: const Icon(
                                Icons.person_outline_rounded,
                                color: AppColors.primary,
                                size: 22,
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 15,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: AppColors.border,
                                  width: 1.5,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: AppColors.border,
                                  width: 1.5,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: AppColors.primary,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // 4. Password Input
                          TextField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _login(),
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              color: const Color(0xFF111827),
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Admin Password',
                              hintStyle: GoogleFonts.outfit(
                                fontSize: 14,
                                color: const Color(0xFF9CA3AF),
                                fontWeight: FontWeight.w500,
                              ),
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                                color: AppColors.primary,
                                size: 22,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: const Color(0xFF9CA3AF),
                                  size: 20,
                                ),
                                onPressed: () {
                                  setState(() => _obscurePassword = !_obscurePassword);
                                },
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 15,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: AppColors.border,
                                  width: 1.5,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: AppColors.border,
                                  width: 1.5,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: AppColors.primary,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),

                          // 5. Submit Button
                          ElevatedButton(
                            onPressed: _isLoading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 3,
                              shadowColor: AppColors.primary.withValues(alpha: 0.4),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.2,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        isReauth ? 'Authorize & Proceed' : 'Sign In',
                                        style: GoogleFonts.outfit(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 18,
                                        color: Colors.white,
                                      ),
                                    ],
                                  ),
                          ),

                          const Spacer(),

                          // 6. Security Note at bottom
                          Center(
                            child: Container(
                              margin: const EdgeInsets.only(top: 8.0, bottom: 6.0),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: AppColors.border.withValues(alpha: 0.8),
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.shield_outlined,
                                    size: 14,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Authorized Personnel Access Only',
                                    style: GoogleFonts.outfit(
                                      color: const Color(0xFF1F2937),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
