import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Colour roles used across the app. Kept as a value type so a light and a
/// dark instance can be swapped wholesale rather than branching per widget.
class AppColors {
  final Color bg, card, cardAlt, border, accent, text, textDim;
  final Color success, warn, danger, info;
  final Color volt, curr, soc, soh, temp, cycle, cap;
  final Color bayA, bayB;
  final Color logBg;

  const AppColors({
    required this.bg,
    required this.card,
    required this.cardAlt,
    required this.border,
    required this.accent,
    required this.text,
    required this.textDim,
    required this.success,
    required this.warn,
    required this.danger,
    required this.info,
    required this.volt,
    required this.curr,
    required this.soc,
    required this.soh,
    required this.temp,
    required this.cycle,
    required this.cap,
    required this.bayA,
    required this.bayB,
    required this.logBg,
  });
}

const _dark = AppColors(
  bg: Color(0xFF0B1220),
  card: Color(0xFF141F30),
  cardAlt: Color(0xFF1B2942),
  border: Color(0xFF25354D),
  accent: Color(0xFF00D4AA),
  text: Color(0xFFE3ECF7),
  textDim: Color(0xFF8296AE),
  success: Color(0xFF00CC66),
  warn: Color(0xFFFFAA00),
  danger: Color(0xFFFF4D4D),
  info: Color(0xFF4FC3F7),
  volt: Color(0xFF4FC3F7),
  curr: Color(0xFFFFB74D),
  soc: Color(0xFF66D97A),
  soh: Color(0xFFCE93D8),
  temp: Color(0xFFEF5350),
  cycle: Color(0xFF90A4AE),
  cap: Color(0xFF4DD0E1),
  bayA: Color(0xFF4FC3F7),
  bayB: Color(0xFFFFB74D),
  logBg: Color(0xFF060B14),
);

const _light = AppColors(
  bg: Color(0xFFF1F5FA),
  card: Color(0xFFFFFFFF),
  cardAlt: Color(0xFFE9EFF7),
  border: Color(0xFFD2DCE8),
  accent: Color(0xFF00A882),
  text: Color(0xFF16202E),
  textDim: Color(0xFF5A7080),
  success: Color(0xFF00A855),
  warn: Color(0xFFD98A00),
  danger: Color(0xFFDE3333),
  info: Color(0xFF0288D1),
  volt: Color(0xFF0288D1),
  curr: Color(0xFFEF6C00),
  soc: Color(0xFF2E9E45),
  soh: Color(0xFF7B1FA2),
  temp: Color(0xFFD32F2F),
  cycle: Color(0xFF546E7A),
  cap: Color(0xFF00838F),
  bayA: Color(0xFF0288D1),
  bayB: Color(0xFFEF6C00),
  logBg: Color(0xFFE2E9F2),
);

/// Drives a full-app rebuild when the user flips the theme.
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.dark);

/// Static accessor so widgets read `P.accent` without threading context.
class P {
  static AppColors get c =>
      themeModeNotifier.value == ThemeMode.light ? _light : _dark;

  static Color get bg => c.bg;
  static Color get card => c.card;
  static Color get cardAlt => c.cardAlt;
  static Color get border => c.border;
  static Color get accent => c.accent;
  static Color get text => c.text;
  static Color get textDim => c.textDim;
  static Color get success => c.success;
  static Color get warn => c.warn;
  static Color get danger => c.danger;
  static Color get info => c.info;
  static Color get volt => c.volt;
  static Color get curr => c.curr;
  static Color get soc => c.soc;
  static Color get soh => c.soh;
  static Color get temp => c.temp;
  static Color get cycle => c.cycle;
  static Color get cap => c.cap;
  static Color get bayA => c.bayA;
  static Color get bayB => c.bayB;
  static Color get logBg => c.logBg;

  /// SOC-driven colour ramp, shared by gauges, tiles and charts so a battery
  /// reads the same everywhere in the app.
  static Color socColor(double soc) {
    if (soc >= 80) return c.success;
    if (soc >= 40) return c.soc;
    if (soc >= 20) return c.warn;
    return c.danger;
  }
}

Future<void> loadSavedTheme() async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getString('chg_theme') == 'light') {
    themeModeNotifier.value = ThemeMode.light;
  }
}

Future<void> setTheme(ThemeMode mode) async {
  themeModeNotifier.value = mode;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
      'chg_theme', mode == ThemeMode.light ? 'light' : 'dark');
}

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.light ? _light : _dark;
  return ThemeData(
    brightness: brightness,
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    cardColor: c.card,
    dividerColor: c.border,
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.accent,
      brightness: brightness,
      surface: c.card,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.card,
      foregroundColor: c.text,
      elevation: 0,
      centerTitle: false,
    ),
    // Styled here rather than per-Switch: the thumb/track property names on the
    // widget have churned across Flutter releases, the theme hooks have not.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.accent : c.textDim),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? c.accent.withValues(alpha: 0.35)
              : c.cardAlt),
    ),
    useMaterial3: true,
  );
}
