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
import '../widgets/cloud_refresh.dart';
import '../widgets/history_tile.dart';
import '../widgets/preset_picker.dart';
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
  String get subtitle =>
      isFasting ? '간헐적 단식 · 물단식 타이머' : '야동 · 자극 콘텐츠 끊기';
  Color get accent => isFasting ? AppColors.fasting : AppColors.abstinence;
  Color get soft => isFasting ? AppColors.fastingSoft : AppColors.abstinenceSoft;
  IconData get icon =>
      isFasting ? Icons.restaurant_outlined : Icons.shield_outlined;
  List<DurationPreset> get presets =>
      isFasting ? fastingPresets : abstinencePresets;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final active =
        isFasting ? state.activeFasting : state.activeAbstinence;
    final history =
        isFasting ? state.fastingHistory : state.abstinenceHistory;
    final success =
        isFasting ? state.fastingSuccess : state.abstinenceSuccess;
    final failed =
        isFasting ? state.fastingFailed : state.abstinenceFailed;
    final total = isFasting ? state.fastingTotal : state.abstinenceTotal;
    final rate =
        isFasting ? state.fastingSuccessRate : state.abstinenceSuccessRate;
    final longest =
        isFasting ? state.fastingLongest : state.abstinenceLongest;

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
                presets: presets,
                success: success,
                failed: failed,
                total: total,
                rate: rate,
                longest: longest,
                history: history,
                allowDays: !isFasting,
                onStart: (duration) => _start(context, duration),
                onDeleteHistory: (id) =>
                    context.read<AppState>().deleteSession(id),
              ),
      ),
    );
  }

  Future<void> _start(BuildContext context, Duration? duration) async {
    final result = await showStartSessionSheet(
      context,
      title: title,
      accent: accent,
      targetDuration: duration,
    );
    if (result == null || !context.mounted) return;

    HapticFeedback.mediumImpact();
    await context.read<AppState>().startSession(
          type: type,
          targetDuration: result.targetDuration,
          startTime: result.startTime,
        );
  }

  Future<void> _confirmEnd(
    BuildContext context,
    TrackingSession session,
  ) async {
    final willSucceed = session.endStatus == SessionStatus.completed;
    final pct = session.targetDuration != null &&
            session.targetDuration!.inSeconds > 0
        ? (session.progress * 100).toStringAsFixed(0)
        : null;

    final String content;
    if (session.isOpenEnded) {
      content =
          '${formatDuration(session.elapsed, short: true)} 동안 유지했습니다. 성공으로 기록할까요?';
    } else if (willSucceed) {
      content =
          '목표 달성 · $pct% 완료. ${formatDuration(session.elapsed, short: true)} 진행했습니다. 성공으로 기록할까요?';
    } else {
      content =
          '목표(${formatTargetDuration(session.targetDuration)}) 미달 · $pct%. '
          '실패로 기록할까요?';
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(willSucceed ? '$title 종료 · 성공' : '$title 종료 · 실패'),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('계속하기'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor:
                  willSucceed ? AppColors.success : AppColors.danger,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(willSucceed ? '성공 기록' : '실패 기록'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      HapticFeedback.mediumImpact();
      final status = await context.read<AppState>().endSession(session.id);
      if (!context.mounted || status == null) return;
      final success = status == SessionStatus.completed;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? '$title 성공! 잘했어요 🎉' : '$title 실패 기록됨. 다시 도전해요 💪',
          ),
        ),
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
    final remaining = session.remaining;
    final reached = session.isTargetReached;
    final pct = session.targetDuration != null &&
            session.targetDuration!.inSeconds > 0
        ? (session.progress * 100).toStringAsFixed(0)
        : null;
    final endColor =
        reached || session.isOpenEnded ? AppColors.success : AppColors.danger;
    final endSoft = reached || session.isOpenEnded
        ? AppColors.successSoft
        : AppColors.dangerSoft;

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
                const SizedBox(height: 8),
                if (reached && session.targetDuration != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.successSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.success.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.celebration_rounded,
                          color: AppColors.success,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '목표 달성 · $pct% 완료. 원하는 만큼 더 이어가다 종료하세요',
                            style: TextStyle(
                              color: AppColors.success,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                TimerRing(
                  elapsed: session.elapsed,
                  target: session.targetDuration,
                  color: accent,
                  size: 260,
                  label: title,
                ),
                const SizedBox(height: 20),
                if (remaining != null && !reached) ...[
                  Text(
                    '남은 시간 ${formatDuration(remaining, short: true)}',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  // 한 줄 유지: 짧은 형식 + 필요 시 자동 축소
                  SizedBox(
                    width: double.infinity,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '완료 예정 ${DateFormat('M/d (E) HH:mm', 'ko').format(session.startTime.add(session.targetDuration!))}',
                        style: TextStyle(
                          color: accent,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                      ),
                    ),
                  ),
                ],
                if (reached && pct != null)
                  Text(
                    '$pct% 완료 · 목표 초과 진행 중',
                    style: TextStyle(
                      color: AppColors.success,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 8),
                Text(
                  '시작 ${DateFormat('M/d (E) HH:mm', 'ko').format(session.startTime)}',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (reached &&
                    session.targetDuration != null &&
                    session.startTime
                        .add(session.targetDuration!)
                        .isBefore(DateTime.now()))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: SizedBox(
                      width: double.infinity,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.center,
                        child: Text(
                          '목표 시각 ${DateFormat('M/d (E) HH:mm', 'ko').format(session.startTime.add(session.targetDuration!))} 도달',
                          style: TextStyle(
                            color: AppColors.success,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ),
                if (session.type == SessionType.fasting) ...[
                  const SizedBox(height: 24),
                  Builder(
                    builder: (context) {
                      final snap = fastingBenefitsFor(session.elapsed);
                      return _MilestoneBenefitsCard(
                        headerTitle: '지금 몸의 변화',
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
                            : '충동이 올 때 자리 이동, 운동, 짧은 산책이 도움이 됩니다. 실패해도 다시 시작하면 됩니다.',
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
            label: '종료',
            icon: Icons.stop_rounded,
            color: endColor,
            soft: endSoft,
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
  final List<DurationPreset> presets;
  final int success;
  final int failed;
  final int total;
  final double rate;
  final Duration longest;
  final List<TrackingSession> history;
  final bool allowDays;
  final void Function(Duration? duration) onStart;
  final void Function(String id) onDeleteHistory;

  const _IdleView({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.soft,
    required this.icon,
    required this.presets,
    required this.success,
    required this.failed,
    required this.total,
    required this.rate,
    required this.longest,
    required this.history,
    required this.allowDays,
    required this.onStart,
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
                  label: '성공',
                  value: '$success',
                  color: AppColors.success,
                ),
                QuickStatChip(
                  label: '실패',
                  value: '$failed',
                  color: AppColors.danger,
                ),
                QuickStatChip(
                  label: '성공률',
                  value: formatPercent(rate),
                  color: accent,
                ),
                QuickStatChip(
                  label: '최장',
                  value: total == 0 ? '-' : formatDurationTiny(longest),
                  color: AppColors.warning,
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: PresetPicker(
              presets: presets,
              accent: accent,
              onSelected: onStart,
              onCustom: () async {
                final d = await showCustomDurationDialog(
                  context,
                  title: '$title 커스텀 시간',
                  accent: accent,
                  allowDays: allowDays,
                );
                if (d != null) onStart(d);
              },
            ),
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
                  '아직 기록이 없어요.\n위에서 목표를 골라 시작해보세요!',
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
