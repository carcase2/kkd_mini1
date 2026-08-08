import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import 'storage_service.dart';

/// 혼자 쓰는 전제: 익명 로그인 + app_data 한 행에 백업 JSON 동기화
class SupabaseSyncService {
  SupabaseSyncService._();
  static final instance = SupabaseSyncService._();

  static const _table = 'app_data';

  bool _ready = false;
  bool get isReady => _ready;

  SupabaseClient get _client => Supabase.instance.client;

  Future<void> init() async {
    if (_ready) return;
    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.publishableKey,
      );
      await _ensureSignedIn();
      _ready = true;
    } catch (e, st) {
      debugPrint('Supabase init failed: $e\n$st');
      _ready = false;
    }
  }

  Future<void> _ensureSignedIn() async {
    final session = _client.auth.currentSession;
    if (session != null) return;
    await _client.auth.signInAnonymously();
  }

  /// 원격 payload와 updated_at. 없으면 null.
  Future<({Map<String, dynamic> payload, DateTime updatedAt})?> pull() async {
    if (!_ready) return null;
    try {
      await _ensureSignedIn();
      final uid = _client.auth.currentUser?.id;
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
    if (!_ready) return false;
    try {
      await _ensureSignedIn();
      final uid = _client.auth.currentUser?.id;
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

  /// 로컬 로드 후: 원격이 더 최신이면 import 후 true, 그 외 push하고 false
  Future<bool> syncAfterLocalLoad(StorageService storage) async {
    if (!_ready) await init();
    if (!_ready) return false;

    final remote = await pull();
    final local = await storage.exportBackup();
    final localExportedAt =
        DateTime.tryParse('${local['exportedAt']}')?.toUtc();

    if (remote == null) {
      await push(local);
      return false;
    }

    final remoteExportedAt =
        DateTime.tryParse('${remote.payload['exportedAt']}')?.toUtc() ??
            remote.updatedAt;

    final useRemote = localExportedAt == null ||
        remoteExportedAt.isAfter(localExportedAt);

    if (useRemote) {
      await storage.importBackup(remote.payload);
      return true; // 로컬이 원격으로 갱신됨
    }

    await push(local);
    return false;
  }
}
