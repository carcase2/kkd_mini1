/// 주기마다 횟수를 세는 체크 항목.
/// 예: 일주일에 한 번 순대국밥, 3일에 한 번, 한 달에 두 번.
enum HabitPeriodUnit { day, week, month }

class Habit {
  final String id;
  final String name;

  /// 한 주기 안의 목표 횟수.
  final int timesPerPeriod;

  /// 주기 길이. 1주, 2주, 3일처럼 단위와 함께 읽는다.
  final int every;
  final HabitPeriodUnit unit;
  final bool active;
  final String? note;
  final DateTime createdAt;

  /// 임의 길이 주기(2주, 3일, 2달)의 기준 날짜.
  /// 매주·매일·매월(every == 1)은 달력 경계라 이 값을 쓰지 않는다.
  final DateTime anchor;

  const Habit({
    required this.id,
    required this.name,
    required this.timesPerPeriod,
    required this.every,
    required this.unit,
    this.active = true,
    this.note,
    required this.createdAt,
    required this.anchor,
  });

  Habit copyWith({
    String? id,
    String? name,
    int? timesPerPeriod,
    int? every,
    HabitPeriodUnit? unit,
    bool? active,
    String? note,
    bool clearNote = false,
    DateTime? createdAt,
    DateTime? anchor,
  }) {
    return Habit(
      id: id ?? this.id,
      name: name ?? this.name,
      timesPerPeriod: timesPerPeriod ?? this.timesPerPeriod,
      every: every ?? this.every,
      unit: unit ?? this.unit,
      active: active ?? this.active,
      note: clearNote ? null : (note ?? this.note),
      createdAt: createdAt ?? this.createdAt,
      anchor: anchor ?? this.anchor,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'timesPerPeriod': timesPerPeriod,
        'every': every,
        'unit': unit.name,
        'active': active,
        'note': note,
        'createdAt': createdAt.toIso8601String(),
        'anchor': anchor.toIso8601String(),
      };

  factory Habit.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.parse(json['createdAt'] as String);
    final anchorRaw = json['anchor'] as String?;
    final anchor = anchorRaw == null
        ? dateOnly(createdAt)
        : dateOnly(DateTime.parse(anchorRaw));
    return Habit(
      id: json['id'] as String,
      name: json['name'] as String,
      timesPerPeriod: (json['timesPerPeriod'] as num?)?.toInt().clamp(1, 99) ?? 1,
      every: (json['every'] as num?)?.toInt().clamp(1, 366) ?? 1,
      unit: habitPeriodUnitFromName(json['unit'] as String?),
      active: json['active'] as bool? ?? true,
      note: json['note'] as String?,
      createdAt: createdAt,
      anchor: anchor,
    );
  }
}

/// 항목을 한 번 체크한 기록.
class HabitCheck {
  final String id;
  final String habitId;
  final DateTime checkedAt;
  final String? note;

  const HabitCheck({
    required this.id,
    required this.habitId,
    required this.checkedAt,
    this.note,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'habitId': habitId,
        'checkedAt': checkedAt.toIso8601String(),
        'note': note,
      };

  factory HabitCheck.fromJson(Map<String, dynamic> json) {
    return HabitCheck(
      id: json['id'] as String,
      habitId: json['habitId'] as String,
      checkedAt: DateTime.parse(json['checkedAt'] as String),
      note: json['note'] as String?,
    );
  }
}

class HabitWindow {
  final DateTime start;
  final DateTime end;

  const HabitWindow({required this.start, required this.end});

  bool contains(DateTime time) => !time.isBefore(start) && time.isBefore(end);
}

class HabitPreset {
  final String label;
  final int times;
  final int every;
  final HabitPeriodUnit unit;

  const HabitPreset({
    required this.label,
    required this.times,
    required this.every,
    required this.unit,
  });
}

const habitPresets = [
  HabitPreset(label: '매일', times: 1, every: 1, unit: HabitPeriodUnit.day),
  HabitPreset(label: '3일에 한 번', times: 1, every: 3, unit: HabitPeriodUnit.day),
  HabitPreset(
    label: '일주일에 한 번',
    times: 1,
    every: 1,
    unit: HabitPeriodUnit.week,
  ),
  HabitPreset(
    label: '일주일에 두 번',
    times: 2,
    every: 1,
    unit: HabitPeriodUnit.week,
  ),
  HabitPreset(label: '2주에 한 번', times: 1, every: 2, unit: HabitPeriodUnit.week),
  HabitPreset(
    label: '한 달에 한 번',
    times: 1,
    every: 1,
    unit: HabitPeriodUnit.month,
  ),
];

/// 처음 설치(또는 이 기능이 아직 저장되지 않은 기기)에 넣어 주는 예시.
List<Habit> starterHabits(DateTime now) {
  final anchor = dateOnly(now);
  return [
    Habit(
      id: 'starter_sundae_gukbap',
      name: '순대국밥 먹기',
      timesPerPeriod: 1,
      every: 1,
      unit: HabitPeriodUnit.week,
      createdAt: now,
      anchor: anchor,
    ),
    Habit(
      id: 'starter_convenience_food',
      name: '편의점 음식 먹기',
      timesPerPeriod: 1,
      every: 1,
      unit: HabitPeriodUnit.week,
      createdAt: now.add(const Duration(milliseconds: 1)),
      anchor: anchor,
    ),
  ];
}

HabitPeriodUnit habitPeriodUnitFromName(String? raw) {
  switch (raw) {
    case 'day':
      return HabitPeriodUnit.day;
    case 'month':
      return HabitPeriodUnit.month;
    case 'week':
    default:
      return HabitPeriodUnit.week;
  }
}

DateTime dateOnly(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// 음수도 내림 나눗셈. Dart `~/` 는 0 쪽으로 자른다.
int floorDiv(int a, int b) {
  if (b <= 0) {
    throw ArgumentError.value(b, 'b', 'must be positive');
  }
  if (a >= 0) return a ~/ b;
  return -(((-a) + b - 1) ~/ b);
}

DateTime _mondayOf(DateTime day) {
  final date = dateOnly(day);
  return date.subtract(Duration(days: date.weekday - DateTime.monday));
}

DateTime _monthStart(DateTime day) {
  final date = dateOnly(day);
  return DateTime(date.year, date.month, 1);
}

int _monthIndex(DateTime monthStart) =>
    monthStart.year * 12 + (monthStart.month - 1);

DateTime _monthFromIndex(int index) {
  var year = index ~/ 12;
  var month = index % 12;
  if (month < 0) {
    month += 12;
    year -= 1;
  }
  return DateTime(year, month + 1, 1);
}

/// [instant]가 속한 현재 주기. 끝 시각은 포함하지 않는다.
HabitWindow habitWindow(Habit habit, DateTime instant) {
  final every = habit.every <= 0 ? 1 : habit.every;
  final today = dateOnly(instant);

  switch (habit.unit) {
    case HabitPeriodUnit.day:
      if (every == 1) {
        return HabitWindow(
          start: today,
          end: today.add(const Duration(days: 1)),
        );
      }
      final anchor = dateOnly(habit.anchor);
      final index = floorDiv(today.difference(anchor).inDays, every);
      final start = anchor.add(Duration(days: index * every));
      return HabitWindow(
        start: start,
        end: start.add(Duration(days: every)),
      );
    case HabitPeriodUnit.week:
      if (every == 1) {
        final start = _mondayOf(today);
        return HabitWindow(
          start: start,
          end: start.add(const Duration(days: 7)),
        );
      }
      final anchor = _mondayOf(habit.anchor);
      final weeks = floorDiv(today.difference(anchor).inDays, 7);
      final index = floorDiv(weeks, every);
      final start = anchor.add(Duration(days: index * every * 7));
      return HabitWindow(
        start: start,
        end: start.add(Duration(days: every * 7)),
      );
    case HabitPeriodUnit.month:
      if (every == 1) {
        final start = _monthStart(today);
        return HabitWindow(
          start: start,
          end: DateTime(start.year, start.month + 1, 1),
        );
      }
      final anchor = _monthStart(habit.anchor);
      final diff = _monthIndex(_monthStart(today)) - _monthIndex(anchor);
      final index = floorDiv(diff, every);
      final start = _monthFromIndex(_monthIndex(anchor) + index * every);
      final end = _monthFromIndex(_monthIndex(start) + every);
      return HabitWindow(start: start, end: end);
  }
}

int countChecksInWindow(
  Habit habit,
  Iterable<HabitCheck> checks,
  DateTime instant,
) {
  final window = habitWindow(habit, instant);
  var count = 0;
  for (final check in checks) {
    if (check.habitId != habit.id) continue;
    if (window.contains(check.checkedAt)) count++;
  }
  return count;
}

String _timesPhrase(int times) {
  if (times == 1) return '한 번';
  if (times == 2) return '두 번';
  return '$times번';
}

String habitPeriodLabel(Habit habit) {
  final times = _timesPhrase(habit.timesPerPeriod);
  final every = habit.every;

  switch (habit.unit) {
    case HabitPeriodUnit.day:
      if (every == 1) {
        return habit.timesPerPeriod == 1 ? '매일' : '하루에 $times';
      }
      return '$every일에 $times';
    case HabitPeriodUnit.week:
      if (every == 1) return '일주일에 $times';
      return '$every주에 $times';
    case HabitPeriodUnit.month:
      if (every == 1) return '한 달에 $times';
      return '$every달에 $times';
  }
}

/// 카드에 쓰는 현재 구간 이름. 오늘 / 이번 주 / 이번 달 / 이번 주기.
String habitWindowNoun(Habit habit) {
  if (habit.every == 1) {
    switch (habit.unit) {
      case HabitPeriodUnit.day:
        return '오늘';
      case HabitPeriodUnit.week:
        return '이번 주';
      case HabitPeriodUnit.month:
        return '이번 달';
    }
  }
  return '이번 주기';
}

int maxEveryFor(HabitPeriodUnit unit) {
  switch (unit) {
    case HabitPeriodUnit.day:
      return 90;
    case HabitPeriodUnit.week:
      return 52;
    case HabitPeriodUnit.month:
      return 24;
  }
}

String everyUnitLabel(HabitPeriodUnit unit) {
  switch (unit) {
    case HabitPeriodUnit.day:
      return '일';
    case HabitPeriodUnit.week:
      return '주';
    case HabitPeriodUnit.month:
      return '달';
  }
}
