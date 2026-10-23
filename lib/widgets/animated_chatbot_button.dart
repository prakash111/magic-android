import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class AnimatedChatbotButton extends StatefulWidget {
  final AppColors colors;
  final bool selected;
  final VoidCallback onPressed;

  const AnimatedChatbotButton({
    super.key,
    required this.colors,
    required this.selected,
    required this.onPressed,
  });

  @override
  State<AnimatedChatbotButton> createState() => _AnimatedChatbotButtonState();
}

class _AnimatedChatbotButtonState extends State<AnimatedChatbotButton>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
    animationBehavior: AnimationBehavior.preserve,
  );
  late final _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
    value: 1,
  );
  late final _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
  );
  late final _animation = Listenable.merge([_clock, _burst, _press]);
  bool _reducedMotion = false;
  bool _tickerEnabled = true;
  bool _active = true;
  bool _animate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _active = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    _tickerEnabled = TickerMode.of(context);
    _syncMotion();
  }

  @override
  void didChangeAccessibilityFeatures() => setState(_syncMotion);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    setState(_syncMotion);
  }

  void _syncMotion() {
    _animate =
        !_reducedMotion &&
        !WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .reduceMotion &&
        _tickerEnabled &&
        _active;
    if (_animate) {
      if (!_clock.isAnimating) _clock.repeat();
    } else {
      _clock.reset();
      _press.reset();
      _burst.value = 1;
    }
  }

  void _tap() {
    if (_animate) _burst.forward(from: 0);
    widget.onPressed();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock.dispose();
    _burst.dispose();
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: SizedBox(
      key: const ValueKey('chatbot-floating-action'),
      width: 72,
      height: 72,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, _) {
          final colors = widget.colors;
          final seconds = _animate
              ? (_clock.lastElapsedDuration?.inMicroseconds ?? 0) /
                    Duration.microsecondsPerSecond
              : 0.0;
          final rotation =
              seconds * 2 * math.pi / (widget.selected ? 2.6 : 4.5);
          return Transform.scale(
            scale: 1 - .1 * Curves.easeOut.transform(_press.value),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: OverflowBox(
                      minWidth: 128,
                      maxWidth: 128,
                      minHeight: 128,
                      maxHeight: 128,
                      child: CustomPaint(
                        size: const Size(128, 128),
                        painter: ChatbotAuraPainter(
                          colors: colors,
                          seconds: seconds,
                          selected: widget.selected,
                          motion: _animate,
                          burst: _burst.value,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(
                        transform: GradientRotation(rotation - math.pi / 2),
                        colors: [
                          colors.glowStart,
                          colors.glowEnd,
                          colors.glowMiddle,
                          colors.glowStart,
                        ],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(3.5),
                      child: Material(
                        color: colors.chatbotSurface,
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: _tap,
                          onTapDown: (_) {
                            if (_animate) _press.forward();
                          },
                          onTapUp: (_) => _press.reverse(),
                          onTapCancel: () => _press.reverse(),
                          canRequestFocus: false,
                          customBorder: const CircleBorder(),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: CustomPaint(
                              painter: ChatbotRobotPainter(
                                colors,
                                seconds: seconds,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class ChatbotAuraPainter extends CustomPainter {
  final AppColors colors;
  final double seconds;
  final bool selected;
  final bool motion;
  final double burst;

  const ChatbotAuraPainter({
    required this.colors,
    required this.seconds,
    required this.selected,
    required this.motion,
    required this.burst,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final bloom = motion
        ? .35 + .35 * (1 - math.cos(seconds * 2 * math.pi / 2.6)) / 2
        : .35;
    final palette = [
      colors.glowStart,
      colors.glowEnd,
      colors.glowMiddle,
      colors.glowStart,
    ];
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(seconds * 2 * math.pi / 6);
    canvas.drawCircle(
      Offset.zero,
      35,
      Paint()
        ..shader = SweepGradient(colors: palette)
            .createShader(const Rect.fromLTWH(-40, -40, 80, 80))
        ..color = colors.chatbotForeground.withValues(
          alpha: selected ? math.min(1, bloom + .15) : bloom,
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.restore();
    if (motion) {
      final wavePeriod = selected ? 1.9 : 2.6;
      for (var index = 0; index < 2; index++) {
        final progress = (seconds / wavePeriod + index * .5) % 1;
        canvas.drawCircle(
          center,
          31 * (1 + .75 * progress),
          Paint()
            ..color = (index == 0 ? colors.glowMiddle : colors.glowEnd)
                .withValues(alpha: .6 * (1 - progress))
            ..style = PaintingStyle.stroke
            ..strokeWidth = selected ? 3 : 2,
        );
      }
    }
    for (var index = 0; index < 3; index++) {
      final angle =
          index * 2 * math.pi / 3 - math.pi / 2 - seconds * 2 * math.pi / 3.4;
      final position = center + Offset(math.cos(angle), math.sin(angle)) * 37;
      final color = index == 1 ? colors.glowMiddle : colors.chatbotForeground;
      canvas.drawCircle(
        position,
        4,
        Paint()
          ..color = (index == 1 ? colors.glowMiddle : colors.glowEnd)
              .withValues(alpha: .8)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(position, 3 - index * .5, Paint()..color = color);
    }
    if (motion && burst < 1) {
      final progress = Curves.easeOut.transform(burst);
      for (var index = 0; index < 8; index++) {
        final angle = index * math.pi / 4;
        final position =
            center +
            Offset(math.cos(angle), math.sin(angle)) * (20 + 34 * progress);
        canvas.drawCircle(
          position,
          3 * (1 - .8 * progress),
          Paint()..color = palette[index % 3].withValues(alpha: 1 - burst),
        );
      }
    }
  }

  @override
  bool shouldRepaint(ChatbotAuraPainter oldDelegate) =>
      oldDelegate.colors != colors ||
      oldDelegate.seconds != seconds ||
      oldDelegate.selected != selected ||
      oldDelegate.motion != motion ||
      oldDelegate.burst != burst;
}

class ChatbotRobotPainter extends CustomPainter {
  final AppColors colors;
  final double seconds;
  const ChatbotRobotPainter(this.colors, {this.seconds = 0});

  static double _keyframe(
    double phase,
    List<double> positions,
    List<double> values,
  ) {
    for (var index = 1; index < positions.length; index++) {
      if (phase <= positions[index]) {
        final t = Curves.easeInOut.transform(
          (phase - positions[index - 1]) /
              (positions[index] - positions[index - 1]),
        );
        return values[index - 1] + (values[index] - values[index - 1]) * t;
      }
    }
    return values.last;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48, size.height / 48);
    canvas.translate(0, -.5 + 1.5 * math.cos(seconds * 2 * math.pi / 3.2));
    final body = Paint()..color = colors.chatbotForeground;
    final stroke = Paint()
      ..color = colors.chatbotForeground
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(24, 10), const Offset(24, 5.5), stroke);
    final pulse = (1 - math.cos(seconds * 2 * math.pi / 1.4)) / 2;
    final tip = Color.lerp(colors.glowEnd, colors.glowMiddle, pulse)!;
    canvas.drawCircle(
      const Offset(24, 4.5),
      4,
      Paint()
        ..color = tip.withValues(alpha: .5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawCircle(
      const Offset(24, 4.5),
      2.6 * (1 + .5 * pulse),
      Paint()..color = tip,
    );
    final face = RRect.fromRectAndRadius(
      const Rect.fromLTWH(9, 11, 30, 25),
      const Radius.circular(10),
    );
    canvas.drawRRect(
      face,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(colors.chatbotSurface, colors.glowStart, .3)!,
            colors.chatbotSurface,
          ],
        ).createShader(face.outerRect),
    );
    canvas.drawRRect(face, stroke);
    for (final x in [4.5, 40.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 19.5, 3.5, 10),
          const Radius.circular(1.75),
        ),
        body,
      );
    }
    final gaze = _keyframe(
      (seconds / 7) % 1,
      [0, .18, .26, .40, .50, .64, .74, 1],
      [0, 0, -1.6, -1.6, 1.6, 1.6, 0, 0],
    );
    final blink = _keyframe(
      (seconds / 4.8) % 1,
      [0, .91, .94, .97, 1],
      [1, 1, .08, 1, 1],
    );
    for (final x in [17.5, 30.5]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x + gaze, 22.5),
          width: 6,
          height: 8 * blink,
        ),
        Paint()..color = colors.glowHighlight,
      );
    }
    canvas.drawPath(
      Path()
        ..moveTo(19, 30.5)
        ..quadraticBezierTo(24, 34.1, 29, 30.5),
      stroke..strokeWidth = 1.8,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(ChatbotRobotPainter oldDelegate) =>
      oldDelegate.colors != colors || oldDelegate.seconds != seconds;
}
