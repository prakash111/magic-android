import '../services/app_localizations.dart';

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../theme/brand_config.dart';
import 'auth_motion.dart';

/// One finite timeline: type -> send -> gather letters -> logo -> wordmark.
/// Authentication runs independently; no timer fabricates startup progress.
class PromptCreationIntro extends StatelessWidget {
  static const duration = Duration(milliseconds: 5400);
  static const prompt = 'Create something magical';
  final Animation<double> animation;
  const PromptCreationIntro({super.key, required this.animation});
  static double stage(double time, double start, double end) =>
      ((time - start) / (end - start)).clamp(0.0, 1.0);
  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);

    final prompt = appTr(PromptCreationIntro.prompt);
    final colors = AuthPalette.of(context);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        AppLocalizations.watch(context);
        final time = animation.value * duration.inMilliseconds / 1000;
        final entry = Curves.easeOutCubic.transform(stage(time, .05, .65));
        final morph = Curves.easeInOutCubic.transform(stage(time, 2.25, 3.2));
        final textFade = 1 - stage(time, 1.95, 2.4);
        final glyph = stage(time, 2.8, 4.2);
        final typed = (stage(time, .65, 1.6) * prompt.length).floor();
        final word = stage(time, 3.4, 4.6);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 190,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  AppLocalizations.watch(context);
                  final pillWidth = math.min(296.0, constraints.maxWidth - 8);
                  return CustomPaint(
                    painter: _CreationParticles(colors, time, pillWidth),
                    child: Center(
                      child: Opacity(
                        opacity: entry,
                        child: Transform.translate(
                          offset: Offset(0, 10 * (1 - entry)),
                          child: Container(
                            key: const ValueKey('prompt-morph-tile'),
                            width: lerpDouble(pillWidth, 114, morph),
                            height: lerpDouble(58, 114, morph),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                lerpDouble(29, 35, morph)!,
                              ),
                              color: colors.surface,
                              gradient: morph > 0
                                  ? LinearGradient(
                                      colors: [
                                        Color.lerp(
                                          colors.surface,
                                          colors.indigo,
                                          morph,
                                        )!,
                                        Color.lerp(
                                          colors.surface,
                                          colors.violet,
                                          morph,
                                        )!,
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : null,
                              border: Border.all(
                                color: Color.lerp(
                                  colors.outline,
                                  colors.base.onPrimary.withValues(alpha: .2),
                                  morph,
                                )!,
                              ),
                              boxShadow: morph > 0
                                  ? [
                                      BoxShadow(
                                        color: colors.indigo.withValues(
                                          alpha: .4 * morph,
                                        ),
                                        blurRadius: 45 * morph,
                                        offset: Offset(0, 12 * morph),
                                      ),
                                    ]
                                  : [],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                lerpDouble(29, 35, morph)!,
                              ),
                              child: CustomPaint(
                                foregroundPainter: morph < .4
                                    ? _PromptEdge(colors, time / 2.6, 1 - morph)
                                    : MagicShinePainter(
                                        stage(time, 3.9, 4.7) * .4,
                                      ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    if (textFade > 0)
                                      Opacity(
                                        opacity: textFade,
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            left: 20,
                                            right: 8,
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: ClipRect(
                                                  child: Align(
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    child: Text(
                                                      '${prompt.substring(0, typed)}${time < 2 && (time * 2).floor().isEven ? '│' : ''}',
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.clip,
                                                      style: TextStyle(
                                                        color: colors.text,
                                                        fontSize: 15,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Transform.scale(
                                                scale: time >= 1.7 && time < 2.1
                                                    ? .85
                                                    : 1,
                                                child: Container(
                                                  width: 40,
                                                  height: 40,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    gradient: colors.gradient,
                                                  ),
                                                  child: Icon(
                                                    Icons.arrow_upward_rounded,
                                                    size: 20,
                                                    color:
                                                        colors.base.onPrimary,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    if (glyph > 0)
                                      SizedBox(
                                        width: 78,
                                        height: 78,
                                        child: BrandConfig.splashLogoBase64.isEmpty
                                            ? BrandConfig.logoBase64.isEmpty
                                            ? CustomPaint(
                                                painter: MagicSparklePainter(
                                                  color: colors.base.onPrimary,
                                                  progress: glyph,
                                                ),
                                              )
                                            : const AuthBrandLogo()
                                            : AuthBrandLogo(
                                                base64Image: BrandConfig.splashLogoBase64,
                                              ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Semantics(
              label: BrandConfig.name,
              header: true,
              child: ExcludeSemantics(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    for (var i = 0; i < BrandConfig.name.length; i++)
                      Builder(
                        builder: (localizationContext) {
                          AppLocalizations.watch(localizationContext);
                          final value = Curves.easeOutCubic.transform(
                            ((word * 1.5) -
                                    i /
                                        math.max(1, BrandConfig.name.length) *
                                        .5)
                                .clamp(0.0, 1.0),
                          );
                          final angle = (i.isEven ? -1 : 1) * (1 - value) * .65;
                          return Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(
                                (i.isEven ? -35 : 35) * (1 - value),
                                -55 * (1 - value),
                              ),
                              child: Transform.rotate(
                                angle: angle,
                                child: Text(
                                  BrandConfig.name[i],
                                  style: TextStyle(
                                    color: colors.text,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 42,
                                    letterSpacing: -.6,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Opacity(
              opacity: stage(time, 4.1, 4.75),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: .8),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: colors.outline),
                ),
                child: Text(
                  appTr('SEO Suite • Generative AI • Social Suite'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.muted, fontSize: 12),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CreationParticles extends CustomPainter {
  final AuthPalette colors;
  final double time, pillWidth;
  const _CreationParticles(this.colors, this.time, this.pillWidth);
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final shock = PromptCreationIntro.stage(time, 3.4, 4.8);
    if (shock > 0 && shock < 1) {
      for (var i = 0; i < 2; i++) {
        final progress = (shock - i * .12).clamp(0.0, 1.0);
        canvas.drawCircle(
          center,
          36 + progress * 230,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8
            ..color = (i == 0 ? colors.link : colors.cyan).withValues(
              alpha: (1 - progress) * .65,
            ),
        );
      }
    }
    final reveal = PromptCreationIntro.stage(time, 2.8, 3.7);
    final paint = Paint();
    for (var x = 0.0; x < size.width; x += 22) {
      for (var y = 0.0; y < size.height; y += 22) {
        final distance = (Offset(x, y) - center).distance;
        final band =
            (1 - ((distance - (36 + shock * 230)).abs() / 65)).clamp(0.0, 1.0) *
            (1 - shock);
        paint.color = colors.link.withValues(
          alpha: (reveal * .08 + band * .6).clamp(0.0, 1.0),
        );
        canvas.drawCircle(Offset(x, y), 1 + band, paint);
      }
    }
    final prompt = appTr(PromptCreationIntro.prompt);
    for (var i = 0; i < prompt.length; i++) {
      if (prompt[i] == ' ') continue;
      final progress = PromptCreationIntro.stage(
        time,
        1.95 + i * .015,
        2.9 + i * .015,
      );
      if (progress <= 0 || progress >= 1) continue;
      final p = Curves.easeInOutCubic.transform(progress), u = 1 - p;
      final start = Offset(center.dx - pillWidth / 2 + 24 + i * 7, center.dy);
      final control = Offset(
        center.dx + (i.isEven ? -95 : 95),
        center.dy - 100 - i % 4 * 12,
      );
      final position =
          start * (u * u) + control * (2 * u * p) + center * (p * p);
      final color = [colors.text, colors.link, colors.cyan, colors.pink][i % 4];
      final text = TextPainter(
        text: TextSpan(
          text: prompt[i],
          style: TextStyle(
            fontSize: 16 * (1 - .5 * p),
            fontWeight: FontWeight.w500,
            color: color.withValues(alpha: (1 - progress).clamp(0.0, 1.0)),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(position.dx, position.dy);
      canvas.rotate((i.isEven ? -1 : 1) * p * 2);
      text.paint(canvas, Offset(-text.width / 2, -text.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_CreationParticles oldDelegate) =>
      time != oldDelegate.time ||
      colors.base != oldDelegate.colors.base ||
      pillWidth != oldDelegate.pillWidth;
}

class _PromptEdge extends CustomPainter {
  final AuthPalette colors;
  final double phase, opacity;
  const _PromptEdge(this.colors, this.phase, this.opacity);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1);
    final shader = SweepGradient(
      colors: [
        colors.cyan.withValues(alpha: 0),
        colors.cyan.withValues(alpha: opacity),
        colors.pink.withValues(alpha: opacity),
        colors.indigo.withValues(alpha: opacity),
        colors.indigo.withValues(alpha: 0),
      ],
      stops: const [0, .65, .8, .9, 1],
      transform: GradientRotation(phase * math.pi * 2),
    ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(29)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(_PromptEdge oldDelegate) =>
      phase != oldDelegate.phase ||
      opacity != oldDelegate.opacity ||
      colors.base != oldDelegate.colors.base;
}
