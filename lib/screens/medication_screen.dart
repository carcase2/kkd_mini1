import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/medication.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/picker_theme.dart';
import '../widgets/cloud_refresh.dart';
import '../widgets/sticky_bottom_bar.dart';

class MedicationScreen extends StatelessWidget {
  const MedicationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = AppPalette.of(context);
    final meds = state.sortedMedications;
    final sets = state.sortedMedicationSets;
    final dueCount = state.medicationDueCount;
    final isEmpty = meds.isEmpty && sets.isEmpty;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: CloudRefresh(
                color: c.warning,
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
                        color: c.warningSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.medication_rounded,
                        color: c.warning,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '약',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: c.textPrimary,
                            ),
                          ),
                          Text(
                            '개별 · 세트로 복용 관리',
                            style: TextStyle(
                              color: c.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: '추가',
                      onSelected: (v) {
                        if (v == 'med') {
                          _showMedicationEditor(context);
                        } else if (v == 'set') {
                          _showMedicationSetEditor(context);
                        }
                      },
                      itemBuilder: (ctx) => const [
                        PopupMenuItem(value: 'med', child: Text('약 추가')),
                        PopupMenuItem(value: 'set', child: Text('세트 추가')),
                      ],
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: c.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.add_rounded, color: c.warning),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (!isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          c.warning.withValues(alpha: 0.22),
                          c.warningSoft,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: c.warning.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _SummaryStat(
                            label: '약',
                            value: '${meds.where((m) => m.active).length}',
                            colors: c,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 36,
                          color: c.warning.withValues(alpha: 0.3),
                        ),
                        Expanded(
                          child: _SummaryStat(
                            label: '세트',
                            value: '${sets.where((s) => s.active).length}',
                            colors: c,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 36,
                          color: c.warning.withValues(alpha: 0.3),
                        ),
                        Expanded(
                          child: _SummaryStat(
                            label: '복용 가능',
                            value: '$dueCount',
                            colors: c,
                            highlight: dueCount > 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            if (isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
                  child: _EmptyState(
                    colors: c,
                    onAdd: () => _showMedicationEditor(context),
                    onAddSet: () => _showMedicationSetEditor(context),
                  ),
                ),
              )
            else ...[
              if (sets.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: Row(
                      children: [
                        Icon(Icons.layers_rounded, size: 18, color: c.warning),
                        const SizedBox(width: 6),
                        Text(
                          '복용 세트',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => _showMedicationSetEditor(context),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            '세트 추가',
                            style: TextStyle(
                              color: c.warning,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _MedicationSetCard(
                            set: sets[index],
                            colors: c,
                          ),
                        );
                      },
                      childCount: sets.length,
                    ),
                  ),
                ),
              ] else if (meds.length >= 2)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                    child: Material(
                      color: c.warningSoft,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        onTap: () => _showMedicationSetEditor(context),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: c.warning.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.layers_rounded, color: c.warning),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '약을 세트로 묶어 함께 복용 기록하기',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: c.textPrimary,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: c.textMuted,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.medication_rounded,
                        size: 18,
                        color: c.warning,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '개별 약',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${meds.length}개',
                        style: TextStyle(color: c.textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
              if (meds.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                    child: Text(
                      '세트를 만들려면 먼저 약을 추가하세요.',
                      style: TextStyle(color: c.textMuted, fontSize: 13),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _MedicationCard(
                            medication: meds[index],
                            colors: c,
                          ),
                        );
                      },
                      childCount: meds.length,
                    ),
                  ),
                ),
            ],
                  ],
                ),
              ),
            ),
            StickyBottomBar(
              child: Row(
                children: [
                  Expanded(
                    child: StickyActionButton(
                      label: '약 추가',
                      icon: Icons.medication_rounded,
                      color: c.warning,
                      soft: c.warningSoft,
                      filled: false,
                      onTap: () => _showMedicationEditor(context),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StickyActionButton(
                      label: '세트 추가',
                      icon: Icons.layers_rounded,
                      color: c.warning,
                      onTap: () => _showMedicationSetEditor(context),
                      enabled: meds.isNotEmpty,
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
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: highlight ? colors.danger : colors.warning,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
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
  final VoidCallback onAddSet;

  const _EmptyState({
    required this.colors,
    required this.onAdd,
    required this.onAddSet,
  });

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
          Icon(Icons.medication_liquid_rounded, size: 48, color: colors.warning),
          const SizedBox(height: 16),
          Text(
            '등록된 약이 없어요',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '약을 추가하고, 여러 약을 세트로 묶어\n함께 먹는 주기도 관리할 수 있어요.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textSecondary,
              height: 1.5,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: colors.warning,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text(
              '약 추가하기',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _quickAddAllergyMed(context),
            child: Text(
              '3세대 비염약 (24시간) 바로 추가',
              style: TextStyle(
                color: colors.warning,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _quickAddAllergyMed(BuildContext context) async {
    HapticFeedback.lightImpact();
    await context.read<AppState>().addMedication(
          name: '3세대 비염약',
          intervalMinutes: 24 * 60,
          note: '24시간마다 1회',
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('3세대 비염약을 추가했어요')),
      );
    }
  }
}

// ── 세트 카드 ──────────────────────────────────────────────────

class _MedicationSetCard extends StatelessWidget {
  final MedicationSet set;
  final AppPalette colors;

  const _MedicationSetCard({required this.set, required this.colors});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final members = state.membersOfSet(set);
    final last = state.lastSetDose(set.id);
    final next = state.nextSetDoseTime(set);
    final until = state.timeUntilNextSetDose(set);
    final due = state.isMedicationSetDue(set);
    final progress = state.setDoseCycleProgress(set);
    final weekCount = state.setDoseCountThisWeek(set.id);
    final history = state.setDosesFor(set.id);

    final statusColor = !set.active
        ? colors.textMuted
        : due
            ? colors.success
            : colors.fasting;

    String statusText;
    if (!set.active) {
      statusText = '비활성';
    } else if (last == null) {
      statusText = '첫 복용 대기';
    } else if (due) {
      statusText = '복용 가능';
    } else {
      statusText = '대기 중';
    }

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: due && set.active
              ? colors.success.withValues(alpha: 0.4)
              : colors.fasting.withValues(alpha: 0.25),
        ),
        boxShadow: appCardShadow(colors),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.layers_rounded, color: statusColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              set.name,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: set.active
                                    ? colors.textPrimary
                                    : colors.textMuted,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colors.fasting.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '세트',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: colors.fasting,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${set.intervalLabel} · ${members.length}종',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 4, right: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert_rounded, color: colors.textMuted),
                  onSelected: (value) => _onMenu(context, value, set, state),
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(value: 'edit', child: Text('수정')),
                    PopupMenuItem(
                      value: 'toggle',
                      child: Text(set.active ? '비활성화' : '활성화'),
                    ),
                    const PopupMenuItem(value: 'history', child: Text('복용 기록')),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        '삭제',
                        style: TextStyle(color: colors.danger),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Member chips
          if (members.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: members.map((m) {
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: colors.chipBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: colors.border),
                    ),
                    child: Text(
                      m.name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                  );
                }).toList(),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                '구성 약이 없어요 · 세트를 수정해 주세요',
                style: TextStyle(fontSize: 12, color: colors.danger),
              ),
            ),

          // Next dose
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: due && set.active ? colors.successSoft : colors.chipBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    last == null
                        ? '다음 세트 복용'
                        : (due ? '다음 세트 복용' : '다음 세트 복용까지'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (last == null)
                    Text(
                      '기록이 없어요 · 지금 세트로 복용해도 됩니다',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: colors.textPrimary,
                      ),
                    )
                  else if (due) ...[
                    Text(
                      '지금 복용 가능',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: colors.success,
                      ),
                    ),
                    if (until != null && until.isNegative) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${formatDuration(until.abs(), short: true)} 지남'
                        ' · ${DateFormat('M/d HH:mm').format(next!)} 예정',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ] else ...[
                    Text(
                      formatDuration(until!, short: true),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: colors.fasting,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('M월 d일 (E) a h:mm', 'ko').format(next!),
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (last != null) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: colors.border,
                        color: due ? colors.success : colors.fasting,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Icon(Icons.history_rounded, size: 14, color: colors.textMuted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    last == null
                        ? '마지막 세트 복용 없음'
                        : '마지막 ${DateFormat('M/d HH:mm').format(last.takenAt)}',
                    style: TextStyle(fontSize: 12, color: colors.textMuted),
                  ),
                ),
                Text(
                  '이번 주 $weekCount회',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          set.active ? colors.fasting : colors.textMuted,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: set.active && members.isNotEmpty
                        ? () => _takeSetNow(context, set)
                        : null,
                    icon: const Icon(Icons.done_all_rounded, size: 20),
                    label: const Text(
                      '세트 먹었어요',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.textSecondary,
                    side: BorderSide(color: colors.border),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: set.active && members.isNotEmpty
                      ? () => _takeSetCustom(context, set)
                      : null,
                  child: const Text(
                    '시간 지정',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),

          if (history.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(height: 1, color: colors.border),
                  const SizedBox(height: 10),
                  Text(
                    '최근 세트 복용',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...history.take(3).map((dose) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 6,
                            color: colors.fasting.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              DateFormat('M월 d일 (E) HH:mm', 'ko')
                                  .format(dose.takenAt),
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _deleteSetDose(context, dose.id),
                            child: Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: colors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (history.length > 3)
                    TextButton(
                      onPressed: () =>
                          _showSetHistory(context, set, history),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        '전체 ${history.length}건 보기',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.fasting,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _onMenu(
    BuildContext context,
    String value,
    MedicationSet set,
    AppState state,
  ) async {
    switch (value) {
      case 'edit':
        await _showMedicationSetEditor(context, existing: set);
      case 'toggle':
        await state.setMedicationSetActive(set.id, !set.active);
      case 'history':
        await _showSetHistory(context, set, state.setDosesFor(set.id));
      case 'delete':
        await _confirmDeleteSet(context, set);
    }
  }

  Future<void> _takeSetNow(BuildContext context, MedicationSet set) async {
    final state = context.read<AppState>();
    final members = state.membersOfSet(set);
    final early =
        !state.isMedicationSetDue(set) && state.lastSetDose(set.id) != null;
    final names = members.map((m) => m.name).join(', ');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = AppPalette.of(ctx);
        return AlertDialog(
          title: Text('${set.name} 세트 복용'),
          content: Text(
            early
                ? '아직 세트 주기가 안 지났어요.\n$names\n그래도 지금 시각으로 함께 기록할까요?'
                : '다음 약을 함께 기록합니다.\n$names',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: c.fasting),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('세트 기록'),
            ),
          ],
        );
      },
    );
    if (ok == true && context.mounted) {
      HapticFeedback.mediumImpact();
      await state.logMedicationSetDose(setId: set.id);
      if (context.mounted) {
        final next = state.nextSetDoseTime(set);
        final msg = next == null
            ? '세트 복용 기록했어요'
            : '세트 기록 완료 · 다음 ${DateFormat('M/d HH:mm').format(next)}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    }
  }

  Future<void> _takeSetCustom(BuildContext context, MedicationSet set) async {
    final when = await _pickDateTime(context, accent: colors.fasting);
    if (when == null || !context.mounted) return;

    HapticFeedback.lightImpact();
    await context.read<AppState>().logMedicationSetDose(
          setId: set.id,
          when: when,
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${DateFormat('M/d HH:mm').format(when)} 세트 복용 기록'),
        ),
      );
    }
  }

  Future<void> _deleteSetDose(BuildContext context, String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('세트 복용 기록 삭제'),
        content: const Text('세트 기록과 함께 찍힌 구성 약 기록도 삭제됩니다.'),
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
      await context.read<AppState>().deleteMedicationSetDose(id);
    }
  }

  Future<void> _confirmDeleteSet(BuildContext context, MedicationSet set) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${set.name} 세트 삭제'),
        content: const Text('세트와 세트 복용 기록만 삭제됩니다. 구성 약은 유지됩니다.'),
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
      await context.read<AppState>().deleteMedicationSet(set.id);
    }
  }
}

// ── 개별 약 카드 ───────────────────────────────────────────────

class _MedicationCard extends StatelessWidget {
  final Medication medication;
  final AppPalette colors;

  const _MedicationCard({
    required this.medication,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final last = state.lastDose(medication.id);
    final next = state.nextDoseTime(medication);
    final until = state.timeUntilNextDose(medication);
    final due = state.isMedicationDue(medication);
    final progress = state.doseCycleProgress(medication);
    final weekCount = state.doseCountThisWeek(medication.id);
    final history = state.dosesFor(medication.id);

    final statusColor = !medication.active
        ? colors.textMuted
        : due
            ? colors.success
            : colors.warning;

    String statusText;
    if (!medication.active) {
      statusText = '비활성';
    } else if (last == null) {
      statusText = '첫 복용 대기';
    } else if (due) {
      statusText = '복용 가능';
    } else {
      statusText = '대기 중';
    }

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: due && medication.active
              ? colors.success.withValues(alpha: 0.4)
              : colors.border,
        ),
        boxShadow: appCardShadow(colors),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
            child: Row(
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
                    Icons.medication_rounded,
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
                        medication.name,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: medication.active
                              ? colors.textPrimary
                              : colors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        medication.intervalLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.textSecondary,
                        ),
                      ),
                      if (medication.note != null &&
                          medication.note!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          medication.note!,
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.textMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 4, right: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert_rounded, color: colors.textMuted),
                  onSelected: (value) =>
                      _onMenu(context, value, medication, state),
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(value: 'edit', child: Text('수정')),
                    PopupMenuItem(
                      value: 'toggle',
                      child: Text(medication.active ? '비활성화' : '활성화'),
                    ),
                    const PopupMenuItem(value: 'history', child: Text('복용 기록')),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        '삭제',
                        style: TextStyle(color: colors.danger),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: due && medication.active
                    ? colors.successSoft
                    : colors.chipBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    last == null ? '다음 복용' : (due ? '다음 복용' : '다음 복용까지'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (last == null)
                    Text(
                      '기록이 없어요 · 지금 복용해도 됩니다',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: colors.textPrimary,
                      ),
                    )
                  else if (due) ...[
                    Text(
                      '지금 복용 가능',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: colors.success,
                      ),
                    ),
                    if (until != null && until.isNegative) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${formatDuration(until.abs(), short: true)} 지남'
                        ' · ${DateFormat('M/d HH:mm').format(next!)} 예정',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ] else ...[
                    Text(
                      formatDuration(until!, short: true),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: colors.warning,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('M월 d일 (E) a h:mm', 'ko').format(next!),
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (last != null) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: colors.border,
                        color: due ? colors.success : colors.warning,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Icon(Icons.history_rounded, size: 14, color: colors.textMuted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    last == null
                        ? '마지막 복용 없음'
                        : '마지막 ${DateFormat('M/d HH:mm').format(last.takenAt)}',
                    style: TextStyle(fontSize: 12, color: colors.textMuted),
                  ),
                ),
                Text(
                  '이번 주 $weekCount회',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: medication.active
                          ? colors.warning
                          : colors.textMuted,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: medication.active
                        ? () => _takeNow(context, medication)
                        : null,
                    icon: const Icon(Icons.check_rounded, size: 20),
                    label: const Text(
                      '먹었어요',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.textSecondary,
                    side: BorderSide(color: colors.border),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: medication.active
                      ? () => _takeCustom(context, medication)
                      : null,
                  child: const Text(
                    '시간 지정',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          if (history.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(height: 1, color: colors.border),
                  const SizedBox(height: 10),
                  Text(
                    '최근 복용',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...history.take(3).map((dose) {
                    final fromSet = dose.setId != null;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 6,
                            color: colors.warning.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${DateFormat('M월 d일 (E) HH:mm', 'ko').format(dose.takenAt)}'
                              '${fromSet ? ' · 세트' : ''}',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _deleteDose(context, dose.id),
                            child: Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: colors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (history.length > 3)
                    TextButton(
                      onPressed: () =>
                          _showHistory(context, medication, history),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        '전체 ${history.length}건 보기',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.warning,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _onMenu(
    BuildContext context,
    String value,
    Medication med,
    AppState state,
  ) async {
    switch (value) {
      case 'edit':
        await _showMedicationEditor(context, existing: med);
      case 'toggle':
        await state.setMedicationActive(med.id, !med.active);
      case 'history':
        await _showHistory(context, med, state.dosesFor(med.id));
      case 'delete':
        await _confirmDeleteMed(context, med);
    }
  }

  Future<void> _takeNow(BuildContext context, Medication med) async {
    final state = context.read<AppState>();
    final early = !state.isMedicationDue(med) && state.lastDose(med.id) != null;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = AppPalette.of(ctx);
        return AlertDialog(
          title: Text('${med.name} 복용'),
          content: Text(
            early
                ? '아직 복용 주기가 안 지났어요.\n그래도 지금 시각으로 기록할까요?'
                : '현재 시각으로 복용 기록할까요?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: c.warning),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('기록'),
            ),
          ],
        );
      },
    );
    if (ok == true && context.mounted) {
      HapticFeedback.mediumImpact();
      await state.logMedicationDose(medicationId: med.id);
      if (context.mounted) {
        final next = state.nextDoseTime(med);
        final msg = next == null
            ? '복용 기록했어요'
            : '기록 완료 · 다음 ${DateFormat('M/d HH:mm').format(next)}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    }
  }

  Future<void> _takeCustom(BuildContext context, Medication med) async {
    final when = await _pickDateTime(context, accent: colors.warning);
    if (when == null || !context.mounted) return;

    HapticFeedback.lightImpact();
    await context.read<AppState>().logMedicationDose(
          medicationId: med.id,
          when: when,
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${DateFormat('M/d HH:mm').format(when)} 복용 기록'),
        ),
      );
    }
  }

  Future<void> _deleteDose(BuildContext context, String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('복용 기록 삭제'),
        content: const Text('이 복용 기록을 삭제할까요?'),
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
      await context.read<AppState>().deleteMedicationDose(id);
    }
  }

  Future<void> _confirmDeleteMed(BuildContext context, Medication med) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${med.name} 삭제'),
        content: const Text('약과 관련된 복용 기록이 모두 삭제됩니다. 포함됐던 세트에서도 제거됩니다.'),
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
      await context.read<AppState>().deleteMedication(med.id);
    }
  }
}

// ── 공통 유틸 ──────────────────────────────────────────────────

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

  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

Future<void> _showHistory(
  BuildContext context,
  Medication med,
  List<MedicationDose> history,
) async {
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
                      child: Text(
                        '${med.name} 복용 기록',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      '${history.length}건',
                      style: TextStyle(color: c.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: history.isEmpty
                    ? Center(
                        child: Text(
                          '기록이 없어요',
                          style: TextStyle(color: c.textMuted),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        itemCount: history.length,
                        separatorBuilder: (_, _) => Divider(color: c.border),
                        itemBuilder: (context, index) {
                          final dose = history[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              dose.setId != null
                                  ? Icons.layers_rounded
                                  : Icons.medication_rounded,
                              color: c.warning,
                            ),
                            title: Text(
                              DateFormat('yyyy.M.d (E) HH:mm', 'ko')
                                  .format(dose.takenAt),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: c.textPrimary,
                              ),
                            ),
                            subtitle: dose.setId != null
                                ? Text(
                                    '세트로 복용',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: c.textMuted,
                                    ),
                                  )
                                : null,
                            trailing: IconButton(
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                color: c.danger,
                              ),
                              onPressed: () async {
                                await context
                                    .read<AppState>()
                                    .deleteMedicationDose(dose.id);
                                if (ctx.mounted) Navigator.pop(ctx);
                              },
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

Future<void> _showSetHistory(
  BuildContext context,
  MedicationSet set,
  List<MedicationSetDose> history,
) async {
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
                      child: Text(
                        '${set.name} 세트 기록',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      '${history.length}건',
                      style: TextStyle(color: c.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: history.isEmpty
                    ? Center(
                        child: Text(
                          '기록이 없어요',
                          style: TextStyle(color: c.textMuted),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        itemCount: history.length,
                        separatorBuilder: (_, _) => Divider(color: c.border),
                        itemBuilder: (context, index) {
                          final dose = history[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.layers_rounded,
                              color: c.fasting,
                            ),
                            title: Text(
                              DateFormat('yyyy.M.d (E) HH:mm', 'ko')
                                  .format(dose.takenAt),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: c.textPrimary,
                              ),
                            ),
                            trailing: IconButton(
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                color: c.danger,
                              ),
                              onPressed: () async {
                                await context
                                    .read<AppState>()
                                    .deleteMedicationSetDose(dose.id);
                                if (ctx.mounted) Navigator.pop(ctx);
                              },
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

Future<void> _showMedicationEditor(
  BuildContext context, {
  Medication? existing,
}) async {
  final c = AppPalette.of(context);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: c.surfaceElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _MedicationEditorSheet(existing: existing),
  );
}

class _MedicationEditorSheet extends StatefulWidget {
  final Medication? existing;

  const _MedicationEditorSheet({this.existing});

  @override
  State<_MedicationEditorSheet> createState() => _MedicationEditorSheetState();
}

class _MedicationEditorSheetState extends State<_MedicationEditorSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _noteCtrl;
  int? _selectedMinutes;
  int _customHours = 24;
  bool _useCustom = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameCtrl = TextEditingController(text: existing?.name ?? '');
    _noteCtrl = TextEditingController(text: existing?.note ?? '');
    _selectedMinutes = existing?.intervalMinutes ?? (24 * 60);
    _useCustom = existing != null &&
        !medicationIntervalPresets.any(
          (p) => p.minutes == existing.intervalMinutes,
        );
    if (_useCustom && existing != null) {
      _customHours =
          (existing.intervalMinutes / 60).round().clamp(1, 24 * 30);
      _selectedMinutes = null;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('약 이름을 입력하세요')),
      );
      return;
    }
    final minutes =
        _useCustom ? _customHours * 60 : (_selectedMinutes ?? 24 * 60);
    final note = _noteCtrl.text.trim();
    final state = context.read<AppState>();
    final existing = widget.existing;

    if (existing == null) {
      await state.addMedication(
        name: name,
        intervalMinutes: minutes,
        note: note.isEmpty ? null : note,
      );
    } else {
      await state.updateMedication(
        existing.copyWith(
          name: name,
          intervalMinutes: minutes,
          note: note.isEmpty ? null : note,
          clearNote: note.isEmpty,
        ),
      );
    }

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final msg = existing == null ? '약을 추가했어요' : '약을 수정했어요';
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final existing = widget.existing;
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final navBar = media.viewPadding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 28 + navBar + keyboard),
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
              existing == null ? '약 추가' : '약 수정',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '약 이름',
                hintText: '예: 3세대 비염약',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: '메모 (선택)',
                hintText: '예: 식후, 졸음 주의',
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '복용 주기',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            _IntervalPicker(
              colors: c,
              selectedMinutes: _selectedMinutes,
              useCustom: _useCustom,
              customHours: _customHours,
              onPreset: (m) => setState(() {
                _useCustom = false;
                _selectedMinutes = m;
              }),
              onCustom: () => setState(() {
                _useCustom = true;
                _selectedMinutes = null;
              }),
              onCustomHours: (h) => setState(() => _customHours = h),
            ),
            const SizedBox(height: 22),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: c.warning,
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
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

Future<void> _showMedicationSetEditor(
  BuildContext context, {
  MedicationSet? existing,
}) async {
  final state = context.read<AppState>();
  final allMeds = state.sortedMedications;
  final c = AppPalette.of(context);

  if (allMeds.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('세트를 만들려면 먼저 약을 1개 이상 추가하세요')),
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: c.surfaceElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _MedicationSetEditorSheet(
      existing: existing,
      allMeds: allMeds,
    ),
  );
}

class _MedicationSetEditorSheet extends StatefulWidget {
  final MedicationSet? existing;
  final List<Medication> allMeds;

  const _MedicationSetEditorSheet({
    this.existing,
    required this.allMeds,
  });

  @override
  State<_MedicationSetEditorSheet> createState() =>
      _MedicationSetEditorSheetState();
}

class _MedicationSetEditorSheetState extends State<_MedicationSetEditorSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _noteCtrl;
  late final Set<String> _selectedIds;
  int? _selectedMinutes;
  int _customHours = 24;
  bool _useCustom = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameCtrl = TextEditingController(text: existing?.name ?? '');
    _noteCtrl = TextEditingController(text: existing?.note ?? '');
    _selectedIds = {...?existing?.medicationIds};
    _selectedMinutes = existing?.intervalMinutes ?? (24 * 60);
    _useCustom = existing != null &&
        !medicationIntervalPresets.any(
          (p) => p.minutes == existing.intervalMinutes,
        );
    if (_useCustom && existing != null) {
      _customHours =
          (existing.intervalMinutes / 60).round().clamp(1, 24 * 30);
      _selectedMinutes = null;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('세트 이름을 입력하세요')),
      );
      return;
    }
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('구성 약을 선택하세요')),
      );
      return;
    }
    final minutes =
        _useCustom ? _customHours * 60 : (_selectedMinutes ?? 24 * 60);
    final note = _noteCtrl.text.trim();
    final app = context.read<AppState>();
    final existing = widget.existing;

    if (existing == null) {
      await app.addMedicationSet(
        name: name,
        medicationIds: _selectedIds.toList(),
        intervalMinutes: minutes,
        note: note.isEmpty ? null : note,
      );
    } else {
      await app.updateMedicationSet(
        existing.copyWith(
          name: name,
          medicationIds: _selectedIds.toList(),
          intervalMinutes: minutes,
          note: note.isEmpty ? null : note,
          clearNote: note.isEmpty,
        ),
      );
    }

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final msg = existing == null ? '세트를 추가했어요' : '세트를 수정했어요';
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final existing = widget.existing;
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final navBar = media.viewPadding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 28 + navBar + keyboard),
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
              existing == null ? '세트 추가' : '세트 수정',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '함께 먹는 약을 선택하면 한 번에 기록할 수 있어요',
              style: TextStyle(fontSize: 12, color: c.textMuted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '세트 이름',
                hintText: '예: 아침 세트, 비염 루틴',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: '메모 (선택)',
                hintText: '예: 식후, 물과 함께',
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '구성 약 (2개 이상 권장)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            ...widget.allMeds.map((m) {
              final selected = _selectedIds.contains(m.id);
              return CheckboxListTile(
                value: selected,
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _selectedIds.add(m.id);
                    } else {
                      _selectedIds.remove(m.id);
                    }
                  });
                },
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: c.fasting,
                title: Text(
                  m.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
                subtitle: Text(
                  m.intervalLabel,
                  style: TextStyle(fontSize: 12, color: c.textMuted),
                ),
              );
            }),
            if (_selectedIds.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '최소 1개 이상 선택하세요',
                  style: TextStyle(fontSize: 12, color: c.danger),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              '세트 복용 주기',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            _IntervalPicker(
              colors: c,
              selectedMinutes: _selectedMinutes,
              useCustom: _useCustom,
              customHours: _customHours,
              accent: c.fasting,
              onPreset: (m) => setState(() {
                _useCustom = false;
                _selectedMinutes = m;
              }),
              onCustom: () => setState(() {
                _useCustom = true;
                _selectedMinutes = null;
              }),
              onCustomHours: (h) => setState(() => _customHours = h),
            ),
            const SizedBox(height: 22),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: c.fasting,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _save,
              child: Text(
                existing == null ? '세트 추가' : '저장',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _IntervalPicker extends StatelessWidget {
  final AppPalette colors;
  final int? selectedMinutes;
  final bool useCustom;
  final int customHours;
  final Color? accent;
  final ValueChanged<int> onPreset;
  final VoidCallback onCustom;
  final ValueChanged<int> onCustomHours;

  const _IntervalPicker({
    required this.colors,
    required this.selectedMinutes,
    required this.useCustom,
    required this.customHours,
    required this.onPreset,
    required this.onCustom,
    required this.onCustomHours,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ?? colors.warning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...medicationIntervalPresets.map((p) {
              final selected = !useCustom && selectedMinutes == p.minutes;
              return ChoiceChip(
                label: Text(p.label),
                selected: selected,
                onSelected: (_) => onPreset(p.minutes),
                selectedColor: color.withValues(alpha: 0.2),
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: selected ? color : colors.textSecondary,
                  fontSize: 13,
                ),
                side: BorderSide(color: selected ? color : colors.border),
                backgroundColor: colors.chipBg,
              );
            }),
            ChoiceChip(
              label: const Text('직접 입력'),
              selected: useCustom,
              onSelected: (_) => onCustom(),
              selectedColor: color.withValues(alpha: 0.2),
              labelStyle: TextStyle(
                fontWeight: FontWeight.w700,
                color: useCustom ? color : colors.textSecondary,
                fontSize: 13,
              ),
              side: BorderSide(color: useCustom ? color : colors.border),
              backgroundColor: colors.chipBg,
            ),
          ],
        ),
        if (!useCustom && selectedMinutes != null) ...[
          const SizedBox(height: 8),
          Text(
            () {
              for (final p in medicationIntervalPresets) {
                if (p.minutes == selectedMinutes) return p.description;
              }
              return '';
            }(),
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
        ],
        if (useCustom) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                '몇 시간마다',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: colors.textSecondary,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed:
                    customHours > 1 ? () => onCustomHours(customHours - 1) : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text(
                '$customHours',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
              IconButton(
                onPressed: customHours < 24 * 30
                    ? () => onCustomHours(customHours + 1)
                    : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
              Text(
                '시간',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
