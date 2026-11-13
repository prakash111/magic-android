import 'package:flutter/material.dart';

const phoneAgentGradient = LinearGradient(
  colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

ThemeData phoneAgentTheme(ThemeData base) {
  final dark = base.brightness == Brightness.dark;
  final surface = dark ? const Color(0xFF1B1F2E) : Colors.white;
  final border = dark ? const Color(0xFF2D3348) : const Color(0xFFE2E8F0);
  final scheme = base.colorScheme.copyWith(
    primary: dark ? const Color(0xFFA5B4FC) : const Color(0xFF6366F1),
    surface: surface,
    surfaceContainerHighest: dark
        ? const Color(0xFF252A3B)
        : const Color(0xFFF1F5F9),
    outlineVariant: border,
    onSurfaceVariant: dark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
  );
  final background = dark ? const Color(0xFF131620) : const Color(0xFFF8FAFC);
  return base.copyWith(
    scaffoldBackgroundColor: background,
    cardColor: surface,
    colorScheme: scheme,
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: border),
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
    ),
  );
}

class PhoneAgentCard extends StatelessWidget {
  const PhoneAgentCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: child,
  );
}

class PhoneAgentButton extends StatelessWidget {
  const PhoneAgentButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: onPressed == null ? null : phoneAgentGradient,
      color: onPressed == null ? Theme.of(context).disabledColor : null,
      borderRadius: BorderRadius.circular(15),
    ),
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white70,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[Icon(icon, size: 17), const SizedBox(width: 6)],
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ),
  );
}
