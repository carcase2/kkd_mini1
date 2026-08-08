import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/session.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/stat_card.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '통계',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '한눈에 보는 나의 루틴',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 단식 섹션
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: _SectionHeader(
                  title: '단식',
                  icon: Icons.restaurant_outlined,
                  color: AppColors.fasting,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _SuccessFailChart(
                  success: state.fastingSuccess,
                  failed: state.fastingFailed,
                  color: AppColors.fasting,
                  emptyLabel: '단식 기록이 없어요',
                ),
              ),
            ),
            /* 단식 통계 카드 */
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: StatCardGrid(
                  cards: [
                    StatCard(
                      label: '총 시도',
                      value: '${state.fastingTotal}회',
                      icon: Icons.flag_outlined,
                      color: AppColors.fasting,
                      softColor: AppColors.fastingSoft,
                    ),
                    StatCard(
                      label: '성공률',
                      value: formatPercent(state.fastingSuccessRate),
                      icon: Icons.trending_up_rounded,
                      color: AppColors.success,
                      softColor: AppColors.successSoft,
                    ),
                    StatCard(
                      label: '총 단식 시간',
                      value: formatDurationTiny(state.fastingTotalTime),
                      icon: Icons.schedule_rounded,
                      color: AppColors.fasting,
                      softColor: AppColors.fastingSoft,
                    ),
                    StatCard(
                      label: '최장 단식',
                      value: formatDurationTiny(state.fastingLongest),
                      icon: Icons.emoji_events_outlined,
                      color: AppColors.warning,
                    ),
                  ],
                ),
              ),
            ),
            if (state.fastingHistory.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: _RecentBars(
                    sessions: state.fastingHistory.take(7).toList().reversed.toList(),
                    color: AppColors.fasting,
                    title: '최근 단식 시간',
                  ),
                ),
              ),

            // 금욕 섹션
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: _SectionHeader(
                  title: '금욕',
                  icon: Icons.shield_outlined,
                  color: AppColors.abstinence,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _SuccessFailChart(
                  success: state.abstinenceSuccess,
                  failed: state.abstinenceFailed,
                  color: AppColors.abstinence,
                  emptyLabel: '금욕 기록이 없어요',
                ),
              ),
            ),
            /* 금욕 통계 카드 */
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: StatCardGrid(
                  cards: [
                    StatCard(
                      label: '총 시도',
                      value: '${state.abstinenceTotal}회',
                      icon: Icons.flag_outlined,
                      color: AppColors.abstinence,
                      softColor: AppColors.abstinenceSoft,
                    ),
                    StatCard(
                      label: '성공률',
                      value: formatPercent(state.abstinenceSuccessRate),
                      icon: Icons.trending_up_rounded,
                      color: AppColors.success,
                      softColor: AppColors.successSoft,
                    ),
                    StatCard(
                      label: '총 유지 시간',
                      value: formatDurationTiny(state.abstinenceTotalTime),
                      icon: Icons.schedule_rounded,
                      color: AppColors.abstinence,
                      softColor: AppColors.abstinenceSoft,
                    ),
                    StatCard(
                      label: '최장 유지',
                      value: formatDurationTiny(state.abstinenceLongest),
                      icon: Icons.emoji_events_outlined,
                      color: AppColors.warning,
                    ),
                  ],
                ),
              ),
            ),
            if (state.activeAbstinence != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.abstinenceSoft,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.abstinence.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.timer_outlined,
                            color: AppColors.abstinence),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '현재 금욕 스트릭',
                                style: TextStyle(
                                  color: AppColors.abstinence,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                formatDuration(
                                  state.activeAbstinence!.elapsed,
                                  short: true,
                                ),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // 독서 섹션
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: _SectionHeader(
                  title: '독서',
                  icon: Icons.menu_book_rounded,
                  color: AppColors.reading,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: StatCardGrid(
                  cards: [
                    StatCard(
                      label: '연속 일수',
                      value: '${state.readingStreak}일',
                      icon: Icons.local_fire_department_rounded,
                      color: AppColors.reading,
                      softColor: AppColors.readingSoft,
                    ),
                    StatCard(
                      label: '오늘',
                      value: formatDurationTiny(state.readingToday),
                      icon: Icons.today_rounded,
                      color: AppColors.success,
                      softColor: AppColors.successSoft,
                    ),
                    StatCard(
                      label: '이번 주',
                      value: formatDurationTiny(state.readingThisWeek),
                      icon: Icons.date_range_rounded,
                      color: AppColors.reading,
                      softColor: AppColors.readingSoft,
                    ),
                    StatCard(
                      label: '이번 달',
                      value: formatDurationTiny(state.readingThisMonth),
                      icon: Icons.calendar_month_rounded,
                      color: AppColors.warning,
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: StatCardGrid(
                  cards: [
                    StatCard(
                      label: '총 독서 시간',
                      value: formatDurationTiny(state.readingTotalTime),
                      icon: Icons.schedule_rounded,
                      color: AppColors.reading,
                      softColor: AppColors.readingSoft,
                    ),
                    StatCard(
                      label: '세션',
                      value: '${state.readingSessionCount}회',
                      icon: Icons.history_rounded,
                      color: AppColors.abstinence,
                      softColor: AppColors.abstinenceSoft,
                    ),
                    StatCard(
                      label: '읽는 중',
                      value: '${state.booksReadingCount}권',
                      icon: Icons.menu_book_outlined,
                      color: AppColors.success,
                      softColor: AppColors.successSoft,
                    ),
                    StatCard(
                      label: '완독',
                      value: '${state.booksCompletedCount}권',
                      icon: Icons.emoji_events_outlined,
                      color: AppColors.warning,
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: _ReadingWeekChart(
                  minutesByDay: state.readingMinutesByDay,
                ),
              ),
            ),

            // 체크 섹션
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: _SectionHeader(
                  title: '체크',
                  icon: Icons.favorite_rounded,
                  color: AppColors.check,
                ),
              ),
            ),
            /* 체크 통계 카드 */
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: StatCardGrid(
                  cards: [
                    StatCard(
                      label: '이번 주',
                      value: '${state.masturbationThisWeek}회',
                      icon: Icons.date_range_rounded,
                      color: AppColors.check,
                      softColor: AppColors.checkSoft,
                    ),
                    StatCard(
                      label: '이번 달',
                      value: '${state.masturbationThisMonth}회',
                      icon: Icons.calendar_month_rounded,
                      color: AppColors.warning,
                    ),
                    StatCard(
                      label: '전체 기록',
                      value: '${state.masturbationTotal}회',
                      icon: Icons.list_alt_rounded,
                      color: AppColors.abstinence,
                      softColor: AppColors.abstinenceSoft,
                    ),
                    StatCard(
                      label: '마지막 이후',
                      value: state.lastMasturbation == null
                          ? '-'
                          : formatDurationTiny(
                              state.timeSinceLastMasturbation,
                            ),
                      icon: Icons.hourglass_empty_rounded,
                      color: AppColors.success,
                      softColor: AppColors.successSoft,
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                child: _MasturbationWeekChart(
                  byDay: state.masturbationByDay,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;

  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _SuccessFailChart extends StatelessWidget {
  final int success;
  final int failed;
  final Color color;
  final String emptyLabel;

  const _SuccessFailChart({
    required this.success,
    required this.failed,
    required this.color,
    required this.emptyLabel,
  });

  @override
  Widget build(BuildContext context) {
    final total = success + failed;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: total == 0
          ? SizedBox(
              height: 128,
              child: Center(
                child: Text(
                  emptyLabel,
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: SizedBox(
                    height: 120,
                    width: 120,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 3,
                        centerSpaceRadius: 34,
                        sections: [
                          PieChartSectionData(
                            value: success.toDouble(),
                            color: AppColors.success,
                            title: '',
                            radius: 26,
                            showTitle: false,
                          ),
                          PieChartSectionData(
                            value: failed.toDouble(),
                            color: AppColors.danger,
                            title: '',
                            radius: 26,
                            showTitle: false,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _Legend(
                  color: AppColors.success,
                  label: '성공',
                  value: '$success회',
                ),
                const SizedBox(height: 10),
                _Legend(
                  color: AppColors.danger,
                  label: '실패',
                  value: '$failed회',
                ),
                const SizedBox(height: 10),
                _Legend(
                  color: color,
                  label: '성공률',
                  value: formatPercent(
                    total == 0 ? 0 : success / total,
                  ),
                ),
              ],
            ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  final String value;

  const _Legend({
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class _RecentBars extends StatelessWidget {
  final List<TrackingSession> sessions;
  final Color color;
  final String title;

  const _RecentBars({
    required this.sessions,
    required this.color,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) return const SizedBox.shrink();

    final maxHours = sessions
        .map((s) => s.elapsed.inMinutes / 60.0)
        .fold<double>(1, (a, b) => a > b ? a : b);

    return Container(
      height: 180,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxHours * 1.2,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final s = sessions[group.x.toInt()];
                      return BarTooltipItem(
                        formatDuration(s.elapsed, short: true),
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= sessions.length) {
                          return const SizedBox.shrink();
                        }
                        final d = sessions[i].startTime;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '${d.month}/${d.day}',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textMuted,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(sessions.length, (i) {
                  final hours = sessions[i].elapsed.inMinutes / 60.0;
                  final ok =
                      sessions[i].status == SessionStatus.completed;
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: hours,
                        color: ok ? color : AppColors.danger.withValues(alpha: 0.7),
                        width: 14,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadingWeekChart extends StatelessWidget {
  final Map<DateTime, int> minutesByDay;
  const _ReadingWeekChart({required this.minutesByDay});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days = List.generate(14, (i) {
      final d = today.subtract(Duration(days: 13 - i));
      return DateTime(d.year, d.month, d.day);
    });
    final values =
        days.map((d) => (minutesByDay[d] ?? 0).toDouble()).toList();
    final maxY = values.fold<double>(1, (a, b) => a > b ? a : b);

    return Container(
      height: 200,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '최근 14일 독서 (분)',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY * 1.15 + 1,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      return BarTooltipItem(
                        '${rod.toY.toInt()}분',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= days.length) {
                          return const SizedBox.shrink();
                        }
                        if (i % 2 != 0 && i != days.length - 1) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '${days[i].month}/${days[i].day}',
                            style: TextStyle(
                              fontSize: 9,
                              color: AppColors.textMuted,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: AppColors.border.withValues(alpha: 0.5),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(days.length, (i) {
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: values[i],
                        color: values[i] == 0
                            ? AppColors.border
                            : AppColors.reading,
                        width: 10,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MasturbationWeekChart extends StatelessWidget {
  final Map<DateTime, int> byDay;
  const _MasturbationWeekChart({required this.byDay});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days = List.generate(14, (i) {
      final d = today.subtract(Duration(days: 13 - i));
      return DateTime(d.year, d.month, d.day);
    });
    final values = days.map((d) => (byDay[d] ?? 0).toDouble()).toList();
    final maxY = values.fold<double>(1, (a, b) => a > b ? a : b);

    return Container(
      height: 200,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '최근 14일 체크 횟수',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY + 1,
                barTouchData: BarTouchData(enabled: true),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= days.length) {
                          return const SizedBox.shrink();
                        }
                        // only show every few labels
                        if (i % 2 != 0 && i != days.length - 1) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '${days[i].month}/${days[i].day}',
                            style: TextStyle(
                              fontSize: 9,
                              color: AppColors.textMuted,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: AppColors.border.withValues(alpha: 0.5),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(days.length, (i) {
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: values[i],
                        color: values[i] == 0
                            ? AppColors.border
                            : AppColors.check,
                        width: 10,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
