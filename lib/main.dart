import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'providers/app_state.dart';
import 'screens/lock_screen.dart';
import 'screens/login_screen.dart';
import 'screens/shell.dart';
import 'services/notification_service.dart';
import 'services/supabase_sync_service.dart';
import 'theme/app_theme.dart';
import 'utils/app_version.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko');
  await AppVersion.load();
  await NotificationService.instance.init();
  await SupabaseSyncService.instance.init();

  final appState = AppState();
  await appState.load();

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
  StreamSubscription<AuthState>? _authSub;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loggedIn = SupabaseSyncService.instance.isLoggedIn;
    _authSub = SupabaseSyncService.instance.authStateChanges.listen((event) {
      final loggedIn = SupabaseSyncService.instance.isLoggedIn;
      if (!mounted) return;
      setState(() => _loggedIn = loggedIn);
      if (loggedIn) {
        // 로그인 직후 클라우드 동기화
        context.read<AppState>().syncCloud();
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      context.read<AppState>().onAppPaused();
    }
  }

  Future<void> _onLoggedIn() async {
    await context.read<AppState>().syncCloud();
    if (!mounted) return;
    setState(() => _loggedIn = true);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final themeMode = appState.themeMode;
    final isDark = themeMode == ThemeMode.dark;
    final locked = appState.isLocked;

    Widget home;
    if (!_loggedIn) {
      home = LoginScreen(onLoggedIn: _onLoggedIn);
    } else if (locked) {
      home = const LockScreen();
    } else {
      home = const AppShell();
    }

    return MaterialApp(
      title: '절제',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      builder: (context, child) {
        final palette = Theme.of(context).extension<AppPalette>() ??
            (isDark ? AppPalette.dark : AppPalette.light);
        AppColors.bind(palette);
        SystemChrome.setSystemUIOverlayStyle(AppTheme.overlay(isDark));
        return child ?? const SizedBox.shrink();
      },
      home: home,
    );
  }
}
