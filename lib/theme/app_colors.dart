import 'package:flutter/material.dart';

import 'brand_config.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color page;
  final Color surface;
  final Color input;
  final Color inputHint;
  final Color outline;
  final Color primary;
  final Color onPrimary;
  final Color text;
  final Color muted;
  final Color navigation;
  final Color chatbotSurface;
  final Color chatbotForeground;
  final Color glowStart;
  final Color glowMiddle;
  final Color glowEnd;
  final Color glowHighlight;
  final List<Color> toolAccents;

  const AppColors({
    required this.page,
    required this.surface,
    required this.input,
    required this.inputHint,
    required this.outline,
    required this.primary,
    required this.onPrimary,
    required this.text,
    required this.muted,
    required this.navigation,
    required this.chatbotSurface,
    required this.chatbotForeground,
    required this.glowStart,
    required this.glowMiddle,
    required this.glowEnd,
    required this.glowHighlight,
    required this.toolAccents,
  });

  static const dark = AppColors(
    page: Color(BrandConfig.background),
    surface: Color(BrandConfig.surface),
    input: Color(BrandConfig.surface),
    inputHint: Color(0xFF818898),
    outline: Color(0xFF2C3246),
    primary: Color(BrandConfig.primary),
    onPrimary: Colors.white,
    text: Color(BrandConfig.text),
    muted: Color(0xFF818898),
    navigation: Color(0xFF171B28),
    chatbotSurface: Color(BrandConfig.surface),
    chatbotForeground: Colors.white,
    glowStart: Color(0xFF4F46E5),
    glowMiddle: Color(0xFFF472B6),
    glowEnd: Color(0xFF06B6D4),
    glowHighlight: Color(0xFF38BDF8),
    toolAccents: [
      Color(0xFF6366F1),
      Color(0xFF38BDF8),
      Color(0xFFF472B6),
      Color(0xFF10B981),
      Color(0xFFF59E0B),
      Color(0xFFA78BFA),
    ],
  );

  static const light = AppColors(
    page: Color(0xFFF8FAFC),
    surface: Colors.white,
    input: Color(0xFFF1F5F9),
    inputHint: Color(0xFF475569),
    outline: Color(0xFFE2E8F0),
    primary: Color(BrandConfig.primary),
    onPrimary: Colors.white,
    text: Color(0xFF0F172A),
    muted: Color(0xFF64748B),
    navigation: Colors.white,
    chatbotSurface: Color(BrandConfig.surface),
    chatbotForeground: Colors.white,
    glowStart: Color(0xFF4F46E5),
    glowMiddle: Color(0xFFF472B6),
    glowEnd: Color(0xFF06B6D4),
    glowHighlight: Color(0xFF38BDF8),
    toolAccents: [
      Color(0xFF4F46E5),
      Color(0xFF0369A1),
      Color(0xFFBE185D),
      Color(0xFF047857),
      Color(0xFFB45309),
      Color(0xFF7C3AED),
    ],
  );

  static AppColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  Color toolAccent(String key) {
    var hash = 0;
    for (final unit in key.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return toolAccents[hash % toolAccents.length];
  }

  @override
  AppColors copyWith({
    Color? page,
    Color? surface,
    Color? input,
    Color? inputHint,
    Color? outline,
    Color? primary,
    Color? onPrimary,
    Color? text,
    Color? muted,
    Color? navigation,
    Color? chatbotSurface,
    Color? chatbotForeground,
    Color? glowStart,
    Color? glowMiddle,
    Color? glowEnd,
    Color? glowHighlight,
    List<Color>? toolAccents,
  }) => AppColors(
    page: page ?? this.page,
    surface: surface ?? this.surface,
    input: input ?? this.input,
    inputHint: inputHint ?? this.inputHint,
    outline: outline ?? this.outline,
    primary: primary ?? this.primary,
    onPrimary: onPrimary ?? this.onPrimary,
    text: text ?? this.text,
    muted: muted ?? this.muted,
    navigation: navigation ?? this.navigation,
    chatbotSurface: chatbotSurface ?? this.chatbotSurface,
    chatbotForeground: chatbotForeground ?? this.chatbotForeground,
    glowStart: glowStart ?? this.glowStart,
    glowMiddle: glowMiddle ?? this.glowMiddle,
    glowEnd: glowEnd ?? this.glowEnd,
    glowHighlight: glowHighlight ?? this.glowHighlight,
    toolAccents: toolAccents ?? this.toolAccents,
  );

  static Color _lerpColor(Color first, Color second, double t) =>
      first == second ? first : Color.lerp(first, second, t)!;

  @override
  AppColors lerp(covariant AppColors? other, double t) {
    if (other == null || t <= 0) return this;
    if (t >= 1) return other;
    return AppColors(
      page: _lerpColor(page, other.page, t),
      surface: _lerpColor(surface, other.surface, t),
      input: _lerpColor(input, other.input, t),
      inputHint: _lerpColor(inputHint, other.inputHint, t),
      outline: _lerpColor(outline, other.outline, t),
      primary: _lerpColor(primary, other.primary, t),
      onPrimary: _lerpColor(onPrimary, other.onPrimary, t),
      text: _lerpColor(text, other.text, t),
      muted: _lerpColor(muted, other.muted, t),
      navigation: _lerpColor(navigation, other.navigation, t),
      chatbotSurface: _lerpColor(chatbotSurface, other.chatbotSurface, t),
      chatbotForeground: _lerpColor(
        chatbotForeground,
        other.chatbotForeground,
        t,
      ),
      glowStart: _lerpColor(glowStart, other.glowStart, t),
      glowMiddle: _lerpColor(glowMiddle, other.glowMiddle, t),
      glowEnd: _lerpColor(glowEnd, other.glowEnd, t),
      glowHighlight: _lerpColor(glowHighlight, other.glowHighlight, t),
      toolAccents: [
        for (var i = 0; i < toolAccents.length; i++)
          Color.lerp(
            toolAccents[i],
            other.toolAccents[i % other.toolAccents.length],
            t,
          )!,
      ],
    );
  }
}
