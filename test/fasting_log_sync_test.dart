import 'package:discipline_tracker/models/fasting_log.dart';
import 'package:discipline_tracker/models/session.dart';
import 'package:discipline_tracker/services/fasting_log_repository.dart';
import 'package:discipline_tracker/services/fasting_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'chat row keeps the 19:19 KST instant and is not an app_data session',
    () {
      final row = FastingLog.tryFromRow({
        'id': 7,
        'user_id': 'user-1',
        'start_at': '2026-10-31T19:19:00+09:00',
        'end_at': null,
        'status': 'active',
        'target_minutes': null,
        'milestones': [12, 16],
        'source': 'chat',
        'note': null,
        'app_session_id': null,
      });
      expect(row, isNotNull);
      expect(row!.source, 'chat');
      expect(row.sessionId, 'remote:7');
      expect(row.startAt.toUtc(), DateTime.utc(2026, 10, 31, 10, 19));
      expect(row.milestones, [12, 16]);
      expect(row.targetMinutes, isNull);

      final session = row.toSession();
      expect(session.type, SessionType.fasting);
      expect(session.origin, 'chat');
      expect(session.status, SessionStatus.active);
      expect(session.startTime.toUtc(), DateTime.utc(2026, 10, 31, 10, 19));
      expect(session.isOpenEnded, isTrue);
      expect(session.toJson().containsKey('origin'), isFalse);

      expect(
        FastingLog.tryFromRow({
          'id': 'local-1',
          'type': 'fasting',
          'startTime': '2026-10-31T19:19:00',
          'status': 'active',
        }),
        isNull,
      );
    },
  );

  test('insert payload is an app row and omits an empty target', () {
    final open = buildFastingInsert(
      userId: 'user-1',
      startAt: DateTime.parse('2026-10-31T20:00:00+09:00'),
      status: SessionStatus.active,
      appSessionId: 'local-1',
    );
    expect(open['source'], 'app');
    expect(open['status'], 'active');
    expect(open['user_id'], 'user-1');
    expect(open['app_session_id'], 'local-1');
    expect(open.containsKey('target_minutes'), isFalse);
    expect(open.containsKey('milestones'), isFalse);
    expect(open.containsKey('id'), isFalse);
    expect(open.containsKey('end_at'), isFalse);

    final closed = buildFastingInsert(
      userId: 'user-1',
      startAt: DateTime.parse('2026-10-31T20:00:00+09:00'),
      endAt: DateTime.parse('2026-10-31T19:00:00+09:00'),
      status: SessionStatus.completed,
      appSessionId: 'local-2',
      targetMinutes: 90,
    );
    expect(closed['target_minutes'], 90);
    expect(closed['status'], 'completed');
    expect(
      DateTime.parse(closed['end_at'] as String).toUtc(),
      DateTime.parse('2026-10-31T20:00:00+09:00').toUtc(),
    );
    expect(
      buildFastingFinish(
        endAt: DateTime.utc(2026, 10, 31, 12),
        status: SessionStatus.failed,
      ),
      {
        'end_at': DateTime.utc(2026, 10, 31, 12).toIso8601String(),
        'status': 'failed',
      },
    );
    expect(fastingTargetMinutes(null), isNull);
    expect(fastingTargetMinutes(Duration.zero), isNull);
  });

  test('an existing active fast blocks another start', () {
    final chat = FastingLog(
      remoteId: 7,
      startAt: DateTime.parse('2026-10-31T19:19:00+09:00'),
      status: SessionStatus.active,
      source: 'chat',
    );
    final merged = mergeFasting(
      serverRows: [chat],
      pending: [
        FastingPending(
          appSessionId: 'local',
          startAt: DateTime.parse('2026-10-31T20:00:00+09:00'),
          status: SessionStatus.active,
        ),
      ],
    );
    expect(merged.rows, [chat]);
    expect(merged.pending, isEmpty);
  });

  test('logged-in start reads the chat fast and does not insert', () async {
    final harness = _Harness()
      ..remote.rows.add(
        FastingLog(
          remoteId: 7,
          userId: 'user-1',
          startAt: DateTime.parse('2026-10-31T19:19:00+09:00'),
          status: SessionStatus.active,
          source: 'chat',
          milestones: const [12],
        ),
      );
    final rows = await harness.repo.start(
      startAt: DateTime.parse('2026-10-31T20:05:00+09:00'),
    );

    expect(harness.remote.inserts, isEmpty);
    expect(rows, hasLength(1));
    expect(rows.single.source, 'chat');
    expect(rows.single.remoteId, 7);
    expect(rows.single.milestones, [12]);
    expect(
      rows.single.toSession().startTime.toUtc(),
      DateTime.utc(2026, 10, 31, 10, 19),
    );
  });

  test('start inserts an open app row when nothing is active', () async {
    final harness = _Harness();
    final rows = await harness.repo.start(
      startAt: DateTime.parse('2026-10-31T20:00:00+09:00'),
    );

    expect(harness.remote.inserts, hasLength(1));
    expect(harness.remote.inserts.single['source'], 'app');
    expect(harness.remote.inserts.single['status'], 'active');
    expect(
      harness.remote.inserts.single.containsKey('target_minutes'),
      isFalse,
    );
    expect(rows.single.status, SessionStatus.active);
    expect(rows.single.remoteId, isNotNull);
    expect(rows.single.source, 'app');
  });

  test('finish, fail, and cancel update the active row', () async {
    final harness = _Harness();
    await harness.repo.start(
      startAt: DateTime.parse('2026-10-31T20:00:00+09:00'),
    );
    final id = harness.remote.rows.single.sessionId;

    await harness.repo.finish(
      sessionId: id,
      status: SessionStatus.failed,
      endAt: DateTime.parse('2026-10-31T21:00:00+09:00'),
    );
    expect(harness.remote.finishes.single.status, SessionStatus.failed);
    expect(harness.remote.rows.single.status, SessionStatus.failed);
    expect(harness.remote.inserts, hasLength(1));

    harness.remote.rows
      ..clear()
      ..add(
        FastingLog(
          remoteId: 7,
          userId: 'user-1',
          startAt: DateTime.parse('2026-10-31T19:19:00+09:00'),
          status: SessionStatus.active,
          source: 'chat',
        ),
      );
    harness.remote.finishes.clear();
    await harness.repo.refresh();
    final ended = await harness.repo.finish(
      sessionId: 'remote:7',
      status: SessionStatus.completed,
      endAt: DateTime.parse('2026-10-31T19:00:00+09:00'),
    );
    expect(harness.remote.inserts, hasLength(1));
    expect(harness.remote.finishes.single.status, SessionStatus.completed);
    expect(
      harness.remote.finishes.single.endAt.toUtc(),
      DateTime.utc(2026, 10, 31, 10, 19),
    );
    expect(ended.single.status, SessionStatus.completed);
    expect(ended.where((row) => row.source == 'chat'), isNotEmpty);

    harness.remote.rows
      ..clear()
      ..add(
        FastingLog(
          remoteId: 8,
          userId: 'user-1',
          startAt: DateTime.parse('2026-10-31T18:00:00+09:00'),
          status: SessionStatus.active,
          source: 'chat',
        ),
      );
    await harness.repo.refresh();
    await harness.repo.finish(
      sessionId: 'remote:8',
      status: SessionStatus.cancelled,
      endAt: DateTime.parse('2026-10-31T18:10:00+09:00'),
    );
    expect(harness.remote.rows.single.status, SessionStatus.cancelled);
  });

  test(
    'offline start and finish sync later without a second active row',
    () async {
      final harness = _Harness()..remote.offline = true;
      final started = await harness.repo.start(
        startAt: DateTime.parse('2026-10-31T20:00:00+09:00'),
      );
      expect(started.single.status, SessionStatus.active);
      expect(started.single.remoteId, isNull);
      expect(harness.remote.inserts, isEmpty);

      final sessionId = started.single.sessionId;
      final closed = await harness.repo.finish(
        sessionId: sessionId,
        status: SessionStatus.completed,
        endAt: DateTime.parse('2026-10-31T22:00:00+09:00'),
      );
      expect(closed.single.status, SessionStatus.completed);
      expect(harness.remote.finishes, isEmpty);

      harness.remote.offline = false;
      final synced = await harness.repo.refresh();
      expect(synced.single.status, SessionStatus.completed);
      expect(synced.single.source, 'app');
      expect(
        harness.remote.rows.where((row) => row.status == SessionStatus.active),
        isEmpty,
      );
      expect(harness.remote.inserts, hasLength(1));
      expect(harness.remote.inserts.single['status'], 'completed');
      expect(harness.remote.finishes, isEmpty);
    },
  );

  test(
    'offline close of a chat fast updates that row after reconnect',
    () async {
      final harness = _Harness()
        ..remote.rows.add(
          FastingLog(
            remoteId: 7,
            userId: 'user-1',
            startAt: DateTime.parse('2026-10-31T19:19:00+09:00'),
            status: SessionStatus.active,
            source: 'chat',
          ),
        );
      await harness.repo.refresh();
      harness.remote.offline = true;

      final closed = await harness.repo.finish(
        sessionId: 'remote:7',
        status: SessionStatus.completed,
        endAt: DateTime.parse('2026-10-31T21:19:00+09:00'),
      );
      expect(closed.single.status, SessionStatus.completed);
      expect(harness.remote.rows.single.status, SessionStatus.active);

      harness.remote.offline = false;
      final synced = await harness.repo.refresh();
      expect(synced.single.status, SessionStatus.completed);
      expect(synced.single.source, 'chat');
      expect(harness.remote.finishes, hasLength(1));
      expect(harness.remote.inserts, isEmpty);
    },
  );

  test(
    'a different account does not receive the previous pending fast',
    () async {
      final harness = _Harness()..remote.offline = true;
      await harness.repo.start(
        startAt: DateTime.parse('2026-10-31T20:00:00+09:00'),
      );
      expect(harness.store.cache.pending, isNotEmpty);
      expect(harness.store.cache.userId, 'user-1');

      harness
        ..userId = 'user-2'
        ..remote.offline = false
        ..remote.rows.clear();
      final rows = await harness.repo.refresh();
      expect(rows, isEmpty);
      expect(harness.remote.inserts, isEmpty);
      expect(harness.store.cache.userId, 'user-2');
    },
  );

  test(
    'logged-out changes stay on device until the same user signs in',
    () async {
      final harness = _Harness()..loggedIn = false;
      final started = await harness.repo.start(
        startAt: DateTime.parse('2026-10-31T20:00:00+09:00'),
      );
      expect(started.single.status, SessionStatus.active);
      expect(harness.remote.inserts, isEmpty);

      harness.loggedIn = true;
      final synced = await harness.repo.refresh();
      expect(synced.single.source, 'app');
      expect(harness.remote.inserts.single['user_id'], 'user-1');
    },
  );
}

class _Harness {
  _Harness() {
    repo = FastingLogRepository(
      remoteProvider: () => loggedIn ? remote : null,
      userIdProvider: () => loggedIn ? userId : null,
      store: store,
    );
  }

  final store = _MemoryFastingStore();
  final remote = _FakeFastingRemote();
  late final FastingLogRepository repo;
  String? userId = 'user-1';
  bool loggedIn = true;
}

class _MemoryFastingStore implements FastingCacheStore {
  FastingCache cache = const FastingCache();

  @override
  Future<FastingCache> read() async => cache;

  @override
  Future<void> write(FastingCache value) async {
    cache = value;
  }
}

class _FakeFastingRemote implements FastingRemote {
  final List<FastingLog> rows = [];
  final List<Map<String, dynamic>> inserts = [];
  final List<({int id, DateTime endAt, SessionStatus status})> finishes = [];
  var nextId = 100;
  var offline = false;

  @override
  Future<List<FastingLog>> fetchAll() async {
    if (offline) throw FastingRequestException('offline');
    return [...rows];
  }

  @override
  Future<void> insert(Map<String, dynamic> payload) async {
    if (offline) throw FastingRequestException('offline');
    final status = SessionStatus.values.byName(payload['status'] as String);
    final startAt = DateTime.parse(payload['start_at'] as String);
    if (status == SessionStatus.active &&
        rows.any((row) => row.status == SessionStatus.active)) {
      throw FastingUniqueViolation();
    }
    if (rows.any(
      (row) =>
          row.source == payload['source'] &&
          row.startAt.toUtc().isAtSameMomentAs(startAt.toUtc()),
    )) {
      throw FastingUniqueViolation();
    }
    inserts.add(payload);
    rows.add(
      FastingLog(
        remoteId: nextId++,
        userId: payload['user_id'] as String?,
        startAt: startAt,
        endAt: payload['end_at'] == null
            ? null
            : DateTime.parse(payload['end_at'] as String),
        status: status,
        targetMinutes: payload['target_minutes'] as int?,
        source: payload['source'] as String? ?? 'app',
        note: payload['note'] as String?,
        appSessionId: payload['app_session_id'] as String?,
      ),
    );
  }

  @override
  Future<bool> finish({
    required int remoteId,
    required DateTime endAt,
    required SessionStatus status,
  }) async {
    if (offline) throw FastingRequestException('offline');
    final index = rows.indexWhere(
      (row) => row.remoteId == remoteId && row.status == SessionStatus.active,
    );
    if (index < 0) return false;
    finishes.add((id: remoteId, endAt: endAt, status: status));
    rows[index] = rows[index].copyWith(endAt: endAt, status: status);
    return true;
  }
}
