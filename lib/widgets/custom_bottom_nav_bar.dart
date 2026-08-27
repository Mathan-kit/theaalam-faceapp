import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CustomBottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  const CustomBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  static const List<Map<String, dynamic>> _items = [
    {
      'label': 'Home',
      'icon': Icons.home_rounded,
      'inactiveIcon': Icons.home_outlined,
    },
    {
      'label': 'Logs',
      'icon': Icons.calendar_today_rounded,
      'inactiveIcon': Icons.calendar_today_outlined,
    },
    {
      'label': 'Staff',
      'icon': Icons.people_rounded,
      'inactiveIcon': Icons.people_outline_rounded,
    },
    {
      'label': 'Settings',
      'icon': Icons.settings_rounded,
      'inactiveIcon': Icons.settings_outlined,
    },
  ];

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 16.0,
        right: 16.0,
        bottom: bottomPadding > 0 ? bottomPadding + 10.0 : 20.0,
      ),
      child: SizedBox(
        height: 66,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            // 1. Background Rounded Card Container
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 56,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFEFE6D8),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFD97706).withValues(alpha: 0.09),
                      blurRadius: 18,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18.8),
                  child: Image.asset(
                    'assets/images/bottomenubavckgroud.png',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),

            // 2. Interactive Navigation Items Row
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 66,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(_items.length, (index) {
                  final isSelected = selectedIndex == index;
                  final item = _items[index];

                  return Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => onItemSelected(index),
                            child: SizedBox(
                              height: 66,
                              child: isSelected
                                  ? _buildActiveItem(item)
                                  : _buildInactiveItem(item),
                            ),
                          ),
                        ),
                        // Vertical divider between items (except around the active tab)
                        if (index < _items.length - 1 &&
                            !isSelected &&
                            selectedIndex != index + 1)
                          Container(
                            height: 24,
                            width: 1,
                            margin: const EdgeInsets.only(bottom: 16),
                            color: const Color(0xFFE5D7C5),
                          )
                        else if (index < _items.length - 1)
                          const SizedBox(width: 1),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveItem(Map<String, dynamic> item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3.0),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: CustomPaint(
          painter: _HouseTabPainter(),
          child: SizedBox(
            width: 60,
            height: 62,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(
                  item['icon'] as IconData,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(height: 2),
                Text(
                  item['label'] as String,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 5),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInactiveItem(Map<String, dynamic> item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Icon(
            item['inactiveIcon'] as IconData,
            color: const Color(0xFF374151),
            size: 20,
          ),
          const SizedBox(height: 3),
          Text(
            item['label'] as String,
            style: GoogleFonts.outfit(
              color: const Color(0xFF374151),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _HouseTabPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Peak roof geometry
    const peakOffset = 9.0;
    const cornerR = 8.0;

    final path = Path();
    // Start at top-left corner
    path.moveTo(cornerR, peakOffset + 4);
    // Roof left slope to apex
    path.lineTo(w / 2 - 2, 1);
    // Rounded apex peak
    path.quadraticBezierTo(w / 2, 0, w / 2 + 2, 1);
    // Roof right slope
    path.lineTo(w - cornerR, peakOffset + 4);
    // Top-right rounded shoulder
    path.quadraticBezierTo(w, peakOffset + 6, w, peakOffset + 12);
    // Right vertical side
    path.lineTo(w, h - cornerR);
    // Bottom-right rounded corner
    path.quadraticBezierTo(w, h, w - cornerR, h);
    // Bottom horizontal line
    path.lineTo(cornerR, h);
    // Bottom-left rounded corner
    path.quadraticBezierTo(0, h, 0, h - cornerR);
    // Left vertical side
    path.lineTo(0, peakOffset + 12);
    // Top-left rounded shoulder
    path.quadraticBezierTo(0, peakOffset + 6, cornerR, peakOffset + 4);
    path.close();

    // 1. Soft Warm Shadow
    final shadowPaint = Paint()
      ..color = const Color(0xFFD97706).withValues(alpha: 0.38)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawPath(path.shift(const Offset(0, 2)), shadowPaint);

    // 2. Vibrant Amber / Orange Gradient Fill
    final fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFFBBF24), // Gold
          Color(0xFFF59E0B), // Warm amber
          Color(0xFFEA580C), // Deep orange
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(path, fillPaint);

    // 3. Inner White Accent Stroke
    final borderPath = Path();
    const inset = 1.8;
    borderPath.moveTo(cornerR + inset, peakOffset + 4 + inset);
    borderPath.lineTo(w / 2 - 2, 1 + inset);
    borderPath.quadraticBezierTo(w / 2, inset + 0.3, w / 2 + 2, 1 + inset);
    borderPath.lineTo(w - cornerR - inset, peakOffset + 4 + inset);
    borderPath.quadraticBezierTo(w - inset, peakOffset + 6 + inset, w - inset, peakOffset + 12 + inset);
    borderPath.lineTo(w - inset, h - cornerR - inset);
    borderPath.quadraticBezierTo(w - inset, h - inset, w - cornerR - inset, h - inset);
    borderPath.lineTo(cornerR + inset, h - inset);
    borderPath.quadraticBezierTo(inset, h - inset, inset, h - cornerR - inset);
    borderPath.lineTo(inset, peakOffset + 12 + inset);
    borderPath.quadraticBezierTo(inset, peakOffset + 6 + inset, cornerR + inset, peakOffset + 4 + inset);
    borderPath.close();

    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawPath(borderPath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
