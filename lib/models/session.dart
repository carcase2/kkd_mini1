enum SessionType { fasting, abstinence }

enum SessionStatus { active, completed, failed, cancelled }

class TrackingSession {
  final String id;
  final SessionType type;
  final DateTime startTime;
  final DateTime? endTime;
  final Duration? targetDuration; // null = open-ended (시간 지정 없음)
  final SessionStatus status;
  final String? note;

  const TrackingSession({
    required this.id,
    required this.type,
    required this.startTime,
    this.endTime,
    this.targetDuration,
    required this.status,
    this.note,
  });

  bool get isOpenEnded => targetDuration == null;

  Duration get elapsed {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }

  Duration? get remaining {
    if (targetDuration == null || status != SessionStatus.active) return null;
    final left = targetDuration! - elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  /// 목표 대비 진행률. 목표 초과 시 1.0 초과 가능 (예: 1.1 = 110%).
  double get progress {
    if (targetDuration == null || targetDuration!.inSeconds == 0) return 0;
    return elapsed.inSeconds / targetDuration!.inSeconds;
  }

  bool get isTargetReached {
    if (targetDuration == null) return false;
    return elapsed >= targetDuration!;
  }

  /// 종료 시 상태. 단식·금욕은 지난 시간 기록이므로 항상 완료.
  SessionStatus get endStatus => SessionStatus.completed;

  TrackingSession copyWith({
    String? id,
    SessionType? type,
    DateTime? startTime,
    DateTime? endTime,
    Duration? targetDuration,
    bool clearTarget = false,
    SessionStatus? status,
    String? note,
  }) {
    return TrackingSession(
      id: id ?? this.id,
      type: type ?? this.type,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      targetDuration: clearTarget ? null : (targetDuration ?? this.targetDuration),
      status: status ?? this.status,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime?.toIso8601String(),
        'targetDurationSeconds': targetDuration?.inSeconds,
        'status': status.name,
        'note': note,
      };

  factory TrackingSession.fromJson(Map<String, dynamic> json) {
    return TrackingSession(
      id: json['id'] as String,
      type: SessionType.values.byName(json['type'] as String),
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: json['endTime'] != null
          ? DateTime.parse(json['endTime'] as String)
          : null,
      targetDuration: json['targetDurationSeconds'] != null
          ? Duration(seconds: json['targetDurationSeconds'] as int)
          : null,
      status: SessionStatus.values.byName(json['status'] as String),
      note: json['note'] as String?,
    );
  }
}

class MasturbationLog {
  final String id;
  final DateTime timestamp;
  final String? note;

  const MasturbationLog({
    required this.id,
    required this.timestamp,
    this.note,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'note': note,
      };

  factory MasturbationLog.fromJson(Map<String, dynamic> json) {
    return MasturbationLog(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      note: json['note'] as String?,
    );
  }
}

