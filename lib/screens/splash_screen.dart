import '../services/app_localizations.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/mobile_api.dart';
import '../theme/brand_config.dart';
import '../services/startup_service.dart';
import '../widgets/welcome_experience.dart';
import '../widgets/auth_motion.dart';
import '../widgets/prompt_creation_intro.dart';
import 'home_screen.dart';
import 'auth/login_screen.dart';

class SplashScreen extends StatefulWidget {
  final Function(ThemeMode) onThemeChanged;
  final MobileApi? api;
  const SplashScreen({super.key, required this.onThemeChanged, this.api});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  bool starting = false, retry = false;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: PromptCreationIntro.duration,
    )..forward();
    start();
  }

  Future<void> start() async {
    if (starting) return;
    setState(() {
      starting = true;
      retry = false;
    });
    try {
      final loggedIn = await StartupService(
        api: widget.api ?? MobileApi.instance,
      ).restoreSession();
      var welcomed = true;
      try {
        final preferences = await SharedPreferences.getInstance().timeout(
          const Duration(seconds: 2),
        );
        welcomed = preferences.getBool(welcomeCompletedKey) ?? false;
      } catch (_) {
        // Preference storage is optional; authentication and licensing are not.
      }
      if (!mounted) return;
      if (!MediaQuery.disableAnimationsOf(context)) {
        await controller.forward().orCancel;
      }
      if (!mounted) return;
      Widget destination() => loggedIn
          ? HomeScreen(onThemeChanged: widget.onThemeChanged, api: widget.api)
          : LoginScreen(onThemeChanged: widget.onThemeChanged, api: widget.api);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (localizationContext) {
            AppLocalizations.watch(localizationContext);
            return welcomed
                ? destination()
                : WelcomeScreen(destination: destination);
          },
        ),
      );
    } catch (_) {
      if (!mounted) return;
      controller.value = 1;
      setState(() {
        starting = false;
        retry = true;
      });
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Widget status(AuthPalette colors) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (!retry)
        SizedBox(
          width: 148,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 4,
              backgroundColor: colors.outline,
              color: colors.cyan,
              semanticsLabel: appTr('Preparing your workspace'),
            ),
          ),
        ),
      const SizedBox(height: 16),
      Text(
        appTr(
          retry
              ? 'Unable to load your workspace. Please check your connection and retry.'
              : 'Preparing your workspace…',
        ),
        textAlign: TextAlign.center,
        style: TextStyle(color: colors.muted, fontSize: 13),
      ),
      if (retry)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: FilledButton(onPressed: start, child: Text(appTr('Retry'))),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);

    final colors = AuthPalette.of(context);
    final reduced = MediaQuery.disableAnimationsOf(context);
    final artwork = PromptCreationIntro(
      animation: reduced ? const AlwaysStoppedAnimation(1) : controller,
    );
    final footer = Text(
      appTr("Powered by :value", {"value": BrandConfig.name}),
      textAlign: TextAlign.center,
      style: TextStyle(color: colors.muted, fontSize: 11),
    );
    return Scaffold(
      backgroundColor: colors.page,
      body: AuthScene(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              AppLocalizations.watch(context);
              final loading = AnimatedBuilder(
                animation: controller,
                child: status(colors),
                builder: (localizationContext, child) {
                  AppLocalizations.watch(localizationContext);
                  return Opacity(
                    opacity: retry || reduced
                        ? 1
                        : PromptCreationIntro.stage(
                            controller.value * 5.4,
                            4.5,
                            5.2,
                          ),
                    child: child,
                  );
                },
              );
              if (constraints.maxHeight < 700 ||
                  MediaQuery.textScalerOf(context).scale(14) > 19) {
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        artwork,
                        const SizedBox(height: 44),
                        loading,
                        const SizedBox(height: 36),
                        footer,
                      ],
                    ),
                  ),
                );
              }
              return Stack(
                fit: StackFit.expand,
                children: [
                  Align(
                    alignment: const Alignment(0, -.12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: artwork,
                    ),
                  ),
                  Positioned(
                    bottom: constraints.maxHeight * .13,
                    left: 28,
                    right: 28,
                    child: loading,
                  ),
                  Positioned(bottom: 20, left: 20, right: 20, child: footer),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
