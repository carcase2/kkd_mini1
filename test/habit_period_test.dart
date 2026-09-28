import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:discipline_tracker/models/habit.dart';
import 'package:discipline_tracker/providers/app_state.dart';
import 'package:discipline_tracker/screens/habit_screen.dart';
import 'package:discipline_tracker/screens/shell.dart';
import 'package:discipline_tracker/theme/app_theme.dart';

Habit _habit({
  required int times,
  required int every,
  required HabitPeriodUnit unit,
  DateTime? anchor,
  String id = 'h',
}) {
  final base = anchor ?? DateTime(2026, 9, 1);
  return Habit(
    id: id,
    name: '테스트',
    timesPerPeriod: times,
    every: every,
    unit: unit,
    createdAt: base,
    anchor: base,
  );
}

void main() {
  test('일주일에 한 번은 이번 주 월요일부터 센다', () {
    final habit = _habit(times: 1, every: 1, unit: HabitPeriodUnit.week);
    final wednesday = DateTime(2026, 9, 30);
    final window = habitWindow(habit, wednesday);

    expect(window.start.weekday, DateTime.monday);
    expect(window.end.difference(window.start), const Duration(days: 7));
    expect(window.contains(wednesday), isTrue);
    expect(window.contains(window.start), isTrue);
    expect(window.contains(window.end), isFalse);
    expect(
      window.contains(window.start.subtract(const Duration(minutes: 1))),
      isFalse,
    );
    expect(habitPeriodLabel(habit), '일주일에 한 번');
    expect(habitWindowNoun(habit), '이번 주');
  });

  test('3일 주기는 기준일부터 묶고, 기준일 이전도 포함한다', () {
    final anchor = DateTime(2026, 9, 10);
    final habit = _habit(
      times: 1,
      every: 3,
      unit: HabitPeriodUnit.day,
      anchor: anchor,
    );

    final first = habitWindow(habit, DateTime(2026, 9, 10, 21));
    expect(first.start, DateTime(2026, 9, 10));
    expect(first.end, DateTime(2026, 9, 13));

    final next = habitWindow(habit, DateTime(2026, 9, 13, 0, 1));
    expect(next.start, DateTime(2026, 9, 13));

    final before = habitWindow(habit, DateTime(2026, 9, 8, 12));
    expect(before.start, DateTime(2026, 9, 7));
    expect(before.end, DateTime(2026, 9, 10));
    expect(habitPeriodLabel(habit), '3일에 한 번');
  });

  test('2주·2달 주기와 한 달 주기를 구분한다', () {
    final anchor = DateTime(2026, 3, 15);
    final twoWeeks = _habit(
      times: 1,
      every: 2,
      unit: HabitPeriodUnit.week,
      anchor: anchor,
    );
    final weekWindow = habitWindow(twoWeeks, DateTime(2026, 3, 20));
    expect(weekWindow.start, DateTime(2026, 3, 9));
    expect(weekWindow.end, DateTime(2026, 3, 23));
    expect(habitPeriodLabel(twoWeeks), '2주에 한 번');

    final twoMonths = _habit(
      times: 2,
      every: 2,
      unit: HabitPeriodUnit.month,
      anchor: anchor,
    );
    final monthWindow = habitWindow(twoMonths, DateTime(2026, 10, 2));
    expect(monthWindow.start, DateTime(2026, 9, 1));
    expect(monthWindow.end, DateTime(2026, 11, 1));
    expect(habitPeriodLabel(twoMonths), '2달에 두 번');

    final calendarMonth = _habit(
      times: 1,
      every: 1,
      unit: HabitPeriodUnit.month,
    );
    final september = habitWindow(calendarMonth, DateTime(2026, 9, 28, 23));
    expect(september.start, DateTime(2026, 9, 1));
    expect(september.end, DateTime(2026, 10, 1));
    expect(habitPeriodLabel(calendarMonth), '한 달에 한 번');
  });

  test('이번 주기 안의 체크만 횟수에 넣는다', () {
    final habit = _habit(times: 1, every: 1, unit: HabitPeriodUnit.week);
    final window = habitWindow(habit, DateTime(2026, 9, 30));
    final checks = [
      HabitCheck(
        id: 'old',
        habitId: habit.id,
        checkedAt: window.start.subtract(const Duration(hours: 2)),
      ),
      HabitCheck(
        id: 'now',
        habitId: habit.id,
        checkedAt: DateTime(2026, 9, 30, 12),
      ),
      HabitCheck(
        id: 'other',
        habitId: 'else',
        checkedAt: DateTime(2026, 9, 30, 12),
      ),
    ];

    expect(
      countChecksInWindow(habit, checks, DateTime(2026, 9, 30, 18)),
      1,
    );
  });

  test('저장된 항목은 다시 읽어 같은 주기를 유지한다', () {
    final original = starterHabits(DateTime(2026, 9, 28, 8)).first;
    final restored = Habit.fromJson(original.toJson());

    expect(restored.name, '순대국밥 먹기');
    expect(restored.unit, HabitPeriodUnit.week);
    expect(restored.every, 1);
    expect(restored.timesPerPeriod, 1);
    expect(habitPeriodLabel(restored), '일주일에 한 번');
    expect(dateOnly(restored.anchor), DateTime(2026, 9, 28));
  });

  test('주기를 바꾸면 오늘부터 다시 센다', () async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    await state.addHabit(
      name: '순대국밥 먹기',
      timesPerPeriod: 1,
      every: 1,
      unit: HabitPeriodUnit.week,
    );
    final created = state.habits.single;
    await state.updateHabit(
      created.copyWith(every: 3, unit: HabitPeriodUnit.day),
    );

    final updated = state.habits.single;
    expect(updated.every, 3);
    expect(updated.unit, HabitPeriodUnit.day);
    expect(dateOnly(updated.anchor), dateOnly(DateTime.now()));
    expect(habitWindow(updated, DateTime.now()).start, dateOnly(DateTime.now()));
    expect(habitPeriodLabel(updated), '3일에 한 번');
    state.dispose();
  });

  testWidgets('빈 화면에서 순대국밥을 추가하고 체크한다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('ko');
    final state = AppState();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const HabitScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('체크할 항목이 없어요'), findsOneWidget);
    await tester.tap(find.text('순대국밥 먹기 · 일주일에 한 번'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('순대국밥 먹기'), findsOneWidget);
    expect(find.text('일주일에 한 번'), findsOneWidget);
    expect(find.text('이번 주 0/1'), findsOneWidget);

    await tester.tap(find.text('체크'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('이번 주 완료'), findsOneWidget);
    expect(state.habitChecksInCurrentWindow(state.habits.single), 1);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('좁은 화면에서도 습관 탭이 들어간다', (tester) async {
    await initializeDateFormatting('ko');
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = AppState();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const AppShell(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('습관'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('습관').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('주기마다 횟수를 체크'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
}
