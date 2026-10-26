import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:webtoon_reader/services/lock_service.dart';
import 'package:webtoon_reader/services/supabase_sync_service.dart' as webtoon;
import 'package:webtoon_reader/webtoon_app.dart';

import 'providers/app_state.dart';
import 'screens/lock_screen.dart';
import 'screens/login_screen.dart';
import 'screens/mode_picker_screen.dart';
import 'screens/shell.dart';
import 'screens/webtoon_cloud_gate.dart';
import 'services/biometric_service.dart';
import 'services/dual_auth.dart';
import 'services/notification_service.dart';
import 'services/supabase_sync_service.dart';
import 'theme/app_theme.dart';
import 'utils/app_version.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko');
  await AppVersion.load();
  await NotificationService.instance.init();

  LockService.hostProvidesLock = true;
  await DualAuth.instance.init();
  final discipline = DualAuth.instance.disciplineClient;
  if (discipline != null) {
    await SupabaseSyncService.instance.attach(discipline);
  }
  final webtoonClient = DualAuth.instance.webtoonClient;
  if (webtoonClient != null) {
    await webtoon.SupabaseSyncService.instance.attach(webtoonClient);
  }
  webtoon.SupabaseSyncService.instance.hostSignOut = DualAuth.instance.signOut;

  final appState = AppState();
  LockService.hostLock = appState.lockApp;
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
  StreamSubscription<AuthState>? _disciplineAuthSub;
  StreamSubscription<AuthState>? _webtoonAuthSub;
  bool _loggedIn = false;
  AppMode? _mode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loggedIn = DualAuth.instance.anyLoggedIn;
    final discipline = DualAuth.instance.disciplineClient;
    final webtoonClient = DualAuth.instance.webtoonClient;
    if (discipline != null) {
      _disciplineAuthSub = discipline.auth.onAuthStateChange.listen((_) {
        _onAuthChanged();
      });
    }
    if (webtoonClient != null) {
      _webtoonAuthSub = webtoonClient.auth.onAuthStateChange.listen((_) {
        _onAuthChanged();
      });
    }
    if (_loggedIn && DualAuth.instance.disciplineLoggedIn) {
      context.read<AppState>().syncCloud();
    }
  }

  void _onAuthChanged() {
    // 아이패드 Face ID 창은 세션 갱신을 일으킨다. 그때 트리를 다시
    // 그리면 진행 중인 얼굴 인식이 끊긴다.
    if (BiometricService.instance.isAuthenticating) return;
    final loggedIn = DualAuth.instance.anyLoggedIn;
    if (!mounted) return;
    setState(() {
      _loggedIn = loggedIn;
      if (!loggedIn) _mode = null;
    });
    if (loggedIn && DualAuth.instance.disciplineLoggedIn) {
      context.read<AppState>().syncCloud();
    }
  }

  @override
  void dispose() {
    _disciplineAuthSub?.cancel();
    _webtoonAuthSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (BiometricService.instance.isAuthenticating) return;
    final downloading = LockService.instance.isKeepAwakeActive;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (!downloading) {
        context.read<AppState>().onAppPaused();
      }
    } else if (state == AppLifecycleState.resumed) {
      unawaited(context.read<AppState>().onAppResumed());
      if (_loggedIn && DualAuth.instance.disciplineLoggedIn) {
        context.read<AppState>().syncCloud();
      }
    }
  }

  Future<void> _onLoggedIn() async {
    if (DualAuth.instance.disciplineLoggedIn) {
      await context.read<AppState>().syncCloud();
    }
    if (!mounted) return;
    setState(() => _loggedIn = true);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final themeMode = appState.themeMode;
    final isDark = themeMode == ThemeMode.dark;
    final locked = appState.isLocked;
    final auth = DualAuth.instance;

    Widget home;
    if (!_loggedIn) {
      home = LoginScreen(onLoggedIn: _onLoggedIn);
    } else if (locked) {
      home = const LockScreen();
    } else if (_mode == null) {
      home = ModePickerScreen(
        onSelect: (mode) => setState(() => _mode = mode),
      );
    } else if (_mode == AppMode.discipline) {
      home = ModeFrame(
        title: '절제',
        notice: auth.disciplineLoggedIn ? null : auth.disciplineError,
        onSwitch: () => setState(() => _mode = null),
        child: const AppShell(),
      );
    } else {
      home = ModeFrame(
        title: '만화',
        onSwitch: () => setState(() => _mode = null),
        child: auth.webtoonLoggedIn
            ? const WebtoonApp()
            : const WebtoonCloudGate(),
      );
    }

    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
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
      },
    );
  }
}
