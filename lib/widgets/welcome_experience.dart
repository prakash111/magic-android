import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_colors.dart';
import '../theme/brand_config.dart';

const welcomeCompletedKey = 'has_seen_mobile_intro_v1';

class WelcomeBackdrop extends StatelessWidget {
  final Widget child;
  const WelcomeBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return ColoredBox(
      color: colors.page,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(top: -160, right: -130, child: _aurora(colors.glowStart)),
          Positioned(
            bottom: -180,
            left: -140,
            child: _aurora(colors.glowMiddle),
          ),
          IgnorePointer(child: CustomPaint(painter: _Sparkles(colors))),
          child,
        ],
      ),
    );
  }

  Widget _aurora(Color color) => Container(
    width: 460,
    height: 460,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [color.withValues(alpha: .18), color.withValues(alpha: 0)],
      ),
    ),
  );
}

class WelcomeBrand extends StatelessWidget {
  final Animation<double> animation;
  const WelcomeBrand({super.key, required this.animation});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final progress = Curves.easeOutCubic.transform(animation.value);
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - progress)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: .82 + progress * .18,
                  child: Container(
                    width: 112,
                    height: 112,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [colors.glowStart, colors.glowMiddle],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                        color: colors.onPrimary.withValues(alpha: .35),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colors.primary.withValues(alpha: .35),
                          blurRadius: 52,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      size: 58,
                      color: colors.onPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  BrandConfig.name,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.3,
                    color: colors.text,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: colors.outline),
                  ),
                  child: Text(
                    'SEO Suite • Generative AI • Social Suite',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: colors.muted),
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

class WelcomeScreen extends StatefulWidget {
  final Widget Function() destination;
  const WelcomeScreen({super.key, required this.destination});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final controller = PageController();
  int page = 0;
  bool finishing = false;
  static const titles = [
    'Create anything, instantly',
    'Plan and publish everywhere',
    'Your AI assistant, always on',
    'Your workspace is ready',
  ];
  static const descriptions = [
    'Write, design and generate videos with AI tools in one workspace.',
    'Schedule posts, run campaigns and reach your connected platforms from one calendar.',
    'Explore ideas, get answers and turn a conversation into your next creation.',
    'Sign in to explore your tools, saved documents and connected accounts.',
  ];

  Future<void> finish() async {
    if (finishing) return;
    setState(() => finishing = true);
    try {
      final preferences = await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 2),
      );
      await preferences
          .setBool(welcomeCompletedKey, true)
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // A cosmetic preference must never prevent access to the sign-in screen.
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => widget.destination()),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: colors.page,
      body: WelcomeBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 12, 4),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded, color: colors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        BrandConfig.name,
                        style: TextStyle(
                          color: colors.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: finishing ? null : finish,
                      child: const Text('Skip'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: controller,
                  itemCount: titles.length,
                  onPageChanged: (value) => setState(() => page = value),
                  itemBuilder: (context, index) => LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 16,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: math.max(0, constraints.maxHeight - 32),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _WelcomeArtwork(page: index),
                            const SizedBox(height: 32),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: Text(
                                titles[index],
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: colors.text,
                                  fontSize: 30,
                                  height: 1.15,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -.9,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 380),
                              child: Text(
                                descriptions[index],
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: colors.muted,
                                  height: 1.6,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 12, 28, 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          titles.length,
                          (index) => Semantics(
                            label:
                                'Welcome page ${index + 1} of ${titles.length}',
                            selected: page == index,
                            button: true,
                            child: SizedBox(
                              height: 48,
                              width: 48,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(24),
                                onTap: finishing
                                    ? null
                                    : () => controller.animateToPage(
                                        index,
                                        duration: Duration(
                                          milliseconds: reducedMotion ? 1 : 350,
                                        ),
                                        curve: Curves.easeOutCubic,
                                      ),
                                child: Center(
                                  child: AnimatedContainer(
                                    duration: Duration(
                                      milliseconds: reducedMotion ? 0 : 250,
                                    ),
                                    width: page == index ? 28 : 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: page == index
                                          ? colors.primary
                                          : colors.outline,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: finishing
                              ? null
                              : page == titles.length - 1
                              ? finish
                              : () => controller.nextPage(
                                  duration: Duration(
                                    milliseconds: reducedMotion ? 1 : 350,
                                  ),
                                  curve: Curves.easeOutCubic,
                                ),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(54),
                          ),
                          icon: Icon(
                            page == titles.length - 1
                                ? Icons.auto_awesome_rounded
                                : Icons.arrow_forward_rounded,
                          ),
                          label: Text(
                            finishing
                                ? 'Opening your workspace…'
                                : page == titles.length - 1
                                ? 'Get started'
                                : 'Next',
                          ),
                        ),
                      ),
                      if (page == titles.length - 1)
                        TextButton(
                          onPressed: finishing ? null : finish,
                          child: const Text('Sign in'),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomeArtwork extends StatelessWidget {
  final int page;
  const _WelcomeArtwork({required this.page});
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final icons = [
      Icons.edit_note_rounded,
      Icons.calendar_month_rounded,
      Icons.smart_toy_rounded,
      Icons.auto_awesome_rounded,
    ];
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: AspectRatio(
        aspectRatio: 1.25,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: colors.primary.withValues(alpha: .2)),
                gradient: RadialGradient(
                  colors: [
                    colors.primary.withValues(alpha: .16),
                    colors.primary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
            Container(
              width: 190,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border.all(color: colors.outline),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: .12),
                    blurRadius: 32,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icons[page], size: 64, color: colors.primary),
                  const SizedBox(height: 18),
                  if (page == 1)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(
                        14,
                        (i) => Container(
                          width: 13,
                          height: 13,
                          decoration: BoxDecoration(
                            color: i == 9 ? colors.primary : colors.input,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    )
                  else if (page == 3)
                    Icon(
                      Icons.check_circle_rounded,
                      color: colors.glowEnd,
                      size: 32,
                    )
                  else
                    ...List.generate(
                      3,
                      (i) => Container(
                        height: 7,
                        width: i == 2 ? 75 : 120,
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: i == 0
                              ? colors.primary.withValues(alpha: .4)
                              : colors.outline,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              top: 14,
              right: 4,
              child: _orbit(
                context,
                page == 1 ? Icons.send_rounded : Icons.image_outlined,
                colors.glowEnd,
              ),
            ),
            Positioned(
              bottom: 10,
              left: 0,
              child: _orbit(
                context,
                page == 2
                    ? Icons.chat_bubble_outline_rounded
                    : Icons.play_arrow_rounded,
                colors.glowMiddle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _orbit(BuildContext context, IconData icon, Color accent) {
    final colors = AppColors.of(context);
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: accent.withValues(alpha: .5)),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: .12), blurRadius: 22),
        ],
      ),
      child: Icon(icon, color: accent),
    );
  }
}

class _Sparkles extends CustomPainter {
  final AppColors colors;
  const _Sparkles(this.colors);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = colors.primary.withValues(alpha: .25);
    for (var i = 0; i < 22; i++) {
      final x = ((i * 79 + 31) % 101) / 101 * size.width;
      final y = ((i * 43 + 17) % 97) / 97 * size.height;
      canvas.drawCircle(Offset(x, y), i % 3 == 0 ? 2 : 1, paint);
    }
  }

  @override
  bool shouldRepaint(_Sparkles oldDelegate) => oldDelegate.colors != colors;
}
