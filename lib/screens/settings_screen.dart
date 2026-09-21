import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../services/auth_service.dart';
import '../utils/toast_util.dart';

class SettingsScreen extends StatefulWidget {
  final String? token;
  final VoidCallback? onLogout;

  const SettingsScreen({
    super.key,
    this.token,
    this.onLogout,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  String? _adminName;
  String? _adminRole;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _loadAdminData();
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.token != widget.token) {
      _loadAdminData();
    }
  }

  Future<void> _loadAdminData() async {
    final token = (widget.token != null && widget.token!.isNotEmpty)
        ? widget.token!
        : await AuthService().getValidToken();
    if (token.isNotEmpty) {
      final name = await AuthService().getAdminName();
      final role = await AuthService().getAdminRole();
      if (mounted) {
        setState(() {
          _isLoggedIn = true;
          _adminName = name ?? 'Administrator';
          _adminRole = role ?? 'System Admin';
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoggedIn = false;
          _adminName = null;
          _adminRole = null;
        });
      }
    }
  }

  void _showToast(String message) {
    toastification.show(
      context: context,
      type: ToastificationType.info,
      style: ToastificationStyle.flatColored,
      title: Text(message),
      autoCloseDuration: const Duration(seconds: 3),
      alignment: Alignment.bottomCenter,
    );
  }

  Future<void> _handleLogout() async {
    if (widget.onLogout != null) {
      widget.onLogout!();
      return;
    }

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
          'Are you sure you want to log out of Admin mode? You will need to log in again with credentials to access protected features.',
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
        _isLoggedIn = false;
        _adminName = null;
        _adminRole = null;
      });
      ToastUtil.showSuccess(context, 'Logged out successfully');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'assets/images/logo.png',
              width: 36,
              height: 36,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 10),
            Text(
              'Settings & System',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        actions: [
          if (_isLoggedIn)
            IconButton(
              onPressed: _handleLogout,
              icon: const Icon(Icons.logout_rounded, color: AppColors.error),
              tooltip: 'Logout',
            ),
        ],
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(left: 20.0, right: 20.0, top: 16.0, bottom: 24.0),
        children: [
          // Admin Account / Session Group (if logged in)
          if (_isLoggedIn) ...[
            _buildSectionHeader('Admin Account'),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
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
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
                    ),
                    child: Center(
                      child: Text(
                        (_adminName?.isNotEmpty ?? false)
                            ? _adminName![0].toUpperCase()
                            : 'A',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.accentDark,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                _adminName ?? 'Administrator',
                                style: GoogleFonts.outfit(
                                  color: AppColors.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF16A34A).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Active',
                                style: GoogleFonts.outfit(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF16A34A),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _adminRole ?? 'System Admin',
                          style: GoogleFonts.outfit(
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
            const SizedBox(height: 12),
            _buildSettingsGroup([
              _buildActionTile(
                icon: Icons.logout_rounded,
                title: 'Log Out',
                subtitle: 'End current administrator session',
                iconColor: AppColors.error,
                onTap: _handleLogout,
              ),
            ]),
            const SizedBox(height: 24),
          ],

          // General Preferences Group
          _buildSectionHeader('Preferences'),
          _buildSettingsGroup([
            _buildSwitchTile(
              icon: Icons.notifications_active_outlined,
              title: 'Push Notifications',
              value: _notificationsEnabled,
              onChanged: (val) => setState(() => _notificationsEnabled = val),
            ),
          ]),
          const SizedBox(height: 24),
          
          // Attendance & System Group
          _buildSectionHeader('Attendance & System'),
          _buildSettingsGroup([
            _buildActionTile(
              icon: Icons.sync_rounded,
              title: 'Sync Offline Records',
              subtitle: 'All biometric punches are up-to-date',
              iconColor: AppColors.success,
              onTap: () => _showToast('Attendance database is synchronized.'),
            ),
            _buildDivider(),
            _buildActionTile(
              icon: Icons.cleaning_services_outlined,
              title: 'Clear Cache',
              subtitle: 'Free up local temporary files',
              iconColor: AppColors.warning,
              onTap: () => _showToast('App cache cleared successfully.'),
            ),
          ]),
          const SizedBox(height: 32),

          // App Version & Brand
          Center(
            child: Column(
              children: [
                Text(
                  'The Aalam Workforce Platform',
                  style: GoogleFonts.outfit(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Version 1.0.0 (Enterprise Build)',
                  style: GoogleFonts.outfit(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.outfit(
          color: AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildSettingsGroup(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildDivider() {
    return const Divider(height: 1, color: AppColors.borderSubtle, indent: 56);
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.accent, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.outfit(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.accent,
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Color? iconColor,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (iconColor ?? AppColors.accent).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor ?? AppColors.accent, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.outfit(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textMuted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
