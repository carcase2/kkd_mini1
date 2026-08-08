import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/session.dart';
import '../theme/app_theme.dart';

class PresetPicker extends StatelessWidget {
  final List<DurationPreset> presets;
  final Color accent;
  final void Function(Duration? duration) onSelected;
  final VoidCallback onCustom;

  const PresetPicker({
    super.key,
    required this.presets,
    required this.accent,
    required this.onSelected,
    required this.onCustom,
  });

  String? _expectedEndLabel(Duration? duration) {
    if (duration == null) return null;
    final end = DateTime.now().add(duration);
    return '완료 ${DateFormat('M/d HH:mm', 'ko').format(end)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final items = <_PresetItem>[
      ...presets.map(
        (p) => _PresetItem(
          label: p.label,
          description: p.description,
          expectedEnd: _expectedEndLabel(p.duration),
          outlined: p.duration == null,
          onTap: () => onSelected(p.duration),
        ),
      ),
      _PresetItem(
        label: '커스텀',
        description: '직접 시간 지정',
        icon: Icons.tune_rounded,
        onTap: onCustom,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '목표 시간 선택',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: c.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '지금 시작하면 완료 예정이 같이 보여요',
          style: TextStyle(fontSize: 13, color: c.textSecondary),
        ),
        const SizedBox(height: 14),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _PresetRow(
              label: item.label,
              description: item.description,
              expectedEnd: item.expectedEnd,
              accent: accent,
              outlined: item.outlined,
              icon: item.icon,
              onTap: item.onTap,
            ),
          ),
        ),
      ],
    );
  }
}

class _PresetItem {
  final String label;
  final String description;
  final String? expectedEnd;
  final bool outlined;
  final IconData? icon;
  final VoidCallback onTap;

  const _PresetItem({
    required this.label,
    required this.description,
    required this.onTap,
    this.expectedEnd,
    this.outlined = false,
    this.icon,
  });
}

/// 목표 카드: [시간]  설명 · 완료 예정  ›
class _PresetRow extends StatelessWidget {
  final String label;
  final String description;
  final String? expectedEnd;
  final Color accent;
  final bool outlined;
  final IconData? icon;
  final VoidCallback onTap;

  const _PresetRow({
    required this.label,
    required this.description,
    required this.accent,
    required this.onTap,
    this.expectedEnd,
    this.outlined = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);

    return Material(
      color: outlined ? c.surface : accent.withValues(alpha: 0.08),
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
            border: Border.all(
              color: outlined
                  ? accent.withValues(alpha: 0.45)
                  : accent.withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: accent),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: accent,
                  height: 1.2,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 13,
                        color: c.textSecondary,
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                    if (expectedEnd != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        expectedEnd!,
                        style: TextStyle(
                          fontSize: 12,
                          color: accent,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: accent.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 커스텀 시간 선택 다이얼로그
Future<Duration?> showCustomDurationDialog(
  BuildContext context, {
  required String title,
  required Color accent,
  bool allowDays = true,
}) async {
  int days = 0;
  int hours = allowDays ? 0 : 16;
  int minutes = 0;

  return showModalBottomSheet<Duration>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setModalState) {
          final media = MediaQuery.of(ctx);
          return Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 20,
              bottom: media.viewInsets.bottom + media.viewPadding.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '원하는 목표 시간을 직접 설정하세요',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    if (allowDays)
                      Expanded(
                        child: _NumberPicker(
                          label: '일',
                          value: days,
                          min: 0,
                          max: 365,
                          onChanged: (v) => setModalState(() => days = v),
                        ),
                      ),
                    if (allowDays) const SizedBox(width: 10),
                    Expanded(
                      child: _NumberPicker(
                        label: '시간',
                        value: hours,
                        min: 0,
                        max: 23,
                        onChanged: (v) => setModalState(() => hours = v),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _NumberPicker(
                        label: '분',
                        value: minutes,
                        min: 0,
                        max: 59,
                        step: 5,
                        onChanged: (v) => setModalState(() => minutes = v),
                      ),
                    ),
                  ],
                ),
                Builder(
                  builder: (_) {
                    final total = Duration(
                      days: days,
                      hours: hours,
                      minutes: minutes,
                    );
                    if (total.inMinutes < 1) {
                      return const SizedBox(height: 24);
                    }
                    final end = DateTime.now().add(total);
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          '지금 시작 시 완료 예정  '
                          '${DateFormat('M/d (E) HH:mm', 'ko').format(end)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: accent,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    final total = Duration(
                      days: days,
                      hours: hours,
                      minutes: minutes,
                    );
                    if (total.inMinutes < 1) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('최소 1분 이상 설정해주세요')),
                      );
                      return;
                    }
                    Navigator.pop(ctx, total);
                  },
                  child: const Text(
                    '이 시간으로 시작',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

class _NumberPicker extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  const _NumberPicker({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          IconButton(
            onPressed:
                value + step <= max ? () => onChanged(value + step) : null,
            icon: const Icon(Icons.keyboard_arrow_up_rounded),
            color: AppColors.textPrimary,
          ),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          IconButton(
            onPressed:
                value - step >= min ? () => onChanged(value - step) : null,
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            color: AppColors.textPrimary,
          ),
        ],
      ),
    );
  }
}
