import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import 'storage_service.dart';

/// 이메일 로그인 사용자별 app_data JSON 동기화
class SupabaseSyncService {
  SupabaseSyncService._();
  static final instance = SupabaseSyncService._();

  static const _table = 'app_data';

  bool _ready = false;
  bool get isReady => _ready;

  SupabaseClient get _client => Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

  bool get isLoggedIn {
    final user = currentUser;
    if (user == null) return false;
    // 익명 세션은 로그인으로 취급하지 않음
    return user.isAnonymous != true;
  }

  String? get email => currentUser?.email;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<void> init() async {
    if (_ready) return;
    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.publishableKey,
      );
      // 예전 익명 세션은 버리고 로그인 화면으로
      final user = _client.auth.currentUser;
      if (user != null && user.isAnonymous == true) {
        await _client.auth.signOut();
      }
      _ready = true;
    } catch (e, st) {
      debugPrint('Supabase init failed: $e\n$st');
      _ready = false;
    }
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
    if (!_ready) return;
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

      await _client.from(_table).upsert(
        {
          'user_id': uid,
          'payload': backupRoot,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id',
      );
      return true;
    } catch (e, st) {
      debugPrint('Supabase push failed: $e\n$st');
      return false;
    }
  }

  /// payload에서 실제 데이터 수정 시각 추출.
  /// - dataRevisedAt 있으면 그대로 사용 (신규 클라)
  /// - 없으면 exportedAt/updated_at 은 쓰지 않음 (구버전 버그로 now 오염됨)
  ///   → 기록 내용의 최신 시각으로 추정
  DateTime? _revisedAtOf(Map<String, dynamic> root) {
    final explicit = root['dataRevisedAt'];
    if (explicit != null) {
      final parsed = DateTime.tryParse('$explicit')?.toUtc();
      if (parsed != null) return parsed;
    }
    final data = root['data'];
    if (data is Map) {
      return StorageService.inferRevisedAtFromDataMap(
        Map<String, dynamic>.from(data),
      );
    }
    return null;
  }

  /// 로컬 로드 후: 원격이 더 최신이면 import 후 true, 그 외 push하고 false
  ///
  /// 중요: `exportedAt`은 export 시마다 now로 찍히므로 비교에 쓰면 안 됨.
  /// `dataRevisedAt`(실제 데이터 변경 시각)으로 LWW 한다.
  Future<bool> syncAfterLocalLoad(StorageService storage) async {
    if (!_ready) await init();
    if (!_ready || !isLoggedIn) return false;

    final remote = await pull();
    // 구버전 업그레이드: 저장된 수정 시각이 없으면 기록 내용에서 추정
    await storage.ensureDataRevisedAt();
    final local = await storage.exportBackup();
    final localEmpty = _isEffectivelyEmpty(local);
    final localRevisedAt =
        await storage.loadDataRevisedAt() ?? _revisedAtOf(local);

    if (remote == null) {
      if (!localEmpty) {
        if (localRevisedAt == null) {
          await storage.markDataRevised();
        }
        final payload = await storage.exportBackup();
        await push(payload);
      }
      return false;
    }

    final remoteEmpty = _isEffectivelyEmpty(remote.payload);
    // 재설치 직후처럼 로컬이 비어 있으면 원격 우선
    if (localEmpty && !remoteEmpty) {
      await storage.importBackup(remote.payload);
      return true;
    }

    final remoteRevisedAt = _revisedAtOf(remote.payload);

    // 로컬에 데이터가 있고 원격 수정 시각을 전혀 모르면 로컬 유지 후 push
    if (!localEmpty && remoteRevisedAt == null) {
      final payload = await storage.exportBackup();
      await push(payload);
      return false;
    }

    // 원격만 시각을 알면 원격 적용
    if (localRevisedAt == null && !remoteEmpty && remoteRevisedAt != null) {
      await storage.importBackup(remote.payload);
      return true;
    }

    final useRemote = !remoteEmpty &&
        localRevisedAt != null &&
        remoteRevisedAt != null &&
        remoteRevisedAt.isAfter(localRevisedAt);

    if (useRemote) {
      await storage.importBackup(remote.payload);
      return true;
    }

    // 동일 시각이면 불필요한 push 생략
    if (!localEmpty &&
        localRevisedAt != null &&
        remoteRevisedAt != null &&
        remoteRevisedAt.isAtSameMomentAs(localRevisedAt)) {
      return false;
    }

    if (!localEmpty) {
      if (localRevisedAt == null) {
        await storage.markDataRevised();
      }
      final payload = await storage.exportBackup();
      await push(payload);
    }
    return false;
  }

  bool _isEffectivelyEmpty(Map<String, dynamic> root) {
    final data = root['data'];
    if (data is! Map) return true;
    final map = Map<String, dynamic>.from(data);
    bool emptyList(dynamic v) => v is! List || v.isEmpty;
    return emptyList(map['sessions']) &&
        emptyList(map['masturbationLogs']) &&
        emptyList(map['medications']) &&
        emptyList(map['medicationDoses']) &&
        emptyList(map['medicationSets']) &&
        emptyList(map['medicationSetDoses']) &&
        emptyList(map['books']) &&
        emptyList(map['readingLogs']);
  }
}
