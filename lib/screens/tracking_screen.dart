import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/session.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/history_tile.dart';
import '../widgets/preset_picker.dart';
import '../widgets/start_session_sheet.dart';
import '../widgets/stat_card.dart';
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
                onComplete: () => _confirmComplete(context, active),
                onFail: () => _confirmFail(context, active),
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

  Future<void> _confirmComplete(
    BuildContext context,
    TrackingSession session,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$title 성공으로 기록할까요?'),
        content: Text(
          session.isOpenEnded
              ? '${formatDuration(session.elapsed, short: true)} 동안 유지했습니다.'
              : session.isTargetReached
                  ? '목표 시간을 달성했습니다! 👏'
                  : '목표(${formatTargetDuration(session.targetDuration)}) 전에 종료합니다. 그래도 성공으로 기록할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.success),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('성공 기록'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      HapticFeedback.lightImpact();
      await context.read<AppState>().completeSession(session.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$title 성공! 잘했어요 🎉')),
        );
      }
    }
  }

  Future<void> _confirmFail(
    BuildContext context,
    TrackingSession session,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$title 실패로 기록할까요?'),
        content: Text(
          '${formatDuration(session.elapsed, short: true)} 진행 후 중단합니다. '
          '실패도 기록하면 통계에 도움이 됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('실패 기록'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      HapticFeedback.mediumImpact();
      await context.read<AppState>().failSession(session.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$title 실패 기록됨. 다시 도전해요 💪')),
        );
      }
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
  final VoidCallback onComplete;
  final VoidCallback onFail;
  final VoidCallback onCancel;

  const _ActiveView({
    required this.session,
    required this.title,
    required this.accent,
    required this.soft,
    required this.onComplete,
    required this.onFail,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = session.remaining;
    final reached = session.isTargetReached;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.successSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.celebration_rounded, color: AppColors.success, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '목표 달성! 성공으로 기록할 수 있어요',
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
          if (remaining != null && !reached)
            Text(
              '남은 시간 ${formatDuration(remaining, short: true)}',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(height: 8),
          Text(
            '시작 ${DateFormat('M/d (E) HH:mm', 'ko').format(session.startTime)}',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: '실패',
                  icon: Icons.close_rounded,
                  color: AppColors.danger,
                  soft: AppColors.dangerSoft,
                  onTap: onFail,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _ActionButton(
                  label: '성공 완료',
                  icon: Icons.check_rounded,
                  color: AppColors.success,
                  soft: AppColors.successSoft,
                  filled: true,
                  onTap: onComplete,
                ),
              ),
            ],
          ),
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
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Color soft;
  final bool filled;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.soft,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? color : soft,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: filled
                ? null
                : Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: filled ? Colors.white : color, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: filled ? Colors.white : color,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
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
    return CustomScrollView(
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
    );
  }
}
