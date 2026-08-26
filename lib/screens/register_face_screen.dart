import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import '../config/api_config.dart';
import '../services/ml_service.dart';
import '../theme/app_colors.dart';
import '../utils/toast_util.dart';

class RegisterFaceScreen extends StatefulWidget {
  final String? employeeName;
  final String? empCode;
  
  const RegisterFaceScreen({super.key, this.employeeName, this.empCode});

  @override
  State<RegisterFaceScreen> createState() => _RegisterFaceScreenState();
}

class _RegisterFaceScreenState extends State<RegisterFaceScreen> {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  final FaceDetector _faceDetector = FaceDetector(options: FaceDetectorOptions(enableContours: false, enableClassification: false));

  @override
  void initState() {
    super.initState();
    _initCamera();
    MLService().initialize();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        final frontCamera = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => cameras.first,
        );
        _cameraController = CameraController(
          frontCamera,
          ResolutionPreset.medium,
          enableAudio: false,
        );
        await _cameraController!.initialize();
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  Future<void> _authorizeFace() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    setState(() => _isProcessing = true);

    try {
      // 1. Take Picture
      final XFile file = await _cameraController!.takePicture();
      final bytes = await File(file.path).readAsBytes();
      
      // 2. Decode image
      img.Image? originalImage = img.decodeImage(bytes);
      if (originalImage == null) throw Exception("Could not decode image");

      // 3. Detect Face using MLKit
      final inputImage = InputImage.fromFilePath(file.path);
      final List<Face> faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        throw Exception("No face detected! Please position your face clearly in the frame.");
      }
      if (faces.length > 1) {
        throw Exception("Multiple faces detected! Please ensure only one person is in frame.");
      }

      // 4. Extract Vector
      final Rect boundingBox = faces.first.boundingBox;
      final List<double>? vector = MLService().extractFaceVector(originalImage, boundingBox);

      if (vector == null) {
        throw Exception("Failed to extract biometric vector from model.");
      }

      // 5. POST to API
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}employees_update_vector'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'emp_code': widget.empCode,
          'face_vector': jsonEncode(vector),
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (!mounted) return;
        ToastUtil.showSuccess(context, "Face biometrics enrolled successfully!");
        Navigator.pop(context, true);
      } else {
        String errorMessage = "Biometric enrollment failed";
        try {
          final resData = jsonDecode(response.body);
          if (resData['message'] != null) errorMessage = resData['message'];
        } catch (_) {}
        throw Exception(errorMessage);
      }
    } catch (e) {
      debugPrint("Authorization Error: $e");
      if (mounted) {
        ToastUtil.showError(context, e.toString().replaceAll("Exception: ", ""));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Biometric Enrollment',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Employee Info Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.accentLight,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
                      ),
                      child: Center(
                        child: Text(
                          widget.employeeName != null && widget.employeeName!.isNotEmpty
                              ? widget.employeeName![0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.employeeName ?? 'Unknown Employee',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Employee ID: ${widget.empCode ?? 'N/A'}',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Circular Biometric Scanner Viewfinder
              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer Soft Glow
                    Container(
                      width: 270,
                      height: 270,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accent.withValues(alpha: 0.12),
                            blurRadius: 36,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                    ),

                    // Camera View Container
                    Container(
                      width: 260,
                      height: 260,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF090D16),
                        border: Border.all(
                          color: AppColors.accent,
                          width: 2,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_isCameraInitialized && _cameraController != null && _cameraController!.value.isInitialized)
                            FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: _cameraController!.value.previewSize?.height ?? 260,
                                height: _cameraController!.value.previewSize?.width ?? 260,
                                child: CameraPreview(_cameraController!),
                              ),
                            )
                          else
                            const Center(
                              child: CircularProgressIndicator(
                                color: AppColors.accent,
                                strokeWidth: 2.5,
                              ),
                            ),
                            
                          // Biometric HUD Reticle Overlay
                          CustomPaint(
                            painter: _BiometricEnrollmentReticlePainter(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Instructions
              Center(
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.accent),
                        const SizedBox(width: 6),
                        Text(
                          'Align face directly within the circle',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ensure good lighting and avoid shadows or glare',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 36),

              // Capture & Authorize Button
              ElevatedButton(
                onPressed: _isProcessing ? null : _authorizeFace,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 2,
                  shadowColor: AppColors.primary.withValues(alpha: 0.3),
                ),
                child: _isProcessing 
                  ? const SizedBox(
                      width: 22, 
                      height: 22, 
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2)
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt_rounded, size: 18, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          'Capture & Enroll Biometrics',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _BiometricEnrollmentReticlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final amberPaint = Paint()
      ..color = const Color(0xFFF59E0B).withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    final dashedPaint = Paint()
      ..color = const Color(0xFFF59E0B).withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    // 1. Target Corner Reticles
    final rInset = size.width * 0.32;
    const bLen = 18.0;
    // Top-Left
    canvas.drawPath(Path()..moveTo(center.dx - rInset, center.dy - rInset + bLen)..lineTo(center.dx - rInset, center.dy - rInset)..lineTo(center.dx - rInset + bLen, center.dy - rInset), amberPaint);
    // Top-Right
    canvas.drawPath(Path()..moveTo(center.dx + rInset, center.dy - rInset + bLen)..lineTo(center.dx + rInset, center.dy - rInset)..lineTo(center.dx + rInset - bLen, center.dy - rInset), amberPaint);
    // Bottom-Left
    canvas.drawPath(Path()..moveTo(center.dx - rInset, center.dy + rInset - bLen)..lineTo(center.dx - rInset, center.dy + rInset)..lineTo(center.dx - rInset + bLen, center.dy + rInset), amberPaint);
    // Bottom-Right
    canvas.drawPath(Path()..moveTo(center.dx + rInset, center.dy + rInset - bLen)..lineTo(center.dx + rInset, center.dy + rInset)..lineTo(center.dx + rInset - bLen, center.dy + rInset), amberPaint);

    // 2. Guide Ring
    final midRadius = size.width * 0.40;
    canvas.drawCircle(center, midRadius, dashedPaint);

    // 3. Four outer arc segments
    final outerRadius = size.width * 0.46;
    for (int i = 0; i < 4; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: outerRadius),
        (i * math.pi / 2) + 0.15,
        (math.pi / 2) - 0.3,
        false,
        amberPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

