/// 복용 주기 있는 약
class Medication {
  final String id;
  final String name;
  /// 복용 간격 (분). 예: 24시간 = 1440
  final int intervalMinutes;
  final String? note;
  final bool active;
  final DateTime createdAt;

  const Medication({
    required this.id,
    required this.name,
    required this.intervalMinutes,
    this.note,
    this.active = true,
    required this.createdAt,
  });

  Duration get interval => Duration(minutes: intervalMinutes);

  String get intervalLabel => formatIntervalMinutes(intervalMinutes);

  Medication copyWith({
    String? id,
    String? name,
    int? intervalMinutes,
    String? note,
    bool clearNote = false,
    bool? active,
    DateTime? createdAt,
  }) {
    return Medication(
      id: id ?? this.id,
      name: name ?? this.name,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      note: clearNote ? null : (note ?? this.note),
      active: active ?? this.active,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'intervalMinutes': intervalMinutes,
        'note': note,
        'active': active,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Medication.fromJson(Map<String, dynamic> json) {
    return Medication(
      id: json['id'] as String,
      name: json['name'] as String,
      intervalMinutes: json['intervalMinutes'] as int,
      note: json['note'] as String?,
      active: json['active'] as bool? ?? true,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

/// 약 복용 기록 1건
class MedicationDose {
  final String id;
  final String medicationId;
  final DateTime takenAt;
  final String? note;
  /// 세트로 함께 복용한 경우 세트 ID
  final String? setId;

  const MedicationDose({
    required this.id,
    required this.medicationId,
    required this.takenAt,
    this.note,
    this.setId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'medicationId': medicationId,
        'takenAt': takenAt.toIso8601String(),
        'note': note,
        'setId': setId,
      };

  factory MedicationDose.fromJson(Map<String, dynamic> json) {
    return MedicationDose(
      id: json['id'] as String,
      medicationId: json['medicationId'] as String,
      takenAt: DateTime.parse(json['takenAt'] as String),
      note: json['note'] as String?,
      setId: json['setId'] as String?,
    );
  }
}

/// 여러 약을 함께 먹는 세트 (예: 비염약 + 비타민)
class MedicationSet {
  final String id;
  final String name;
  final List<String> medicationIds;
  /// 세트 복용 간격 (분)
  final int intervalMinutes;
  final String? note;
  final bool active;
  final DateTime createdAt;

  const MedicationSet({
    required this.id,
    required this.name,
    required this.medicationIds,
    required this.intervalMinutes,
    this.note,
    this.active = true,
    required this.createdAt,
  });

  Duration get interval => Duration(minutes: intervalMinutes);

  String get intervalLabel => formatIntervalMinutes(intervalMinutes);

  MedicationSet copyWith({
    String? id,
    String? name,
    List<String>? medicationIds,
    int? intervalMinutes,
    String? note,
    bool clearNote = false,
    bool? active,
    DateTime? createdAt,
  }) {
    return MedicationSet(
      id: id ?? this.id,
      name: name ?? this.name,
      medicationIds: medicationIds ?? this.medicationIds,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      note: clearNote ? null : (note ?? this.note),
      active: active ?? this.active,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'medicationIds': medicationIds,
        'intervalMinutes': intervalMinutes,
        'note': note,
        'active': active,
        'createdAt': createdAt.toIso8601String(),
      };

  factory MedicationSet.fromJson(Map<String, dynamic> json) {
    return MedicationSet(
      id: json['id'] as String,
      name: json['name'] as String,
      medicationIds: (json['medicationIds'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      intervalMinutes: json['intervalMinutes'] as int,
      note: json['note'] as String?,
      active: json['active'] as bool? ?? true,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

/// 세트 복용 기록 1건 (구성 약 일괄 복용)
class MedicationSetDose {
  final String id;
  final String setId;
  final DateTime takenAt;
  final String? note;

  const MedicationSetDose({
    required this.id,
    required this.setId,
    required this.takenAt,
    this.note,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'setId': setId,
        'takenAt': takenAt.toIso8601String(),
        'note': note,
      };

  factory MedicationSetDose.fromJson(Map<String, dynamic> json) {
    return MedicationSetDose(
      id: json['id'] as String,
      setId: json['setId'] as String,
      takenAt: DateTime.parse(json['takenAt'] as String),
      note: json['note'] as String?,
    );
  }
}

String formatIntervalMinutes(int intervalMinutes) {
  final d = Duration(minutes: intervalMinutes);
  if (d.inDays >= 1 && d.inMinutes % (24 * 60) == 0) {
    final days = d.inDays;
    return days == 1 ? '24시간 (매일)' : '$days일마다';
  }
  if (d.inHours >= 1 && d.inMinutes % 60 == 0) {
    return '${d.inHours}시간마다';
  }
  if (d.inMinutes >= 60) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return m == 0 ? '$h시간마다' : '$h시간 $m분마다';
  }
  return '${d.inMinutes}분마다';
}

/// 복용 간격 프리셋
class IntervalPreset {
  final String label;
  final int minutes;
  final String description;

  const IntervalPreset({
    required this.label,
    required this.minutes,
    required this.description,
  });
}

const medicationIntervalPresets = [
  IntervalPreset(
    label: '6시간',
    minutes: 6 * 60,
    description: '하루 4회',
  ),
  IntervalPreset(
    label: '8시간',
    minutes: 8 * 60,
    description: '하루 3회',
  ),
  IntervalPreset(
    label: '12시간',
    minutes: 12 * 60,
    description: '하루 2회',
  ),
  IntervalPreset(
    label: '24시간',
    minutes: 24 * 60,
    description: '매일 1회 · 3세대 비염약 등',
  ),
  IntervalPreset(
    label: '48시간',
    minutes: 48 * 60,
    description: '이틀에 1회',
  ),
  IntervalPreset(
    label: '7일',
    minutes: 7 * 24 * 60,
    description: '주 1회',
  ),
];
