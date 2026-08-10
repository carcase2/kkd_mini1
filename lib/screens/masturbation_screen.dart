import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/picker_theme.dart';
import '../widgets/cloud_refresh.dart';
import '../widgets/history_tile.dart';
import '../widgets/stat_card.dart';
import '../widgets/sticky_bottom_bar.dart';

class MasturbationScreen extends StatelessWidget {
  const MasturbationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = AppPalette.of(context);
    final logs = state.sortedMasturbationLogs;
    final last = state.lastMasturbation;
    final since = state.timeSinceLastMasturbation;
    final days = since.inDays;
    final hours = since.inHours.remainder(24);
    final minutes = since.inMinutes.remainder(60);

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: CloudRefresh(
                color: AppColors.check,
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
                        color: AppColors.checkSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.favorite_rounded,
                        color: AppColors.check,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '체크',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            '기록하고 마지막 이후 경과를 확인해요',
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

            // 경과 강조 카드
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.check.withValues(alpha: 0.28),
                        AppColors.checkSoft,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: AppColors.check.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '마지막 체크 이후',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (last == null)
                        const Text(
                          '아직 기록이 없어요',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        )
                      else ...[
                        // 큰 일수 강조
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '$days',
                              style: TextStyle(
                                fontSize: 56,
                                fontWeight: FontWeight.w900,
                                height: 1,
                                color: AppColors.check,
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.only(bottom: 8, left: 4),
                              child: Text(
                                '일',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.check,
                                ),
                              ),
                            ),
                            if (hours > 0 || days == 0) ...[
                              const SizedBox(width: 10),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text(
                                  days == 0 && hours == 0
                                      ? '$minutes분'
                                      : '$hours시간',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          formatElapsedDays(since),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '마지막: ${DateFormat('M월 d일 (E) a h:mm', 'ko').format(last.timestamp)}',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '총 ${formatDuration(since, short: true)} 지남',
                          style: TextStyle(
                            color: AppColors.check.withValues(alpha: 0.9),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // Stats row — equal chips
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: StatsRow(
                  chips: [
                    QuickStatChip(
                      label: '이번 주',
                      value: '${state.masturbationThisWeek}',
                      color: AppColors.check,
                    ),
                    QuickStatChip(
                      label: '이번 달',
                      value: '${state.masturbationThisMonth}',
                      color: AppColors.warning,
                    ),
                    QuickStatChip(
                      label: '전체',
                      value: '${state.masturbationTotal}',
                      color: AppColors.abstinence,
                    ),
                  ],
                ),
              ),
            ),

            // Recent 7-day activity
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: _WeekStrip(byDay: state.masturbationByDay),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    const Text(
                      '기록 히스토리',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${logs.length}건',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (logs.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(
                    child: Text(
                      '아직 기록이 없어요.\n체크 버튼으로 기록해보세요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted, height: 1.5),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final log = logs[index];
                      return MasturbationHistoryTile(
                        log: log,
                        onDelete: () => _delete(context, log.id),
                      );
                    },
                    childCount: logs.length,
                  ),
                ),
              ),
                ],
                ),
              ),
            ),
            StickyBottomBar(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StickyActionButton(
                    label: '지금 체크하기',
                    icon: Icons.add_rounded,
                    color: c.check,
                    onTap: () => _logNow(context),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () => _logCustom(context),
                    child: Text(
                      '다른 날짜/시간으로 기록',
                      style: TextStyle(
                        color: c.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logNow(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('지금 체크할까요?'),
        content: const Text('현재 시각으로 기록됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.check),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('기록'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      HapticFeedback.mediumImpact();
      await context.read<AppState>().logMasturbation();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('기록했어요')),
        );
      }
    }
  }

  Future<void> _logCustom(BuildContext context) async {
    final now = DateTime.now();
    final c = AppPalette.of(context);
    final date = await showAppDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2020),
      lastDate: now,
      accent: c.check,
    );
    if (date == null || !context.mounted) return;

    final time = await showAppTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
      accent: c.check,
    );
    if (time == null || !context.mounted) return;

    final when = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    HapticFeedback.lightImpact();
    await context.read<AppState>().logMasturbation(when: when);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${DateFormat('M/d HH:mm').format(when)} 기록 완료',
          ),
        ),
      );
    }
  }

  Future<void> _delete(BuildContext context, String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('기록을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('삭제', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<AppState>().deleteMasturbationLog(id);
    }
  }
}

class _WeekStrip extends StatelessWidget {
  final Map<DateTime, int> byDay;
  const _WeekStrip({required this.byDay});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days = List.generate(7, (i) {
      final d = today.subtract(Duration(days: 6 - i));
      return DateTime(d.year, d.month, d.day);
    });

    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '최근 7일',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: days.map((day) {
              final count = byDay[day] ?? 0;
              final isToday = day.year == today.year &&
                  day.month == today.month &&
                  day.day == today.day;
              final intensity =
                  count == 0 ? 0.0 : (count / 3).clamp(0.25, 1.0);

              return Column(
                children: [
                  Text(
                    weekdays[day.weekday - 1],
                    style: TextStyle(
                      fontSize: 11,
                      color: isToday ? AppColors.check : AppColors.textMuted,
                      fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: count == 0
                          ? AppColors.surfaceElevated
                          : AppColors.check.withValues(alpha: intensity),
                      borderRadius: BorderRadius.circular(10),
                      border: isToday
                          ? Border.all(color: AppColors.check, width: 1.5)
                          : null,
                    ),
                    child: Text(
                      count > 0 ? '$count' : '',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: count > 0 && intensity > 0.5
                            ? Colors.white
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${day.day}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isToday ? AppColors.check : AppColors.textMuted,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
