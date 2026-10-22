import 'dart:async';

import 'package:flutter/material.dart';

import 'navigation/app_route_observer.dart';
import 'screens/library_screen.dart';
import 'services/storage_service.dart';
import 'services/supabase_sync_service.dart';
import 'services/theme_mode_service.dart';
import 'theme/app_theme.dart';

/// 만화 서재. 로그인·잠금은 껍데기 앱이 담당합니다.
class WebtoonApp extends StatefulWidget {
  const WebtoonApp({super.key});

  @override
  State<WebtoonApp> createState() => _WebtoonAppState();
}

class _WebtoonAppState extends State<WebtoonApp> with WidgetsBindingObserver {
  bool _booting = true;
  Object? _error;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ThemeModeService.instance.addListener(_onTheme);
    unawaited(_boot());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ThemeModeService.instance.removeListener(_onTheme);
    super.dispose();
  }

  void _onTheme() {
    if (mounted) setState(() {});
  }

  Future<void> _boot() async {
    try {
      await StorageService.instance.init();
      ThemeModeService.instance.load();
      final applied = await StorageService.instance.syncWithCloud();
      if (!mounted) return;
      setState(() {
        _booting = false;
        if (applied) _epoch++;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _booting = false;
        _error = e;
      });
    }
  }

  Future<void> _syncOnResume() async {
    if (!SupabaseSyncService.instance.isLoggedIn) return;
    try {
      final applied = await StorageService.instance.syncWithCloud();
      ThemeModeService.instance.load();
      if (applied && mounted) setState(() => _epoch++);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      unawaited(StorageService.instance.flushCloudSync());
      return;
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncOnResume());
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = ThemeModeService.instance.mode;
    final platformDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final dark = mode == ThemeMode.dark ||
        (mode == ThemeMode.system && platformDark);
    final theme = dark ? AppTheme.dark() : AppTheme.light();

    return Theme(
      data: theme,
      child: _booting
          ? const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            )
          : _error != null
              ? Scaffold(
                  body: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('만화 서재를 열지 못했습니다.\n$_error'),
                    ),
                  ),
                )
              : KeyedSubtree(
                  key: ValueKey(_epoch),
                  child: Navigator(
                    observers: [appRouteObserver],
                    onGenerateRoute: (settings) {
                      return MaterialPageRoute<void>(
                        settings: settings,
                        builder: (_) => const LibraryScreen(),
                      );
                    },
                  ),
                ),
    );
  }
}
