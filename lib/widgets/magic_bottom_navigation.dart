import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'animated_chatbot_button.dart';

class MagicBottomNavigation extends StatelessWidget {
  final List<Map> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const MagicBottomNavigation({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final chatIndex = items.indexWhere((item) => item['component'] == 'chat');
    final barTop = chatIndex < 0 ? 0.0 : 28.0;
    final height =
        80.0 + math.max(0.0, MediaQuery.textScalerOf(context).scale(11) - 11);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final fraction = chatIndex < 0 ? null : (chatIndex + .5) / items.length;
    final chatFraction =
        Directionality.of(context) == TextDirection.rtl && fraction != null
        ? 1 - fraction
        : fraction;
    final data = NavigationBarThemeData(
      height: height,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: colors.primary,
      indicatorShape: const StadiumBorder(),
      labelPadding: const EdgeInsets.only(top: 16),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected)
              ? colors.onPrimary
              : colors.muted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? colors.text
              : colors.muted,
        ),
      ),
    );
    return SizedBox(
      height: barTop + height + bottom,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  key: const ValueKey('navigation-cradle'),
                  painter: NavigationCradlePainter(
                    colors: colors,
                    barTop: barTop,
                    chatFraction: chatFraction,
                  ),
                ),
              ),
            ),
            Positioned(
              top: barTop,
              left: 0,
              right: 0,
              child: NavigationBarTheme(
                data: data,
                child: NavigationBar(
                  labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                  selectedIndex: selectedIndex,
                  onDestinationSelected: onSelected,
                  destinations: [
                    for (final item in items)
                      if (item['component'] == 'chat')
                        NavigationBarTheme(
                          data: data.copyWith(
                            indicatorColor: Colors.transparent,
                            labelTextStyle: WidgetStatePropertyAll(
                              TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: colors.text,
                              ),
                            ),
                          ),
                          child: const NavigationDestination(
                            icon: SizedBox(width: 24, height: 24),
                            label: 'Chatbot',
                            tooltip: 'Open Chatbot',
                          ),
                        )
                      else
                        NavigationDestination(
                          icon: Icon(switch (item['component']) {
                            'dashboard' => Icons.home_outlined,
                            'social' => Icons.calendar_today_outlined,
                            'documents' => Icons.folder_outlined,
                            'workspace' => Icons.grid_view_outlined,
                            'account' => Icons.person_outline_rounded,
                            'plans' => Icons.workspace_premium_outlined,
                            _ => Icons.auto_awesome_outlined,
                          }),
                          selectedIcon: Icon(switch (item['component']) {
                            'dashboard' => Icons.home_rounded,
                            'social' => Icons.calendar_today_rounded,
                            'workspace' => Icons.grid_view_rounded,
                            'account' => Icons.person_rounded,
                            _ => Icons.auto_awesome_rounded,
                          }),
                          label: item['label'].toString(),
                        ),
                  ],
                ),
              ),
            ),
            if (chatFraction != null)
              Positioned(
                left: constraints.maxWidth * chatFraction - 36,
                top: 0,
                child: ExcludeSemantics(
                  child: AnimatedChatbotButton(
                    colors: colors,
                    selected: selectedIndex == chatIndex,
                    onPressed: () => onSelected(chatIndex),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class NavigationCradlePainter extends CustomPainter {
  final AppColors colors;
  final double barTop;
  final double? chatFraction;
  const NavigationCradlePainter({
    required this.colors,
    required this.barTop,
    required this.chatFraction,
  });

  Path outlineForSize(Size size) {
    final host = Rect.fromLTRB(0, barTop, size.width, size.height);
    final fraction = chatFraction;
    return const CircularNotchedRectangle().getOuterPath(
      host,
      fraction == null
          ? null
          : Rect.fromCircle(
              center: Offset(size.width * fraction, 36),
              radius: 42,
            ),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final outline = outlineForSize(size);
    canvas.drawPath(outline, Paint()..color = colors.navigation);
    canvas.drawPath(
      outline,
      Paint()
        ..color = colors.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final fraction = chatFraction;
    if (fraction == null) return;
    final center = size.width * fraction;
    for (final side in [-1, 1]) {
      for (var tick = 0; tick < 2; tick++) {
        final start = Offset(
          center + side * (48 + tick * 2),
          barTop + 3 + tick * 9,
        );
        final end = Offset(
          start.dx + side * 5,
          start.dy + (tick == 0 ? -2 : 2),
        );
        final paint = Paint()
          ..color = colors.glowHighlight.withValues(alpha: .85)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          start,
          end,
          Paint()
            ..color = colors.glowEnd.withValues(alpha: .5)
            ..strokeWidth = 3
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        canvas.drawLine(start, end, paint);
      }
    }
  }

  @override
  bool shouldRepaint(NavigationCradlePainter oldDelegate) =>
      oldDelegate.colors != colors ||
      oldDelegate.barTop != barTop ||
      oldDelegate.chatFraction != chatFraction;
}
