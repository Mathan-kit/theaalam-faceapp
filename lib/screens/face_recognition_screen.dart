import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../services/ml_service.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../utils/toast_util.dart';
import '../widgets/app_background.dart';
import '../widgets/custom_bottom_nav_bar.dart';

import 'staff_screen.dart';
import 'logs_screen.dart';
import 'settings_screen.dart';
import 'login_screen.dart';

class StaffAttendanceState {
  DateTime? checkInTime;
  DateTime? checkOutTime;
  DateTime lastUpdated;

  StaffAttendanceState({
    this.checkInTime,
    this.checkOutTime,
    required this.lastUpdated,
  });
}

class FaceRecognitionScreen extends StatefulWidget {
  final String token;
  const FaceRecognitionScreen({super.key, required this.token});

  @override
  State<FaceRecognitionScreen> createState() => _FaceRecognitionScreenState();
}

class _FaceRecognitionScreenState extends State<FaceRecognitionScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  int _currentIndex = 0;

  bool _isProcessingFrame = false;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: false,
      enableClassification: false,
      performanceMode: FaceDetectorMode.fast,
    ),
  );
  List<Map<String, dynamic>> _authorizedEmployees = [];
  static const String _tmpEmployeesCacheKey = 'tmp_authorized_employees';
  Timer? _backgroundApiSyncTimer;
  bool _isSyncingEmployees = false;
  final Map<String, DateTime> _lastScanCooldownMap = {};
  final Map<String, StaffAttendanceState> _staffDailyStatus = {};
  String _lastTrackedDate = '';

  final List<Map<String, dynamic>> _recentAttendances = [];
  DateTime? _lastUnknownFaceTime;

  bool _isCameraActive = false;
  Timer? _cameraTimeoutTimer;
  Timer? _countdownTicker;
  int _secondsRemaining = 10;

  Timer? _liveClockTimer;
  DateTime _currentTime = DateTime.now();

  Map<String, dynamic>? _attendanceFeedback;
  Timer? _feedbackTimer;
  final ScrollController _logsScrollController = ScrollController();
  late AnimationController _scannerAnimController;
  late AnimationController _fingerTapController;
  late Animation<double> _fingerTapScaleAnimation;
  String _authToken = '';
  String? _adminName;

  // Safe base URL helper to prevent 404 errors missing the slash
  String get safeBaseUrl {
    return ApiConfig.baseUrl.endsWith('/') ? ApiConfig.baseUrl : '${ApiConfig.baseUrl}/';
  }

  @override
  void initState() {
    super.initState();
    _authToken = widget.token;
    _loadAdminInfo();
    WidgetsBinding.instance.addObserver(this);
    _scannerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _fingerTapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _fingerTapScaleAnimation = Tween<double>(begin: 0.92, end: 1.12).animate(
      CurvedAnimation(parent: _fingerTapController, curve: Curves.easeInOut),
    );

    _checkAndResetDailyData();

    // Start live clock updates
    _liveClockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
        _checkAndResetDailyData();
      }
    });

    MLService().initialize();
    _initEmployeesAndStartBackgroundSync();
    _fetchTodayAttendanceLogs();
  }

  Future<void> _loadAdminInfo() async {
    final token = await AuthService().getValidToken();
    if (token.isNotEmpty) {
      final name = await AuthService().getAdminName();
      if (mounted) {
        setState(() {
          _authToken = token;
          _adminName = name;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _authToken = '';
          _adminName = null;
        });
      }
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.logout_rounded, color: AppColors.error, size: 22),
            ),
            const SizedBox(width: 12),
            Text(
              'Confirm Logout',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        content: Text(
          _adminName != null
              ? 'Are you sure you want to log out ($_adminName)? You will need to log in again with credentials to access protected features.'
              : 'Are you sure you want to log out of Admin mode? You will need to log in again with credentials to access protected features.',
          style: GoogleFonts.outfit(
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: Text(
              'Logout',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await AuthService().logout();
      if (!mounted) return;
      setState(() {
        _authToken = '';
        _adminName = null;
        _currentIndex = 0;
      });
      ToastUtil.showSuccess(context, 'Logged out successfully');
    }
  }

  void _checkAndResetDailyData() {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (_lastTrackedDate.isNotEmpty && _lastTrackedDate != today) {
      _staffDailyStatus.clear();
      _lastScanCooldownMap.clear();
      _recentAttendances.clear();
      _fetchTodayAttendanceLogs();
    }
    _lastTrackedDate = today;
  }

  Future<String> _getAuthToken() async {
    if (_authToken.isNotEmpty) return _authToken;
    _authToken = await AuthService().getValidToken();
    return _authToken;
  }

  Future<void> _fetchTodayAttendanceLogs() async {
    final token = await _getAuthToken();
    if (token.isEmpty) return;
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final response = await http.get(
        Uri.parse('${safeBaseUrl}attendance_logs?date=$dateStr'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final resData = jsonDecode(response.body);
        List<dynamic> logs = [];
        if (resData['data'] is Map) {
          final present = resData['data']['present'] ?? [];
          final absent = resData['data']['absent'] ?? [];
          logs = [...present, ...absent];
        } else if (resData['data'] is List) {
          logs = resData['data'];
        }

        for (var log in logs) {
          final empCode = log['emp_code']?.toString() ?? '';
          if (empCode.isEmpty) continue;

          DateTime? inTime;
          DateTime? outTime;

          if (log['in_time'] != null && log['in_time'].toString().isNotEmpty) {
            inTime = DateTime.tryParse(log['in_time'].toString());
          }
          if (log['out_time'] != null && log['out_time'].toString().isNotEmpty) {
            outTime = DateTime.tryParse(log['out_time'].toString());
          }

          if (inTime != null || outTime != null) {
            _staffDailyStatus[empCode] = StaffAttendanceState(
              checkInTime: inTime,
              checkOutTime: outTime,
              lastUpdated: DateTime.now(),
            );
          }
        }
      }
    } catch (e) {
      debugPrint("Failed to fetch today's attendance logs: $e");
    }
  }

  /// Dual Check Part 1: Fast instant load from local TMP cache (0ms delay)
  Future<void> _loadAuthorizedEmployeesFromTmp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_tmpEmployeesCacheKey);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(cachedJson);
        final list = decoded
            .where((e) {
              final vec = e['face_vector'];
              return vec != null && vec != 'null' && vec != '[]' && vec.toString().length > 10;
            })
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        if (list.isNotEmpty && mounted) {
          setState(() {
            _authorizedEmployees = list;
          });
          debugPrint("TMP Cache: Instantly loaded ${_authorizedEmployees.length} authorized employees.");
        }
      }
    } catch (e) {
      debugPrint("Error loading TMP cache: $e");
    }
  }

  /// Dual Check Part 2: Background API sync - fetches latest data & updates TMP cache
  Future<void> _syncAuthorizedEmployeesFromApi({bool silent = false}) async {
    if (_isSyncingEmployees) return;
    _isSyncingEmployees = true;

    try {
      final token = await _getAuthToken();
      final headers = {
        'Accept': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final response = await http.get(
        Uri.parse('${safeBaseUrl}employees'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final resData = jsonDecode(response.body);
        final List<dynamic> data = resData['data'] ?? [];
        final parsedEmployees = data
            .where((e) {
              final vec = e['face_vector'];
              return vec != null && vec != 'null' && vec != '[]' && vec.toString().length > 10;
            })
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        if (mounted) {
          setState(() {
            _authorizedEmployees = parsedEmployees;
          });
        } else {
          _authorizedEmployees = parsedEmployees;
        }

        // Save into TMP cache ("tem") for instant recall next time or offline
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_tmpEmployeesCacheKey, jsonEncode(parsedEmployees));
        debugPrint("API Sync: Successfully synced ${_authorizedEmployees.length} employees and updated TMP cache.");
      } else {
        debugPrint("API Sync: Server returned status ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("API Sync: Background fetch error: $e");
    } finally {
      _isSyncingEmployees = false;
    }
  }

  /// Dual Check initializer: TMP first + API sync + starts continuous background timer
  Future<void> _initEmployeesAndStartBackgroundSync() async {
    // 1. Check TMP first (Instant recall)
    await _loadAuthorizedEmployeesFromTmp();

    // 2. Fetch fresh data from API in background
    await _syncAuthorizedEmployeesFromApi(silent: _authorizedEmployees.isNotEmpty);

    // 3. Start continuous background API sync timer
    _startBackgroundApiSync();
  }

  /// Keep API syncing continuously in the background every 30 seconds
  void _startBackgroundApiSync() {
    _backgroundApiSyncTimer?.cancel();
    _backgroundApiSyncTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _syncAuthorizedEmployeesFromApi(silent: true);
        _fetchTodayAttendanceLogs();
      }
    });
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
    _backgroundApiSyncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _scannerAnimController.dispose();
    _fingerTapController.dispose();
    _cameraTimeoutTimer?.cancel();
    _countdownTicker?.cancel();
    _liveClockTimer?.cancel();
    _feedbackTimer?.cancel();
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
    if (state == AppLifecycleState.resumed) {
      _syncAuthorizedEmployeesFromApi(silent: true);
      _fetchTodayAttendanceLogs();
    }
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _cameraController?.stopImageStream();
      _cameraController?.dispose();
      _cameraController = null;
      _cameraTimeoutTimer?.cancel();
      _countdownTicker?.cancel();
      if (mounted) {
        setState(() {
          _isCameraInitialized = false;
          _isCameraActive = false;
        });
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
      final format = InputImageFormatValue.fromRawValue(image.format.raw) ??
          (Platform.isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888);

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
        await Future.delayed(const Duration(milliseconds: 600));
        _isProcessingFrame = false;
      }
    }
  }

  void _findMatchingEmployee(List<double> vector) {
    if (_authorizedEmployees.isEmpty) {
      debugPrint("Warning: No authorized employees loaded. Triggering dual sync...");
      _loadAuthorizedEmployeesFromTmp();
      _syncAuthorizedEmployeesFromApi(silent: true);

      if (_lastUnknownFaceTime == null || DateTime.now().difference(_lastUnknownFaceTime!).inSeconds > 3) {
        _lastUnknownFaceTime = DateTime.now();
        if (mounted) {
          ToastUtil.showError(context, "Syncing employee biometrics... Please wait.");
        }
      }
      return;
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
      _processDynamicAttendance(matchedEmployee, vector);
    } else {
      if (_lastUnknownFaceTime == null || DateTime.now().difference(_lastUnknownFaceTime!).inSeconds > 3) {
        _lastUnknownFaceTime = DateTime.now();
        if (mounted) {
          ToastUtil.showError(context, "Face Not Authorized");
        }
      }
    }
  }

  Future<void> _processDynamicAttendance(Map<String, dynamic> employee, List<double> vector) async {
    final empCode = employee['emp_code']?.toString() ?? '';
    final empName = employee['employee_name'] ?? 'Employee';
    if (empCode.isEmpty) return;

    _checkAndResetDailyData();

    // Prevent rapid duplicate hits within 10s cooldown
    final lastTime = _lastScanCooldownMap[empCode];
    if (lastTime != null && DateTime.now().difference(lastTime).inSeconds < 10) {
      return;
    }
    _lastScanCooldownMap[empCode] = DateTime.now();

    final staffState = _staffDailyStatus[empCode];

    // CASE 1: Employee has not checked in today -> Log Check-In
    if (staffState == null || staffState.checkInTime == null) {
      await _submitAttendance(
        employee: employee,
        vector: vector,
        type: 'check_in',
        isCheckIn: true,
      );
      return;
    }

    // CASE 2: Employee has checked in, but has not checked out yet
    if (staffState.checkOutTime == null) {
      final elapsed = DateTime.now().difference(staffState.checkInTime!);
      final elapsedMinutes = elapsed.inMinutes;

      // 30-Minute Gap Check
      if (elapsedMinutes < 30) {
        final remainingMins = 30 - elapsedMinutes;
        final inTimeStr = DateFormat('hh:mm a').format(staffState.checkInTime!);
        _showFeedback(
          statusType: FeedbackType.info,
          name: empName,
          msg: "Already Checked In at $inTimeStr\nCheck-Out available in $remainingMins min(s)",
          time: staffState.checkInTime!,
        );
        return;
      }

      // 30+ Minutes Passed -> Log Check-Out
      await _submitAttendance(
        employee: employee,
        vector: vector,
        type: 'check_out',
        isCheckIn: false,
      );
      return;
    }

    // CASE 3: Employee has already completed both Check-In and Check-Out today
    final outTimeStr = DateFormat('hh:mm a').format(staffState.checkOutTime!);
    _showFeedback(
      statusType: FeedbackType.info,
      name: empName,
      msg: "Already Checked Out today at $outTimeStr",
      time: staffState.checkOutTime!,
    );
  }

  Future<void> _submitAttendance({
    required Map<String, dynamic> employee,
    required List<double> vector,
    required String type,
    required bool isCheckIn,
  }) async {
    final empCode = employee['emp_code']?.toString() ?? '';
    final empName = employee['employee_name'] ?? 'Employee';

    final token = await _getAuthToken();

    try {
      final response = await http.post(
        Uri.parse('${safeBaseUrl}daily_emp_attendance'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'emp_code': empCode,
          'type': type,
          'face_vector': jsonEncode(vector),
          'lat_lan': '',
        }),
      );

      String msg = isCheckIn ? "Check In Successful" : "Check Out Successful";
      FeedbackType statusType = isCheckIn ? FeedbackType.checkInSuccess : FeedbackType.checkOutSuccess;
      DateTime logTime = DateTime.now();

      try {
        final resData = jsonDecode(response.body);
        if (resData['message'] != null) {
          msg = resData['message'];
        }

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

        if (resData['type'] == 'Duplicate') {
          statusType = FeedbackType.info;
          if (isCheckIn) {
            msg = "Already Checked In today at ${DateFormat('hh:mm a').format(logTime)}";
          } else {
            msg = "Already Checked Out today at ${DateFormat('hh:mm a').format(logTime)}";
          }
        } else if (resData['type'] == 'Error') {
          statusType = FeedbackType.warning;
        } else if (resData['success'] != null) {
          statusType = resData['success'] == true
              ? (isCheckIn ? FeedbackType.checkInSuccess : FeedbackType.checkOutSuccess)
              : FeedbackType.warning;
        } else {
          statusType = (response.statusCode == 200 || response.statusCode == 201)
              ? (isCheckIn ? FeedbackType.checkInSuccess : FeedbackType.checkOutSuccess)
              : FeedbackType.warning;
        }
      } catch (_) {
        statusType = (response.statusCode == 200 || response.statusCode == 201)
            ? (isCheckIn ? FeedbackType.checkInSuccess : FeedbackType.checkOutSuccess)
            : FeedbackType.warning;
      }

      // Update local daily status
      if (statusType == FeedbackType.checkInSuccess ||
          statusType == FeedbackType.checkOutSuccess ||
          statusType == FeedbackType.info) {
        if (_staffDailyStatus[empCode] == null) {
          _staffDailyStatus[empCode] = StaffAttendanceState(
            checkInTime: isCheckIn ? logTime : null,
            checkOutTime: !isCheckIn ? logTime : null,
            lastUpdated: DateTime.now(),
          );
        } else {
          if (isCheckIn) {
            _staffDailyStatus[empCode]!.checkInTime = logTime;
          } else {
            _staffDailyStatus[empCode]!.checkOutTime = logTime;
          }
        }
      }

      _cameraTimeoutTimer?.cancel();
      _countdownTicker?.cancel();

      if (mounted) {
        _showFeedback(
          statusType: statusType,
          name: empName,
          msg: msg,
          time: logTime,
        );
        setState(() {
          _recentAttendances.insert(0, {
            'name': empName,
            'message': msg,
            'time': logTime,
            'statusType': statusType,
            'isCheckIn': isCheckIn,
          });
          if (_recentAttendances.length > 20) _recentAttendances.removeLast();
        });
      }
    } catch (e) {
      debugPrint("Attendance log API request failed: $e");
    }
  }

  void _showFeedback({
    required FeedbackType statusType,
    required String name,
    required String msg,
    required DateTime time,
  }) {
    _setCameraActive(false);
    setState(() {
      _attendanceFeedback = {
        'statusType': statusType,
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
    _countdownTicker?.cancel();

    setState(() {
      _secondsRemaining = 10;
    });

    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsRemaining > 1) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        timer.cancel();
      }
    });

    _cameraTimeoutTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && _isCameraActive) {
        _setCameraActive(false);
      }
    });
  }

  void _onTapScanCircle() async {
    if (_attendanceFeedback != null) {
      _feedbackTimer?.cancel();
      setState(() {
        _attendanceFeedback = null;
      });
    }
    if (_isCameraActive) {
      _startCameraTimeout();
    } else {
      await _setCameraActive(true);
      _startCameraTimeout();
    }
  }

  Widget _buildHomeBody(ThemeData theme) {
    final String timeString = DateFormat('hh:mm:ss a').format(_currentTime);
    final String dateString = DateFormat('EEEE, dd MMM yyyy').format(_currentTime);
    const Color activeThemeColor = AppColors.accent;

    final bool showCameraView = _isCameraActive &&
        _isCameraInitialized &&
        _cameraController != null &&
        _cameraController!.value.isInitialized;

    return SafeArea(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(left: 20.0, right: 20.0, top: 16.0, bottom: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top App Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Image.asset(
                      'assets/images/logo.png',
                      width: 40,
                      height: 40,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'THE AALAM',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Workforce Attendance',
                          style: GoogleFonts.outfit(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Live Clock / Live Badge & Logout
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: _isCameraActive ? AppColors.success : AppColors.textMuted,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _isCameraActive ? 'Scanning' : 'Standby',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _isCameraActive ? AppColors.success : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_authToken.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Material(
                        color: Colors.transparent,
                        child: Tooltip(
                          message: _adminName != null ? 'Logged in as $_adminName - Tap to Logout' : 'Admin Mode - Tap to Logout',
                          child: InkWell(
                            onTap: _handleLogout,
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: AppColors.error.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.logout_rounded,
                                    size: 14,
                                    color: AppColors.error,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Logout',
                                    style: GoogleFonts.outfit(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.error,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Dynamic Attendance System Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.fingerprint_rounded,
                      color: AppColors.accent,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Attendance Active',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Auto Check-In & Out',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        timeString,
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppColors.accent,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateString,
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Center Circular Viewfinder (Tap Hand to Scan)
            Center(
              child: GestureDetector(
                onTap: _onTapScanCircle,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer Glow
                    Container(
                      height: 270,
                      width: 270,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: activeThemeColor.withValues(
                              alpha: _isCameraActive ? 0.25 : 0.06,
                            ),
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
                        color: showCameraView ? const Color(0xFF090D16) : AppColors.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _isCameraActive ? activeThemeColor : AppColors.border,
                          width: 2.5,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_attendanceFeedback != null)
                            _buildAnimatedFeedback()
                          else if (showCameraView)
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
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  AnimatedBuilder(
                                    animation: _fingerTapController,
                                    builder: (context, child) {
                                      return Transform.scale(
                                        scale: _fingerTapScaleAnimation.value,
                                        child: Container(
                                          padding: const EdgeInsets.all(18),
                                          decoration: BoxDecoration(
                                            color: activeThemeColor.withValues(alpha: 0.12),
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: activeThemeColor.withValues(
                                                  alpha: 0.25 * _fingerTapController.value,
                                                ),
                                                blurRadius: 18 * _fingerTapController.value + 4,
                                                spreadRadius: 3 * _fingerTapController.value,
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            Icons.touch_app_rounded,
                                            size: 56,
                                            color: activeThemeColor,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    'Tap Circle to Scan',
                                    style: GoogleFonts.outfit(
                                      color: AppColors.textPrimary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '30-min gap for Check-Out',
                                    style: GoogleFonts.outfit(
                                      color: AppColors.textMuted,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Futuristic AI Reticle Overlay (Only when camera is actively streaming)
                          if (showCameraView)
                            AnimatedBuilder(
                              animation: _scannerAnimController,
                              builder: (context, child) {
                                return CustomPaint(
                                  painter: _AiScannerReticlePainter(
                                    color: activeThemeColor,
                                    progress: _scannerAnimController.value,
                                  ),
                                );
                              },
                            ),

                          // 10s Timer Pill Badge inside viewfinder top
                          if (_isCameraActive && _attendanceFeedback == null)
                            Positioned(
                              top: 14,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white24, width: 0.8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.timer_outlined,
                                        size: 12,
                                        color: activeThemeColor,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${_secondsRemaining}s',
                                        style: GoogleFonts.outfit(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
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
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Status Text & Instructions
            if (_isCameraActive)
              Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: activeThemeColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Scanning Face Biometrics...',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: activeThemeColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Position face in front of the camera',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              )
            else
              Center(
                child: Column(
                  children: [
                    Text(
                      'Ready to Scan',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tap the circle above to start 10s face scan',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),

            // Recent Attendance Activity Stream Section
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
                        'Today\'s Activity',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Auto-resets daily',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_recentAttendances.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24.0),
                      child: Center(
                        child: Text(
                          "No recent attendance punches recorded yet today.",
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
                        final FeedbackType statusType = log['statusType'] ?? FeedbackType.checkInSuccess;
                        final String msg = log['message']?.toString() ?? '';

                        Color itemColor;
                        IconData itemIcon;

                        switch (statusType) {
                          case FeedbackType.checkInSuccess:
                            itemColor = AppColors.success; // Green for Check In
                            itemIcon = Icons.login_rounded;
                            break;
                          case FeedbackType.checkOutSuccess:
                            itemColor = AppColors.error; // Red for Check Out
                            itemIcon = Icons.logout_rounded;
                            break;
                          case FeedbackType.info:
                            itemColor = const Color(0xFF0EA5E9); // Cyan / Info
                            itemIcon = Icons.info_outline_rounded;
                            break;
                          case FeedbackType.warning:
                            itemColor = AppColors.warning;
                            itemIcon = Icons.warning_amber_rounded;
                            break;
                        }

                        return Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: itemColor.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                itemIcon,
                                size: 16,
                                color: itemColor,
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
                              style: TextStyle(
                                color: itemColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
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
      body = LogsScreen(
        token: _authToken,
        onLogout: _handleLogout,
      );
    } else if (_currentIndex == 2) {
      body = StaffScreen(
        token: _authToken,
        onLogout: _handleLogout,
      );
    } else if (_currentIndex == 3) {
      body = SettingsScreen(
        token: _authToken,
        onLogout: _handleLogout,
      );
    } else {
      body = _buildHomeBody(theme);
    }

    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: false,
        body: body,
        bottomNavigationBar: CustomBottomNavBar(
          selectedIndex: _currentIndex,
          onItemSelected: (index) async {
            if (index != 0) {
              if (_authToken.isEmpty) {
                final token = await AuthService().getValidToken();
                if (mounted && token.isNotEmpty) {
                  setState(() {
                    _authToken = token;
                  });
                  _loadAdminInfo();
                }
              }
              if (_authToken.isEmpty) {
                if (!context.mounted) return;
                // Not authenticated as Admin -> Prompt Login Screen!
                final dynamic result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LoginScreen(isModal: true),
                  ),
                );
                if (!mounted) return;
                if (result != null && result is String && result.isNotEmpty) {
                  setState(() {
                    _authToken = result;
                  });
                  _loadAdminInfo();
                  _syncAuthorizedEmployeesFromApi();
                  _fetchTodayAttendanceLogs();
                } else {
                  // User cancelled / went back without logging in
                  return;
                }
              }
            }

            if (_currentIndex == 0 && index != 0) {
              _cameraController?.stopImageStream();
              _cameraController?.dispose();
              _cameraController = null;
              _isCameraInitialized = false;
              _isCameraActive = false;
              _cameraTimeoutTimer?.cancel();
              _countdownTicker?.cancel();
            } else if (_currentIndex != 0 && index == 0) {
              _syncAuthorizedEmployeesFromApi();
              _fetchTodayAttendanceLogs();
            }
            setState(() {
              _currentIndex = index;
            });
          },
        ),
      ),
    );
  }

  Widget _buildAnimatedFeedback() {
    final FeedbackType statusType = _attendanceFeedback!['statusType'] ?? FeedbackType.checkInSuccess;
    final String name = _attendanceFeedback!['name'];
    final String msg = _attendanceFeedback!['msg'];
    final DateTime time = _attendanceFeedback!['time'];

    Color color;
    IconData iconData;

    switch (statusType) {
      case FeedbackType.checkInSuccess:
        color = AppColors.success; // Green Check In
        iconData = Icons.check_circle_rounded;
        break;
      case FeedbackType.checkOutSuccess:
        color = AppColors.error; // Red Check Out
        iconData = Icons.check_circle_rounded;
        break;
      case FeedbackType.info:
        color = const Color(0xFF0EA5E9);
        iconData = Icons.verified_user_rounded;
        break;
      case FeedbackType.warning:
        color = AppColors.warning;
        iconData = Icons.info_outline_rounded;
        break;
    }

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
                iconData,
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
              "$msg\n${DateFormat('hh:mm a').format(time)}",
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}

enum FeedbackType {
  checkInSuccess,
  checkOutSuccess,
  info,
  warning,
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
    canvas.drawPath(
      Path()
        ..moveTo(center.dx - rInset, center.dy - rInset + bLen)
        ..lineTo(center.dx - rInset, center.dy - rInset)
        ..lineTo(center.dx - rInset + bLen, center.dy - rInset),
      bracketPaint,
    );
    // Top-Right
    canvas.drawPath(
      Path()
        ..moveTo(center.dx + rInset, center.dy - rInset + bLen)
        ..lineTo(center.dx + rInset, center.dy - rInset)
        ..lineTo(center.dx + rInset - bLen, center.dy - rInset),
      bracketPaint,
    );
    // Bottom-Left
    canvas.drawPath(
      Path()
        ..moveTo(center.dx - rInset, center.dy + rInset - bLen)
        ..lineTo(center.dx - rInset, center.dy + rInset)
        ..lineTo(center.dx - rInset + bLen, center.dy + rInset),
      bracketPaint,
    );
    // Bottom-Right
    canvas.drawPath(
      Path()
        ..moveTo(center.dx + rInset, center.dy + rInset - bLen)
        ..lineTo(center.dx + rInset, center.dy + rInset)
        ..lineTo(center.dx + rInset - bLen, center.dy + rInset),
      bracketPaint,
    );

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