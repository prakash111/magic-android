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

    return FadeTransition(
      opacity: animation.drive(CurveTween(curve: Curves.easeOutCubic)),
      child: SlideTransition(
        position: animation.drive(
          Tween<Offset>(
            begin: const Offset(0, .025),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic)),
        ),
        child: child,
      ),
    );
  }
}
