import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 라이트/다크 모두에서 날짜·시간 피커 숫자가 보이도록 테마를 구성
ThemeData pickerTheme(
  BuildContext context, {
  required Color accent,
}) {
  final base = Theme.of(context);
  final c = AppPalette.of(context);
  final isDark = base.brightness == Brightness.dark;

  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: accent,
      onPrimary: Colors.white,
      surface: c.surfaceElevated,
      onSurface: c.textPrimary,
      onSurfaceVariant: c.textSecondary,
      outline: c.border,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surfaceElevated,
      surfaceTintColor: Colors.transparent,
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: c.surfaceElevated,
      headerBackgroundColor: accent,
      headerForegroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      dayForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        if (states.contains(WidgetState.disabled)) return c.textMuted;
        return c.textPrimary;
      }),
      dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return accent;
        return Colors.transparent;
      }),
      todayForegroundColor: WidgetStateProperty.all(accent),
      todayBorder: BorderSide(color: accent),
      yearForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        return c.textPrimary;
      }),
      yearBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return accent;
        return Colors.transparent;
      }),
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: c.surfaceElevated,
      elevation: 0,
      hourMinuteTextColor: c.textPrimary,
      hourMinuteColor: c.chipBg,
      dayPeriodTextColor: c.textPrimary,
      dayPeriodColor: c.chipBg,
      dialBackgroundColor: isDark ? c.chipBg : const Color(0xFFF0F3F8),
      dialHandColor: accent,
      dialTextColor: WidgetStateColor.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return Colors.white;
        }
        return c.textPrimary;
      }),
      entryModeIconColor: c.textSecondary,
      helpTextStyle: TextStyle(
        color: c.textSecondary,
        fontWeight: FontWeight.w600,
      ),
      hourMinuteTextStyle: TextStyle(
        color: c.textPrimary,
        fontSize: 40,
        fontWeight: FontWeight.w700,
      ),
      dayPeriodTextStyle: TextStyle(
        color: c.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      cancelButtonStyle: TextButton.styleFrom(foregroundColor: c.textSecondary),
      confirmButtonStyle: TextButton.styleFrom(foregroundColor: accent),
    ),
  );
}

/// 날짜 피커 (테마 적용)
Future<DateTime?> showAppDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  required Color accent,
}) {
  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    builder: (ctx, child) => Theme(
      data: pickerTheme(ctx, accent: accent),
      child: child!,
    ),
  );
}

/// 시간 피커 (테마 적용 — 라이트 모드 숫자 가시성 보장)
Future<TimeOfDay?> showAppTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  required Color accent,
}) {
  return showTimePicker(
    context: context,
    initialTime: initialTime,
    builder: (ctx, child) => Theme(
      data: pickerTheme(ctx, accent: accent),
      child: child!,
    ),
  );
}
