import 'package:flutter/material.dart';

/// A short entrance for meaningful content changes, without global tap effects.
class TapFx extends StatelessWidget {
  final Widget child;
  const TapFx({super.key, required this.child});
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180),
    transitionBuilder: (child, animation) => ScaleTransition(
      scale: Tween<double>(begin: .96, end: 1).animate(animation),
      child: FadeTransition(opacity: animation, child: child),
    ),
    child: child,
  );
}
