import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/backup_merge.dart';
import 'storage_service.dart';

enum WebtoonSyncStatus {
  applied,
  unchanged,
  notLoggedIn,
  pullFailed,
  remoteEmpty,
}

/// 이메일 로그인 사용자별 webtoon_app_data JSON 동기화.
/// 클라이언트는 껍데기 앱이 attach 합니다. Supabase.initialize 는 쓰지 않습니다.
class SupabaseSyncService {
  SupabaseSyncService._();
  static final instance = SupabaseSyncService._();

  static const _table = 'webtoon_app_data';

  /// 설정되면 로그아웃은 껍데기가 두 계정을 함께 끊습니다.
  Future<void> Function()? hostSignOut;

  SupabaseClient? _attached;
  bool _ready = false;
  bool get isReady => _ready && _attached != null;

  /// 이 실행에서 서재가 한 번이라도 있었는지.
  /// 재설치 직후 빈 서재가 클라우드를 덮어쓰지 못하게 합니다.
  bool _seenNonEmptyLocal = false;

  WebtoonSyncStatus lastStatus = WebtoonSyncStatus.notLoggedIn;
  bool _pullFailed = false;

  SupabaseClient get _client {
    final client = _attached;
    if (client == null) {
      throw StateError('만화 Supabase 클라이언트가 연결되지 않았습니다');
    }
    return client;
  }

  User? get currentUser => _attached?.auth.currentUser;

  bool get isLoggedIn {
    final user = currentUser;
    if (user == null) return false;
    // 익명 세션은 로그인으로 취급하지 않음
    return user.isAnonymous != true;
  }

  String? get email => currentUser?.email;

  Stream<AuthState> get authStateChanges {
    final client = _attached;
    if (client == null) return const Stream.empty();
    return client.auth.onAuthStateChange;
  }

  Future<void> attach(SupabaseClient client) async {
    _attached = client;
    try {
      final user = client.auth.currentUser;
      if (user != null && user.isAnonymous == true) {
        await client.auth.signOut();
      }
      _ready = true;
    } catch (e, st) {
      debugPrint('Supabase attach failed: $e\n$st');
      _ready = false;
    }
  }

  Future<void> init() async {
    if (_ready) return;
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    if (!_ready) await init();
    await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signUp({
    required String email,
    required String password,
  }) async {
    if (!_ready) await init();
    final res = await _client.auth.signUp(
      email: email.trim(),
      password: password,
    );
    // autoconfirm 꺼져 있으면 세션이 없을 수 있음 → 바로 로그인 시도
    if (res.session == null) {
      await signIn(email: email, password: password);
    }
  }

  Future<void> signOut() async {
    final hook = hostSignOut;
    if (hook != null) {
      await hook();
      return;
    }
    if (!_ready || _attached == null) return;
    await _client.auth.signOut();
  }

  /// 원격 payload와 updated_at. 행이 없으면 null.
  /// 조회 실패는 [_pullFailed] 로 구분해서 빈 서재로 올리지 않습니다.
  Future<({Map<String, dynamic> payload, DateTime updatedAt})?> pull() async {
    _pullFailed = false;
    if (!_ready || !isLoggedIn) return null;
    try {
      final uid = currentUser?.id;
      if (uid == null) return null;

      final row = await _client
          .from(_table)
          .select('payload, updated_at')
          .eq('user_id', uid)
          .maybeSingle();

      if (row == null) return null;
      final payload = _payloadMap(row['payload']);
      if (payload == null) {
        _pullFailed = true;
        return null;
      }
      final updatedAt = DateTime.tryParse('${row['updated_at']}')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      return (
        payload: payload,
        updatedAt: updatedAt,
      );
    } catch (e, st) {
      debugPrint('Supabase pull failed: $e\n$st');
      _pullFailed = true;
      return null;
    }
  }

  Map<String, dynamic>? _payloadMap(dynamic raw) {
    if (raw is String && raw.isNotEmpty) {
      try {
        raw = jsonDecode(raw);
      } catch (_) {
        return null;
      }
    }
    if (raw is! Map) return null;
    return Map<String, dynamic>.from(raw);
  }

  Future<bool> push(Map<String, dynamic> backupRoot) async {
    if (!_ready || !isLoggedIn) return false;
    // 로컬이 비어 있는데 이번 실행에서 만화를 본 적이 없으면 올리지 않습니다.
    // 자동 백업이 원격 서재를 빈 목록으로 지우던 경우입니다.
    if (isBackupEffectivelyEmpty(backupRoot) && !_seenNonEmptyLocal) {
      return false;
    }
    if (!isBackupEffectivelyEmpty(backupRoot)) {
      _seenNonEmptyLocal = true;
    }
    try {
      final uid = currentUser?.id;
      if (uid == null) return false;

      await _client.from(_table).upsert({
        'user_id': uid,
        'payload': backupRoot,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      return true;
    } catch (e, st) {
      debugPrint('Supabase push failed: $e\n$st');
      return false;
    }
  }

  /// 로컬·원격을 회차 단위로 합칩니다. 읽기 위치가 바뀌면 true.
  Future<bool> syncAfterLocalLoad(StorageService storage) async {
    if (!_ready) await init();
    if (!_ready || !isLoggedIn) {
      lastStatus = WebtoonSyncStatus.notLoggedIn;
      return false;
    }

    final localBefore = storage.exportBackup();
    if (!isBackupEffectivelyEmpty(localBefore)) {
      _seenNonEmptyLocal = true;
    }

    final remote = await pull();
    final local = storage.exportBackup();
    final localEmpty = isBackupEffectivelyEmpty(local);

    if (_pullFailed) {
      lastStatus = WebtoonSyncStatus.pullFailed;
      return false;
    }

    if (remote == null || isBackupEffectivelyEmpty(remote.payload)) {
      if (shouldUploadLocalShelf(
        pullFailed: false,
        remoteMissing: true,
        localEmpty: localEmpty,
      )) {
        await push(local);
      }
      lastStatus = WebtoonSyncStatus.remoteEmpty;
      return false;
    }

    if (localEmpty) {
      await storage.importBackup(remote.payload);
      _seenNonEmptyLocal = true;
      lastStatus = WebtoonSyncStatus.applied;
      return true;
    }

    final merged = mergeWebtoonBackups(local, remote.payload);
    final reload = backupShouldReloadUi(local, merged);
    if (reload) {
      await storage.importBackup(merged);
    }
    await push(merged);
    lastStatus =
        reload ? WebtoonSyncStatus.applied : WebtoonSyncStatus.unchanged;
    return reload;
  }
}
