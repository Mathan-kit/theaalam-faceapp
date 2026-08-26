import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';

import '../config/api_config.dart';
import '../services/ml_service.dart';
import '../theme/app_colors.dart';
import '../utils/toast_util.dart';

import 'login_screen.dart';
import 'staff_screen.dart';
import 'logs_screen.dart';
import 'settings_screen.dart';

class FaceRecognitionScreen extends StatefulWidget {
  final String token;
  const FaceRecognitionScreen({super.key, required this.token});

  @override
  State<FaceRecognitionScreen> createState() => _FaceRecognitionScreenState();
}

class _FaceRecognitionScreenState extends State<FaceRecognitionScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  int _currentIndex = 0;
  String _adminName = 'Admin';
  String _adminRole = 'System Admin';

  bool _isProcessingFrame = false;
  final FaceDetector _faceDetector = FaceDetector(options: FaceDetectorOptions(enableContours: false, enableClassification: false));
  List<Map<String, dynamic>> _authorizedEmployees = [];
  final Map<String, DateTime> _lastAttendanceMap = {};
  final List<Map<String, dynamic>> _recentAttendances = [];
  DateTime? _lastUnknownFaceTime;
  bool _isCheckInTab = true;
  bool _isCameraActive = false;
  bool _hasLocationAccess = false;
  Timer? _cameraTimeoutTimer;
  Map<String, dynamic>? _attendanceFeedback;
  Timer? _feedbackTimer;
  final ScrollController _logsScrollController = ScrollController();
  late AnimationController _scannerAnimController;

  // Safe base URL helper to prevent 404 errors missing the slash
  String get safeBaseUrl {
    return ApiConfig.baseUrl.endsWith('/') ? ApiConfig.baseUrl : '${ApiConfig.baseUrl}/';
  }

  @override
  void initState() {
    super.initState();  
    WidgetsBinding.instance.addObserver(this);
    _scannerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLocationAccess(showMessage: true);
    });
    _loadAdminDetails();
    MLService().initialize();
    _loadAuthorizedEmployees();
    _initCamera();
  }

  bool _isDialogShowing = false;

  void _showLocationDialog({required bool isGps}) {
    if (_isDialogShowing) return;
    _isDialogShowing = true;
    _setCameraActive(false);
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: AppColors.surface,
          title: const Row(
            children: [
              Icon(Icons.location_off_rounded, color: AppColors.error),
              SizedBox(width: 10),
              Text(
                "Location Required",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
            ],
          ),
          content: Text(
            isGps ? "Please enable device location to mark biometric attendance." : "Location permission is denied. Please enable it in App Settings.",
            style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _isDialogShowing = false;
              },
              child: const Text("Cancel", style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                _isDialogShowing = false;
                if (isGps) {
                  await Geolocator.openLocationSettings();
                } else {
                  await Geolocator.openAppSettings();
                }
                _checkLocationAccess(showMessage: true);
              },
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: Text(isGps ? "Turn On" : "Settings"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        );
      },
    ).then((_) => _isDialogShowing = false);
  }

  Future<bool> _checkLocationAccess({bool showMessage = false}) async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) setState(() => _hasLocationAccess = false);
      if (showMessage && mounted) {
        _showLocationDialog(isGps: true);
      }
      return false;
    }
    
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    
    if (permission == LocationPermission.deniedForever) {
      if (mounted) setState(() => _hasLocationAccess = false);
      if (showMessage && mounted) {
        _showLocationDialog(isGps: false);
      }
      return false;
    }

    bool hasAccess = (permission == LocationPermission.whileInUse || permission == LocationPermission.always);
    if (mounted) {
      setState(() {
        _hasLocationAccess = hasAccess;
      });
      if (!hasAccess && showMessage) {
        ToastUtil.showError(context, "Location permission is required to mark attendance.");
      }
    }
    return hasAccess;
  }

  Future<void> _loadAuthorizedEmployees() async {
    try {
      final response = await http.get(
        Uri.parse('${safeBaseUrl}employees'),
        headers: {'Accept': 'application/json', 'Authorization': 'Bearer ${widget.token}'},
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final resData = jsonDecode(response.body);
        final List<dynamic> data = resData['data'] ?? [];
        _authorizedEmployees = data
            .where((e) {
              final vec = e['face_vector'];
              return vec != null && vec != 'null' && vec != '[]' && vec.toString().length > 10;
            })
            .map((e) => e as Map<String, dynamic>)
            .toList();
        
        debugPrint("Successfully loaded ${_authorizedEmployees.length} authorized employees into memory.");
      }
    } catch (e) {
      debugPrint("Failed to load authorized employees: $e");
    }
  }

  Future<void> _loadAdminDetails() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _adminName = prefs.getString('admin_name') ?? 'Admin';
        _adminRole = prefs.getString('admin_role') ?? 'System Admin';
      });
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        debugPrint('No cameras available on this device');
        return;
      }
      
      final frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController?.dispose();
      
      CameraController controller = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      
      try {
        await controller.initialize();
      } catch (e) {
        debugPrint('Camera nv21 init failed, attempting fallback format: $e');
        controller = CameraController(
          frontCamera,
          ResolutionPreset.medium,
          enableAudio: false,
        );
        await controller.initialize();
      }

      if (!mounted) {
        controller.dispose();
        return;
      }

      _cameraController = controller;
      setState(() {
        _isCameraInitialized = true;
      });

      if (_isCameraActive) {
        try {
          await _cameraController!.startImageStream(_processCameraFrame);
        } catch (streamErr) {
          debugPrint('Error starting image stream in _initCamera: $streamErr');
        }
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
      if (mounted) {
        setState(() {
          _isCameraInitialized = false;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scannerAnimController.dispose();
    _cameraTimeoutTimer?.cancel();
    _faceDetector.close();
    _cameraController?.dispose();
    _logsScrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _cameraController?.stopImageStream();
      _cameraController?.dispose();
      _cameraController = null;
      if (mounted) {
        setState(() {
          _isCameraInitialized = false;
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      _checkLocationAccess(showMessage: true);
      if (_currentIndex == 0) {
        _initCamera();
      }
    }
  }

  Future<void> _processCameraFrame(CameraImage image) async {
    if (_isProcessingFrame || !mounted || !_isCameraActive || _cameraController == null) return;
    _isProcessingFrame = true;

    try {
      if (image.planes.isEmpty) return;

      final camera = _cameraController!.description;
      final sensorOrientation = camera.sensorOrientation;
      final rotation = InputImageRotationValue.fromRawValue(sensorOrientation) ?? InputImageRotation.rotation270deg;
      final format = InputImageFormatValue.fromRawValue(image.format.raw) ?? (Platform.isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888);

      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final inputImageData = InputImageMetadata(
        size: imageSize,
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      final inputImage = InputImage.fromBytes(bytes: bytes, metadata: inputImageData);
      final List<Face> faces = await _faceDetector.processImage(inputImage);

      if (faces.isNotEmpty) {
        final Rect boundingBox = faces.first.boundingBox;
        final List<double>? vector = MLService().extractFaceVectorFromCameraImage(image, boundingBox);
        
        if (vector != null) {
          _findMatchingEmployee(vector);
        }
      }
    } catch (e, stack) {
      debugPrint('Camera Frame Error: $e\n$stack');
    } finally {
      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 1000));
        _isProcessingFrame = false;
      }
    }
  }

  void _findMatchingEmployee(List<double> vector) {
    if (_authorizedEmployees.isEmpty) {
      debugPrint("Warning: No authorized employees loaded.");
    }

    double minDistance = double.maxFinite;
    Map<String, dynamic>? matchedEmployee;

    for (var employee in _authorizedEmployees) {
      final rawVector = employee['face_vector'];
      if (rawVector == null) continue;

      try {
        List<dynamic> parsed;
        if (rawVector is String) {
          parsed = jsonDecode(rawVector);
        } else if (rawVector is List) {
          parsed = rawVector;
        } else {
          continue;
        }
        
        List<double> storedVector = parsed.map((e) => (e as num).toDouble()).toList();
        double distance = MLService().calculateDistance(vector, storedVector);
        
        if (distance < minDistance) {
          minDistance = distance;
          matchedEmployee = employee;
        }
      } catch (_) {
        continue;
      }
    }

    if (minDistance < 0.8 && matchedEmployee != null) {
      _markAttendance(matchedEmployee, vector);
    } else {
      if (_lastUnknownFaceTime == null || DateTime.now().difference(_lastUnknownFaceTime!).inSeconds > 3) {
        _lastUnknownFaceTime = DateTime.now();
        if (mounted) {
          ToastUtil.showError(context, "Face Not Authorized");
        }
      }
    }
  }

  Future<void> _markAttendance(Map<String, dynamic> employee, List<double> vector) async {
    final empCode = employee['emp_code']?.toString() ?? '';
    if (empCode.isEmpty) return;

    final lastTime = _lastAttendanceMap[empCode];
    if (lastTime != null && DateTime.now().difference(lastTime).inSeconds < 60) {
      return; 
    }
    
    _lastAttendanceMap[empCode] = DateTime.now();

    Position? currentPosition;
    try {
      currentPosition = await _determinePosition();
    } catch (e) {
      debugPrint("Location error: $e");
    }

    if (currentPosition == null) {
      if (mounted) {
        ToastUtil.showError(context, "Location is mandatory for attendance. Please enable GPS.");
        await _setCameraActive(false);
      }
      _lastAttendanceMap.remove(empCode);
      return;
    }

    try {
      String latLanStr = '${currentPosition.latitude},${currentPosition.longitude}';

      final response = await http.post(
        Uri.parse('${safeBaseUrl}daily_emp_attendance'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: jsonEncode({
          'emp_code': empCode,
          'type': _isCheckInTab ? 'check_in' : 'check_out',
          'face_vector': jsonEncode(vector),
          'lat_lan': latLanStr,
        }),
      );

      String msg = "Failed to log attendance";
      bool isSuccess = false;
      DateTime logTime = DateTime.now();
      
      try {
        final resData = jsonDecode(response.body);
        if (resData['message'] != null) msg = resData['message'];

        if (resData['data'] != null) {
          String? timeStr = resData['data']['out_time'] ?? resData['data']['in_time'];
          if (timeStr != null) {
            logTime = DateTime.tryParse(timeStr) ?? DateTime.now();
          }
        } else if (resData['type'] == 'Duplicate' && msg.contains(' at ')) {
          try {
            final parts = msg.split(' at ');
            if (parts.length > 1) {
              String timePart = parts[1].replaceAll('.', '').trim();
              logTime = DateFormat('h:mm a').parse(timePart);
              msg = parts[0].trim();
            }
          } catch (_) {}
        }

        if (resData['type'] == 'Duplicate' || resData['type'] == 'Error') {
          isSuccess = false; 
        } else if (resData['success'] != null) {
          isSuccess = resData['success'] == true;
        } else {
          isSuccess = response.statusCode == 200 || response.statusCode == 201;
        }
      } catch (_) {
        isSuccess = response.statusCode == 200 || response.statusCode == 201;
      }

      _cameraTimeoutTimer?.cancel();

      if (mounted) {
        _showFeedback(isSuccess, employee['employee_name'] ?? 'Employee', msg, logTime);
        setState(() {
          _recentAttendances.insert(0, {
            'name': employee['employee_name'] ?? 'Employee',
            'message': msg,
            'time': logTime,
            'isSuccess': isSuccess,
          });
          if (_recentAttendances.length > 20) _recentAttendances.removeLast();
        });
      }
    } catch (e) {
      debugPrint("Attendance log API request failed: $e");
    }
  }

  void _showFeedback(bool isSuccess, String name, String msg, DateTime time) {
    _setCameraActive(false);
    setState(() {
      _attendanceFeedback = {
        'isSuccess': isSuccess,
        'name': name,
        'msg': msg,
        'time': time,
      };
    });
    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _attendanceFeedback = null;
        });
      }
    });
  }

  Future<void> _setCameraActive(bool active) async {
    if (_isCameraActive == active) return;
    setState(() {
      _isCameraActive = active;
    });

    if (active) {
      if (_cameraController == null || !_isCameraInitialized || !_cameraController!.value.isInitialized) {
        await _initCamera();
      }
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        try {
          await _cameraController!.startImageStream(_processCameraFrame);
        } catch (e) {
          debugPrint('Error starting image stream in _setCameraActive: $e');
        }
      }
    } else {
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        try {
          await _cameraController!.stopImageStream();
        } catch (e) {
          debugPrint('Error stopping camera stream: $e');
        }
      }
    }
  }

  void _startCameraTimeout() {
    _cameraTimeoutTimer?.cancel();
    _cameraTimeoutTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && _isCameraActive) {
        _setCameraActive(false);
      }
    });
  }

  Future<Position?> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }
    
    if (permission == LocationPermission.deniedForever) return null;

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high, 
        timeLimit: const Duration(seconds: 5)
      );
    } catch (e) {
      debugPrint("Error getting location: $e");
      return null;
    }
  }

  Widget _buildHomeBody(ThemeData theme) {
    final Color activeColor = _isCheckInTab ? AppColors.success : AppColors.error;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/images/logo.png',
                        errorBuilder: (context, error, stackTrace) => const Icon(
                          Icons.fingerprint,
                          color: AppColors.accent,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'THE AALAM',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Workforce Attendance',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                
                // Right controls: Location status pill + Admin avatar
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _hasLocationAccess ? AppColors.successLight : AppColors.errorLight,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _hasLocationAccess ? AppColors.success.withValues(alpha: 0.3) : AppColors.error.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _hasLocationAccess ? Icons.location_on_rounded : Icons.location_off_rounded,
                            size: 13,
                            color: _hasLocationAccess ? AppColors.success : AppColors.error,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _hasLocationAccess ? "GPS Ready" : "No GPS",
                            style: TextStyle(
                              color: _hasLocationAccess ? AppColors.success : AppColors.error,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Admin avatar menu
                    PopupMenuButton<String>(
                      offset: const Offset(0, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      color: AppColors.surface,
                      elevation: 8,
                      onSelected: (value) async {
                        if (value == 'logout') {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.remove('auth_token');
                          if (mounted) {
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(builder: (context) => const LoginScreen()),
                              (route) => false,
                            );
                          }
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem<String>(
                          enabled: false,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_adminName, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary, fontSize: 15)),
                              const SizedBox(height: 2),
                              Text(_adminRole, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem<String>(
                          value: 'logout',
                          child: Row(
                            children: [
                              Icon(Icons.logout_rounded, color: AppColors.error, size: 18),
                              SizedBox(width: 10),
                              Text('Logout', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600, fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.accentLight,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.accent.withValues(alpha: 0.3), width: 1.2),
                        ),
                        child: Center(
                          child: Text(
                            _adminName.isNotEmpty ? _adminName[0].toUpperCase() : 'A',
                            style: const TextStyle(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // Segmented Tab Switcher (Check In / Check Out)
            Container(
              height: 48,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        bool hasAccess = await _checkLocationAccess(showMessage: true);
                        if (!hasAccess) return;

                        setState(() => _isCheckInTab = true);
                        await _setCameraActive(true);
                        _startCameraTimeout();
                        _lastAttendanceMap.clear();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: _isCheckInTab ? AppColors.success : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: _isCheckInTab
                              ? [
                                  BoxShadow(
                                    color: AppColors.success.withValues(alpha: 0.25),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.login_rounded,
                              size: 16,
                              color: _isCheckInTab ? Colors.white : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Check In',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: _isCheckInTab ? Colors.white : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        bool hasAccess = await _checkLocationAccess(showMessage: true);
                        if (!hasAccess) return;

                        setState(() => _isCheckInTab = false);
                        await _setCameraActive(true);
                        _startCameraTimeout();
                        _lastAttendanceMap.clear();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: !_isCheckInTab ? AppColors.error : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: !_isCheckInTab
                              ? [
                                  BoxShadow(
                                    color: AppColors.error.withValues(alpha: 0.25),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.logout_rounded,
                              size: 16,
                              color: !_isCheckInTab ? Colors.white : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Check Out',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: !_isCheckInTab ? Colors.white : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Biometric Camera Viewfinder
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer Ambient Glow
                  Container(
                    height: 270,
                    width: 270,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: activeColor.withValues(alpha: _isCameraActive ? 0.2 : 0.06),
                          blurRadius: 36,
                          spreadRadius: 4,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                  ),

                  // Main Circular Aperture
                  Container(
                    height: 260,
                    width: 260,
                    decoration: BoxDecoration(
                      color: _isCameraActive ? const Color(0xFF090D16) : AppColors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _isCameraActive ? activeColor.withValues(alpha: 0.8) : AppColors.border,
                        width: 2.5,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_isCameraActive)
                          if (_isCameraInitialized && _cameraController != null && _cameraController!.value.isInitialized)
                            SizedBox.expand(
                              child: FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: _cameraController!.value.previewSize?.height ?? 260,
                                  height: _cameraController!.value.previewSize?.width ?? 260,
                                  child: CameraPreview(_cameraController!),
                                ),
                              ),
                            )
                          else
                            Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: activeColor,
                              ),
                            )
                        else if (_attendanceFeedback != null)
                          _buildAnimatedFeedback()
                        else
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: activeColor.withValues(alpha: 0.08),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.face_retouching_natural_rounded,
                                    size: 56,
                                    color: activeColor,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Tap Check In to Scan',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                        // Futuristic AI Reticle Overlay
                        if (_isCameraActive)
                          AnimatedBuilder(
                            animation: _scannerAnimController,
                            builder: (context, child) {
                              return CustomPaint(
                                painter: _AiScannerReticlePainter(
                                  color: activeColor,
                                  progress: _scannerAnimController.value,
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            
            // Status Text & Pulse
            if (_isCameraActive)
              Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: activeColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Scanning Biometric Features...',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: activeColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Position face within the reticle frame',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              )
            else
              Center(
                child: Text(
                  'Ready to Mark Attendance',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            
            const SizedBox(height: 24),
            
            // Recent Attendance Stream Section
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Recent Activity',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Today',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_recentAttendances.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24.0),
                      child: Center(
                        child: Text(
                          "No recent attendance logs recorded yet.",
                          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _recentAttendances.length > 5 ? 5 : _recentAttendances.length,
                      separatorBuilder: (context, index) => const Divider(color: AppColors.borderSubtle, height: 16),
                      itemBuilder: (context, index) {
                        final log = _recentAttendances[index];
                        final timeStr = DateFormat('hh:mm a').format(log['time'] as DateTime);
                        final bool isSuccess = log['isSuccess'] ?? true;
                        final String msg = log['message']?.toString() ?? '';
                        final bool isCheckIn = !msg.toLowerCase().contains('out');

                        return Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: isSuccess
                                    ? (isCheckIn ? AppColors.successLight : AppColors.errorLight)
                                    : AppColors.warningLight,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isSuccess
                                    ? (isCheckIn ? Icons.login_rounded : Icons.logout_rounded)
                                    : Icons.warning_amber_rounded,
                                size: 16,
                                color: isSuccess
                                    ? (isCheckIn ? AppColors.success : AppColors.error)
                                    : AppColors.warning,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    log['name'] ?? 'Employee',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    msg,
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              timeStr,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget body;
    if (_currentIndex == 1) {
      body = LogsScreen(token: widget.token);
    } else if (_currentIndex == 2) {
      body = StaffScreen(token: widget.token);
    } else if (_currentIndex == 3) {
      body = const SettingsScreen();
    } else {
      body = _buildHomeBody(theme);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: body,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: const Border(top: BorderSide(color: AppColors.border, width: 1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          backgroundColor: AppColors.surface,
          surfaceTintColor: Colors.transparent,
          indicatorColor: AppColors.accentLight,
          elevation: 0,
          onDestinationSelected: (index) {
            if (_currentIndex == 0 && index != 0) {
              _cameraController?.dispose();
              _cameraController = null;
              _isCameraInitialized = false;
              _isCameraActive = false;
              _cameraTimeoutTimer?.cancel();
            } else if (_currentIndex != 0 && index == 0) {
              _loadAuthorizedEmployees();
              _lastAttendanceMap.clear();
              _initCamera();
            }
            setState(() {
              _currentIndex = index;
            });
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined, color: AppColors.textSecondary),
              selectedIcon: Icon(Icons.home_rounded, color: AppColors.accent),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined, color: AppColors.textSecondary),
              selectedIcon: Icon(Icons.receipt_long_rounded, color: AppColors.accent),
              label: 'Logs',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_outline_rounded, color: AppColors.textSecondary),
              selectedIcon: Icon(Icons.people_rounded, color: AppColors.accent),
              label: 'Staff',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined, color: AppColors.textSecondary),
              selectedIcon: Icon(Icons.settings_rounded, color: AppColors.accent),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedFeedback() {
    final bool isSuccess = _attendanceFeedback!['isSuccess'];
    final String name = _attendanceFeedback!['name'];
    final String msg = _attendanceFeedback!['msg'];
    final DateTime time = _attendanceFeedback!['time'];
    final Color color = isSuccess ? AppColors.success : AppColors.warning;

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isSuccess ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                size: 36,
                color: color,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "$msg\n${DateFormat('h:mm a').format(time)}",
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiScannerReticlePainter extends CustomPainter {
  final Color color;
  final double progress;

  _AiScannerReticlePainter({required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Outer Target Brackets
    final bracketPaint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const bLen = 22.0;
    final rInset = radius * 0.72;

    // 4 Corner Brackets
    // Top-Left
    canvas.drawPath(Path()..moveTo(center.dx - rInset, center.dy - rInset + bLen)..lineTo(center.dx - rInset, center.dy - rInset)..lineTo(center.dx - rInset + bLen, center.dy - rInset), bracketPaint);
    // Top-Right
    canvas.drawPath(Path()..moveTo(center.dx + rInset, center.dy - rInset + bLen)..lineTo(center.dx + rInset, center.dy - rInset)..lineTo(center.dx + rInset - bLen, center.dy - rInset), bracketPaint);
    // Bottom-Left
    canvas.drawPath(Path()..moveTo(center.dx - rInset, center.dy + rInset - bLen)..lineTo(center.dx - rInset, center.dy + rInset)..lineTo(center.dx - rInset + bLen, center.dy + rInset), bracketPaint);
    // Bottom-Right
    canvas.drawPath(Path()..moveTo(center.dx + rInset, center.dy + rInset - bLen)..lineTo(center.dx + rInset, center.dy + rInset)..lineTo(center.dx + rInset - bLen, center.dy + rInset), bracketPaint);

    // Animated Scanning Beam
    final scanY = (center.dy - rInset) + (rInset * 2 * progress);
    final scanPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.7),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(center.dx - rInset, scanY - 1, rInset * 2, 2))
      ..strokeWidth = 2;

    canvas.drawLine(Offset(center.dx - rInset + 8, scanY), Offset(center.dx + rInset - 8, scanY), scanPaint);
  }

  @override
  bool shouldRepaint(covariant _AiScannerReticlePainter oldDelegate) => true;
}