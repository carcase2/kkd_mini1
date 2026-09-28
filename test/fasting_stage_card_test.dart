import 'package:discipline_tracker/theme/app_theme.dart';
import 'package:discipline_tracker/widgets/fasting_stage_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('16시간이 되면 그 시간과 장점이 보인다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: FastingStageCard(
            elapsed: Duration(hours: 16, minutes: 5),
            accent: Color(0xFF3B82F6),
            soft: Color(0xFFE8F1FF),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('16시간 지났습니다'), findsOneWidget);
    expect(find.text('오토파지 입문'), findsOneWidget);
    expect(find.textContaining('다음 18시간'), findsOneWidget);
    expect(find.text('20시간'), findsOneWidget);
    expect(find.text('24시간'), findsOneWidget);
    expect(find.text('48시간'), findsOneWidget);
  });

  testWidgets('21시간이면 20시간에 멈춰 보이지 않는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: FastingStageCard(
            elapsed: Duration(hours: 21, minutes: 5),
            accent: Color(0xFF3B82F6),
            soft: Color(0xFFE8F1FF),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('21시간 지났습니다'), findsOneWidget);
    expect(find.text('지방 대사 안정'), findsOneWidget);
    expect(find.textContaining('다음 22시간'), findsOneWidget);
  });

  testWidgets('24시간이면 하루 단식 장점이 보인다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: FastingStageCard(
            elapsed: Duration(hours: 24, minutes: 20),
            accent: Color(0xFF3B82F6),
            soft: Color(0xFFE8F1FF),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('24시간 지났습니다'), findsOneWidget);
    expect(find.text('하루 단식 구간'), findsOneWidget);
    expect(find.textContaining('다음 30시간'), findsOneWidget);
  });

  testWidgets('시작 화면은 시간 목표 없이 시작 버튼을 보여 준다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: FastingStartCard(
            accent: const Color(0xFF3B82F6),
            soft: const Color(0xFFE8F1FF),
            onStartNow: () {},
            onStartPast: () {},
          ),
        ),
      ),
    );

    expect(find.text('단식 시작'), findsOneWidget);
    expect(find.text('지난 시각부터 시작'), findsOneWidget);
    expect(find.textContaining('12시간, 24시간, 48시간'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('24'), findsOneWidget);
    expect(find.text('36'), findsOneWidget);
  });
}
