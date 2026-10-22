import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  static const _accent = Color(0xFF9A3412);
  static const _accentDark = Color(0xFFE8B86D);

  static ThemeData light() {
    const paper = Color(0xFFF3EEE6);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: _accent,
          brightness: Brightness.light,
        ).copyWith(
          primary: _accent,
          secondary: const Color(0xFF57534E),
          tertiary: const Color(0xFF0F766E),
          surface: paper,
          surfaceContainerLow: const Color(0xFFFAF7F2),
          surfaceContainerHighest: const Color(0xFFE7E0D4),
          outlineVariant: const Color(0xFFD6CDBF),
        );

    return _base(
      scheme: scheme,
      scaffold: paper,
      appBarBg: paper,
      cardColor: const Color(0xFFFFFCF8),
      cardBorder: scheme.outlineVariant.withValues(alpha: 0.7),
      statusBar: SystemUiOverlayStyle.dark,
    );
  }

  static ThemeData dark() {
    const surface = Color(0xFF0C0B0A);
    const surfaceHigh = Color(0xFF171513);
    const surfaceHigher = Color(0xFF221F1C);

    final scheme =
        ColorScheme.fromSeed(
          seedColor: _accentDark,
          brightness: Brightness.dark,
          surface: surface,
        ).copyWith(
          primary: _accentDark,
          secondary: const Color(0xFFD6C7B2),
          tertiary: const Color(0xFF5EEAD4),
          surface: surface,
          surfaceContainerLow: surfaceHigh,
          surfaceContainerHighest: surfaceHigher,
          outlineVariant: const Color(0xFF3A342C),
        );

    return _base(
      scheme: scheme,
      scaffold: surface,
      appBarBg: surface,
      cardColor: surfaceHigh,
      cardBorder: scheme.outlineVariant.withValues(alpha: 0.55),
      statusBar: SystemUiOverlayStyle.light,
    );
  }

  static ThemeData _base({
    required ColorScheme scheme,
    required Color scaffold,
    required Color appBarBg,
    required Color cardColor,
    required Color cardBorder,
    required SystemUiOverlayStyle statusBar,
  }) {
    final isLight = scheme.brightness == Brightness.light;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: isLight ? 0.5 : 0,
        backgroundColor: appBarBg,
        foregroundColor: scheme.onSurface,
        systemOverlayStyle: statusBar,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: isLight ? 0.5 : 0,
        color: cardColor,
        shadowColor: Colors.black.withValues(alpha: isLight ? 0.08 : 0),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: cardBorder),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: isLight ? 3 : 2,
        extendedPadding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        selectedColor: scheme.primaryContainer,
        checkmarkColor: scheme.onPrimaryContainer,
        labelStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight
            ? Colors.white
            : scheme.surfaceContainerHighest.withValues(alpha: 0.65),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: isLight ? 0.9 : 0),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: isLight ? 0.9 : 0),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.45),
        space: 1,
        thickness: 1,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        iconColor: scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isLight ? Colors.white : scheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        showDragHandle: true,
        dragHandleColor: scheme.outlineVariant,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isLight ? Colors.white : scheme.surface,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
      ),
    );
  }

  /// 리더 화면은 항상 어두운 배경으로 유지합니다.
  static const readerBackground = Color(0xFF000000);
}
