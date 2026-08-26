import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../utils/toast_util.dart';
import 'dart:convert';
import '../config/api_config.dart';
import '../theme/app_colors.dart';
import 'register_face_screen.dart';

class StaffScreen extends StatefulWidget {
  final String token;
  const StaffScreen({super.key, required this.token});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  bool _isLoading = true;
  List<dynamic> _staffList = [];
  List<dynamic> _filteredStaffList = [];
  String? _error;
  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'All';

  @override
  void initState() {
    super.initState();
    _fetchStaff();
    _searchController.addListener(_filterStaff);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterStaff() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      _filteredStaffList = _staffList.where((staff) {
        final name = (staff['employee_name'] ?? '').toString().toLowerCase();
        final code = (staff['emp_code'] ?? '').toString().toLowerCase();
        final category = (staff['employee_category'] ?? '').toString().toLowerCase();
        final bool matchesQuery = query.isEmpty || name.contains(query) || code.contains(query) || category.contains(query);

        final bool isActive = staff['status'] == 'Active';
        final hasFace = staff['face_vector'] != null && staff['face_vector'].toString().length > 10;

        if (_selectedFilter == 'Active') {
          return matchesQuery && isActive;
        } else if (_selectedFilter == 'Inactive') {
          return matchesQuery && !isActive;
        } else if (_selectedFilter == 'Registered') {
          return matchesQuery && hasFace;
        } else if (_selectedFilter == 'Pending') {
          return matchesQuery && !hasFace;
        }
        return matchesQuery;
      }).toList();
    });
  }

  Future<void> _fetchStaff() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}employees'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final resData = jsonDecode(response.body);
        setState(() {
          _staffList = resData['data'] ?? [];
          _filteredStaffList = List.from(_staffList);
          _isLoading = false;
        });
      } else {
        String errorMessage = 'Failed to load staff';
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
      debugPrint('Error fetching staff: $e');
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
                          'Staff Directory',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          '${_staffList.length} Total Employees',
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
                    _fetchStaff();
                  },
                  icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),
          
          // Search Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name, code or category...',
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textSecondary),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                filled: true,
                fillColor: AppColors.surface,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Row(
              children: ['All', 'Active', 'Inactive', 'Registered', 'Pending'].map((filter) {
                final isSelected = _selectedFilter == filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: FilterChip(
                    label: Text(filter),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedFilter = filter;
                      });
                      _filterStaff();
                    },
                    backgroundColor: AppColors.surface,
                    selectedColor: AppColors.accentLight,
                    side: BorderSide(
                      color: isSelected ? AppColors.accent : AppColors.border,
                      width: 1,
                    ),
                    labelStyle: TextStyle(
                      color: isSelected ? AppColors.accent : AppColors.textSecondary,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 12,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    showCheckmark: false,
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          
          // Staff List Content
          Expanded(
            child: _buildContent(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
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
                  _fetchStaff();
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

    if (_filteredStaffList.isEmpty) {
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
              child: const Icon(Icons.people_outline_rounded, color: AppColors.textMuted, size: 36),
            ),
            const SizedBox(height: 12),
            Text(
              'No employees match your search',
              style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w500, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: _filteredStaffList.length,
      itemBuilder: (context, index) {
        final staff = _filteredStaffList[index];
        final bool isActive = staff['status'] == 'Active';
        final bool hasFaceVector = staff['face_vector'] != null && staff['face_vector'].toString().length > 10;
        final String name = staff['employee_name'] ?? 'Unknown';
        final String empCode = staff['emp_code']?.toString() ?? 'N/A';
        final String category = staff['employee_category'] ?? 'General';
        
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Avatar + Info + Active Status
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar Circle
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isActive ? AppColors.accentLight : AppColors.surfaceSubtle,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isActive ? AppColors.accent.withValues(alpha: 0.2) : AppColors.border,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: TextStyle(
                            color: isActive ? AppColors.accent : AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    
                    // Name & Details
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
                          const SizedBox(height: 2),
                          Text(
                            category,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'ID: $empCode',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Status Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isActive ? AppColors.successLight : AppColors.errorLight,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        isActive ? 'Active' : 'Inactive',
                        style: TextStyle(
                          color: isActive ? AppColors.success : AppColors.error,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12.0),
                  child: Divider(color: AppColors.borderSubtle, height: 1),
                ),
                
                // Bottom Row: Biometric Status & Action Button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Face Registration status pill
                    Row(
                      children: [
                        Icon(
                          hasFaceVector ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                          size: 15,
                          color: hasFaceVector ? AppColors.success : AppColors.warning,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          hasFaceVector ? 'Face Enrolled' : 'Face Not Enrolled',
                          style: TextStyle(
                            color: hasFaceVector ? AppColors.success : AppColors.warning,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),

                    // Enroll / Update Face Button
                    InkWell(
                      onTap: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => RegisterFaceScreen(
                              employeeName: name,
                              empCode: empCode,
                            ),
                          ),
                        );
                        if (result == true) {
                          _fetchStaff();
                        }
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.accentLight,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              hasFaceVector ? Icons.sync_rounded : Icons.add_a_photo_outlined,
                              size: 14,
                              color: AppColors.accent,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              hasFaceVector ? 'Update Biometrics' : 'Enroll Face',
                              style: const TextStyle(
                                color: AppColors.accent,
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
              ],
            ),
          ),
        );
      },
    );
  }
}
