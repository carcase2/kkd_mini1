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

  /// 종료 시 성공/실패. 자유 모드·목표 달성 = 성공, 미달 = 실패.
  SessionStatus get endStatus {
    if (isOpenEnded || isTargetReached) return SessionStatus.completed;
    return SessionStatus.failed;
  }

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

/// 프리셋 시간 옵션
class DurationPreset {
  final String label;
  final Duration? duration; // null = 시간 지정 없음
  final String description;

  const DurationPreset({
    required this.label,
    required this.duration,
    required this.description,
  });
}

const fastingPresets = [
  DurationPreset(label: '12시간', duration: Duration(hours: 12), description: '입문 단식'),
  DurationPreset(label: '16:8', duration: Duration(hours: 16), description: '가장 인기 있는 단식'),
  DurationPreset(label: '18시간', duration: Duration(hours: 18), description: '중급 단식'),
  DurationPreset(label: '20시간', duration: Duration(hours: 20), description: 'OMAD 준비'),
  DurationPreset(label: '24시간', duration: Duration(hours: 24), description: '하루 단식'),
  DurationPreset(label: '36시간', duration: Duration(hours: 36), description: '심화 단식'),
  DurationPreset(label: '48시간', duration: Duration(hours: 48), description: '2일 단식'),
  DurationPreset(label: '72시간', duration: Duration(hours: 72), description: '3일 단식'),
  DurationPreset(label: '자유', duration: null, description: '목표 없이 시작'),
];

const abstinencePresets = [
  DurationPreset(label: '1일', duration: Duration(days: 1), description: '하루 도전'),
  DurationPreset(label: '3일', duration: Duration(days: 3), description: '주말 챌린지'),
  DurationPreset(label: '7일', duration: Duration(days: 7), description: '일주일'),
  DurationPreset(label: '14일', duration: Duration(days: 14), description: '2주 챌린지'),
  DurationPreset(label: '30일', duration: Duration(days: 30), description: '한 달 금욕'),
  DurationPreset(label: '60일', duration: Duration(days: 60), description: '2개월'),
  DurationPreset(label: '90일', duration: Duration(days: 90), description: '리부트'),
  DurationPreset(label: '자유', duration: null, description: '목표 없이 시작'),
];
