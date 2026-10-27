import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/brand_config.dart';

/// Tokens shared by the native sign-in, registration and launch experience.
class AuthPalette {
  final AppColors base;
  final bool dark;
  AuthPalette.of(BuildContext context)
    : base = AppColors.of(context),
      dark = Theme.of(context).brightness == Brightness.dark;
  Color get page => base.page;
  Color get surface => base.surface;
  Color get outline => dark ? const Color(0xFF2D3348) : base.outline;
  Color get text => base.text;
  Color get muted => dark ? const Color(0xFF94A3B8) : base.muted;
  Color get link => dark ? const Color(0xFFA5B4FC) : base.glowStart;
  Color get indigo => base.primary;
  Color get violet => AppTheme.accent;
  Color get cyan => base.glowEnd;
  Color get pink => base.glowMiddle;
  Color get success => dark ? const Color(0xFF6EE7B7) : const Color(0xFF047857);
  LinearGradient get gradient => LinearGradient(
    colors: [indigo, Color.lerp(indigo, violet, .65)!, violet],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AuthScene extends StatefulWidget {
  final Widget child;
  const AuthScene({super.key, required this.child});
  @override
  State<AuthScene> createState() => _AuthSceneState();
}

class _AuthSceneState extends State<AuthScene> with TickerProviderStateMixin {
  late final entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final ambient = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motion =
        !MediaQuery.disableAnimationsOf(context) && TickerMode.of(context);
    if (motion) {
      if (entrance.value < 1 && !entrance.isAnimating) entrance.forward();
      if (!ambient.isAnimating) ambient.repeat();
    } else {
      entrance.value = 1;
      ambient.stop();
    }
  }

  @override
  void dispose() {
    entrance.dispose();
    ambient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _AuthMotion(
    entrance: entrance,
    ambient: ambient,
    child: Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: IgnorePointer(
            child: CustomPaint(
              painter: AuthBackdropPainter(AuthPalette.of(context), ambient),
            ),
          ),
        ),
        Theme(
          data: Theme.of(context).copyWith(
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: AuthPalette.of(context).link,
                textStyle: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          child: widget.child,
        ),
      ],
    ),
  );
}

class _AuthMotion extends InheritedWidget {
  final Animation<double> entrance, ambient;
  const _AuthMotion({
    required this.entrance,
    required this.ambient,
    required super.child,
  });
  static _AuthMotion? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AuthMotion>();
  @override
  bool updateShouldNotify(_AuthMotion oldWidget) =>
      entrance != oldWidget.entrance || ambient != oldWidget.ambient;
}

Animation<double> authAmbient(BuildContext context) =>
    _AuthMotion.of(context)?.ambient ?? const AlwaysStoppedAnimation(0);

class AuthEntrance extends StatelessWidget {
  final Widget child;
  final int index;
  final bool horizontal;
  final bool springIn;
  const AuthEntrance({
    super.key,
    required this.child,
    this.index = 0,
    this.horizontal = false,
    this.springIn = false,
  });
  @override
  Widget build(BuildContext context) {
    final animation =
        _AuthMotion.of(context)?.entrance ??
        const AlwaysStoppedAnimation<double>(1);
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final start = math.min(.55, index * .055);
        final raw = ((animation.value - start) / (1 - start)).clamp(0.0, 1.0);
        final value = Curves.easeOutCubic.transform(raw);
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: horizontal
                ? Offset((index.isEven ? -26 : 26) * (1 - value), 0)
                : Offset(0, 18 * (1 - value)),
            child: springIn
                ? Transform.rotate(
                    angle: -.45 * (1 - value),
                    child: Transform.scale(
                      scale: .35 + .65 * Curves.easeOutBack.transform(raw),
                      child: child,
                    ),
                  )
                : child,
          ),
        );
      },
    );
  }
}

class AuthBackdropPainter extends CustomPainter {
  final AuthPalette colors;
  final Animation<double> phase;
  AuthBackdropPainter(this.colors, this.phase) : super(repaint: phase);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(colors.page, BlendMode.srcOver);
    final angle = phase.value * math.pi * 2;
    final drift = Offset(math.sin(angle) * 22, math.cos(angle) * 20);
    for (final item in [
      (Offset(size.width + 15, 20) + drift, colors.indigo),
      (Offset(-20, size.height - 10) - drift, colors.violet),
    ]) {
      final radius = math.min(320.0, size.width * .83);
      canvas.drawCircle(
        item.$1,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              item.$2.withValues(alpha: colors.dark ? .29 : .11),
              item.$2.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: item.$1, radius: radius)),
      );
    }
    final paint = Paint();
    for (var i = 0; i < 35; i++) {
      final x =
          ((i * 73 + 23) % 101) / 101 * size.width + math.sin(angle + i) * 5;
      final y =
          ((i * 37 + 19) % 103) / 103 * size.height + math.cos(angle + i) * 7;
      paint.color = [
        colors.link,
        colors.cyan,
        colors.pink,
      ][i % 3].withValues(alpha: .16 + .22 * (.5 + .5 * math.sin(angle + i)));
      canvas.drawCircle(Offset(x, y), i % 4 == 0 ? 1.2 : .7, paint);
    }
  }

  @override
  bool shouldRepaint(AuthBackdropPainter oldDelegate) =>
      oldDelegate.colors.base != colors.base ||
      oldDelegate.colors.dark != colors.dark ||
      oldDelegate.phase != phase;
}

class MagicSparklePainter extends CustomPainter {
  final Color color;
  final double progress, twinkle;
  const MagicSparklePainter({
    required this.color,
    this.progress = 1,
    this.twinkle = 0,
  });
  static Path mainStar() => Path()
    ..moveTo(52, 16)
    ..cubicTo(54, 38, 62, 48, 88, 54)
    ..cubicTo(62, 60, 54, 70, 52, 92)
    ..cubicTo(50, 70, 42, 60, 16, 54)
    ..cubicTo(42, 48, 50, 38, 52, 16)
    ..close();
  static Path smallStar(double x, double y, double r) => Path()
    ..moveTo(x, y - r)
    ..cubicTo(x + 1, y - 2, x + 2, y - 1, x + r, y)
    ..cubicTo(x + 2, y + 1, x + 1, y + 2, x, y + r)
    ..cubicTo(x - 1, y + 2, x - 2, y + 1, x - r, y)
    ..cubicTo(x - 2, y - 1, x - 1, y - 2, x, y - r)
    ..close();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 108, size.height / 108);
    final path = mainStar();
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * (progress / .7).clamp(0.0, 1.0)),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(
          alpha: ((progress - .45) / .35).clamp(0.0, 1.0),
        ),
    );
    for (var i = 0; i < 2; i++) {
      final p = ((progress - .55 - i * .12) / .25).clamp(0.0, 1.0);
      final center = i == 0 ? const Offset(88, 24) : const Offset(84, 83);
      final scale =
          Curves.easeOutBack.transform(p) *
          (1 + math.sin(twinkle * math.pi * 2 + i) * .09);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(scale);
      canvas.translate(-center.dx, -center.dy);
      canvas.drawPath(
        smallStar(center.dx, center.dy, i == 0 ? 12 : 11),
        Paint()..color = color.withValues(alpha: p),
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(MagicSparklePainter oldDelegate) =>
      progress != oldDelegate.progress ||
      twinkle != oldDelegate.twinkle ||
      color != oldDelegate.color;
}

class AuthBrandLogo extends StatelessWidget {
  const AuthBrandLogo({super.key});
  static String _encoded = '';
  static MemoryImage? _image;
  @override
  Widget build(BuildContext context) {
    if (_image == null || _encoded != BrandConfig.logoBase64) {
      _encoded = BrandConfig.logoBase64;
      _image = MemoryImage(base64Decode(_encoded));
    }
    return Image(image: _image!, fit: BoxFit.contain);
  }
}

class AuthMark extends StatelessWidget {
  const AuthMark({super.key});
  @override
  Widget build(BuildContext context) {
    final colors = AuthPalette.of(context);
    final phase = authAmbient(context);
    return ExcludeSemantics(
      child: AuthEntrance(
        springIn: true,
        child: AnimatedBuilder(
          animation: phase,
          builder: (context, _) => Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              gradient: colors.gradient,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: colors.base.onPrimary.withValues(alpha: .3),
              ),
              boxShadow: [
                BoxShadow(
                  color: colors.indigo.withValues(
                    alpha: .28 + .12 * math.sin(phase.value * math.pi * 8),
                  ),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: CustomPaint(
                foregroundPainter: MagicShinePainter(phase.value * 4 % 1),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: BrandConfig.logoBase64.isEmpty
                      ? CustomPaint(
                          painter: MagicSparklePainter(
                            color: colors.base.onPrimary,
                            twinkle: phase.value * 4,
                          ),
                        )
                      : const AuthBrandLogo(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MagicShinePainter extends CustomPainter {
  final double phase;
  const MagicShinePainter(this.phase);
  @override
  void paint(Canvas canvas, Size size) {
    if (phase == 0 || phase > .4) return;
    final x = -size.width + phase / .4 * size.width * 3;
    final rect = Rect.fromLTWH(x, 0, size.width * .6, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Colors.transparent, Color(0x33FFFFFF), Colors.transparent],
          transform: GradientRotation(-.2),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(MagicShinePainter oldDelegate) =>
      phase != oldDelegate.phase;
}

class AuthPrimaryButton extends StatelessWidget {
  final String label, busyLabel;
  final bool busy;
  final VoidCallback? onPressed;
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.busyLabel = 'Please wait…',
  });
  @override
  Widget build(BuildContext context) {
    final colors = AuthPalette.of(context);
    final phase = authAmbient(context);
    return LayoutBuilder(
      builder: (context, constraints) => Center(
        child: AnimatedContainer(
          duration: Duration(
            milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 400,
          ),
          curve: Curves.easeInOutCubic,
          width: busy ? 56 : constraints.maxWidth,
          height: 56,
          decoration: BoxDecoration(
            gradient: colors.gradient,
            borderRadius: BorderRadius.circular(busy ? 28 : 18),
            boxShadow: [
              BoxShadow(
                color: colors.indigo.withValues(alpha: .26),
                blurRadius: 25,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(busy ? 28 : 18),
            child: AnimatedBuilder(
              animation: phase,
              builder: (_, child) => CustomPaint(
                foregroundPainter: MagicShinePainter(phase.value * 4 % 1),
                child: child,
              ),
              child: FilledButton(
                onPressed: busy ? null : onPressed,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  disabledBackgroundColor: Colors.transparent,
                  foregroundColor: colors.base.onPrimary,
                  disabledForegroundColor: colors.base.onPrimary,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(busy ? 28 : 18),
                  ),
                ),
                child: busy
                    ? Semantics(
                        label: busyLabel,
                        liveRegion: true,
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: colors.base.onPrimary,
                          ),
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              label,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Icon(Icons.arrow_forward_rounded, size: 20),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthInput extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final bool enabled, obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted, onChanged;
  const AuthInput({
    super.key,
    required this.controller,
    required this.label,
    this.icon,
    this.enabled = true,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
    this.autofillHints,
    this.textInputAction,
    this.focusNode,
    this.validator,
    this.onSubmitted,
    this.onChanged,
  });
  @override
  State<AuthInput> createState() => _AuthInputState();
}

class _AuthInputState extends State<AuthInput> {
  bool focused = false;
  @override
  Widget build(BuildContext context) {
    final colors = AuthPalette.of(context);
    final phase = authAmbient(context);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (value) => setState(() => focused = value),
      child: AnimatedBuilder(
        animation: focused ? phase : const AlwaysStoppedAnimation<double>(0),
        builder: (_, child) => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: focused
                ? [
                    BoxShadow(
                      color: Color.lerp(
                        colors.indigo,
                        colors.cyan,
                        .5 + .5 * math.sin(phase.value * math.pi * 8),
                      )!.withValues(alpha: .18),
                      blurRadius: 14,
                      spreadRadius: 2,
                    ),
                  ]
                : [],
          ),
          child: child,
        ),
        child: TextFormField(
          focusNode: widget.focusNode,
          controller: widget.controller,
          enabled: widget.enabled,
          obscureText: widget.obscure,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          autofillHints: widget.autofillHints,
          autocorrect:
              !(widget.autofillHints?.any(
                    (hint) => const [
                      AutofillHints.password,
                      AutofillHints.newPassword,
                    ].contains(hint),
                  ) ??
                  false) &&
              widget.keyboardType != TextInputType.emailAddress,
          enableSuggestions:
              !(widget.autofillHints?.any(
                    (hint) => const [
                      AutofillHints.password,
                      AutofillHints.newPassword,
                    ].contains(hint),
                  ) ??
                  false),
          decoration: InputDecoration(
            labelText: widget.label,
            labelStyle: TextStyle(color: colors.muted),
            floatingLabelStyle: TextStyle(color: colors.link),
            filled: true,
            fillColor: colors.surface,
            prefixIcon: widget.icon == null
                ? null
                : Icon(
                    widget.icon,
                    color: focused ? colors.link : colors.muted,
                    size: 20,
                  ),
            suffixIcon: widget.suffix,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 18,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: colors.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: colors.outline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: colors.base.primary, width: 1.8),
            ),
            errorMaxLines: 3,
          ),
          validator: widget.validator,
          onChanged: widget.onChanged,
          onFieldSubmitted: widget.onSubmitted,
        ),
      ),
    );
  }
}

class AuthSuccess extends StatefulWidget {
  final VoidCallback onContinue;
  final String title, message;
  const AuthSuccess({
    super.key,
    required this.onContinue,
    this.title = 'Welcome back',
    this.message = 'Your workspace is ready.',
  });
  @override
  State<AuthSuccess> createState() => _AuthSuccessState();
}

class _AuthSuccessState extends State<AuthSuccess>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.value = 1;
    } else {
      controller.forward();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AuthPalette.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: controller,
              builder: (_, _) => CustomPaint(
                painter: _SuccessPainter(colors, controller.value),
                child: const SizedBox(width: 160, height: 160),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.text,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.muted, height: 1.5),
            ),
            const SizedBox(height: 30),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: AuthPrimaryButton(
                label: 'Continue',
                onPressed: widget.onContinue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuccessPainter extends CustomPainter {
  final AuthPalette colors;
  final double progress;
  const _SuccessPainter(this.colors, this.progress);
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: center, radius: 52);
    canvas.drawCircle(
      center,
      52,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = colors.outline,
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * (progress / .7).clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(colors: [colors.success, colors.cyan])
            .createShader(rect),
    );
    final path = Path()
      ..moveTo(center.dx - 21, center.dy)
      ..lineTo(center.dx - 5, center.dy + 15)
      ..lineTo(center.dx + 24, center.dy - 17);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(
        0,
        metric.length * ((progress - .55) / .3).clamp(0.0, 1.0),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = colors.success,
    );
    if (progress > .6 && progress < 1) {
      final p = (progress - .6) / .4;
      for (var i = 0; i < 22; i++) {
        final angle = i / 22 * math.pi * 2;
        final position =
            center + Offset(math.cos(angle), math.sin(angle)) * (65 + p * 35);
        canvas.drawCircle(
          position,
          2 * (1 - p),
          Paint()
            ..color = [
              colors.cyan,
              colors.pink,
              colors.success,
            ][i % 3].withValues(alpha: 1 - p),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_SuccessPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      colors.base != oldDelegate.colors.base;
}

Route<T> authRoute<T>(BuildContext context, WidgetBuilder builder) {
  final reduced = MediaQuery.disableAnimationsOf(context);
  return PageRouteBuilder<T>(
    transitionDuration: Duration(milliseconds: reduced ? 0 : 500),
    reverseTransitionDuration: Duration(milliseconds: reduced ? 0 : 400),
    pageBuilder: (context, _, _) => builder(context),
    transitionsBuilder: (_, animation, _, child) => FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween(begin: const Offset(.12, 0), end: Offset.zero).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      ),
    ),
  );
}
