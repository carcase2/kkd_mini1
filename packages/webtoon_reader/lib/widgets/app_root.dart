import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/library_screen.dart';
import '../screens/lock_screen.dart';
import '../screens/login_screen.dart';
import '../services/chapter_archive_queue.dart';
import '../services/cloud_backup_queue.dart';
import '../services/download_activity_service.dart';
import '../models/fetch_status.dart';
import '../services/lock_service.dart';
import '../services/storage_service.dart';
import '../services/supabase_sync_service.dart';
import '../services/theme_mode_service.dart';

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> with WidgetsBindingObserver {
  StreamSubscription<AuthState>? _authSub;
  bool _loggedIn = false;
  bool _syncing = false;
  /// 로그인·클라우드 동기화 후 LibraryScreen 을 다시 마운트하기 위한 키
  int _libraryEpoch = 0;

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
        unawaited(_syncCloud());
      }
    });
    if (_loggedIn) {
      unawaited(_syncCloud());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      unawaited(StorageService.instance.flushCloudSync());
      return;
    }
    if (state == AppLifecycleState.resumed && _loggedIn) {
      unawaited(_syncCloud());
    }
  }

  Future<void> _syncCloud() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final applied = await StorageService.instance.syncWithCloud();
      ThemeModeService.instance.load();
      if (!mounted) return;
      if (applied) {
        setState(() => _libraryEpoch++);
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _onLoggedIn() async {
    await _syncCloud();
    if (!mounted) return;
    setState(() {
      _loggedIn = true;
      _libraryEpoch++;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loggedIn) {
      return LoginScreen(onLoggedIn: _onLoggedIn);
    }

    return ListenableBuilder(
      listenable: LockService.instance,
      builder: (context, _) {
        final lock = LockService.instance;
        final content = lock.isLocked
            ? const LockScreen()
            : LibraryScreen(key: ValueKey(_libraryEpoch));
        return Stack(
          fit: StackFit.expand,
          children: [
            content,
            if (_syncing)
              const Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: LinearProgressIndicator(minHeight: 2),
              ),
            ListenableBuilder(
              listenable: Listenable.merge([
                CloudBackupQueue.instance,
                ChapterArchiveQueue.instance,
              ]),
              builder: (context, _) {
                return ValueListenableBuilder<int>(
              valueListenable: DownloadActivityService.instance.pendingJobs,
              builder: (context, pendingJobs, _) {
                return ValueListenableBuilder<FetchStatus?>(
                  valueListenable: DownloadActivityService.instance.status,
                  builder: (context, status, _) {
                    final backup = CloudBackupQueue.instance;
                    final archive = ChapterArchiveQueue.instance;
                    if (status == null &&
                        pendingJobs <= 0 &&
                        !backup.isRunning &&
                        !archive.isRunning) {
                      return const SizedBox.shrink();
                    }
                    final scheme = Theme.of(context).colorScheme;
                    final progress = status?.overallProgress;
                    final text = status != null
                        ? (progress == null
                            ? status.phaseLabel
                            : '${status.phaseLabel} ${(progress * 100).round()}%')
                        : archive.isRunning
                            ? '읽은 회차 보관 중'
                            : pendingJobs > 0
                                ? '보관 대기 $pendingJobs개'
                                : '클라우드 백업 ${backup.pendingCount}화';
                    return Positioned(
                      right: 12,
                      bottom: 12 + MediaQuery.paddingOf(context).bottom,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            unawaited(DownloadActivityService.instance.openQueue());
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: scheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    text,
                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                          color: scheme.onPrimaryContainer,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
                );
              },
            ),
            if (lock.privacyShieldVisible)
              ColoredBox(
                color: Colors.black,
                child: Center(
                  child: Icon(
                    Icons.lock_rounded,
                    color: Colors.white.withValues(alpha: 0.8),
                    size: 42,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
