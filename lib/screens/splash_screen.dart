import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/mobile_api.dart';
import '../services/startup_service.dart';
import '../theme/app_colors.dart';
import '../widgets/welcome_experience.dart';
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
      duration: const Duration(milliseconds: 1400),
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
          builder: (_) => welcomed
              ? destination()
              : WelcomeScreen(destination: destination),
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

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.page,
      body: WelcomeBackdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  WelcomeBrand(
                    animation: MediaQuery.disableAnimationsOf(context)
                        ? const AlwaysStoppedAnimation(1)
                        : controller,
                  ),
                  const SizedBox(height: 56),
                  if (!retry)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    retry
                        ? 'Unable to load your workspace. Please check your connection and retry.'
                        : 'Preparing your workspace…',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.muted, fontSize: 13),
                  ),
                  if (retry)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: FilledButton(
                        onPressed: start,
                        child: const Text('Retry'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
