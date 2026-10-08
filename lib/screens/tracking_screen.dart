import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/session.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/abstinence_benefits.dart';
import '../utils/fasting_benefits.dart';
import '../utils/format.dart';
import '../widgets/abstinence_start_card.dart';
import '../widgets/cloud_refresh.dart';
import '../widgets/fasting_stage_card.dart';
import '../widgets/history_tile.dart';
import '../widgets/start_session_sheet.dart';
import '../widgets/stat_card.dart';
import '../widgets/sticky_bottom_bar.dart';
import '../widgets/timer_ring.dart';

/// 단식 / 금욕 공용 트래킹 화면
class TrackingScreen extends StatelessWidget {
  final SessionType type;

  const TrackingScreen({super.key, required this.type});

  bool get isFasting => type == SessionType.fasting;

  String get title => isFasting ? '단식' : '금욕';
  String get subtitle => isFasting
      ? '시작하면 시간이 쌓이고, 단계마다 장점이 나와요'
      : '시작하면 시간이 쌓이고, 구간마다 변화가 나와요';
  Color get accent => isFasting ? AppColors.fasting : AppColors.abstinence;
  Color get soft => isFasting ? AppColors.fastingSoft : AppColors.abstinenceSoft;
  IconData get icon =>
      isFasting ? Icons.restaurant_outlined : Icons.shield_outlined;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final active =
        isFasting ? state.activeFasting : state.activeAbstinence;
    final history =
        isFasting ? state.fastingHistory : state.abstinenceHistory;
    final total = isFasting ? state.fastingTotal : state.abstinenceTotal;
    final longest =
        isFasting ? state.fastingLongest : state.abstinenceLongest;
    final totalTime =
        isFasting ? state.fastingTotalTime : state.abstinenceTotalTime;
    final average =
        isFasting ? state.fastingAverage : state.abstinenceAverage;

    return Scaffold(
      body: SafeArea(
        child: active != null
            ? _ActiveView(
                session: active,
                title: title,
                accent: accent,
                soft: soft,
                onEnd: () => _confirmEnd(context, active),
                onCancel: () => _confirmCancel(context, active),
              )
            : _IdleView(
                title: title,
                subtitle: subtitle,
                accent: accent,
                soft: soft,
                icon: icon,
                total: total,
                longest: longest,
                totalTime: totalTime,
                average: average,
                history: history,
                emptyHistory: isFasting
                    ? '아직 기록이 없어요.\n단식을 시작하면 여기에 시간이 쌓여요.'
                    : '아직 기록이 없어요.\n금욕을 시작하면 여기에 시간이 쌓여요.',
                startCard: isFasting
                    ? FastingStartCard(
                        accent: accent,
                        soft: soft,
                        onStartNow: () => _startNow(context),
                        onStartPast: () => _startPast(context),
                      )
                    : AbstinenceStartCard(
                        accent: accent,
                        soft: soft,
                        onStartNow: () => _startNow(context),
                        onStartPast: () => _startPast(context),
                      ),
                onDeleteHistory: (id) =>
                    context.read<AppState>().deleteSession(id),
              ),
      ),
    );
  }

  Future<void> _startNow(BuildContext context) async {
    HapticFeedback.mediumImpact();
    await context.read<AppState>().startSession(
          type: type,
          startTime: DateTime.now(),
        );
  }

  Future<void> _startPast(BuildContext context) async {
    final result = await showStartSessionSheet(
      context,
      title: title,
      accent: accent,
      targetDuration: null,
      goalLabel: '지난 시각부터 이어서',
      openEndedNote: isFasting
          ? '고른 시각부터 시간이 쌓이고, 12·24·48시간 등 그 구간의 장점이 나와요.'
          : '고른 시각부터 시간이 쌓이고, 1일·7일·30일 등 그 구간의 변화가 나와요.',
      pickPast: true,
    );
    if (result == null || !context.mounted) return;

    HapticFeedback.mediumImpact();
    await context.read<AppState>().startSession(
          type: type,
          startTime: result.startTime,
        );
  }

  Future<void> _confirmEnd(
    BuildContext context,
    TrackingSession session,
  ) async {
    final elapsedLabel = formatDuration(session.elapsed, short: true);
    final stage = isFasting
        ? fastingHistoryStage(session.elapsed)
        : abstinenceHistoryStage(session.elapsed);
    final verb = isFasting ? '단식했습니다' : '유지했습니다';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$title을 마칠까요?'),
        content: Text('$elapsedLabel $verb.\n$stage\n이 시간으로 기록합니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('계속하기'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: accent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('기록하기'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      HapticFeedback.mediumImpact();
      final status = await context.read<AppState>().endSession(session.id);
      if (!context.mounted || status == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$elapsedLabel $title을 기록했어요')),
      );
    }
  }

  Future<void> _confirmCancel(
    BuildContext context,
    TrackingSession session,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('세션을 취소할까요?'),
        content: const Text('취소하면 통계에 포함되지 않습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('돌아가기'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('취소하기', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<AppState>().cancelSession(session.id);
    }
  }
}

// ── Active session view ────────────────────────────────────────

class _ActiveView extends StatelessWidget {
  final TrackingSession session;
  final String title;
  final Color accent;
  final Color soft;
  final VoidCallback onEnd;
  final VoidCallback onCancel;

  const _ActiveView({
    required this.session,
    required this.title,
    required this.accent,
    required this.soft,
    required this.onEnd,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final isFasting = session.type == SessionType.fasting;
    final fastingSnap =
        isFasting ? fastingBenefitsFor(session.elapsed) : null;
    final abstinenceSnap =
        isFasting ? null : abstinenceBenefitsFor(session.elapsed);
    final endLabel = isFasting ? '단식 마치기' : '금욕 마치기';

    return Column(
      children: [
        Expanded(
          child: CloudRefresh(
            color: accent,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                children: [
                Row(
                  children: [
                    Text(
                      '$title 진행 중',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: onCancel,
                      child: Text(
                        '취소',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                TimerRing(
                  elapsed: session.elapsed,
                  target: isFasting
                      ? fastingSnap!.next?.from
                      : abstinenceSnap!.next?.from,
                  footer: isFasting
                      ? fastingRingFooter(fastingSnap!)
                      : abstinenceRingFooter(abstinenceSnap!),
                  color: accent,
                  size: 220,
                  label: title,
                ),
                const SizedBox(height: 20),
                Text(
                  '시작 ${DateFormat('M/d (E) HH:mm', 'ko').format(session.startTime)}',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (isFasting) ...[
                  const SizedBox(height: 20),
                  FastingStageCard(
                    elapsed: session.elapsed,
                    accent: accent,
                    soft: soft,
                  ),
                ],
                if (session.type == SessionType.abstinence) ...[
                  const SizedBox(height: 24),
                  Builder(
                    builder: (context) {
                      final snap = abstinenceBenefitsFor(session.elapsed);
                      return _MilestoneBenefitsCard(
                        headerTitle: '지금 나의 변화',
                        elapsed: session.elapsed,
                        currentTitle: snap.current.title,
                        currentSummary: snap.current.summary,
                        currentBenefits: snap.current.benefits,
                        nextTitle: snap.next?.title,
                        nextSummary: snap.next?.summary,
                        nextBenefits: snap.next?.benefits,
                        untilNext: snap.untilNext,
                        accent: accent,
                        soft: soft,
                      );
                    },
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: soft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: accent.withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '팁',
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        session.type == SessionType.fasting
                            ? '물, 무가당 차, 블랙 커피는 보통 단식 중 허용됩니다. 몸이 힘들면 무리하지 마세요.'
                            : '충동이 올 때 자리 이동, 운동, 짧은 산책이 도움이 됩니다. 마치면 그 시간으로 기록되고, 다시 시작할 수 있어요.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              ),
            ),
          ),
        ),
        StickyBottomBar(
          child: StickyActionButton(
            label: endLabel,
            icon: Icons.stop_rounded,
            color: accent,
            soft: soft,
            filled: true,
            onTap: onEnd,
          ),
        ),
      ],
    );
  }
}

/// 단식·금욕 공통: 현재 이점 / 다음 예상 이점 카드
class _MilestoneBenefitsCard extends StatelessWidget {
  final String headerTitle;
  final Duration elapsed;
  final String currentTitle;
  final String currentSummary;
  final String currentBenefits;
  final String? nextTitle;
  final String? nextSummary;
  final String? nextBenefits;
  final Duration? untilNext;
  final Color accent;
  final Color soft;

  const _MilestoneBenefitsCard({
    required this.headerTitle,
    required this.elapsed,
    required this.currentTitle,
    required this.currentSummary,
    required this.currentBenefits,
    this.nextTitle,
    this.nextSummary,
    this.nextBenefits,
    this.untilNext,
    required this.accent,
    required this.soft,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final hasNext = nextTitle != null && nextBenefits != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
        boxShadow: appCardShadow(c),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: soft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.auto_awesome_rounded, color: accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headerTitle,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: c.textPrimary,
                      ),
                    ),
                    Text(
                      '경과 ${formatDuration(elapsed, short: true)} · $currentTitle',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: soft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle_rounded, size: 16, color: accent),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '현재 이점 · $currentSummary',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  currentBenefits,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (hasNext) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.chipBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.flag_rounded,
                        size: 16,
                        color: c.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '다음 예상 이점 · $nextTitle',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (untilNext != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${formatDuration(untilNext!, short: true)} 후'
                      '${nextSummary != null ? ' · $nextSummary' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    nextBenefits!,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Text(
              '가장 긴 단계에 도달했어요. 지금의 루틴을 잘 유지해보세요.',
              style: TextStyle(
                fontSize: 12,
                color: c.textMuted,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            '※ 개인차가 큰 일반적인 설명이며 의료·진단 목적이 아닙니다.',
            style: TextStyle(
              fontSize: 10,
              color: c.textMuted,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Idle (start) view ──────────────────────────────────────────

class _IdleView extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color accent;
  final Color soft;
  final IconData icon;
  final int total;
  final Duration longest;
  final Duration totalTime;
  final Duration average;
  final List<TrackingSession> history;
  final String emptyHistory;
  final Widget startCard;
  final void Function(String id) onDeleteHistory;

  const _IdleView({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.soft,
    required this.icon,
    required this.total,
    required this.longest,
    required this.totalTime,
    required this.average,
    required this.history,
    required this.emptyHistory,
    required this.startCard,
    required this.onDeleteHistory,
  });

  @override
  Widget build(BuildContext context) {
    return CloudRefresh(
      color: accent,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: soft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // 동일 크기 통계 카드
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: StatsRow(
              chips: [
                QuickStatChip(
                  label: '횟수',
                  value: '$total',
                  color: accent,
                ),
                QuickStatChip(
                  label: '누적',
                  value: total == 0 ? '-' : formatDurationTiny(totalTime),
                  color: accent,
                ),
                QuickStatChip(
                  label: '최장',
                  value: total == 0 ? '-' : formatDurationTiny(longest),
                  color: AppColors.warning,
                ),
                QuickStatChip(
                  label: '평균',
                  value: total == 0 ? '-' : formatDurationTiny(average),
                  color: AppColors.success,
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: startCard,
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Row(
              children: [
                const Text(
                  '기록',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  '총 $total회',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (history.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                child: Text(
                  emptyHistory,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, height: 1.5),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 48),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final s = history[index];
                  return SessionHistoryTile(
                    session: s,
                    accent: accent,
                    onDelete: () => onDeleteHistory(s.id),
                  );
                },
                childCount: history.length,
              ),
            ),
          ),
      ],
      ),
    );
  }
}
