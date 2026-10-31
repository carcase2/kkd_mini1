import 'session.dart';

/// public.fasting_log 한 행.
///
/// 스키마는 서버에 이미 있다. 이 앱은 읽기·시작 insert·종료 update만 한다.
class FastingLog {
  final int? remoteId;
  final String? userId;
  final DateTime startAt;
  final DateTime? endAt;
  final SessionStatus status;
  final int? targetMinutes;
  final List<int> milestones;
  final String source;
  final String? note;
  final String? appSessionId;

  const FastingLog({
    this.remoteId,
    this.userId,
    required this.startAt,
    this.endAt,
    required this.status,
    this.targetMinutes,
    this.milestones = const [],
    this.source = 'app',
    this.note,
    this.appSessionId,
  });

  /// 화면·알림에서 쓰는 안정적인 id.
  /// 앱이 만든 행은 app_session_id, 채팅 행은 remote id.
  String get sessionId {
    final local = appSessionId;
    if (local != null && local.isNotEmpty) return local;
    return 'remote:$remoteId';
  }

  TrackingSession toSession() {
    return TrackingSession(
      id: sessionId,
      type: SessionType.fasting,
      startTime: startAt.toLocal(),
      endTime: status == SessionStatus.active ? null : endAt?.toLocal(),
      targetDuration: (targetMinutes != null && targetMinutes! > 0)
          ? Duration(minutes: targetMinutes!)
          : null,
      status: status,
      note: note,
      origin: source,
    );
  }

  FastingLog copyWith({
    int? remoteId,
    String? userId,
    DateTime? startAt,
    DateTime? endAt,
    bool clearEnd = false,
    SessionStatus? status,
    int? targetMinutes,
    List<int>? milestones,
    String? source,
    String? note,
    String? appSessionId,
  }) {
    return FastingLog(
      remoteId: remoteId ?? this.remoteId,
      userId: userId ?? this.userId,
      startAt: startAt ?? this.startAt,
      endAt: clearEnd ? null : (endAt ?? this.endAt),
      status: status ?? this.status,
      targetMinutes: targetMinutes ?? this.targetMinutes,
      milestones: milestones ?? this.milestones,
      source: source ?? this.source,
      note: note ?? this.note,
      appSessionId: appSessionId ?? this.appSessionId,
    );
  }

  static FastingLog? tryFromRow(Map<String, dynamic> row) {
    final status = _statusOf(row['status']);
    final start = _timeOf(row['start_at']);
    final remoteId = _intOf(row['id']);
    if (status == null || start == null || remoteId == null) return null;
    final source = _sourceOf(row['source']);
    if (source == null) return null;
    final target = _intOf(row['target_minutes']);
    return FastingLog(
      remoteId: remoteId,
      userId: _stringOf(row['user_id']),
      startAt: start,
      endAt: _timeOf(row['end_at']),
      status: status,
      targetMinutes: target != null && target > 0 ? target : null,
      milestones: _milestonesOf(row['milestones']),
      source: source,
      note: _stringOf(row['note']),
      appSessionId: _stringOf(row['app_session_id']),
    );
  }

  Map<String, dynamic> toCacheJson() => {
    'remoteId': remoteId,
    'userId': userId,
    'startAt': startAt.toUtc().toIso8601String(),
    'endAt': endAt?.toUtc().toIso8601String(),
    'status': status.name,
    'targetMinutes': targetMinutes,
    'milestones': milestones,
    'source': source,
    'note': note,
    'appSessionId': appSessionId,
  };

  static FastingLog? tryFromCacheJson(Map<String, dynamic> json) {
    final status = _statusOf(json['status']);
    final start = _timeOf(json['startAt']);
    if (status == null || start == null) return null;
    final source = _sourceOf(json['source']);
    if (source == null) return null;
    final target = _intOf(json['targetMinutes']);
    return FastingLog(
      remoteId: _intOf(json['remoteId']),
      userId: _stringOf(json['userId']),
      startAt: start,
      endAt: _timeOf(json['endAt']),
      status: status,
      targetMinutes: target != null && target > 0 ? target : null,
      milestones: _milestonesOf(json['milestones']),
      source: source,
      note: _stringOf(json['note']),
      appSessionId: _stringOf(json['appSessionId']),
    );
  }
}

const fastingTerminalStatuses = <SessionStatus>{
  SessionStatus.completed,
  SessionStatus.failed,
  SessionStatus.cancelled,
};

/// end_at ≥ start_at 제약을 맞춘다.
DateTime safeFastingEnd(DateTime startAt, DateTime? endAt) {
  final end = endAt ?? DateTime.now();
  if (end.isBefore(startAt)) return startAt;
  return end;
}

/// 목표 시간이 없으면 null. 있으면 1분 이상으로 올린다.
int? fastingTargetMinutes(Duration? duration) {
  if (duration == null || duration.inSeconds <= 0) return null;
  final minutes = (duration.inSeconds + 59) ~/ 60;
  if (minutes <= 0) return null;
  return minutes;
}

/// 앱이 넣는 행. source는 항상 app. 목표·메모·종료 시각이 없으면 키를 빼서
/// 서버 기본값(null, milestones '{}')을 그대로 쓴다.
Map<String, dynamic> buildFastingInsert({
  required String userId,
  required DateTime startAt,
  required SessionStatus status,
  String? appSessionId,
  int? targetMinutes,
  String? note,
  DateTime? endAt,
}) {
  final map = <String, dynamic>{
    'user_id': userId,
    'start_at': startAt.toUtc().toIso8601String(),
    'status': status.name,
    'source': 'app',
  };
  if (appSessionId != null && appSessionId.isNotEmpty) {
    map['app_session_id'] = appSessionId;
  }
  if (targetMinutes != null && targetMinutes > 0) {
    map['target_minutes'] = targetMinutes;
  }
  final trimmed = note?.trim();
  if (trimmed != null && trimmed.isNotEmpty) map['note'] = trimmed;
  if (status != SessionStatus.active) {
    map['end_at'] = safeFastingEnd(startAt, endAt).toUtc().toIso8601String();
  }
  return map;
}

/// 진행 중 행을 닫을 때 보내는 열만. source·milestones·start_at은 건드리지 않는다.
Map<String, dynamic> buildFastingFinish({
  required DateTime endAt,
  required SessionStatus status,
}) {
  return {'end_at': endAt.toUtc().toIso8601String(), 'status': status.name};
}

SessionStatus? _statusOf(Object? raw) {
  if (raw is! String) return null;
  for (final status in SessionStatus.values) {
    if (status.name == raw) return status;
  }
  return null;
}

String? _sourceOf(Object? raw) {
  if (raw == null) return 'app';
  if (raw is! String) return null;
  if (raw == 'app' || raw == 'chat') return raw;
  return null;
}

String? _stringOf(Object? raw) {
  if (raw == null) return null;
  final text = raw.toString();
  if (text.isEmpty) return null;
  return text;
}

int? _intOf(Object? raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw.toString());
}

DateTime? _timeOf(Object? raw) {
  if (raw == null) return null;
  return DateTime.tryParse(raw.toString());
}

List<int> _milestonesOf(Object? raw) {
  if (raw == null) return const [];
  if (raw is List) {
    return [
      for (final item in raw)
        if (_intOf(item) != null) _intOf(item)!,
    ];
  }
  if (raw is String) {
    final body = raw.replaceAll('{', '').replaceAll('}', '').trim();
    if (body.isEmpty) return const [];
    return [
      for (final part in body.split(','))
        if (int.tryParse(part.trim()) != null) int.parse(part.trim()),
    ];
  }
  return const [];
}
