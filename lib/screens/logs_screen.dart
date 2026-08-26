import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../utils/toast_util.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../config/api_config.dart';
import '../theme/app_colors.dart';

class LogsScreen extends StatefulWidget {
  final String? token;
  const LogsScreen({super.key, this.token});

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

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  Future<void> _fetchLogs() async {
    if (widget.token == null || widget.token!.isEmpty) {
      setState(() {
        _error = 'No authentication token found.';
        _isLoading = false;
      });
      return;
    }

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}attendance_logs?date=$dateStr'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final resData = jsonDecode(response.body);
        setState(() {
          if (resData['data'] is Map) {
            final present = resData['data']['present'] ?? [];
            final absent = resData['data']['absent'] ?? [];
            _allLogs = [...present, ...absent];
          } else {
            _allLogs = resData['data'] ?? [];
          }
          _summary = resData['summary'];
          _filterLogsByDate();
          _isLoading = false;
        });  
      } else {
        String errorMessage = 'Failed to load logs';
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

        setState(() {
          _error = errorMessage;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching logs: $e');
      String displayError = 'Cannot connect to server. Please check your internet connection.';
      if (mounted) {
        ToastUtil.showError(context, displayError);
      }
      setState(() {
        _error = displayError;
        _isLoading = false;
      });
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
        _isLoading = true;
      });
      _fetchLogs();
    }
  }

  void _navigateDate(int days) {
    final newDate = _selectedDate.add(Duration(days: days));
    if (newDate.isAfter(DateTime.now().add(const Duration(days: 1)))) return;
    setState(() {
      _selectedDate = newDate;
      _isLoading = true;
    });
    _fetchLogs();
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
    final theme = Theme.of(context);

    return SafeArea(
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
                          'Attendance Analytics',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Daily Activity & Logs',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _isLoading = true;
                      _error = null;
                    });
                    _fetchLogs();
                  },
                  icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),
          
          // Date Navigator Widget
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
          
          // KPI Metric Summary Cards
          if (_summary != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
              child: Row(
                children: [
                  _buildKpiCard('Total', _summary!['total_active_employees']?.toString() ?? '0', AppColors.accent),
                  const SizedBox(width: 10),
                  _buildKpiCard('Present', _summary!['present_count']?.toString() ?? '0', AppColors.success),
                  const SizedBox(width: 10),
                  _buildKpiCard('Absent', _summary!['absent_count']?.toString() ?? '0', AppColors.error),
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

  Widget _buildKpiCard(String title, String count, Color color) {
    final isSelected = _currentFilter == title;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _currentFilter = title;
            _filterLogsByDate();
          });
        },
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.08) : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? color : AppColors.border,
              width: isSelected ? 1.8 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              Text(
                count,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: isSelected ? color : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  color: isSelected ? color : AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
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
                decoration: BoxDecoration(
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
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _error = null;
                  });
                  _fetchLogs();
                },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try Again'),
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
              decoration: BoxDecoration(
                color: AppColors.surfaceSubtle,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.history_toggle_off_rounded, size: 40, color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),
            Text(
              'No attendance logs recorded',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('MMMM dd, yyyy').format(_selectedDate),
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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

        final rawStatus = log['status']?.toString() ?? (log['p_flg'] == 1 ? 'Active' : 'Absent');
        final bool isAbsent = rawStatus.toLowerCase() == 'absent' || log['p_flg'] == 0;
        final status = isAbsent ? 'Absent' : (rawStatus.toLowerCase() == 'present' ? 'Active' : rawStatus);

        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // History Circle Icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isAbsent ? AppColors.errorLight : AppColors.accentLight,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.history_rounded,
                    color: isAbsent ? AppColors.error : AppColors.accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                // Name and In/Out Times
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          // In Time
                          const Icon(
                            Icons.login_rounded,
                            size: 14,
                            color: AppColors.success,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            inTimeStr,
                            style: const TextStyle(
                              color: AppColors.success,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 14),
                          // Out Time
                          const Icon(
                            Icons.logout_rounded,
                            size: 14,
                            color: AppColors.error,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            outTimeStr,
                            style: const TextStyle(
                              color: AppColors.error,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isAbsent ? AppColors.errorLight : AppColors.successLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: isAbsent ? AppColors.error : AppColors.success,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
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
