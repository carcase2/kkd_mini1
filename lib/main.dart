import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'providers/app_state.dart';
import 'screens/shell.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko');

  final appState = AppState();
  await appState.load();

  // 기본 라이트 팔레트 바인딩
  AppColors.bind(
    appState.isDarkMode ? AppPalette.dark : AppPalette.light,
  );
  SystemChrome.setSystemUIOverlayStyle(
    AppTheme.overlay(appState.isDarkMode),
  );

  runApp(
    ChangeNotifierProvider.value(
      value: appState,
      child: const DisciplineApp(),
    ),
  );
}

class DisciplineApp extends StatelessWidget {
  const DisciplineApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<AppState>().themeMode;
    final isDark = themeMode == ThemeMode.dark;

    return MaterialApp(
      title: '절제',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      builder: (context, child) {
        // 테마 변경 시 전역 AppColors 동기화
        final palette = Theme.of(context).extension<AppPalette>() ??
            (isDark ? AppPalette.dark : AppPalette.light);
        AppColors.bind(palette);
        SystemChrome.setSystemUIOverlayStyle(AppTheme.overlay(isDark));
        return child ?? const SizedBox.shrink();
      },
      home: const AppShell(),
    );
  }
}
