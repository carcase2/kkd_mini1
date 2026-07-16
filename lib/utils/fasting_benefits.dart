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
    from: Duration(hours: 24),
    title: '하루 단식 구간',
    summary: '케톤 이용이 더 뚜렷해질 수 있음',
    benefits: '24시간 전후는 케톤 이용이 더 활발해질 수 있는 구간입니다. 수분·전해질을 신경 써주세요.',
  ),
  FastingMilestone(
    from: Duration(hours: 36),
    title: '심화 단식',
    summary: '세포 회복 과정이 더 깊어질 수 있음',
    benefits: '장시간 단식으로 대사·회복 과정이 더 깊어진다고 알려진 구간입니다. 컨디션을 꼼꼼히 살피세요.',
  ),
  FastingMilestone(
    from: Duration(hours: 48),
    title: '장기 단식 구간',
    summary: '고강도 도전 · 주의 필요',
    benefits: '48시간 이상은 고강도 도전입니다. 몸의 신호를 최우선으로, 힘들면 안전하게 종료하세요.',
  ),
  FastingMilestone(
    from: Duration(hours: 72),
    title: '초장기 단식',
    summary: '전문가 권고 범위 밖일 수 있음',
    benefits: '72시간 이상은 개인차가 매우 큽니다. 의료 상담 없이 무리하게 이어가지 않는 것이 좋아요.',
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
