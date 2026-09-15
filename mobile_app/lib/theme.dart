// ══════════════════════════════════════════════════════════════
//  theme.dart - the Electica design system, ported to Flutter
//
//  Every value below is lifted from the Electica Service app's own
//  stylesheet (assets/public/assets/index-*.css inside its APK), so the
//  gateway monitor reads as the same product rather than a cousin of it.
//  The CSS custom property each token came from is named beside it.
//
//  This file carries appearance only. No widget behaviour, no state, no
//  feature of the monitor is defined or altered here.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Font families ─────────────────────────────────────────────
//
// Both families are bundled as real .ttf files under assets/fonts/, which
// is the whole point: a bare `fontFamily: 'monospace'` is not a font, it is
// a request the platform answers however it likes. Samsung, Xiaomi and
// Pixel each substitute a different face, at different weights, so the
// digits in a voltage reading changed shape from phone to phone. Shipping
// the files makes every device render identically.

class AppFonts {
  /// UI face - Inter. Same family the Electica app loads.
  static const String ui = 'Inter';

  /// Data face - IBM Plex Mono, the CSS `--mono` stack's first choice.
  /// Used for anything the eye has to compare column-wise: voltages, cell
  /// millivolts, register words, timestamps, log lines.
  static const String mono = 'IBMPlexMono';
}

// ── Corner radii: --r-xs, --r-sm, --r, --r-lg, --r-full ───────
class AppRadius {
  static const double xs = 9;
  static const double sm = 13;
  static const double md = 18;
  static const double lg = 24;
  static const double full = 999;

  static const BorderRadius rXs = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius rSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius rMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius rLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius rFull = BorderRadius.all(Radius.circular(full));
}

// ── Type scale: --f-2xs .. --f-xl ─────────────────────────────
class AppSize {
  static const double f2xs = 10;
  static const double fxs = 11;
  static const double fsm = 13;
  static const double fmd = 15;
  static const double flg = 17;
  static const double fxl = 22;
}

/// Tracking values from the stylesheet. Inter is drawn tight, so headings
/// pull in slightly and small uppercase labels open up - that contrast is
/// most of what makes the original app look deliberate.
class AppTracking {
  static const double tight = -0.01 * AppSize.flg;   // .topbar-title
  static const double mono = -0.02 * AppSize.fsm;    // .mono
  static const double metric = -0.03 * AppSize.fxl;  // .pod-metric-soc
  static const double chip = 0.05 * AppSize.f2xs;    // .chip
  static const double label = 0.06 * AppSize.f2xs;   // .field label
  static const double caps = 0.08 * AppSize.f2xs;    // .topbar-sub
  static const double section = 0.15 * AppSize.f2xs; // .section-label
}

// ══════════════════════════════════════════════════════════════
//  Token set - one instance per theme
// ══════════════════════════════════════════════════════════════

@immutable
class AppTokens {
  // Surfaces: --bg, --surface, --card, --card-2, --elevated
  final Color bg, surface, card, card2, elevated;
  // Lines: --border, --border-light, --hairline
  final Color border, borderLight, hairline;
  // Text: --text, --text-mid, --text-soft, --text-faint
  final Color text, textMid, textSoft, textFaint;
  // Accent ramp: --gold, --gold-dark, --gold-mid, --gold-light, --gold-border, --gold-glow
  final Color gold, goldDark, goldMid, goldLight, goldBorder, goldGlow;
  // Status ramps: --green / --amber / --red / --blue plus -light and -border
  final Color green, greenLight, greenBorder;
  final Color amber, amberLight, amberBorder;
  final Color red, redLight, redBorder;
  final Color blue, blueLight, blueBorder;
  // Ink on top of a gold-filled button (.btn-primary color)
  final Color onGold;
  // Console / log surface (.console background)
  final Color console;

  final List<BoxShadow> shadowSm; // --shadow-sm
  final List<BoxShadow> shadow;   // --shadow
  final List<BoxShadow> shadowGold; // --shadow-gold
  final Gradient sheen;           // --sheen

  const AppTokens({
    required this.bg,
    required this.surface,
    required this.card,
    required this.card2,
    required this.elevated,
    required this.border,
    required this.borderLight,
    required this.hairline,
    required this.text,
    required this.textMid,
    required this.textSoft,
    required this.textFaint,
    required this.gold,
    required this.goldDark,
    required this.goldMid,
    required this.goldLight,
    required this.goldBorder,
    required this.goldGlow,
    required this.green,
    required this.greenLight,
    required this.greenBorder,
    required this.amber,
    required this.amberLight,
    required this.amberBorder,
    required this.red,
    required this.redLight,
    required this.redBorder,
    required this.blue,
    required this.blueLight,
    required this.blueBorder,
    required this.onGold,
    required this.console,
    required this.shadowSm,
    required this.shadow,
    required this.shadowGold,
    required this.sheen,
  });

  /// `:root` in the stylesheet - the app's default appearance.
  static const AppTokens dark = AppTokens(
    bg: Color(0xFF0D0D0F),
    surface: Color(0xFF17171C),
    card: Color(0xFF17171C),
    card2: Color(0xFF1E1E25),
    elevated: Color(0xFF202028),
    border: Color(0x17FFFFFF),        // rgba(255,255,255,.09)
    borderLight: Color(0x0DFFFFFF),   // rgba(255,255,255,.05)
    hairline: Color(0x0FFFFFFF),      // rgba(255,255,255,.06)
    text: Color(0xFFFFFFFF),
    textMid: Color(0x9EFFFFFF),       // rgba(255,255,255,.62)
    textSoft: Color(0x57FFFFFF),      // rgba(255,255,255,.34)
    textFaint: Color(0x2EFFFFFF),     // rgba(255,255,255,.18)
    gold: Color(0xFFC9A96E),
    goldDark: Color(0xFFA8874A),
    goldMid: Color(0xFFD4B878),
    goldLight: Color(0x1FC9A96E),     // rgba(201,169,110,.12)
    goldBorder: Color(0x38C9A96E),    // rgba(201,169,110,.22)
    goldGlow: Color(0x59C9A96E),      // rgba(201,169,110,.35)
    green: Color(0xFF22D3A4),
    greenLight: Color(0x1A22D3A4),
    greenBorder: Color(0x3D22D3A4),
    amber: Color(0xFFF59E0B),
    amberLight: Color(0x1AF59E0B),
    amberBorder: Color(0x3DF59E0B),
    red: Color(0xFFFF6B6B),
    redLight: Color(0x1AFF6B6B),
    redBorder: Color(0x42FF6B6B),
    blue: Color(0xFF818CF8),
    blueLight: Color(0x1A818CF8),
    blueBorder: Color(0x3D818CF8),
    onGold: Color(0xFF17110A),
    console: Color(0xFF08080A),
    shadowSm: [
      BoxShadow(color: Color(0x59000000), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x47000000), blurRadius: 10, offset: Offset(0, 3)),
    ],
    shadow: [
      BoxShadow(color: Color(0x59000000), blurRadius: 6, offset: Offset(0, 2)),
      BoxShadow(color: Color(0x7A000000), blurRadius: 34, offset: Offset(0, 14)),
    ],
    shadowGold: [
      BoxShadow(color: Color(0x4DC9A96E), blurRadius: 22, offset: Offset(0, 6)),
    ],
    sheen: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0x09FFFFFF), Color(0x02FFFFFF), Color(0x00FFFFFF)],
      stops: [0.0, 0.4, 1.0],
    ),
  );

  /// `:root[data-theme=light]`. Note the accent is not a lighter gold but a
  /// warm terracotta - gold on white reads as washed-out beige, so the
  /// original design swaps hue rather than lightness. Kept as-is.
  static const AppTokens light = AppTokens(
    bg: Color(0xFFF7F6F3),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    card2: Color(0xFFF4F3EF),
    elevated: Color(0xFFFFFFFF),
    border: Color(0xFFE5E7EB),
    borderLight: Color(0xFFF1F0EC),
    hairline: Color(0xB3FFFFFF),      // rgba(255,255,255,.7)
    text: Color(0xFF111827),
    textMid: Color(0xFF4B5563),
    textSoft: Color(0xFF9CA3AF),
    textFaint: Color(0xFFC7CCD4),
    gold: Color(0xFFD4654A),
    goldDark: Color(0xFFB8533A),
    goldMid: Color(0xFFE8775C),
    goldLight: Color(0x1AD4654A),     // rgba(212,101,74,.1)
    goldBorder: Color(0x38D4654A),    // rgba(212,101,74,.22)
    goldGlow: Color(0x4DD4654A),      // rgba(212,101,74,.3)
    green: Color(0xFF15803D),
    greenLight: Color(0x1A15803D),
    greenBorder: Color(0x3D15803D),
    amber: Color(0xFFB45309),
    amberLight: Color(0x1AB45309),
    amberBorder: Color(0x42B45309),
    red: Color(0xFFDC2626),
    redLight: Color(0x14DC2626),
    redBorder: Color(0x38DC2626),
    blue: Color(0xFF4F46E5),
    blueLight: Color(0x144F46E5),
    blueBorder: Color(0x384F46E5),
    onGold: Color(0xFFFFFFFF),
    console: Color(0xFFFAF9F6),
    shadowSm: [
      BoxShadow(color: Color(0x0A111827), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x0F111827), blurRadius: 12, offset: Offset(0, 4)),
    ],
    shadow: [
      BoxShadow(color: Color(0x0F111827), blurRadius: 8, offset: Offset(0, 2)),
      BoxShadow(color: Color(0x1A111827), blurRadius: 40, offset: Offset(0, 16)),
    ],
    shadowGold: [
      BoxShadow(color: Color(0x47D4654A), blurRadius: 18, offset: Offset(0, 6)),
    ],
    sheen: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0x8CFFFFFF), Color(0x00FFFFFF), Color(0x00FFFFFF)],
      stops: [0.0, 0.6, 1.0],
    ),
  );

  /// The gold fill behind a primary button (`.btn-primary`).
  LinearGradient get goldFill => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: onGold == const Color(0xFFFFFFFF)
            ? [goldMid, goldDark]
            : [const Color(0xFFE9CD8E), gold, goldDark],
        stops: onGold == const Color(0xFFFFFFFF) ? null : const [0.0, 0.48, 1.0],
      );

  /// Page backdrop (`body` radial gradient in dark, `#app` linear in light).
  Gradient get backdrop => onGold == const Color(0xFFFFFFFF)
      ? const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFBFAF8), Color(0xFFF7F6F3)],
          stops: [0.0, 0.28],
        )
      : const RadialGradient(
          center: Alignment(0.0, -1.16),
          radius: 1.1,
          colors: [Color(0xFF131218), Color(0xFF08080A), Color(0xFF050506)],
          stops: [0.0, 0.46, 1.0],
        );
}

/// Active token set. `light` is kept in step by the theme builder in
/// main.dart, mirroring how `Palette` already tracks the active theme, so
/// widgets can read tokens without threading a BuildContext everywhere.
class Tone {
  static bool light = false;
  static AppTokens get t => light ? AppTokens.light : AppTokens.dark;

  /// Prefer this inside a build method - it follows the real widget theme
  /// rather than the global flag.
  static AppTokens of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
          ? AppTokens.light
          : AppTokens.dark;
}

// ══════════════════════════════════════════════════════════════
//  Reusable text styles, straight off the stylesheet's classes
// ══════════════════════════════════════════════════════════════

class AppText {
  /// `.section-label` - wide-tracked uppercase divider above a group.
  static TextStyle sectionLabel([AppTokens? t]) => TextStyle(
        fontFamily: AppFonts.ui,
        fontSize: AppSize.f2xs,
        fontWeight: FontWeight.w700,
        color: (t ?? Tone.t).textSoft,
        letterSpacing: AppTracking.section,
      );

  /// `.topbar-sub` - small caps subtitle.
  static TextStyle caps([AppTokens? t]) => TextStyle(
        fontFamily: AppFonts.ui,
        fontSize: AppSize.f2xs,
        fontWeight: FontWeight.w600,
        color: (t ?? Tone.t).textSoft,
        letterSpacing: AppTracking.caps,
      );

  /// `.pod-metric-soc` - the one big number on a card.
  static TextStyle metric(Color color) => TextStyle(
        fontFamily: AppFonts.mono,
        fontSize: AppSize.fxl,
        fontWeight: FontWeight.w800,
        color: color,
        letterSpacing: AppTracking.metric,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// `.mono` - any figure meant to be compared down a column.
  static TextStyle mono({
    double size = AppSize.fsm,
    FontWeight weight = FontWeight.w400,
    Color? color,
  }) =>
      TextStyle(
        fontFamily: AppFonts.mono,
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: AppTracking.mono,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

// ══════════════════════════════════════════════════════════════
//  ThemeData
// ══════════════════════════════════════════════════════════════

/// Inter's default tracking is loose for a dense instrument UI. These
/// values follow the stylesheet: pull in as size grows, open up as it
/// shrinks.
TextTheme _interTextTheme(AppTokens t) {
  TextStyle s(double size, FontWeight w, double tracking, {Color? c}) => TextStyle(
        fontFamily: AppFonts.ui,
        fontSize: size,
        fontWeight: w,
        letterSpacing: tracking,
        color: c ?? t.text,
        height: 1.35,
      );

  return TextTheme(
    displayLarge: s(34, FontWeight.w800, -0.8),
    displayMedium: s(28, FontWeight.w800, -0.6),
    displaySmall: s(24, FontWeight.w800, -0.5),
    headlineLarge: s(AppSize.fxl, FontWeight.w800, -0.4),
    headlineMedium: s(19, FontWeight.w700, -0.3),
    headlineSmall: s(AppSize.flg, FontWeight.w800, AppTracking.tight),
    titleLarge: s(AppSize.flg, FontWeight.w700, -0.2),
    titleMedium: s(AppSize.fmd, FontWeight.w700, -0.1),
    titleSmall: s(AppSize.fsm, FontWeight.w700, 0),
    bodyLarge: s(AppSize.fmd, FontWeight.w400, 0, c: t.text),
    bodyMedium: s(AppSize.fsm, FontWeight.w400, 0, c: t.text),
    bodySmall: s(AppSize.fxs, FontWeight.w400, 0.1, c: t.textMid),
    labelLarge: s(AppSize.fsm, FontWeight.w700, 0.1),
    labelMedium: s(AppSize.fxs, FontWeight.w700, AppTracking.label, c: t.textMid),
    labelSmall: s(AppSize.f2xs, FontWeight.w700, AppTracking.chip, c: t.textSoft),
  );
}

ThemeData buildAppTheme(bool dark) {
  final t = dark ? AppTokens.dark : AppTokens.light;
  final brightness = dark ? Brightness.dark : Brightness.light;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: t.gold,
    onPrimary: t.onGold,
    primaryContainer: t.goldLight,
    onPrimaryContainer: t.gold,
    secondary: t.blue,
    onSecondary: dark ? const Color(0xFF0D0D0F) : Colors.white,
    secondaryContainer: t.blueLight,
    onSecondaryContainer: t.blue,
    tertiary: t.green,
    onTertiary: dark ? const Color(0xFF0D0D0F) : Colors.white,
    error: t.red,
    onError: dark ? const Color(0xFF0D0D0F) : Colors.white,
    errorContainer: t.redLight,
    onErrorContainer: t.red,
    surface: t.card,
    onSurface: t.text,
    surfaceContainerLowest: t.bg,
    surfaceContainerLow: t.surface,
    surfaceContainer: t.card,
    surfaceContainerHigh: t.card2,
    surfaceContainerHighest: t.elevated,
    onSurfaceVariant: t.textMid,
    outline: t.border,
    outlineVariant: t.borderLight,
    shadow: Colors.black,
  );

  final text = _interTextTheme(t);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.bg,
    fontFamily: AppFonts.ui,
    textTheme: text,
    primaryTextTheme: text,

    // `.topbar`: flat, sticky, hairline underneath - no Material elevation tint.
    appBarTheme: AppBarTheme(
      backgroundColor: t.bg,
      foregroundColor: t.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.headlineSmall,
      iconTheme: IconThemeData(color: t.gold, size: 22),
      actionsIconTheme: IconThemeData(color: t.gold, size: 22),
      systemOverlayStyle: dark
          ? SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
            )
          : SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark,
            ),
    ),

    // `.card`: 18px radius, 1px border, soft double shadow.
    cardTheme: CardThemeData(
      color: t.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.rMd,
        side: BorderSide(color: t.border),
      ),
    ),

    dividerTheme: DividerThemeData(
      color: t.borderLight,
      thickness: 1,
      space: 1,
    ),

    // `.btn-primary`: gold fill, heavier weight, slight positive tracking.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: t.gold,
        foregroundColor: t.onGold,
        disabledBackgroundColor: t.card2,
        disabledForegroundColor: t.textFaint,
        elevation: 0,
        shadowColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.rSm),
        textStyle: const TextStyle(
          fontFamily: AppFonts.ui,
          fontSize: AppSize.fsm,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.13,
        ),
      ),
    ),

    // `.btn`: neutral surface, hairline border.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: t.card2,
        foregroundColor: t.text,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        side: BorderSide(color: t.border),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.rSm),
        textStyle: const TextStyle(
          fontFamily: AppFonts.ui,
          fontSize: AppSize.fsm,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.gold,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.rXs),
        textStyle: const TextStyle(
          fontFamily: AppFonts.ui,
          fontSize: AppSize.fsm,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.gold,
        foregroundColor: t.onGold,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.rSm),
        textStyle: const TextStyle(
          fontFamily: AppFonts.ui,
          fontSize: AppSize.fsm,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),

    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: t.textMid,
        highlightColor: t.goldLight,
      ),
    ),

    // `.input`: filled, 13px radius, gold focus ring.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.card2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: TextStyle(
        fontFamily: AppFonts.ui,
        fontSize: AppSize.fsm,
        color: t.textSoft,
      ),
      labelStyle: TextStyle(
        fontFamily: AppFonts.ui,
        fontSize: AppSize.fsm,
        color: t.textMid,
      ),
      floatingLabelStyle: TextStyle(
        fontFamily: AppFonts.ui,
        fontSize: AppSize.fsm,
        fontWeight: FontWeight.w700,
        color: t.gold,
      ),
      border: OutlineInputBorder(
        borderRadius: AppRadius.rSm,
        borderSide: BorderSide(color: t.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppRadius.rSm,
        borderSide: BorderSide(color: t.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppRadius.rSm,
        borderSide: BorderSide(color: t.gold, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: AppRadius.rSm,
        borderSide: BorderSide(color: t.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: AppRadius.rSm,
        borderSide: BorderSide(color: t.red, width: 1.5),
      ),
    ),

    // `.chip`: pill, uppercase, tracked.
    chipTheme: ChipThemeData(
      backgroundColor: t.card2,
      selectedColor: t.goldLight,
      disabledColor: t.card2,
      side: BorderSide(color: t.border),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.rFull),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      labelStyle: TextStyle(
        fontFamily: AppFonts.ui,
        fontSize: AppSize.f2xs,
        fontWeight: FontWeight.w700,
        color: t.textMid,
        letterSpacing: AppTracking.chip,
      ),
    ),

    // `.nav`: gold for the active destination, muted for the rest.
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: t.surface,
      selectedItemColor: t.gold,
      unselectedItemColor: t.textSoft,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      selectedLabelStyle: const TextStyle(
        fontFamily: AppFonts.ui,
        fontSize: AppSize.f2xs,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelStyle: const TextStyle(
        fontFamily: AppFonts.ui,
        fontSize: AppSize.f2xs,
        fontWeight: FontWeight.w700,
      ),
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: t.goldLight,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: AppFonts.ui,
          fontSize: AppSize.f2xs,
          fontWeight: FontWeight.w700,
          color: s.contains(WidgetState.selected) ? t.gold : t.textSoft,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? t.gold : t.textSoft,
          size: 22,
        ),
      ),
    ),

    tabBarTheme: TabBarThemeData(
      labelColor: t.gold,
      unselectedLabelColor: t.textSoft,
      indicatorColor: t.gold,
      dividerColor: t.borderLight,
      labelStyle: const TextStyle(
        fontFamily: AppFonts.ui,
        fontSize: AppSize.fxs,
        fontWeight: FontWeight.w800,
        letterSpacing: AppTracking.chip,
      ),
      unselectedLabelStyle: const TextStyle(
        fontFamily: AppFonts.ui,
        fontSize: AppSize.fxs,
        fontWeight: FontWeight.w700,
        letterSpacing: AppTracking.chip,
      ),
    ),

    // `.toast`
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.elevated,
      contentTextStyle: TextStyle(
        fontFamily: AppFonts.ui,
        fontSize: AppSize.fsm,
        fontWeight: FontWeight.w600,
        color: t.text,
      ),
      actionTextColor: t.gold,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.rSm),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: t.elevated,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.rMd,
        side: BorderSide(color: t.border),
      ),
      titleTextStyle: text.titleMedium,
      contentTextStyle: text.bodyMedium?.copyWith(color: t.textMid),
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.elevated,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
    ),

    listTileTheme: ListTileThemeData(
      iconColor: t.textSoft,
      textColor: t.text,
      titleTextStyle: text.titleSmall,
      subtitleTextStyle: text.bodySmall,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.rSm),
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.onGold : t.textSoft,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.gold : t.card2,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.transparent : t.border,
      ),
    ),

    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.gold : Colors.transparent,
      ),
      checkColor: WidgetStateProperty.all(t.onGold),
      side: BorderSide(color: t.border, width: 1.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
      ),
    ),

    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.gold : t.textSoft,
      ),
    ),

    sliderTheme: SliderThemeData(
      activeTrackColor: t.gold,
      inactiveTrackColor: t.card2,
      thumbColor: t.gold,
      overlayColor: t.goldLight,
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: t.gold,
      linearTrackColor: t.card2,
      circularTrackColor: t.card2,
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: t.elevated,
        borderRadius: AppRadius.rXs,
        border: Border.all(color: t.border),
      ),
      textStyle: TextStyle(
        fontFamily: AppFonts.ui,
        fontSize: AppSize.fxs,
        color: t.text,
      ),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: t.elevated,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.rSm,
        side: BorderSide(color: t.border),
      ),
      textStyle: text.bodyMedium,
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: t.gold,
      foregroundColor: t.onGold,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.rMd),
    ),

    iconTheme: IconThemeData(color: t.textMid, size: 20),
    splashFactory: InkSparkle.splashFactory,
    highlightColor: t.goldLight,
    dividerColor: t.borderLight,
  );
}

// ══════════════════════════════════════════════════════════════
//  Small decoration helpers - the stylesheet's `.card`, `.chip`
//  and status-tint rules, ready to drop into a Container.
// ══════════════════════════════════════════════════════════════

/// `.card` - sheen over surface, hairline border, soft shadow.
BoxDecoration appCard(AppTokens t, {BorderRadius? radius, Color? borderColor}) =>
    BoxDecoration(
      color: t.card,
      gradient: t.sheen,
      borderRadius: radius ?? AppRadius.rMd,
      border: Border.all(color: borderColor ?? t.border),
      boxShadow: t.shadowSm,
    );

/// `.banner` / `.chip` status tint - a 10% wash with a matching border.
BoxDecoration appTint(Color tint, {BorderRadius? radius, double fill = 0.10, double line = 0.24}) =>
    BoxDecoration(
      color: tint.withValues(alpha: fill),
      borderRadius: radius ?? AppRadius.rMd,
      border: Border.all(color: tint.withValues(alpha: line)),
    );

/// `.btn-primary` - gold gradient with its glow.
BoxDecoration appGoldFill(AppTokens t, {BorderRadius? radius}) => BoxDecoration(
      gradient: t.goldFill,
      borderRadius: radius ?? AppRadius.rSm,
      boxShadow: t.shadowGold,
    );
