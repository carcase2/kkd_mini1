import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'providers/app_state.dart';
import 'screens/lock_screen.dart';
import 'screens/shell.dart';
import 'services/backup_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko');

  final appState = AppState();
  await appState.load();

  // 주기 자동 백업 (도래 시에만, 앱 시작 시)
  try {
    await BackupService.maybeAutoBackup(appState);
  } catch (_) {
    // 백업 실패해도 앱 실행은 계속
  }

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

class DisciplineApp extends StatefulWidget {
  const DisciplineApp({super.key});

  @override
  State<DisciplineApp> createState() => _DisciplineAppState();
}

class _DisciplineAppState extends State<DisciplineApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 백그라운드로 나갈 때만 자동 잠금
    // (inactive는 알림창·다이얼로그에서도 발생해 제외)
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      final app = context.read<AppState>();
      app.onAppPaused();
      // 백그라운드 전환 시 주기 백업 점검
      BackupService.maybeAutoBackup(app).catchError((_) => false);
    } else if (state == AppLifecycleState.resumed) {
      BackupService.maybeAutoBackup(context.read<AppState>())
          .catchError((_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final themeMode = appState.themeMode;
    final isDark = themeMode == ThemeMode.dark;
    final locked = appState.isLocked;

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
      home: locked ? const LockScreen() : const AppShell(),
    );
  }
}
