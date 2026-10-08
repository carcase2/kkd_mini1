import 'package:discipline_tracker/theme/app_theme.dart';
import 'package:discipline_tracker/utils/abstinence_benefits.dart';
import 'package:discipline_tracker/widgets/abstinence_start_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('경과에 따라 구간 이름이 바뀐다', () {
    expect(
      abstinenceProgressCaption(const Duration(minutes: 20)),
      '시작 · 결심 단계',
    );
    expect(
      abstinenceProgressCaption(const Duration(hours: 12, minutes: 10)),
      '12시간 지남 · 반나절 유지',
    );
    expect(
      abstinenceProgressCaption(const Duration(days: 7, hours: 2)),
      '7일 지남 · 일주일 유지',
    );
    expect(
      abstinenceHistoryStage(const Duration(days: 30)),
      '한 달 유지',
    );
  });

  test('알림은 12시간 이후 구간만 포함한다', () {
    final labels = [
      for (final mark in abstinenceNotifyMarks) abstinenceMarkLabel(mark.from),
    ];
    expect(labels, containsAll(<String>['12시간', '1일', '7일', '30일', '90일']));
    expect(labels, isNot(contains('6시간')));
    expect(abstinenceNotifyId(const Duration(days: 7)), 3100 + 24 * 7);
  });

  testWidgets('시작 화면은 목표 시간 없이 시작 버튼을 보여 준다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: AbstinenceStartCard(
            accent: const Color(0xFF7C6BFF),
            soft: const Color(0xFFF0EDFF),
            onStartNow: () {},
            onStartPast: () {},
          ),
        ),
      ),
    );

    expect(find.text('금욕 시작'), findsOneWidget);
    expect(find.text('지난 시각부터 시작'), findsOneWidget);
    expect(find.textContaining('1일, 7일, 30일'), findsOneWidget);
    expect(find.text('1일'), findsOneWidget);
    expect(find.text('7일'), findsOneWidget);
    expect(find.text('30일'), findsOneWidget);
    expect(find.text('목표 시간 선택'), findsNothing);
  });
}
