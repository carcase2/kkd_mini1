import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// 테마별 팔레트 (라이트 / 다크)
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  final Color bg;
  final Color surface;
  final Color surfaceElevated;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color fasting;
  final Color fastingSoft;
  final Color abstinence;
  final Color abstinenceSoft;
  final Color check;
  final Color checkSoft;
  final Color reading;
  final Color readingSoft;
  final Color success;
  final Color successSoft;
  final Color danger;
  final Color dangerSoft;
  final Color warning;
  final Color warningSoft;
  final Color shadow;
  final Color navBar;
  final Color chipBg;

  const AppPalette({
    required this.bg,
    required this.surface,
    required this.surfaceElevated,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.fasting,
    required this.fastingSoft,
    required this.abstinence,
    required this.abstinenceSoft,
    required this.check,
    required this.checkSoft,
    required this.reading,
    required this.readingSoft,
    required this.success,
    required this.successSoft,
    required this.danger,
    required this.dangerSoft,
    required this.warning,
    required this.warningSoft,
    required this.shadow,
    required this.navBar,
    required this.chipBg,
  });

  /// 라이트 — 기본
  static const light = AppPalette(
    bg: Color(0xFFF4F6FA),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFFFFFFF),
    border: Color(0xFFE6EAF0),
    textPrimary: Color(0xFF1A1F2C),
    textSecondary: Color(0xFF5C677A),
    textMuted: Color(0xFF94A0B4),
    fasting: Color(0xFF3B82F6),
    fastingSoft: Color(0xFFE8F1FF),
    abstinence: Color(0xFF7C6BFF),
    abstinenceSoft: Color(0xFFF0EDFF),
    check: Color(0xFFEF476F),
    checkSoft: Color(0xFFFFE9EF),
    reading: Color(0xFF0D9488),
    readingSoft: Color(0xFFE6F7F5),
    success: Color(0xFF10B981),
    successSoft: Color(0xFFE6F8F1),
    danger: Color(0xFFEF4444),
    dangerSoft: Color(0xFFFEECEC),
    warning: Color(0xFFF59E0B),
    warningSoft: Color(0xFFFEF5E6),
    shadow: Color(0x140A1628),
    navBar: Color(0xFFFFFFFF),
    chipBg: Color(0xFFF0F3F8),
  );

  /// 다크
  static const dark = AppPalette(
    bg: Color(0xFF0C1017),
    surface: Color(0xFF151B24),
    surfaceElevated: Color(0xFF1C2430),
    border: Color(0xFF2A3544),
    textPrimary: Color(0xFFF2F5F8),
    textSecondary: Color(0xFF9AA8B8),
    textMuted: Color(0xFF6B7A8C),
    fasting: Color(0xFF5B9DFF),
    fastingSoft: Color(0xFF1A2F4A),
    abstinence: Color(0xFF8B7CFF),
    abstinenceSoft: Color(0xFF241F45),
    check: Color(0xFFFF6B8A),
    checkSoft: Color(0xFF3A1F2A),
    reading: Color(0xFF2DD4BF),
    readingSoft: Color(0xFF12352F),
    success: Color(0xFF3DDC97),
    successSoft: Color(0xFF143528),
    danger: Color(0xFFFF5C5C),
    dangerSoft: Color(0xFF3A1A1A),
    warning: Color(0xFFFFB020),
    warningSoft: Color(0xFF3A2A10),
    shadow: Color(0x66000000),
    navBar: Color(0xFF151B24),
    chipBg: Color(0xFF1C2430),
  );

  static AppPalette of(BuildContext context) {
    return Theme.of(context).extension<AppPalette>() ?? AppPalette.light;
  }

  @override
  AppPalette copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceElevated,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? fasting,
    Color? fastingSoft,
    Color? abstinence,
    Color? abstinenceSoft,
    Color? check,
    Color? checkSoft,
    Color? reading,
    Color? readingSoft,
    Color? success,
    Color? successSoft,
    Color? danger,
    Color? dangerSoft,
    Color? warning,
    Color? warningSoft,
    Color? shadow,
    Color? navBar,
    Color? chipBg,
  }) {
    return AppPalette(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      fasting: fasting ?? this.fasting,
      fastingSoft: fastingSoft ?? this.fastingSoft,
      abstinence: abstinence ?? this.abstinence,
      abstinenceSoft: abstinenceSoft ?? this.abstinenceSoft,
      check: check ?? this.check,
      checkSoft: checkSoft ?? this.checkSoft,
      reading: reading ?? this.reading,
      readingSoft: readingSoft ?? this.readingSoft,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      shadow: shadow ?? this.shadow,
      navBar: navBar ?? this.navBar,
      chipBg: chipBg ?? this.chipBg,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      fasting: Color.lerp(fasting, other.fasting, t)!,
      fastingSoft: Color.lerp(fastingSoft, other.fastingSoft, t)!,
      abstinence: Color.lerp(abstinence, other.abstinence, t)!,
      abstinenceSoft: Color.lerp(abstinenceSoft, other.abstinenceSoft, t)!,
      check: Color.lerp(check, other.check, t)!,
      checkSoft: Color.lerp(checkSoft, other.checkSoft, t)!,
      reading: Color.lerp(reading, other.reading, t)!,
      readingSoft: Color.lerp(readingSoft, other.readingSoft, t)!,
      success: Color.lerp(success, other.success, t)!,
      successSoft: Color.lerp(successSoft, other.successSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      navBar: Color.lerp(navBar, other.navBar, t)!,
      chipBg: Color.lerp(chipBg, other.chipBg, t)!,
    );
  }
}

/// 기존 `AppColors.xxx` 호출을 현재 테마 팔레트에 연결
/// MaterialApp builder에서 [bind] 호출 필요
class AppColors {
  static AppPalette _p = AppPalette.light;

  static void bind(AppPalette palette) {
    _p = palette;
  }

  static Color get bg => _p.bg;
  static Color get surface => _p.surface;
  static Color get surfaceElevated => _p.surfaceElevated;
  static Color get border => _p.border;
  static Color get textPrimary => _p.textPrimary;
  static Color get textSecondary => _p.textSecondary;
  static Color get textMuted => _p.textMuted;
  static Color get fasting => _p.fasting;
  static Color get fastingSoft => _p.fastingSoft;
  static Color get abstinence => _p.abstinence;
  static Color get abstinenceSoft => _p.abstinenceSoft;
  static Color get check => _p.check;
  static Color get checkSoft => _p.checkSoft;
  static Color get reading => _p.reading;
  static Color get readingSoft => _p.readingSoft;
  static Color get success => _p.success;
  static Color get successSoft => _p.successSoft;
  static Color get danger => _p.danger;
  static Color get dangerSoft => _p.dangerSoft;
  static Color get warning => _p.warning;
  static Color get warningSoft => _p.warningSoft;
  static Color get shadow => _p.shadow;
  static Color get navBar => _p.navBar;
  static Color get chipBg => _p.chipBg;
}

class AppTheme {
  static ThemeData get light => _build(Brightness.light, AppPalette.light);
  static ThemeData get dark => _build(Brightness.dark, AppPalette.dark);

  static ThemeData _build(Brightness brightness, AppPalette p) {
    final isDark = brightness == Brightness.dark;
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: p.bg,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: p.fasting,
        onPrimary: Colors.white,
        secondary: p.abstinence,
        onSecondary: Colors.white,
        error: p.danger,
        onError: Colors.white,
        surface: p.surface,
        onSurface: p.textPrimary,
      ),
    );

    final textTheme = GoogleFonts.notoSansKrTextTheme(base.textTheme).apply(
      bodyColor: p.textPrimary,
      displayColor: p.textPrimary,
    );

    return base.copyWith(
      extensions: [p],
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.notoSansKr(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: p.textPrimary,
        ),
        iconTheme: IconThemeData(color: p.textPrimary),
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: p.border),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.navBar,
        indicatorColor: p.fasting.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.notoSansKr(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? p.fasting : p.textMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? p.fasting : p.textMuted,
            size: 22,
          );
        }),
        elevation: 0,
        height: 70,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: GoogleFonts.notoSansKr(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: p.textPrimary,
        ),
        contentTextStyle: GoogleFonts.notoSansKr(
          fontSize: 14,
          color: p.textSecondary,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surfaceElevated,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? p.surfaceElevated : const Color(0xFF1A1F2C),
        contentTextStyle: GoogleFonts.notoSansKr(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(color: p.border),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.chipBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.fasting, width: 1.5),
        ),
        labelStyle: TextStyle(color: p.textSecondary),
        hintStyle: TextStyle(color: p.textMuted),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: p.surfaceElevated,
        headerBackgroundColor: p.fasting,
        headerForegroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        dayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          if (states.contains(WidgetState.disabled)) return p.textMuted;
          return p.textPrimary;
        }),
        todayForegroundColor: WidgetStateProperty.all(p.fasting),
        todayBorder: BorderSide(color: p.fasting),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: p.surfaceElevated,
        hourMinuteTextColor: p.textPrimary,
        hourMinuteColor: p.chipBg,
        dayPeriodTextColor: p.textPrimary,
        dayPeriodColor: p.chipBg,
        dialBackgroundColor: p.chipBg,
        dialHandColor: p.fasting,
        dialTextColor: WidgetStateColor.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return p.textPrimary;
        }),
        entryModeIconColor: p.textSecondary,
        helpTextStyle: TextStyle(
          color: p.textSecondary,
          fontWeight: FontWeight.w600,
        ),
        hourMinuteTextStyle: TextStyle(
          color: p.textPrimary,
          fontSize: 40,
          fontWeight: FontWeight.w700,
        ),
        dayPeriodTextStyle: TextStyle(
          color: p.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  static SystemUiOverlayStyle overlay(bool isDark) {
    return isDark
        ? const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            systemNavigationBarColor: Color(0xFF151B24),
            systemNavigationBarIconBrightness: Brightness.light,
          )
        : const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            systemNavigationBarColor: Color(0xFFFFFFFF),
            systemNavigationBarIconBrightness: Brightness.dark,
          );
  }
}

List<BoxShadow> appCardShadow(AppPalette p, {bool elevated = false}) {
  return [
    BoxShadow(
      color: p.shadow,
      blurRadius: elevated ? 20 : 12,
      offset: Offset(0, elevated ? 8 : 4),
    ),
  ];
}
