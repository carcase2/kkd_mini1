/// 단식 경과에 따른 일반적인 단계 설명 (교육·동기 부여용, 의료 조언 아님)
class FastingMilestone {
  /// 이 단계가 시작되는 경과 시간
  final Duration from;
  final String title;
  final String benefits;
  final String summary;

  const FastingMilestone({
    required this.from,
    required this.title,
    required this.benefits,
    required this.summary,
  });
}

/// 단식 마일스톤 (대략적인 구간 · 개인차 있음)
const fastingMilestones = <FastingMilestone>[
  FastingMilestone(
    from: Duration.zero,
    title: '소화 단계',
    summary: '마지막 식사 소화 중',
    benefits: '몸이 음식을 소화하고 혈당이 올라간 상태예요. 물·무가당 차로 수분 보충을 시작해보세요.',
  ),
  FastingMilestone(
    from: Duration(hours: 4),
    title: '혈당·인슐린 안정',
    summary: '혈당이 내려가기 시작',
    benefits: '혈당과 인슐린이 서서히 안정됩니다. 배고픔 신호가 올 수 있어요. 가벼운 산책이 도움이 됩니다.',
  ),
  FastingMilestone(
    from: Duration(hours: 8),
    title: '지방 사용 전환 준비',
    summary: '간 글리코겐 소모 시작',
    benefits: '저장된 글리코겐을 쓰기 시작하고, 지방을 에너지로 쓰는 비율이 조금씩 늘어납니다.',
  ),
  FastingMilestone(
    from: Duration(hours: 12),
    title: '지방 연소 본격화',
    summary: '지방 산화가 늘어나는 구간',
    benefits: '많은 사람들이 12시간 전후부터 지방 연소가 본격화된다고 느껴요. 집중력 변화가 있을 수 있습니다.',
  ),
  FastingMilestone(
    from: Duration(hours: 14),
    title: '대사 전환 가속',
    summary: '케톤 생성 준비',
    benefits: '몸이 지방 대사 쪽으로 더 기울어집니다. 약간의 케톤 생성이 시작될 수 있어요.',
  ),
  FastingMilestone(
    from: Duration(hours: 16),
    title: '오토파지 입문',
    summary: '세포 청소 과정이 활발해질 수 있음',
    benefits: '16시간 전후는 흔히 오토파지(세포 자가 청소)가 활발해진다고 이야기되는 구간입니다. 간헐적 단식 목표로 인기 있어요.',
  ),
  FastingMilestone(
    from: Duration(hours: 18),
    title: '깊은 지방 연소',
    summary: '지방·케톤 활용 증가',
    benefits: '지방 연소와 성장호르몬 관련 반응이 더 두드러질 수 있어요. 어지러우면 무리하지 마세요.',
  ),
  FastingMilestone(
    from: Duration(hours: 20),
    title: '지방 대사 안정',
    summary: '하루 한 끼에 가까운 구간',
    benefits:
        '20시간 전후는 지방을 에너지로 쓰는 상태가 더 안정된다고 이야기되는 구간입니다. 한 끼 식사 전에 자주 머무는 시간이에요.',
  ),
  FastingMilestone(
    from: Duration(hours: 22),
    title: '하루 단식에 근접',
    summary: '24시간에 가까워지는 구간',
    benefits:
        '20시간을 넘겼어요. 곧 하루 단식에 들어갑니다. 수분을 챙기고, 힘들면 무리하지 마세요.',
  ),
  FastingMilestone(
    from: Duration(hours: 24),
    title: '하루 단식 구간',
    summary: '케톤 이용이 더 뚜렷해질 수 있음',
    benefits: '24시간 전후는 케톤 이용이 더 활발해질 수 있는 구간입니다. 수분·전해질을 신경 써주세요.',
  ),
  FastingMilestone(
    from: Duration(hours: 30),
    title: '하루를 넘긴 단식',
    summary: '24시간 이후에도 이어지는 구간',
    benefits:
        '하루를 넘기면 지방을 에너지로 쓰는 상태가 더 이어질 수 있어요. 컨디션을 자주 살피세요.',
  ),
  FastingMilestone(
    from: Duration(hours: 36),
    title: '심화 단식',
    summary: '세포 회복 과정이 더 깊어질 수 있음',
    benefits: '장시간 단식으로 대사·회복 과정이 더 깊어진다고 알려진 구간입니다. 컨디션을 꼼꼼히 살피세요.',
  ),
  FastingMilestone(
    from: Duration(hours: 42),
    title: '이틀에 가까워지는 구간',
    summary: '36시간을 넘긴 심화 단식',
    benefits:
        '36시간을 넘기면 회복 과정이 더 깊어진다고 알려진 구간입니다. 어지러우면 식사를 시작하세요.',
  ),
  FastingMilestone(
    from: Duration(hours: 48),
    title: '이틀 단식',
    summary: '고강도 도전 · 주의 필요',
    benefits: '48시간은 고강도 도전입니다. 몸의 신호를 최우선으로, 힘들면 안전하게 종료하세요.',
  ),
  FastingMilestone(
    from: Duration(hours: 60),
    title: '이틀을 넘긴 단식',
    summary: '48시간 이후의 장기 구간',
    benefits:
        '이틀을 넘긴 단식은 개인차가 큽니다. 몸의 신호를 우선하고, 필요하면 바로 식사를 시작하세요.',
  ),
  FastingMilestone(
    from: Duration(hours: 72),
    title: '사흘 단식',
    summary: '매우 긴 구간 · 주의 필요',
    benefits: '72시간은 개인차가 매우 큽니다. 의료 상담 없이 무리하게 이어가지 않는 것이 좋아요.',
  ),
  FastingMilestone(
    from: Duration(hours: 96),
    title: '나흘 단식',
    summary: '72시간을 넘긴 초장기',
    benefits:
        '나흘 이상은 매우 긴 단식입니다. 이 시간을 넘어도 경과는 계속 쌓이지만, 더 늘리기 전에 몸 상태를 먼저 보세요.',
  ),
];

class FastingBenefitSnapshot {
  final FastingMilestone current;
  final FastingMilestone? next;
  /// 다음 단계까지 남은 시간 (next가 있을 때만)
  final Duration? untilNext;

  const FastingBenefitSnapshot({
    required this.current,
    this.next,
    this.untilNext,
  });
}

/// 경과 시간 기준으로 현재·다음 단식 효능 단계 계산
FastingBenefitSnapshot fastingBenefitsFor(Duration elapsed) {
  final d = elapsed.isNegative ? Duration.zero : elapsed;
  var idx = 0;
  for (var i = 0; i < fastingMilestones.length; i++) {
    if (d >= fastingMilestones[i].from) {
      idx = i;
    } else {
      break;
    }
  }

  final current = fastingMilestones[idx];
  final next = idx + 1 < fastingMilestones.length
      ? fastingMilestones[idx + 1]
      : null;
  final untilNext =
      next == null ? null : next.from - d;

  return FastingBenefitSnapshot(
    current: current,
    next: next,
    untilNext: untilNext != null && untilNext.isNegative
        ? Duration.zero
        : untilNext,
  );
}

/// 알림으로 알릴 시간. 12시간부터의 모든 단계.
List<int> get fastingNotifyHours => [
      for (final milestone in fastingMilestones)
        if (milestone.from.inHours >= 12 &&
            milestone.from.inMinutes.remainder(60) == 0)
          milestone.from.inHours,
    ];

int fastingNotifyId(int hours) => 2100 + hours;

FastingMilestone? fastingMilestoneAtHours(int hours) {
  for (final milestone in fastingMilestones) {
    if (milestone.from.inHours == hours &&
        milestone.from.inMinutes.remainder(60) == 0) {
      return milestone;
    }
  }
  return null;
}

/// 실제 지난 시간. 21시간, 24시간, 100시간도 그 숫자 그대로.
String fastingHourHeadline(Duration elapsed) {
  final hours = elapsed.isNegative ? 0 : elapsed.inHours;
  if (hours <= 0) return '단식을 시작했습니다';
  return '$hours시간 지났습니다';
}

/// 홈·기록용 한 줄. 시간은 실제 경과, 이름은 지금 구간.
String fastingProgressCaption(Duration elapsed) {
  final current = fastingBenefitsFor(elapsed).current;
  final hours = elapsed.isNegative ? 0 : elapsed.inHours;
  if (hours <= 0) return '시작 · ${current.title}';
  return '$hours시간 지남 · ${current.title}';
}

String fastingHistoryStage(Duration elapsed) {
  return fastingBenefitsFor(elapsed).current.title;
}

/// 타이머 링 아래. 다음 단계 시각
String fastingRingFooter(FastingBenefitSnapshot snap) {
  final next = snap.next;
  if (next == null) return snap.current.title;
  return '다음 ${next.from.inHours}시간';
}
