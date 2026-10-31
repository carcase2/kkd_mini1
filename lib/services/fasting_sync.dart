import '../models/fasting_log.dart';
import '../models/session.dart';

/// 아직 서버에 반영되지 않은 단식 변경.
///
/// remoteId가 있으면 이미 있는 행(채팅에서 시작한 행 포함)의 종료다.
/// 없으면 이 기기에서 시작한 단식이고, status가 active가 아니면
/// 오프라인에서 이미 끝난 뒤라 닫힌 행으로 insert 한다.
class FastingPending {
  final String? appSessionId;
  final int? remoteId;
  final DateTime startAt;
  final DateTime? endAt;
  final SessionStatus status;
  final int? targetMinutes;
  final String? note;

  const FastingPending({
    this.appSessionId,
    this.remoteId,
    required this.startAt,
    this.endAt,
    required this.status,
    this.targetMinutes,
    this.note,
  });

  Map<String, dynamic> toJson() => {
    'appSessionId': appSessionId,
    'remoteId': remoteId,
    'startAt': startAt.toUtc().toIso8601String(),
    'endAt': endAt?.toUtc().toIso8601String(),
    'status': status.name,
    'targetMinutes': targetMinutes,
    'note': note,
  };

  static FastingPending? tryFromJson(Map<String, dynamic> json) {
    final start = DateTime.tryParse('${json['startAt']}');
    if (start == null) return null;
    SessionStatus? status;
    final rawStatus = json['status'];
    if (rawStatus is String) {
      for (final value in SessionStatus.values) {
        if (value.name == rawStatus) status = value;
      }
    }
    if (status == null) return null;
    final target = json['targetMinutes'];
    int? minutes;
    if (target is int) {
      minutes = target;
    } else if (target is num) {
      minutes = target.toInt();
    } else if (target != null) {
      minutes = int.tryParse('$target');
    }
    final remote = json['remoteId'];
    int? remoteId;
    if (remote is int) {
      remoteId = remote;
    } else if (remote is num) {
      remoteId = remote.toInt();
    } else if (remote != null) {
      remoteId = int.tryParse('$remote');
    }
    final local = json['appSessionId']?.toString();
    return FastingPending(
      appSessionId: local == null || local.isEmpty ? null : local,
      remoteId: remoteId,
      startAt: start,
      endAt: json['endAt'] == null
          ? null
          : DateTime.tryParse('${json['endAt']}'),
      status: status,
      targetMinutes: minutes != null && minutes > 0 ? minutes : null,
      note: json['note']?.toString(),
    );
  }
}

class FastingCache {
  final String? userId;
  final List<FastingLog> serverRows;
  final List<FastingPending> pending;

  const FastingCache({
    this.userId,
    this.serverRows = const [],
    this.pending = const [],
  });

  FastingCache copyWith({
    String? userId,
    bool clearUserId = false,
    List<FastingLog>? serverRows,
    List<FastingPending>? pending,
  }) {
    return FastingCache(
      userId: clearUserId ? null : (userId ?? this.userId),
      serverRows: serverRows ?? this.serverRows,
      pending: pending ?? this.pending,
    );
  }

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'serverRows': serverRows.map((row) => row.toCacheJson()).toList(),
    'pending': pending.map((item) => item.toJson()).toList(),
  };

  factory FastingCache.fromJson(Object? raw) {
    if (raw is! Map) return const FastingCache();
    final json = Map<String, dynamic>.from(raw);
    final rows = <FastingLog>[];
    final rowList = json['serverRows'];
    if (rowList is List) {
      for (final item in rowList) {
        if (item is! Map) continue;
        final row = FastingLog.tryFromCacheJson(
          Map<String, dynamic>.from(item),
        );
        if (row != null) rows.add(row);
      }
    }
    final pending = <FastingPending>[];
    final pendingList = json['pending'];
    if (pendingList is List) {
      for (final item in pendingList) {
        if (item is! Map) continue;
        final entry = FastingPending.tryFromJson(
          Map<String, dynamic>.from(item),
        );
        if (entry != null) pending.add(entry);
      }
    }
    final userId = json['userId']?.toString();
    return FastingCache(
      userId: userId == null || userId.isEmpty ? null : userId,
      serverRows: rows,
      pending: pending,
    );
  }
}

class FastingMerge {
  final List<FastingLog> rows;
  final List<FastingPending> pending;

  const FastingMerge({required this.rows, required this.pending});
}

bool sameFastingInstant(DateTime a, DateTime b) =>
    a.toUtc().isAtSameMomentAs(b.toUtc());

/// 서버 행 위에 아직 올리지 못한 변경을 얹는다.
///
/// 서버에 진행 중 단식이 있으면 기기의 새 시작은 버린다.
/// 사용자당 active 는 하나이고, 채팅에서 시작한 단식이 우선이다.
/// app_data 의 예전 sessions 는 여기서 읽지 않는다.
FastingMerge mergeFasting({
  required List<FastingLog> serverRows,
  required List<FastingPending> pending,
}) {
  final rows = [...serverRows];
  final still = <FastingPending>[];

  for (final item in pending) {
    if (item.remoteId != null) {
      final index = rows.indexWhere((row) => row.remoteId == item.remoteId);
      if (index < 0) continue;
      final row = rows[index];
      if (item.status == SessionStatus.active ||
          row.status != SessionStatus.active) {
        continue;
      }
      if (!fastingTerminalStatuses.contains(item.status)) continue;
      rows[index] = row.copyWith(
        endAt: safeFastingEnd(row.startAt, item.endAt),
        status: item.status,
      );
      still.add(item);
      continue;
    }

    final localId = item.appSessionId;
    if (localId == null || localId.isEmpty) continue;

    final index = rows.indexWhere((row) => row.appSessionId == localId);
    if (index >= 0) {
      final row = rows[index];
      if (item.status != SessionStatus.active &&
          row.status == SessionStatus.active &&
          row.remoteId != null) {
        rows[index] = row.copyWith(
          endAt: safeFastingEnd(row.startAt, item.endAt),
          status: item.status,
        );
        still.add(
          FastingPending(
            appSessionId: localId,
            remoteId: row.remoteId,
            startAt: row.startAt,
            endAt: safeFastingEnd(row.startAt, item.endAt),
            status: item.status,
            targetMinutes: item.targetMinutes ?? row.targetMinutes,
            note: item.note ?? row.note,
          ),
        );
      }
      continue;
    }

    if (rows.any(
      (row) =>
          row.source == 'app' && sameFastingInstant(row.startAt, item.startAt),
    )) {
      continue;
    }

    if (item.status == SessionStatus.active &&
        rows.any((row) => row.status == SessionStatus.active)) {
      continue;
    }

    if (item.status != SessionStatus.active &&
        !fastingTerminalStatuses.contains(item.status)) {
      continue;
    }

    rows.add(
      FastingLog(
        appSessionId: localId,
        startAt: item.startAt,
        endAt: item.status == SessionStatus.active
            ? null
            : safeFastingEnd(item.startAt, item.endAt),
        status: item.status,
        targetMinutes: item.targetMinutes,
        source: 'app',
        note: item.note,
      ),
    );
    still.add(item);
  }

  return FastingMerge(rows: rows, pending: still);
}
