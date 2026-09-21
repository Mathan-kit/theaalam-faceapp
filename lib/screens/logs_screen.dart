import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import '../config/api_config.dart';
import '../theme/app_colors.dart';
import '../services/auth_service.dart';

class LogsScreen extends StatefulWidget {
  final String? token;
  final VoidCallback? onLogout;

  const LogsScreen({
    super.key,
    this.token,
    this.onLogout,
  });

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  bool _isLoading = true;
  List<dynamic> _allLogs = [];
  List<dynamic> _filteredLogs = [];
  Map<String, dynamic>? _summary;
  String _currentFilter = 'Total';
  String? _error;
  DateTime _selectedDate = DateTime.now();

  // In-memory cache by date string for lightning fast switching
  static final Map<String, Map<String, dynamic>> _cache = {};

  @override
  void initState() {
    super.initState();
    _loadFromCacheOrFetch();
  }

  @override
  void didUpdateWidget(covariant LogsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.token != widget.token && (widget.token?.isNotEmpty ?? false)) {
      _fetchLogs(silent: false);
    }
  }

  void _loadFromCacheOrFetch() {
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    if (_cache.containsKey(dateKey)) {
      final cached = _cache[dateKey]!;
      setState(() {
        _allLogs = cached['logs'] ?? [];
        _summary = cached['summary'];
        _filterLogsByDate();
        _isLoading = false;
      });
      // Fetch in background to keep fresh without blocking UI
      _fetchLogs(silent: true);
    } else {
      _fetchLogs(silent: false);
    }
  }

  Future<void> _fetchLogs({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    String authToken = widget.token ?? '';
    if (authToken.isEmpty) {
      authToken = await AuthService().getValidToken();
    }

    if (authToken.isEmpty) {
      if (mounted) {
        setState(() {
          _error = 'No authentication token found.';
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}attendance_logs?date=$dateStr'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final resData = jsonDecode(response.body);
        List<dynamic> logs = [];
        if (resData['data'] is Map) {
          final present = resData['data']['present'] ?? [];
          final absent = resData['data']['absent'] ?? [];
          logs = [...present, ...absent];
        } else {
          logs = resData['data'] ?? [];
        }

        final summary = resData['summary'];

        // Save to cache for instant recall
        _cache[dateStr] = {
          'logs': logs,
          'summary': summary,
        };

        if (mounted) {
          setState(() {
            _allLogs = logs;
            _summary = summary;
            _filterLogsByDate();
            _isLoading = false;
            _error = null;
          });
        }
      } else {
        if (!silent && mounted) {
          String errorMessage = 'Failed to load logs';
          try {
            final resData = jsonDecode(response.body);
            if (resData['message'] != null) errorMessage = resData['message'];
          } catch (_) {}
          setState(() {
            _error = errorMessage;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching logs: $e');
      if (!silent && mounted) {
        setState(() {
          _error = 'Connection timeout. Tap Refresh to retry.';
          _isLoading = false;
        });
      }
    }
  }

  void _filterLogsByDate() {
    if (_currentFilter == 'Total') {
      _filteredLogs = _allLogs;
    } else if (_currentFilter == 'Present') {
      _filteredLogs = _allLogs.where((log) => log['p_flg'] == 1).toList();
    } else if (_currentFilter == 'Absent') {
      _filteredLogs = _allLogs.where((log) => log['p_flg'] != 1).toList();
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.accent,
              onPrimary: Colors.white,
              surface: AppColors.surface,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _loadFromCacheOrFetch();
    }
  }

  void _navigateDate(int days) {
    final newDate = _selectedDate.add(Duration(days: days));
    if (newDate.isAfter(DateTime.now().add(const Duration(days: 1)))) return;
    setState(() {
      _selectedDate = newDate;
    });
    _loadFromCacheOrFetch();
  }

  String _formatTime(dynamic timeVal) {
    if (timeVal == null || timeVal.toString().trim().isEmpty || timeVal.toString() == 'null') {
      return '--:--';
    }
    String str = timeVal.toString().trim();
    try {
      DateTime dt = DateTime.parse(str);
      return DateFormat('hh:mm a').format(dt);
    } catch (_) {
      try {
        final parsed = DateFormat('HH:mm:ss').parse(str);
        return DateFormat('hh:mm a').format(parsed);
      } catch (_) {
        try {
          final parsed = DateFormat('HH:mm').parse(str);
          return DateFormat('hh:mm a').format(parsed);
        } catch (_) {
          if (str.toUpperCase().contains('AM') || str.toUpperCase().contains('PM')) {
            return str;
          }
          final parts = str.split(' ');
          if (parts.length > 1) {
            try {
              DateTime dt = DateTime.parse(str);
              return DateFormat('hh:mm a').format(dt);
            } catch (_) {
              return parts.last;
            }
          }
          return str;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          // Header Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Image.asset(
                      'assets/images/logo.png',
                      width: 38,
                      height: 38,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Attendance Analytics',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Daily Activity & Logs',
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () => _fetchLogs(silent: false),
                      icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
                      tooltip: 'Refresh',
                    ),
                    if (widget.onLogout != null)
                      IconButton(
                        onPressed: widget.onLogout,
                        icon: const Icon(Icons.logout_rounded, color: AppColors.error),
                        tooltip: 'Logout',
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Date Navigator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, size: 22, color: AppColors.textSecondary),
                    onPressed: () => _navigateDate(-1),
                    tooltip: 'Previous Day',
                  ),
                  InkWell(
                    onTap: () => _selectDate(context),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 16, color: AppColors.accent),
                          const SizedBox(width: 8),
                          Text(
                            DateFormat('EEEE, MMM dd, yyyy').format(_selectedDate),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded, size: 22, color: AppColors.textSecondary),
                    onPressed: () => _navigateDate(1),
                    tooltip: 'Next Day',
                  ),
                ],
              ),
            ),
          ),

          // Gradient KPI Metric Summary Cards (Total, Present Green, Absent Red)
          if (_summary != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
              child: Row(
                children: [
                  _buildGradientKpiCard(
                    title: 'Total',
                    count: _summary!['total_active_employees']?.toString() ?? '0',
                    gradientColors: [const Color(0xFF3B82F6), const Color(0xFF1D4ED8)],
                    icon: Icons.people_alt_rounded,
                  ),
                  const SizedBox(width: 10),
                  _buildGradientKpiCard(
                    title: 'Present',
                    count: _summary!['present_count']?.toString() ?? '0',
                    gradientColors: [const Color(0xFF10B981), const Color(0xFF059669)],
                    icon: Icons.check_circle_rounded,
                  ),
                  const SizedBox(width: 10),
                  _buildGradientKpiCard(
                    title: 'Absent',
                    count: _summary!['absent_count']?.toString() ?? '0',
                    gradientColors: [const Color(0xFFEF4444), const Color(0xFFDC2626)],
                    icon: Icons.cancel_rounded,
                  ),
                ],
              ),
            ),

          // Log List Content
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildGradientKpiCard({
    required String title,
    required String count,
    required List<Color> gradientColors,
    required IconData icon,
  }) {
    final isSelected = _currentFilter == title;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _currentFilter = title;
            _filterLogsByDate();
          });
        },
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    colors: gradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isSelected ? null : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? Colors.transparent : gradientColors.first.withValues(alpha: 0.35),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: gradientColors.first.withValues(alpha: isSelected ? 0.3 : 0.05),
                blurRadius: isSelected ? 12 : 4,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 15,
                    color: isSelected ? Colors.white : gradientColors.first,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    count,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: isSelected ? Colors.white : gradientColors.first,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  color: isSelected ? Colors.white.withValues(alpha: 0.9) : AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.accent,
          strokeWidth: 2.5,
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: AppColors.errorLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.cloud_off_rounded, color: AppColors.error, size: 36),
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _fetchLogs(silent: false),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Refresh'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_filteredLogs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppColors.surfaceSubtle,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.history_toggle_off_rounded, size: 40, color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),
            const Text(
              'No attendance logs recorded',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('MMMM dd, yyyy').format(_selectedDate),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(left: 20, right: 20, top: 8, bottom: 20),
      itemCount: _filteredLogs.length,
      itemBuilder: (context, index) {
        final log = _filteredLogs[index];
        final String name = (log['employee'] != null ? log['employee']['employee_name']?.toString() : null)
            ?? log['employee_name']?.toString()
            ?? log['emp_code']?.toString()
            ?? log['name']?.toString()
            ?? 'Unknown Employee';

        final inTimeStr = _formatTime(log['in_time'] ?? log['in_punch'] ?? log['check_in']);
        final outTimeStr = _formatTime(log['out_time'] ?? log['out_punch'] ?? log['check_out']);

        final rawStatus = log['status']?.toString() ?? (log['p_flg'] == 1 ? 'Present' : 'Absent');
        final bool isAbsent = rawStatus.toLowerCase() == 'absent' || log['p_flg'] == 0;
        final status = isAbsent ? 'Absent' : 'Present';

        // Green-White gradient for Present, Red-White gradient for Absent
        final List<Color> cardGradient = isAbsent
            ? [const Color(0xFFFFF1F2), const Color(0xFFFFFFFF)] // Lite Red to White
            : [const Color(0xFFECFDF5), const Color(0xFFFFFFFF)]; // Lite Green to White

        final Color themeColor = isAbsent ? const Color(0xFFEF4444) : const Color(0xFF10B981);
        final Color themeColorDark = isAbsent ? const Color(0xFFDC2626) : const Color(0xFF059669);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: cardGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: themeColor.withValues(alpha: 0.3),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: themeColor.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // Avatar Circle Icon (Green for Present, Red for Absent)
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: themeColor.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: themeColor.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    isAbsent ? Icons.person_off_rounded : Icons.person_rounded,
                    color: themeColorDark,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),

                // Name and In/Out Times
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          // In Time Badge (Green)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD1FAE5), // Light Green Pill
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFF10B981).withValues(alpha: 0.3),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.login_rounded,
                                  size: 13,
                                  color: Color(0xFF047857),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  inTimeStr,
                                  style: GoogleFonts.outfit(
                                    color: const Color(0xFF047857),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Out Time Badge (Red)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEE2E2), // Light Red Pill
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.logout_rounded,
                                  size: 13,
                                  color: Color(0xFFB91C1C),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  outTimeStr,
                                  style: GoogleFonts.outfit(
                                    color: const Color(0xFFB91C1C),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Status Badge (Green Present / Red Absent)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isAbsent ? const Color(0xFFFEE2E2) : const Color(0xFFD1FAE5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: themeColor.withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    status,
                    style: GoogleFonts.outfit(
                      color: themeColorDark,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
