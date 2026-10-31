import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class MagicInteractionLayer extends StatelessWidget {
  final Widget child;
  const MagicInteractionLayer({super.key, required this.child});
  @override
  Widget build(BuildContext context) => child;
}

class MagicPressFeedback extends StatelessWidget {
  final Widget child;
  const MagicPressFeedback({super.key, required this.child});
  @override
  Widget build(BuildContext context) => child;
}

/// Shared with login/registration so all page navigation has the same rhythm.
class MagicPageTransition extends StatelessWidget {
  static const forwardDuration = Duration(milliseconds: 500);
  static const reverseDuration = Duration(milliseconds: 400);
  final Animation<double> animation;
  final Widget child;
  const MagicPageTransition({
    super.key,
    required this.animation,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: animation.drive(
          Tween<Offset>(
            begin: const Offset(.12, 0),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic)),
        ),
        child: child,
      ),
    );
  }
}

class MagicPageTransitionsBuilder extends PageTransitionsBuilder {
  const MagicPageTransitionsBuilder();

  @override
  Duration get transitionDuration => MagicPageTransition.forwardDuration;

  @override
  Duration get reverseTransitionDuration => MagicPageTransition.reverseDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return MagicPageTransition(animation: animation, child: child);
  }
}
