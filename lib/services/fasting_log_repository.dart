import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/fasting_log.dart';
import '../models/session.dart';
import 'fasting_sync.dart';
import 'supabase_sync_service.dart';

/// 네트워크·권한 실패. 대기열은 유지한다.
class FastingRequestException implements Exception {
  final Object cause;

  FastingRequestException(this.cause);

  @override
  String toString() => 'FastingRequestException: $cause';
}

/// unique(user_id, source, start_at) 또는 사용자당 active 1건 위반.
class FastingUniqueViolation implements Exception {}

abstract class FastingRemote {
  Future<List<FastingLog>> fetchAll();

  Future<void> insert(Map<String, dynamic> payload);

  /// 진행 중 행만 닫는다. 이미 닫혀 있으면 false.
  Future<bool> finish({
    required int remoteId,
    required DateTime endAt,
    required SessionStatus status,
  });
}

abstract class FastingCacheStore {
  Future<FastingCache> read();

  Future<void> write(FastingCache cache);
}

class PrefsFastingCacheStore implements FastingCacheStore {
  static const key = 'fasting_log_cache_v1';

  @override
  Future<FastingCache> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return const FastingCache();
    try {
      return FastingCache.fromJson(jsonDecode(raw));
    } catch (e, st) {
      debugPrint('fasting cache read failed: $e\n$st');
      return const FastingCache();
    }
  }

  @override
  Future<void> write(FastingCache cache) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(cache.toJson()));
  }
}

class SupabaseFastingRemote implements FastingRemote {
  SupabaseFastingRemote(this._client, this.userId);

  final SupabaseClient _client;
  final String userId;

  static const _columns =
      'id, user_id, start_at, end_at, status, target_minutes, milestones, source, note, app_session_id, created_at, updated_at';

  @override
  Future<List<FastingLog>> fetchAll() async {
    final raw = await _guard(() {
      return _client.from('fasting_log').select(_columns).eq('user_id', userId);
    });
    final logs = <FastingLog>[];
    for (final row in raw) {
      final log = FastingLog.tryFromRow(Map<String, dynamic>.from(row));
      if (log != null) logs.add(log);
    }
    logs.sort((a, b) => b.startAt.compareTo(a.startAt));
    return logs;
  }

  @override
  Future<void> insert(Map<String, dynamic> payload) {
    return _guard(() async {
      await _client.from('fasting_log').insert(payload);
    });
  }

  @override
  Future<bool> finish({
    required int remoteId,
    required DateTime endAt,
    required SessionStatus status,
  }) async {
    final updated = await _guard(() {
      return _client
          .from('fasting_log')
          .update(buildFastingFinish(endAt: endAt, status: status))
          .eq('id', remoteId)
          .eq('user_id', userId)
          .eq('status', 'active')
          .select('id');
    });
    return updated.isNotEmpty;
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      if (e.code == '23505') throw FastingUniqueViolation();
      throw FastingRequestException(e);
    } catch (e) {
      if (e is FastingUniqueViolation || e is FastingRequestException) {
        rethrow;
      }
      throw FastingRequestException(e);
    }
  }
}

/// 단식의 읽기·시작·종료.
///
/// app_data 동기화와 분리되어 있고, 예전 sessions 는 가져오지 않는다.
/// 로그인되어 있으면 같은 Supabase Auth 사용자로 fasting_log 를 호출한다.
/// 오프라인이거나 로그인이 아니면 이 기기에 대기시켰다가 다음에 올린다.
class FastingLogRepository {
  FastingLogRepository({
    required FastingRemote? Function() remoteProvider,
    required String? Function() userIdProvider,
    required FastingCacheStore store,
  }) : _remoteProvider = remoteProvider, // ignore: prefer_initializing_formals
       _userIdProvider = userIdProvider, // ignore: prefer_initializing_formals
       _store = store; // ignore: prefer_initializing_formals

  factory FastingLogRepository.supabase() {
    final cloud = SupabaseSyncService.instance;
    return FastingLogRepository(
      remoteProvider: () {
        final client = cloud.loggedInClient;
        final userId = cloud.userId;
        if (client == null || userId == null) return null;
        return SupabaseFastingRemote(client, userId);
      },
      userIdProvider: () => cloud.userId,
      store: PrefsFastingCacheStore(),
    );
  }

  final FastingRemote? Function() _remoteProvider;
  final String? Function() _userIdProvider;
  final FastingCacheStore _store;

  Future<List<FastingLog>> readDisplay() async {
    final cache = await _scopedCache();
    return mergeFasting(
      serverRows: cache.serverRows,
      pending: cache.pending,
    ).rows;
  }

  Future<List<FastingLog>> refresh() async {
    final next = await _tryPullAndFlush(await _scopedCache());
    return mergeFasting(
      serverRows: next.serverRows,
      pending: next.pending,
    ).rows;
  }

  /// 진행 중 행이 없을 때만 source=app 으로 insert 한다.
  /// 채팅 등에서 이미 active 가 있으면 그 행을 그대로 돌려준다.
  Future<List<FastingLog>> start({
    required DateTime startAt,
    int? targetMinutes,
    String? note,
  }) async {
    final pulled = await _tryPullAndFlush(await _scopedCache());
    final view = mergeFasting(
      serverRows: pulled.serverRows,
      pending: pulled.pending,
    );
    if (view.rows.any((row) => row.status == SessionStatus.active)) {
      return view.rows;
    }
    final withPending = pulled.copyWith(
      pending: [
        ...view.pending,
        FastingPending(
          appSessionId: DateTime.now().microsecondsSinceEpoch.toString(),
          startAt: startAt,
          status: SessionStatus.active,
          targetMinutes: targetMinutes,
          note: note,
        ),
      ],
    );
    await _store.write(withPending);
    final flushed = await _tryPullAndFlush(withPending);
    return mergeFasting(
      serverRows: flushed.serverRows,
      pending: flushed.pending,
    ).rows;
  }

  /// active 행에 end_at 과 status 를 쓴다. 삭제는 하지 않는다.
  Future<List<FastingLog>> finish({
    required String sessionId,
    required SessionStatus status,
    required DateTime endAt,
  }) async {
    final cache = await _scopedCache();
    final view = mergeFasting(
      serverRows: cache.serverRows,
      pending: cache.pending,
    );
    if (!fastingTerminalStatuses.contains(status)) return view.rows;
    FastingLog? row;
    for (final log in view.rows) {
      if (log.sessionId == sessionId) row = log;
    }
    if (row == null || row.status != SessionStatus.active) return view.rows;
    final target = row;

    final pending = [...cache.pending]
      ..removeWhere(
        (item) =>
            (target.appSessionId != null &&
                item.appSessionId == target.appSessionId) ||
            (target.remoteId != null && item.remoteId == target.remoteId),
      );
    pending.add(
      FastingPending(
        appSessionId: target.appSessionId,
        remoteId: target.remoteId,
        startAt: target.startAt,
        endAt: safeFastingEnd(target.startAt, endAt),
        status: status,
        targetMinutes: target.targetMinutes,
        note: target.note,
      ),
    );
    final withPending = cache.copyWith(pending: pending);
    await _store.write(withPending);
    final flushed = await _tryPullAndFlush(withPending);
    return mergeFasting(
      serverRows: flushed.serverRows,
      pending: flushed.pending,
    ).rows;
  }

  /// 다른 계정 캐시·대기열은 올리지 않고 버린다.
  Future<FastingCache> _scopedCache() async {
    final cache = await _store.read();
    final userId = _userIdProvider();
    if (userId != null && cache.userId != null && cache.userId != userId) {
      final fresh = FastingCache(userId: userId);
      await _store.write(fresh);
      return fresh;
    }
    if (userId != null && cache.userId == null) {
      return cache.copyWith(userId: userId);
    }
    return cache;
  }

  Future<FastingCache> _tryPullAndFlush(FastingCache cache) async {
    final remote = _remoteProvider();
    final userId = _userIdProvider() ?? cache.userId;
    if (remote == null) {
      final view = mergeFasting(
        serverRows: cache.serverRows,
        pending: cache.pending,
      );
      final next = cache.copyWith(userId: userId, pending: view.pending);
      await _store.write(next);
      return next;
    }

    List<FastingLog> server;
    try {
      server = await remote.fetchAll();
    } on FastingRequestException catch (e, st) {
      debugPrint('fasting pull failed: $e\n$st');
      final view = mergeFasting(
        serverRows: cache.serverRows,
        pending: cache.pending,
      );
      final next = cache.copyWith(userId: userId, pending: view.pending);
      await _store.write(next);
      return next;
    }

    var pending = mergeFasting(
      serverRows: server,
      pending: cache.pending,
    ).pending;
    pending = await _flush(remote, server, pending);
    try {
      server = await remote.fetchAll();
    } on FastingRequestException catch (e, st) {
      debugPrint('fasting refresh failed: $e\n$st');
    }
    final view = mergeFasting(serverRows: server, pending: pending);
    final next = FastingCache(
      userId: userId,
      serverRows: server,
      pending: view.pending,
    );
    await _store.write(next);
    return next;
  }

  Future<List<FastingPending>> _flush(
    FastingRemote remote,
    List<FastingLog> server,
    List<FastingPending> pending,
  ) async {
    final left = <FastingPending>[];
    final known = [...server];
    for (var i = 0; i < pending.length; i++) {
      final item = pending[i];
      try {
        final uploaded = await _uploadOne(remote, known, item);
        if (!uploaded) left.add(item);
      } on FastingUniqueViolation {
        // 같은 시각·진행 중 제약은 서버 행을 다시 읽어 맞춘다.
      } on FastingRequestException catch (e, st) {
        debugPrint('fasting push failed: $e\n$st');
        left.add(item);
        left.addAll(pending.skip(i + 1));
        break;
      }
    }
    return left;
  }

  /// true면 대기열에서 뺀다. false면 다음에 다시 시도한다.
  Future<bool> _uploadOne(
    FastingRemote remote,
    List<FastingLog> known,
    FastingPending item,
  ) async {
    if (item.remoteId != null &&
        fastingTerminalStatuses.contains(item.status)) {
      await remote.finish(
        remoteId: item.remoteId!,
        endAt: safeFastingEnd(item.startAt, item.endAt),
        status: item.status,
      );
      return true;
    }

    final localId = item.appSessionId;
    if (localId != null) {
      final existing = _firstWhereOrNull(
        known,
        (row) => row.appSessionId == localId,
      );
      if (existing != null) {
        if (fastingTerminalStatuses.contains(item.status) &&
            existing.status == SessionStatus.active &&
            existing.remoteId != null) {
          await remote.finish(
            remoteId: existing.remoteId!,
            endAt: safeFastingEnd(existing.startAt, item.endAt),
            status: item.status,
          );
        }
        return true;
      }
    }

    if (item.status == SessionStatus.active &&
        known.any((row) => row.status == SessionStatus.active)) {
      return true;
    }

    final userId = _userIdProvider();
    if (userId == null) return false;
    try {
      await remote.insert(
        buildFastingInsert(
          userId: userId,
          startAt: item.startAt,
          status: item.status,
          appSessionId: item.appSessionId,
          targetMinutes: item.targetMinutes,
          note: item.note,
          endAt: item.endAt,
        ),
      );
      return true;
    } on FastingUniqueViolation {
      if (item.status == SessionStatus.active) return true;
      final bumped = item.startAt.add(const Duration(seconds: 1));
      try {
        await remote.insert(
          buildFastingInsert(
            userId: userId,
            startAt: bumped,
            status: item.status,
            appSessionId: item.appSessionId,
            targetMinutes: item.targetMinutes,
            note: item.note,
            endAt: item.endAt ?? bumped,
          ),
        );
        return true;
      } on FastingUniqueViolation {
        return true;
      }
    }
  }
}

T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T item) test) {
  for (final item in items) {
    if (test(item)) return item;
  }
  return null;
}
