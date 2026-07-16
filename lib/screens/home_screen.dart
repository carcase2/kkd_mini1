import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/timer_ring.dart';

class HomeScreen extends StatelessWidget {
  final void Function(int tabIndex) onNavigate;

  const HomeScreen({super.key, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = AppPalette.of(context);
    final fasting = state.activeFasting;
    final abstinence = state.activeAbstinence;
    final sinceLast = state.timeSinceLastMasturbation;
    final hasMasturbation = state.lastMasturbation != null;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '절제',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.6,
                              color: c.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '건강한 습관을 기록하는 루틴 앱',
                            style: TextStyle(
                              color: c.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _greeting(),
                            style: TextStyle(
                              color: c.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 테마 토글
                    Material(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: () => context.read<AppState>().toggleTheme(),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: c.border),
                            boxShadow: appCardShadow(c),
                          ),
                          child: Icon(
                            state.isDarkMode
                                ? Icons.light_mode_rounded
                                : Icons.dark_mode_outlined,
                            color: c.textSecondary,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: _OverviewBanner(state: state, colors: c),
              ),
            ),
            if (fasting != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: _ActiveCard(
                    title: '단식 진행 중',
                    color: c.fasting,
                    soft: c.fastingSoft,
                    colors: c,
                    elapsed: fasting.elapsed,
                    target: fasting.targetDuration,
                    startTime: fasting.startTime,
                    showExpectedEnd: true,
                    onTap: () => onNavigate(1),
                  ),
                ),
              ),
            if (abstinence != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: _ActiveCard(
                    title: '금욕 진행 중',
                    color: c.abstinence,
                    soft: c.abstinenceSoft,
                    colors: c,
                    elapsed: abstinence.elapsed,
                    target: abstinence.targetDuration,
                    startTime: abstinence.startTime,
                    onTap: () => onNavigate(2),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: _CheckCard(
                  colors: c,
                  hasRecord: hasMasturbation,
                  since: sinceLast,
                  onTap: () => onNavigate(3),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  '빠른 현황',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
              ),
            ),
            // 빠른 현황 — 가로 한 줄 리스트
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _QuickRow(
                      title: '단식',
                      icon: Icons.restaurant_outlined,
                      color: c.fasting,
                      soft: c.fastingSoft,
                      colors: c,
                      status: fasting != null
                          ? '${formatDuration(fasting.elapsed, short: true)} 진행'
                          : '대기 중',
                      detail:
                          '성공 ${state.fastingSuccess} · 실패 ${state.fastingFailed} · 총 ${state.fastingTotal}회',
                      onTap: () => onNavigate(1),
                    ),
                    const SizedBox(height: 8),
                    _QuickRow(
                      title: '금욕',
                      icon: Icons.shield_outlined,
                      color: c.abstinence,
                      soft: c.abstinenceSoft,
                      colors: c,
                      status: abstinence != null
                          ? '${formatDuration(abstinence.elapsed, short: true)} 진행'
                          : '대기 중',
                      detail:
                          '성공 ${state.abstinenceSuccess} · 실패 ${state.abstinenceFailed} · 총 ${state.abstinenceTotal}회',
                      onTap: () => onNavigate(2),
                    ),
                    const SizedBox(height: 8),
                    _QuickRow(
                      title: '체크',
                      icon: Icons.favorite_border_rounded,
                      color: c.check,
                      soft: c.checkSoft,
                      colors: c,
                      status: hasMasturbation
                          ? formatElapsedDayHour(sinceLast)
                          : '기록 없음',
                      detail:
                          '주 ${state.masturbationThisWeek}회 · 월 ${state.masturbationThisMonth}회',
                      onTap: () => onNavigate(3),
                    ),
                    const SizedBox(height: 8),
                    _QuickRow(
                      title: '약',
                      icon: Icons.medication_rounded,
                      color: c.warning,
                      soft: c.warningSoft,
                      colors: c,
                      status: state.activeMedications.isEmpty &&
                              state.activeMedicationSets.isEmpty
                          ? '등록 없음'
                          : state.medicationDueCount > 0
                              ? '복용 가능 ${state.medicationDueCount}개'
                              : _medicationHomeStatus(state),
                      detail: state.activeMedications.isEmpty &&
                              state.activeMedicationSets.isEmpty
                          ? '약·세트로 복용 시간을 기록하세요'
                          : _medicationHomeDetail(state),
                      onTap: () => onNavigate(4),
                    ),
                    const SizedBox(height: 8),
                    _QuickRow(
                      title: '통계',
                      icon: Icons.insights_rounded,
                      color: c.success,
                      soft: c.successSoft,
                      colors: c,
                      status:
                          '단식 성공 ${formatPercent(state.fastingSuccessRate)}',
                      detail:
                          '금욕 성공 ${formatPercent(state.abstinenceSuccessRate)}',
                      onTap: () => onNavigate(5),
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 6) return '늦은 밤에도 꾸준히 💪';
    if (h < 12) return '좋은 아침이에요 ☀️';
    if (h < 18) return '오늘도 한 걸음씩 🔥';
    return '저녁 루틴 체크해볼까요 🌙';
  }

  String _medicationHomeStatus(AppState state) {
    final meds = state.activeMedications.length;
    final sets = state.activeMedicationSets.length;
    if (sets > 0 && meds > 0) return '약 $meds · 세트 $sets';
    if (sets > 0) return '세트 $sets개 관리 중';
    return '약 $meds개 관리 중';
  }

  String _medicationHomeDetail(AppState state) {
    Duration? soonest;
    String? name;

    for (final set in state.activeMedicationSets) {
      final until = state.timeUntilNextSetDose(set);
      if (until == null || until <= Duration.zero) {
        return '${set.name} 세트 · 복용 가능';
      }
      if (soonest == null || until < soonest) {
        soonest = until;
        name = '${set.name} 세트';
      }
    }

    for (final med in state.activeMedications) {
      final until = state.timeUntilNextDose(med);
      if (until == null || until <= Duration.zero) {
        return '${med.name} · 복용 가능';
      }
      if (soonest == null || until < soonest) {
        soonest = until;
        name = med.name;
      }
    }

    if (name != null && soonest != null) {
      return '$name · ${formatDuration(soonest, short: true)} 후';
    }
    return '주기별 복용 시간을 기록하세요';
  }
}

class _OverviewBanner extends StatelessWidget {
  final AppState state;
  final AppPalette colors;
  const _OverviewBanner({required this.state, required this.colors});

  @override
  Widget build(BuildContext context) {
    final activeCount =
        (state.activeFasting != null ? 1 : 0) +
        (state.activeAbstinence != null ? 1 : 0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.fasting.withValues(alpha: 0.14),
            colors.abstinence.withValues(alpha: 0.12),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
        boxShadow: appCardShadow(colors),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(14),
              boxShadow: appCardShadow(colors),
            ),
            child: Icon(Icons.bolt_rounded, color: colors.fasting, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  activeCount > 0
                      ? '챌린지 $activeCount개 진행 중'
                      : '진행 중인 챌린지 없음',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  activeCount > 0 ? '아래에서 타이머를 확인하세요' : '단식·금욕을 시작해보세요',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 홈 카드 텍스트 — 길어도 잘리지 않게 축소
class _CardLine extends StatelessWidget {
  final String text;
  final TextStyle style;

  const _CardLine({
    required this.text,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: style,
          maxLines: 1,
        ),
      ),
    );
  }
}

class _CheckCard extends StatelessWidget {
  final AppPalette colors;
  final bool hasRecord;
  final Duration since;
  final VoidCallback onTap;

  const _CheckCard({
    required this.colors,
    required this.hasRecord,
    required this.since,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = colors.check;
    final soft = colors.checkSoft;

    return Material(
      color: soft,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.28)),
            boxShadow: appCardShadow(colors),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.2)),
                ),
                child: Icon(Icons.favorite_rounded, color: color, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CardLine(
                      text: '체크',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _CardLine(
                      text: hasRecord
                          ? formatElapsedDayHour(since)
                          : '아직 기록 없음',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                        color: colors.textPrimary,
                      ),
                    ),
                    if (hasRecord) ...[
                      const SizedBox(height: 2),
                      _CardLine(
                        text: '마지막 체크 이후',
                        style: TextStyle(
                          fontSize: 10,
                          color: colors.textSecondary,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveCard extends StatelessWidget {
  final String title;
  final Color color;
  final Color soft;
  final AppPalette colors;
  final Duration elapsed;
  final Duration? target;
  final DateTime? startTime;
  final bool showExpectedEnd;
  final VoidCallback onTap;

  const _ActiveCard({
    required this.title,
    required this.color,
    required this.soft,
    required this.colors,
    required this.elapsed,
    required this.target,
    this.startTime,
    this.showExpectedEnd = false,
    required this.onTap,
  });

  String? get _expectedEndLabel {
    if (!showExpectedEnd || target == null || startTime == null) return null;
    final end = startTime!.add(target!);
    return '완료 예정 ${DateFormat('M월 d일 (E) a h:mm', 'ko').format(end)}';
  }

  String? get _remainingLabel {
    if (!showExpectedEnd || target == null) return null;
    if (elapsed >= target!) {
      final pct = target!.inSeconds > 0
          ? ((elapsed.inSeconds / target!.inSeconds) * 100).toStringAsFixed(0)
          : null;
      return pct != null ? '$pct% 완료' : '목표 시간 도달';
    }
    final left = target! - elapsed;
    return '남은 시간 ${formatDuration(left, short: true)}';
  }

  @override
  Widget build(BuildContext context) {
    final pct = target != null && target!.inSeconds > 0
        ? ((elapsed.inSeconds / target!.inSeconds) * 100).toStringAsFixed(0)
        : null;
    final expectedEnd = _expectedEndLabel;
    final remaining = _remainingLabel;
    final reached = target != null && elapsed >= target!;

    return Material(
      color: soft,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.28)),
            boxShadow: appCardShadow(colors),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              TimerRing(
                elapsed: elapsed,
                target: target,
                color: color,
                size: 48,
                compact: true,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CardLine(
                      text: title,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _CardLine(
                      text: formatDuration(elapsed, short: true),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _CardLine(
                      text: target != null
                          ? '목표 ${formatTargetDuration(target)}${pct != null ? ' · $pct%' : ''}'
                          : '자유 모드',
                      style: TextStyle(
                        fontSize: 10,
                        color: colors.textSecondary,
                        height: 1.1,
                      ),
                    ),
                    if (remaining != null) ...[
                      const SizedBox(height: 2),
                      _CardLine(
                        text: remaining,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: reached ? colors.success : color,
                          height: 1.1,
                        ),
                      ),
                    ],
                    if (expectedEnd != null && !reached) ...[
                      const SizedBox(height: 2),
                      _CardLine(
                        text: expectedEnd,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: color,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// 빠른 현황 — 제목 아래 상세 (잘림 없음)
/// [아이콘]  단식
///          대기 중
///          성공 0 · 실패 1 · 총 1회  ›
class _QuickRow extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Color soft;
  final AppPalette colors;
  final String status;
  final String detail;
  final VoidCallback onTap;

  const _QuickRow({
    required this.title,
    required this.icon,
    required this.color,
    required this.soft,
    required this.colors,
    required this.status,
    required this.detail,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.border),
            boxShadow: appCardShadow(colors),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: soft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: color,
                        height: 1.2,
                      ),
                      maxLines: 1,
                    ),
                    const SizedBox(height: 3),
                    SizedBox(
                      width: double.infinity,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          status,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: colors.textPrimary,
                            height: 1.2,
                          ),
                          maxLines: 1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      width: double.infinity,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          detail,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                            height: 1.2,
                          ),
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: color.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
