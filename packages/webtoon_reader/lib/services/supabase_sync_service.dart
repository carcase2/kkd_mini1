import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/backup_merge.dart';
import 'storage_service.dart';

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

  /// 원격 payload와 updated_at. 없으면 null.
  Future<({Map<String, dynamic> payload, DateTime updatedAt})?> pull() async {
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
      final raw = row['payload'];
      if (raw is! Map) return null;
      final updatedAt = DateTime.tryParse('${row['updated_at']}')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      return (
        payload: Map<String, dynamic>.from(raw),
        updatedAt: updatedAt,
      );
    } catch (e, st) {
      debugPrint('Supabase pull failed: $e\n$st');
      return null;
    }
  }

  Future<bool> push(Map<String, dynamic> backupRoot) async {
    if (!_ready || !isLoggedIn) return false;
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
    if (!_ready || !isLoggedIn) return false;

    final remote = await pull();
    final local = storage.exportBackup();
    final localEmpty = isBackupEffectivelyEmpty(local);

    if (remote == null) {
      if (!localEmpty) await push(local);
      return false;
    }

    final remoteEmpty = isBackupEffectivelyEmpty(remote.payload);
    if (localEmpty && !remoteEmpty) {
      await storage.importBackup(remote.payload);
      return true;
    }
    if (remoteEmpty) {
      if (!localEmpty) await push(local);
      return false;
    }

    final merged = mergeWebtoonBackups(local, remote.payload);
    final reload = backupShouldReloadUi(local, merged);
    if (reload) {
      await storage.importBackup(merged);
    }
    await push(merged);
    return reload;
  }
}
