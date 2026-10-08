import 'package:discipline_tracker/models/session.dart';
import 'package:discipline_tracker/utils/fasting_benefits.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('20시간을 넘어도 실제 시간과 다음 구간이 이어진다', () {
    final at19 = fastingBenefitsFor(const Duration(hours: 19));
    expect(at19.current.from, const Duration(hours: 18));
    expect(at19.next?.from, const Duration(hours: 20));

    final at21 = fastingBenefitsFor(const Duration(hours: 21, minutes: 10));
    expect(at21.current.from, const Duration(hours: 20));
    expect(at21.next?.from, const Duration(hours: 22));
    expect(
      fastingHourHeadline(const Duration(hours: 21, minutes: 10)),
      '21시간 지났습니다',
    );

    final at24 = fastingBenefitsFor(const Duration(hours: 24));
    expect(at24.current.title, '하루 단식 구간');
    expect(fastingHourHeadline(const Duration(hours: 24, minutes: 40)),
        '24시간 지났습니다');

    final at30 = fastingBenefitsFor(const Duration(hours: 30));
    expect(at30.current.title, '하루를 넘긴 단식');
    expect(fastingHourHeadline(const Duration(hours: 100)), '100시간 지났습니다');
    expect(fastingBenefitsFor(const Duration(hours: 100)).current.from,
        const Duration(hours: 96));
  });

  test('16시간·18시간에 도달하면 그 시간 문구가 된다', () {
    expect(
      fastingHourHeadline(const Duration(hours: 16, minutes: 10)),
      '16시간 지났습니다',
    );
    expect(
      fastingBenefitsFor(const Duration(hours: 16, minutes: 10)).next?.from,
      const Duration(hours: 18),
    );

    expect(fastingHourHeadline(const Duration(hours: 18)), '18시간 지났습니다');
    expect(fastingProgressCaption(const Duration(hours: 18, minutes: 5)),
        '18시간 지남 · 깊은 지방 연소');
    expect(
      fastingProgressCaption(const Duration(hours: 25)),
      '25시간 지남 · 하루 단식 구간',
    );
  });

  test('시작 직후에는 0시간 문구를 쓰지 않는다', () {
    expect(
      fastingHourHeadline(const Duration(minutes: 20)),
      '단식을 시작했습니다',
    );
  });

  test('알림은 12시간 이후의 여러 구간을 포함한다', () {
    expect(
      fastingNotifyHours,
      containsAll(<int>[12, 16, 18, 20, 22, 24, 30, 36, 48, 72, 96]),
    );
    expect(fastingNotifyHours, isNot(contains(4)));
    for (final hours in fastingNotifyHours) {
      expect(fastingMilestoneAtHours(hours), isNotNull);
    }
  });

  test('단식은 목표보다 짧아도 종료 시 완료다', () {
    final session = TrackingSession(
      id: '1',
      type: SessionType.fasting,
      startTime: DateTime(2026, 9, 22, 8),
      endTime: DateTime(2026, 9, 22, 12),
      targetDuration: const Duration(hours: 16),
      status: SessionStatus.active,
    );
    expect(session.endStatus, SessionStatus.completed);
    expect(session.isTargetReached, isFalse);
  });

  test('금욕은 예전 목표가 있어도 종료 시 완료다', () {
    final session = TrackingSession(
      id: '2',
      type: SessionType.abstinence,
      startTime: DateTime(2026, 9, 22, 8),
      endTime: DateTime(2026, 9, 23, 12),
      targetDuration: const Duration(days: 7),
      status: SessionStatus.active,
    );
    expect(session.endStatus, SessionStatus.completed);
    expect(session.isTargetReached, isFalse);
  });
}
