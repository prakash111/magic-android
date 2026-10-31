import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_colors.dart';

enum MagicMotionLevel { off, subtle, max }

class MagicMotionSettings extends ChangeNotifier {
  MagicMotionSettings._();

  static final MagicMotionSettings instance = MagicMotionSettings._();
  static const _preferenceKey = 'magic_motion_level';

  MagicMotionLevel _level = MagicMotionLevel.subtle;
  MagicMotionLevel get level => _level;

  Future<void> load() async {
    try {
      final preferences = await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 2),
      );
      final savedLevel = preferences.getString(_preferenceKey);
      _level = MagicMotionLevel.values.firstWhere(
        (level) => level.name == savedLevel,
        orElse: () => MagicMotionLevel.subtle,
      );
      notifyListeners();
    } catch (_) {
      // Motion preferences are optional and must never block app startup.
    }
  }

  Future<void> setLevel(MagicMotionLevel level) async {
    if (_level == level) return;
    _level = level;
    notifyListeners();
    try {
      final preferences = await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 2),
      );
      await preferences
          .setString(_preferenceKey, level.name)
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // Keep the current session responsive when device storage is unavailable.
    }
  }
}

class MagicInteractionLayer extends StatefulWidget {
  final Widget child;

  const MagicInteractionLayer({super.key, required this.child});

  @override
  State<MagicInteractionLayer> createState() => _MagicInteractionLayerState();
}

class _MagicInteractionLayerState extends State<MagicInteractionLayer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final Map<int, _PointerStart> _pointers = {};
  final List<_TapBurst> _bursts = [];
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    MagicMotionSettings.instance.addListener(_handleSettingsChanged);
    _ticker = createTicker(_tick);
  }

  @override
  void dispose() {
    MagicMotionSettings.instance.removeListener(_handleSettingsChanged);
    _ticker.dispose();
    super.dispose();
  }

  void _handleSettingsChanged() {
    if (MagicMotionSettings.instance.level != MagicMotionLevel.off) return;
    _pointers.clear();
    _bursts.clear();
    if (_ticker.isActive) _ticker.stop();
    if (mounted) setState(() {});
  }

  void _pointerDown(PointerDownEvent event) {
    if (MagicMotionSettings.instance.level == MagicMotionLevel.off ||
        MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    _pointers[event.pointer] = _PointerStart(
      position: event.localPosition,
      time: event.timeStamp,
    );
  }

  void _pointerUp(PointerUpEvent event) {
    final start = _pointers.remove(event.pointer);
    if (start == null ||
        MagicMotionSettings.instance.level == MagicMotionLevel.off ||
        MediaQuery.disableAnimationsOf(context)) {
      return;
    }

    final movement = (event.localPosition - start.position).distance;
    final duration = event.timeStamp - start.time;
    if (movement > 16 || duration > const Duration(milliseconds: 450)) return;

    if (!_ticker.isActive) {
      _elapsed = Duration.zero;
      _ticker.start();
    }
    final level = MagicMotionSettings.instance.level;
    _bursts.add(
      _TapBurst(
        position: event.localPosition,
        startedAt: _elapsed,
        strength: level == MagicMotionLevel.max ? 1 : .58,
      ),
    );
    if (_bursts.length > 8) _bursts.removeAt(0);
    if (mounted) setState(() {});
  }

  void _pointerCancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
  }

  void _tick(Duration elapsed) {
    _elapsed = elapsed;
    _bursts.removeWhere(
      (burst) => elapsed - burst.startedAt > const Duration(milliseconds: 760),
    );
    if (_bursts.isEmpty) _ticker.stop();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _pointerDown,
      onPointerUp: _pointerUp,
      onPointerCancel: _pointerCancel,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  key: const ValueKey('magic-tap-burst-painter'),
                  painter: _MagicBurstPainter(
                    bursts: List<_TapBurst>.of(_bursts),
                    elapsed: _elapsed,
                    colors: colors,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PointerStart {
  final Offset position;
  final Duration time;

  const _PointerStart({required this.position, required this.time});
}

class _TapBurst {
  final Offset position;
  final Duration startedAt;
  final double strength;

  const _TapBurst({
    required this.position,
    required this.startedAt,
    required this.strength,
  });
}

class _MagicBurstPainter extends CustomPainter {
  final List<_TapBurst> bursts;
  final Duration elapsed;
  final AppColors colors;

  const _MagicBurstPainter({
    required this.bursts,
    required this.elapsed,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final burst in bursts) {
      final age = elapsed - burst.startedAt;
      final progress =
          (age.inMicroseconds /
                  const Duration(milliseconds: 760).inMicroseconds)
              .clamp(0.0, 1.0);
      final fade = 1 - progress;
      final eased = 1 - math.pow(1 - progress, 3).toDouble();
      final center = burst.position;
      final strength = burst.strength;
      final radius = (30 + eased * 42) * strength;
      final glowBounds = Rect.fromCircle(center: center, radius: radius * 1.65);

      canvas.drawCircle(
        center,
        radius * 1.65,
        Paint()
          ..shader = RadialGradient(
            colors: [
              colors.primary.withValues(alpha: .22 * fade),
              colors.glowEnd.withValues(alpha: .11 * fade),
              Colors.transparent,
            ],
            stops: const [0, .48, 1],
          ).createShader(glowBounds),
      );

      for (var ring = 0; ring < 2; ring++) {
        final ringProgress = ((progress - ring * .16) / (1 - ring * .16)).clamp(
          0.0,
          1.0,
        );
        if (ringProgress <= 0) continue;
        final ringFade = (1 - ringProgress) * (ring == 0 ? .72 : .42);
        final ringRadius =
            (9 + 47 * (1 - math.pow(1 - ringProgress, 3))) * strength;
        canvas.drawCircle(
          center,
          ringRadius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = (2.6 - ringProgress * 1.4) * strength
            ..color = Color.lerp(
              colors.glowEnd,
              colors.glowMiddle,
              ring * .42,
            )!.withValues(alpha: ringFade),
        );
      }

      final particleCount = strength > .8 ? 12 : 7;
      for (var index = 0; index < particleCount; index++) {
        final angle = (math.pi * 2 * index / particleCount) + .18;
        final distance = (12 + 56 * eased) * strength;
        final point = Offset(
          center.dx + math.cos(angle) * distance,
          center.dy + math.sin(angle) * distance + 22 * progress * progress,
        );
        final tail = Offset(
          center.dx + math.cos(angle) * distance * .77,
          center.dy +
              math.sin(angle) * distance * .77 +
              16 * progress * progress,
        );
        final color = colors.toolAccents[index % colors.toolAccents.length];
        canvas.drawLine(
          tail,
          point,
          Paint()
            ..color = color.withValues(alpha: fade * .82)
            ..strokeWidth = (1.2 + strength) * fade
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawCircle(
          point,
          (2.6 * strength * fade).clamp(.4, 2.6),
          Paint()..color = color.withValues(alpha: fade),
        );
      }

      if (progress < .42) {
        final starProgress = progress / .42;
        final starRadius =
            (10 + 5 * math.sin(starProgress * math.pi)) * strength;
        final path = Path()
          ..moveTo(center.dx, center.dy - starRadius)
          ..quadraticBezierTo(
            center.dx + starRadius * .12,
            center.dy - starRadius * .12,
            center.dx + starRadius,
            center.dy,
          )
          ..quadraticBezierTo(
            center.dx + starRadius * .12,
            center.dy + starRadius * .12,
            center.dx,
            center.dy + starRadius,
          )
          ..quadraticBezierTo(
            center.dx - starRadius * .12,
            center.dy + starRadius * .12,
            center.dx - starRadius,
            center.dy,
          )
          ..quadraticBezierTo(
            center.dx - starRadius * .12,
            center.dy - starRadius * .12,
            center.dx,
            center.dy - starRadius,
          )
          ..close();
        canvas.drawPath(
          path,
          Paint()
            ..color = Colors.white.withValues(alpha: 1 - starProgress * .62),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MagicBurstPainter oldDelegate) =>
      oldDelegate.elapsed != elapsed ||
      oldDelegate.bursts != bursts ||
      oldDelegate.colors != colors;
}

class MagicPressFeedback extends StatefulWidget {
  final Widget child;

  const MagicPressFeedback({super.key, required this.child});

  @override
  State<MagicPressFeedback> createState() => _MagicPressFeedbackState();
}

class _MagicPressFeedbackState extends State<MagicPressFeedback>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Offset? _tilt;
  Offset? _pointerStart;

  @override
  void initState() {
    super.initState();
    MagicMotionSettings.instance.addListener(_settingsChanged);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      reverseDuration: const Duration(milliseconds: 460),
    );
  }

  @override
  void dispose() {
    MagicMotionSettings.instance.removeListener(_settingsChanged);
    _controller.dispose();
    super.dispose();
  }

  void _settingsChanged() {
    if (MagicMotionSettings.instance.level != MagicMotionLevel.off) return;
    _pointerStart = null;
    _tilt = null;
    _controller.reverse();
  }

  void _handleDown(PointerDownEvent event) {
    if (MagicMotionSettings.instance.level == MagicMotionLevel.off ||
        MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final localPosition = box.globalToLocal(event.position);
    final size = box.size;
    final intensity = MagicMotionSettings.instance.level == MagicMotionLevel.max
        ? 5.0
        : 2.6;
    _pointerStart = event.position;
    _tilt = Offset(
      -((localPosition.dy / size.height) - .5) * 2 * intensity,
      ((localPosition.dx / size.width) - .5) * 2 * intensity,
    );
    _controller.forward(from: 0);
  }

  void _handleMove(PointerMoveEvent event) {
    final start = _pointerStart;
    if (start == null || (event.position - start).distance < 12) return;
    _release();
  }

  void _release() {
    _pointerStart = null;
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: reducedMotion ? null : _handleDown,
      onPointerMove: _handleMove,
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          final amount = _controller.value;
          final tilt = _tilt ?? Offset.zero;
          final transform = Matrix4.identity()
            ..setEntry(3, 2, .001)
            ..rotateX(tilt.dx * math.pi / 180 * amount)
            ..rotateY(tilt.dy * math.pi / 180 * amount)
            ..scale(1 - .035 * amount);
          return Transform(
            key: const ValueKey('magic-press-feedback-transform'),
            alignment: Alignment.center,
            transform: reducedMotion ? Matrix4.identity() : transform,
            child: child,
          );
        },
      ),
    );
  }
}

class MagicPageTransitionsBuilder extends PageTransitionsBuilder {
  const MagicPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;

    final incoming = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final outgoing = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return AnimatedBuilder(
      animation: Listenable.merge([incoming, outgoing]),
      child: child,
      builder: (context, child) {
        final incomingValue = incoming.value;
        final outgoingValue = outgoing.value;
        final oldPageScale = 1 - outgoingValue * .035;
        final oldPageOpacity = 1 - outgoingValue * .22;
        final newPageScale = .965 + incomingValue * .035;
        final newPageOffset = (1 - incomingValue) * .045;
        return Opacity(
          opacity: oldPageOpacity * incomingValue,
          child: Transform.scale(
            scale: oldPageScale * newPageScale,
            alignment: Alignment.center,
            child: Transform.translate(
              offset: Offset(
                0,
                MediaQuery.sizeOf(context).height * newPageOffset,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
