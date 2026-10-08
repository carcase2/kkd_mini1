import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/habit.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/picker_theme.dart';
import '../widgets/cloud_refresh.dart';

class HabitScreen extends StatelessWidget {
  const HabitScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = AppPalette.of(context);
    final habits = state.sortedHabits;
    final active = habits.where((h) => h.active).length;
    final open = state.habitOpenCount;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: CloudRefresh(
          color: c.habit,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: c.habitSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.checklist_rounded, color: c.habit),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '습관',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: c.textPrimary,
                              ),
                            ),
                            Text(
                              '주기마다 횟수를 체크',
                              style: TextStyle(
                                color: c.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '추가',
                        onPressed: () => _showHabitEditor(context),
                        style: IconButton.styleFrom(
                          backgroundColor: c.habit.withValues(alpha: 0.12),
                          foregroundColor: c.habit,
                        ),
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                ),
              ),
              if (habits.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                    child: _EmptyState(
                      colors: c,
                      onAdd: () => _showHabitEditor(context),
                    ),
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [c.habit.withValues(alpha: 0.2), c.habitSoft],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: c.habit.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _SummaryStat(
                              label: '항목',
                              value: '$active',
                              colors: c,
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 36,
                            color: c.habit.withValues(alpha: 0.3),
                          ),
                          Expanded(
                            child: _SummaryStat(
                              label: '남음',
                              value: '$open',
                              colors: c,
                              highlight: open > 0,
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 36,
                            color: c.habit.withValues(alpha: 0.3),
                          ),
                          Expanded(
                            child: _SummaryStat(
                              label: '완료',
                              value: '${active - open}',
                              colors: c,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  sliver: SliverList.separated(
                    itemCount: habits.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final habit = habits[index];
                      final showPausedHeader =
                          !habit.active &&
                          (index == 0 || habits[index - 1].active);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showPausedHeader) ...[
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8, top: 4),
                              child: Text(
                                '쉬고 있는 항목',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: c.textMuted,
                                ),
                              ),
                            ),
                          ],
                          _HabitCard(habit: habit, colors: c),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final String label;
  final String value;
  final AppPalette colors;
  final bool highlight;

  const _SummaryStat({
    required this.label,
    required this.value,
    required this.colors,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: highlight ? colors.habit : colors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final AppPalette colors;
  final VoidCallback onAdd;

  const _EmptyState({required this.colors, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.border),
        boxShadow: appCardShadow(colors),
      ),
      child: Column(
        children: [
          Icon(Icons.checklist_rounded, size: 48, color: colors.habit),
          const SizedBox(height: 16),
          Text(
            '체크할 항목이 없어요',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '순대국밥, 편의점 음식처럼\n일정 주기마다 한 번씩 기록해 보세요.\n주기는 일주일 외에 매일·며칠·한 달로도 바꿀 수 있어요.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textSecondary,
              height: 1.5,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),
          _ExampleButton(
            colors: colors,
            label: '순대국밥 먹기 · 일주일에 한 번',
            onTap: () => _addExample(context, name: '순대국밥 먹기'),
          ),
          const SizedBox(height: 8),
          _ExampleButton(
            colors: colors,
            label: '편의점 음식 먹기 · 일주일에 한 번',
            onTap: () => _addExample(context, name: '편의점 음식 먹기'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onAdd,
            child: Text(
              '직접 추가',
              style: TextStyle(
                color: colors.habit,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addExample(BuildContext context, {required String name}) async {
    HapticFeedback.lightImpact();
    await context.read<AppState>().addHabit(
      name: name,
      timesPerPeriod: 1,
      every: 1,
      unit: HabitPeriodUnit.week,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$name 항목을 추가했어요')));
  }
}

class _ExampleButton extends StatelessWidget {
  final AppPalette colors;
  final String label;
  final VoidCallback onTap;

  const _ExampleButton({
    required this.colors,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: colors.habit,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: onTap,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _HabitCard extends StatelessWidget {
  final Habit habit;
  final AppPalette colors;

  const _HabitCard({required this.habit, required this.colors});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final now = DateTime.now();
    final count = state.habitChecksInCurrentWindow(habit, now);
    final window = state.currentHabitWindow(habit, now);
    final history = state.checksForHabit(habit.id);
    final noun = habitWindowNoun(habit);
    final met = count >= habit.timesPerPeriod;
    final over = count > habit.timesPerPeriod;
    final ratio = habit.timesPerPeriod == 0
        ? 0.0
        : (count / habit.timesPerPeriod).clamp(0.0, 1.0);

    final Color statusColor;
    final String statusText;
    if (!habit.active) {
      statusColor = colors.textMuted;
      statusText = '쉬는 중';
    } else if (count == 0) {
      statusColor = colors.habit;
      statusText = '$noun 0/${habit.timesPerPeriod}';
    } else if (!met) {
      statusColor = colors.habit;
      statusText = '$noun $count/${habit.timesPerPeriod}';
    } else if (over) {
      statusColor = colors.danger;
      statusText = '$noun $count/${habit.timesPerPeriod}';
    } else {
      statusColor = colors.success;
      statusText = '$noun 완료';
    }

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: habit.active
              ? statusColor.withValues(alpha: 0.35)
              : colors.border,
        ),
        boxShadow: appCardShadow(colors),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    met && habit.active
                        ? Icons.check_circle_rounded
                        : Icons.checklist_rounded,
                    color: statusColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        habit.name,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: habit.active
                              ? colors.textPrimary
                              : colors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        habitPeriodLabel(habit),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colors.textSecondary,
                        ),
                      ),
                      if (habit.note != null && habit.note!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          habit.note!,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                      ),
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert_rounded, color: colors.textMuted),
                  onSelected: (value) => _onMenu(context, value),
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(value: 'edit', child: Text('수정')),
                    PopupMenuItem(
                      value: 'toggle',
                      child: Text(habit.active ? '쉬기' : '다시 사용'),
                    ),
                    const PopupMenuItem(value: 'history', child: Text('기록')),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('삭제', style: TextStyle(color: colors.danger)),
                    ),
                  ],
                ),
              ],
            ),
            if (habit.active) ...[
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 6,
                        backgroundColor: colors.border,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _resetLabel(window.end),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: met
                          ? OutlinedButton.icon(
                              onPressed: () => _checkNow(context),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: colors.danger,
                                side: BorderSide(
                                  color: colors.danger.withValues(alpha: 0.5),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text(
                                '한 번 더 기록',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            )
                          : FilledButton.icon(
                              onPressed: () => _checkNow(context),
                              style: FilledButton.styleFrom(
                                backgroundColor: colors.habit,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.check_rounded, size: 18),
                              label: const Text(
                                '체크',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => _checkAt(context),
                      child: Text(
                        '다른 시각',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (history.isNotEmpty)
                      TextButton(
                        onPressed: () => _undoLast(context, history.first),
                        child: Text(
                          '마지막 취소',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    const Spacer(),
                    Text(
                      '총 ${history.length}회',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _resetLabel(DateTime end) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endDay = DateTime(end.year, end.month, end.day);
    final days = endDay.difference(today).inDays;
    if (days <= 1) return '내일 초기화';
    return '${DateFormat('M월 d일 (E)', 'ko').format(end)} 초기화';
  }

  Future<void> _checkNow(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final state = context.read<AppState>();
    await state.logHabitCheck(habitId: habit.id);
    if (!context.mounted) return;
    final count = state.habitChecksInCurrentWindow(habit);
    final noun = habitWindowNoun(habit);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${habit.name} · $noun $count/${habit.timesPerPeriod}'),
      ),
    );
  }

  Future<void> _checkAt(BuildContext context) async {
    final when = await _pickDateTime(context, accent: colors.habit);
    if (when == null || !context.mounted) return;
    HapticFeedback.lightImpact();
    await context.read<AppState>().logHabitCheck(habitId: habit.id, when: when);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${DateFormat('M/d HH:mm').format(when)} 기록')),
    );
  }

  Future<void> _undoLast(BuildContext context, HabitCheck latest) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('마지막 체크 취소'),
        content: Text(
          '${DateFormat('M월 d일 HH:mm', 'ko').format(latest.checkedAt)} 기록을 취소할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('닫기'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('취소', style: TextStyle(color: colors.danger)),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<AppState>().deleteHabitCheck(latest.id);
    }
  }

  Future<void> _onMenu(BuildContext context, String value) async {
    switch (value) {
      case 'edit':
        await _showHabitEditor(context, existing: habit);
      case 'toggle':
        await context.read<AppState>().setHabitActive(habit.id, !habit.active);
      case 'history':
        await _showHistory(context, habit);
      case 'delete':
        await _confirmDelete(context);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${habit.name} 삭제'),
        content: const Text('항목과 체크 기록이 함께 삭제됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('닫기'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('삭제', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<AppState>().deleteHabit(habit.id);
    }
  }
}

Future<DateTime?> _pickDateTime(
  BuildContext context, {
  required Color accent,
}) async {
  final now = DateTime.now();
  final date = await showAppDatePicker(
    context: context,
    initialDate: now,
    firstDate: DateTime(2020),
    lastDate: now,
    accent: accent,
  );
  if (date == null || !context.mounted) return null;

  final time = await showAppTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(now),
    accent: accent,
  );
  if (time == null) return null;

  final picked = DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
  if (picked.isAfter(now)) return now;
  return picked;
}

Future<void> _showHistory(BuildContext context, Habit habit) async {
  final c = AppPalette.of(context);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: c.surfaceElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        builder: (ctx, scrollController) {
          final state = ctx.watch<AppState>();
          final history = state.checksForHabit(habit.id);
          return Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            habit.name,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: c.textPrimary,
                            ),
                          ),
                          Text(
                            '${habitPeriodLabel(habit)} · ${history.length}회',
                            style: TextStyle(
                              fontSize: 13,
                              color: c.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: history.isEmpty
                    ? Center(
                        child: Text(
                          '아직 기록이 없어요',
                          style: TextStyle(color: c.textMuted),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        itemCount: history.length,
                        separatorBuilder: (_, _) =>
                            Divider(height: 1, color: c.border),
                        itemBuilder: (context, index) {
                          final check = history[index];
                          return ListTile(
                            title: Text(
                              DateFormat(
                                'M월 d일 (E) HH:mm',
                                'ko',
                              ).format(check.checkedAt),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: c.textPrimary,
                              ),
                            ),
                            subtitle: check.note == null
                                ? null
                                : Text(check.note!),
                            trailing: IconButton(
                              tooltip: '삭제',
                              onPressed: () async {
                                await context.read<AppState>().deleteHabitCheck(
                                  check.id,
                                );
                              },
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                color: c.danger,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> _showHabitEditor(BuildContext context, {Habit? existing}) async {
  final c = AppPalette.of(context);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: c.surfaceElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _HabitEditorSheet(existing: existing),
  );
}

class _HabitEditorSheet extends StatefulWidget {
  final Habit? existing;

  const _HabitEditorSheet({this.existing});

  @override
  State<_HabitEditorSheet> createState() => _HabitEditorSheetState();
}

class _HabitEditorSheetState extends State<_HabitEditorSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _noteCtrl;
  late int _times;
  late int _every;
  late HabitPeriodUnit _unit;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameCtrl = TextEditingController(text: existing?.name ?? '');
    _noteCtrl = TextEditingController(text: existing?.note ?? '');
    _times = existing?.timesPerPeriod ?? 1;
    _every = existing?.every ?? 1;
    _unit = existing?.unit ?? HabitPeriodUnit.week;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Habit _draft() {
    final now = DateTime.now();
    return Habit(
      id: widget.existing?.id ?? 'draft',
      name: _nameCtrl.text.trim().isEmpty ? '항목' : _nameCtrl.text.trim(),
      timesPerPeriod: _times,
      every: _every,
      unit: _unit,
      createdAt: widget.existing?.createdAt ?? now,
      anchor: widget.existing?.anchor ?? dateOnly(now),
    );
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('이름을 입력하세요')));
      return;
    }
    final note = _noteCtrl.text.trim();
    final state = context.read<AppState>();
    final existing = widget.existing;
    if (existing == null) {
      await state.addHabit(
        name: name,
        timesPerPeriod: _times,
        every: _every,
        unit: _unit,
        note: note.isEmpty ? null : note,
      );
    } else {
      await state.updateHabit(
        existing.copyWith(
          name: name,
          timesPerPeriod: _times,
          every: _every,
          unit: _unit,
          note: note.isEmpty ? null : note,
          clearNote: note.isEmpty,
        ),
      );
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(content: Text(existing == null ? '항목을 추가했어요' : '항목을 수정했어요')),
    );
  }

  void _applyPreset(HabitPreset preset) {
    setState(() {
      _times = preset.times;
      _every = preset.every;
      _unit = preset.unit;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final existing = widget.existing;
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final draft = _draft();

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + keyboard),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              existing == null ? '항목 추가' : '항목 수정',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '이름과 주기를 원하는 대로 바꿀 수 있어요.',
              style: TextStyle(fontSize: 13, color: c.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: '이름',
                hintText: '예: 순대국밥 먹기',
              ),
            ),
            if (existing == null && _nameCtrl.text.trim().isEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    label: const Text('순대국밥 먹기'),
                    onPressed: () {
                      _nameCtrl.text = '순대국밥 먹기';
                      _applyPreset(habitPresets[2]);
                    },
                  ),
                  ActionChip(
                    label: const Text('편의점 음식 먹기'),
                    onPressed: () {
                      _nameCtrl.text = '편의점 음식 먹기';
                      _applyPreset(habitPresets[2]);
                    },
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: '메모 (선택)',
                hintText: '예: 저녁에, 집에서',
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '빠른 주기',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in habitPresets)
                  ChoiceChip(
                    label: Text(preset.label),
                    selected:
                        preset.times == _times &&
                        preset.every == _every &&
                        preset.unit == _unit,
                    selectedColor: c.habit.withValues(alpha: 0.18),
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w700,
                      color:
                          preset.times == _times &&
                              preset.every == _every &&
                              preset.unit == _unit
                          ? c.habit
                          : c.textSecondary,
                    ),
                    onSelected: (_) => _applyPreset(preset),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              '직접 설정',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            SegmentedButton<HabitPeriodUnit>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: c.habit.withValues(alpha: 0.16),
                selectedForegroundColor: c.habit,
                foregroundColor: c.textSecondary,
              ),
              segments: const [
                ButtonSegment(value: HabitPeriodUnit.day, label: Text('일')),
                ButtonSegment(value: HabitPeriodUnit.week, label: Text('주')),
                ButtonSegment(value: HabitPeriodUnit.month, label: Text('달')),
              ],
              selected: {_unit},
              onSelectionChanged: (next) {
                setState(() {
                  _unit = next.first;
                  final maxEvery = maxEveryFor(_unit);
                  if (_every > maxEvery) _every = maxEvery;
                });
              },
            ),
            const SizedBox(height: 12),
            _StepperRow(
              colors: c,
              label: '주기 길이',
              value: '$_every${everyUnitLabel(_unit)}',
              onMinus: _every > 1 ? () => setState(() => _every -= 1) : null,
              onPlus: _every < maxEveryFor(_unit)
                  ? () => setState(() => _every += 1)
                  : null,
            ),
            const SizedBox(height: 8),
            _StepperRow(
              colors: c,
              label: '한 주기 횟수',
              value: '$_times번',
              onMinus: _times > 1 ? () => setState(() => _times -= 1) : null,
              onPlus: _times < 30 ? () => setState(() => _times += 1) : null,
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: c.habitSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                habitPeriodLabel(draft),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: c.habit,
                ),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: c.habit,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _save,
              child: Text(
                existing == null ? '추가' : '저장',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  final AppPalette colors;
  final String label;
  final String value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  const _StepperRow({
    required this.colors,
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.chipBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: colors.textSecondary,
              ),
            ),
          ),
          IconButton(
            onPressed: onMinus,
            icon: const Icon(Icons.remove_rounded),
            color: colors.habit,
          ),
          SizedBox(
            width: 72,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: colors.textPrimary,
              ),
            ),
          ),
          IconButton(
            onPressed: onPlus,
            icon: const Icon(Icons.add_rounded),
            color: colors.habit,
          ),
        ],
      ),
    );
  }
}
