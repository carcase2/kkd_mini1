/// 금욕 경과에 따른 일반적인 단계 설명 (교육·동기 부여용)
class AbstinenceMilestone {
  final Duration from;
  final String title;
  final String benefits;
  final String summary;

  const AbstinenceMilestone({
    required this.from,
    required this.title,
    required this.benefits,
    required this.summary,
  });
}

/// 금욕 마일스톤 (대략적인 구간 · 개인차 있음)
const abstinenceMilestones = <AbstinenceMilestone>[
  AbstinenceMilestone(
    from: Duration.zero,
    title: '시작 · 결심 단계',
    summary: '의지를 세운 직후',
    benefits:
        '목표를 정한 것만으로도 변화가 시작됩니다. 충동이 와도 짧게 참아보는 연습이 이어집니다.',
  ),
  AbstinenceMilestone(
    from: Duration(hours: 6),
    title: '첫 고비 통과',
    summary: '초반 충동에 익숙해지는 중',
    benefits:
        '짧은 시간이지만 유혹을 넘긴 경험이 쌓입니다. 자리 이동·산책 같은 대체 행동이 도움이 됩니다.',
  ),
  AbstinenceMilestone(
    from: Duration(hours: 12),
    title: '반나절 유지',
    summary: '리듬이 잡히기 시작',
    benefits:
        '하루의 절반을 지켰어요. 자극적인 콘텐츠를 피하는 루틴이 자리 잡기 쉽습니다.',
  ),
  AbstinenceMilestone(
    from: Duration(days: 1),
    title: '하루 달성',
    summary: '기본 루틴이 생기는 구간',
    benefits:
        '하루를 넘기면 자신감이 생깁니다. 수면·집중이 조금 더 안정된다고 느끼는 경우가 많아요.',
  ),
  AbstinenceMilestone(
    from: Duration(days: 3),
    title: '3일 챌린지',
    summary: '초기 적응기',
    benefits:
        '3일 전후는 충동이 다시 올라올 수 있는 구간입니다. 이겨내면 통제감이 한층 커집니다.',
  ),
  AbstinenceMilestone(
    from: Duration(days: 7),
    title: '일주일 유지',
    summary: '습관 전환의 첫 고개',
    benefits:
        '일주일은 새로운 습관이 자리 잡기 시작하는 시점입니다. 에너지·자신감 향상을 느끼는 사람이 많아요.',
  ),
  AbstinenceMilestone(
    from: Duration(days: 14),
    title: '2주 구간',
    summary: '루틴이 안정되는 중',
    benefits:
        '2주 전후는 충동 빈도가 줄었다고 느끼는 경우가 많습니다. 취미·운동으로 시간을 채우기 좋아요.',
  ),
  AbstinenceMilestone(
    from: Duration(days: 30),
    title: '한 달 유지',
    summary: '자기 통제 강화',
    benefits:
        '한 달은 의미 있는 성과입니다. 자기 효능감이 커지고, 일상 집중력이 좋아졌다고 느끼는 경우가 많아요.',
  ),
  AbstinenceMilestone(
    from: Duration(days: 60),
    title: '두 달 구간',
    summary: '장기 습관 정착',
    benefits:
        '두 달 가까이 유지하면 예전 패턴으로 돌아가기 어려워집니다. 관계·목표에 에너지를 쓰기 좋은 때예요.',
  ),
  AbstinenceMilestone(
    from: Duration(days: 90),
    title: '90일 · 리부트',
    summary: '장기 도전 구간',
    benefits:
        '90일은 흔히 리부트로 이야기되는 구간입니다. 정체성·자존감이 단단해졌다고 느끼는 사람이 많아요.',
  ),
  AbstinenceMilestone(
    from: Duration(days: 180),
    title: '반년 유지',
    summary: '삶의 일부로 정착',
    benefits:
        '반년 가까이 유지했다면 습관이 일상에 녹아든 상태입니다. 작은 방심만 조심하면 됩니다.',
  ),
  AbstinenceMilestone(
    from: Duration(days: 365),
    title: '1년 이상',
    summary: '장기 성과',
    benefits:
        '1년 이상은 큰 성취입니다. 지금의 루틴을 유지하면서, 필요하면 새로운 성장 목표를 세워보세요.',
  ),
];

class AbstinenceBenefitSnapshot {
  final AbstinenceMilestone current;
  final AbstinenceMilestone? next;
  final Duration? untilNext;

  const AbstinenceBenefitSnapshot({
    required this.current,
    this.next,
    this.untilNext,
  });
}

AbstinenceBenefitSnapshot abstinenceBenefitsFor(Duration elapsed) {
  final d = elapsed.isNegative ? Duration.zero : elapsed;
  var idx = 0;
  for (var i = 0; i < abstinenceMilestones.length; i++) {
    if (d >= abstinenceMilestones[i].from) {
      idx = i;
    } else {
      break;
    }
  }

  final current = abstinenceMilestones[idx];
  final next = idx + 1 < abstinenceMilestones.length
      ? abstinenceMilestones[idx + 1]
      : null;
  final untilNext = next == null ? null : next.from - d;

  return AbstinenceBenefitSnapshot(
    current: current,
    next: next,
    untilNext: untilNext != null && untilNext.isNegative
        ? Duration.zero
        : untilNext,
  );
}
