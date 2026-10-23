import 'package:flutter/material.dart';

class ThemeSettings extends InheritedWidget {
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;
  const ThemeSettings({
    super.key,
    required this.mode,
    required this.onChanged,
    required super.child,
  });
  static ThemeSettings? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeSettings>();
  @override
  bool updateShouldNotify(ThemeSettings oldWidget) => oldWidget.mode != mode;
}
