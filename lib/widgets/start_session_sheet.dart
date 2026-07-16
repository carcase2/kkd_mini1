import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/picker_theme.dart';

/// 단식/금욕 시작 시트 — 목표 확인 + 시작 시각 지정
class StartSessionResult {
  final Duration? targetDuration;
  final DateTime startTime;

  const StartSessionResult({
    required this.targetDuration,
    required this.startTime,
  });
}

Future<StartSessionResult?> showStartSessionSheet(
  BuildContext context, {
  required String title,
  required Color accent,
  required Duration? targetDuration,
}) {
  final c = AppPalette.of(context);
  return showModalBottomSheet<StartSessionResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: c.surfaceElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _StartSessionSheet(
      title: title,
      accent: accent,
      targetDuration: targetDuration,
    ),
  );
}

class _StartSessionSheet extends StatefulWidget {
  final String title;
  final Color accent;
  final Duration? targetDuration;

  const _StartSessionSheet({
    required this.title,
    required this.accent,
    required this.targetDuration,
  });

  @override
  State<_StartSessionSheet> createState() => _StartSessionSheetState();
}

class _StartSessionSheetState extends State<_StartSessionSheet> {
  /// true = 지금 시작, false = 직접 지정
  bool _useNow = true;
  late DateTime _customStart;

  @override
  void initState() {
    super.initState();
    // 기본 제안: 1시간 전 (이미 시작한 단식을 기록하는 경우가 많음)
    final now = DateTime.now();
    _customStart = DateTime(now.year, now.month, now.day, now.hour, now.minute)
        .subtract(const Duration(hours: 1));
  }

  DateTime get _effectiveStart {
    if (_useNow) return DateTime.now();
    return _clampToPast(_customStart);
  }

  /// 미래 시각이면 하루 전으로 보정, 그래도 미래면 지금으로
  DateTime _clampToPast(DateTime value) {
    final now = DateTime.now();
    var v = DateTime(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
    );
    if (v.isAfter(now)) {
      // 오늘 저녁처럼 미래로 잡힌 경우 → 어제 같은 시각으로
      v = v.subtract(const Duration(days: 1));
    }
    if (v.isAfter(now)) {
      v = now;
    }
    return v;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final date = await showAppDatePicker(
      context: context,
      initialDate: _customStart.isAfter(now) ? now : _customStart,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      accent: widget.accent,
    );
    if (date == null || !mounted) return;
    setState(() {
      _useNow = false;
      _customStart = _clampToPast(
        DateTime(
          date.year,
          date.month,
          date.day,
          _customStart.hour,
          _customStart.minute,
        ),
      );
    });
  }

  Future<void> _pickTime() async {
    final time = await showAppTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_customStart),
      accent: widget.accent,
    );
    if (time == null || !mounted) return;
    setState(() {
      _useNow = false;
      _customStart = _clampToPast(
        DateTime(
          _customStart.year,
          _customStart.month,
          _customStart.day,
          time.hour,
          time.minute,
        ),
      );
    });
  }

  String _formatStart(DateTime dt) {
    return DateFormat('M월 d일 (E)\na h:mm', 'ko').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final targetLabel = formatTargetDuration(widget.targetDuration);
    final media = MediaQuery.of(context);
    final navBar = media.viewPadding.bottom;
    final keyboard = media.viewInsets.bottom;
    final maxSheetHeight = media.size.height * 0.92;
    final previewStart = _effectiveStart;

    return Padding(
      padding: EdgeInsets.only(bottom: navBar),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight - navBar),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            16,
            24,
            keyboard + 40,
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
                    color: c.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '${widget.title} 시작',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '목표 · $targetLabel',
                style: TextStyle(
                  color: widget.accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                '시작 시각',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _ModeChip(
                      label: '지금',
                      subtitle: '바로 시작',
                      selected: _useNow,
                      accent: widget.accent,
                      colors: c,
                      onTap: () => setState(() => _useNow = true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ModeChip(
                      label: '시간 지정',
                      subtitle: '과거 시각',
                      selected: !_useNow,
                      accent: widget.accent,
                      colors: c,
                      onTap: () => setState(() => _useNow = false),
                    ),
                  ),
                ],
              ),
              if (!_useNow) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.border),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PickerButton(
                        icon: Icons.calendar_today_rounded,
                        caption: '날짜',
                        label: DateFormat('yyyy년 M월 d일 (E)', 'ko')
                            .format(_customStart),
                        onTap: _pickDate,
                        accent: widget.accent,
                        colors: c,
                      ),
                      const SizedBox(height: 10),
                      _PickerButton(
                        icon: Icons.access_time_rounded,
                        caption: '시간',
                        label:
                            DateFormat('a h시 mm분', 'ko').format(_customStart),
                        onTap: _pickTime,
                        accent: widget.accent,
                        colors: c,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '선택한 시각부터 경과 시간이 계산됩니다.\n'
                        '오늘 아직 안 된 시각을 고르면 어제 같은 시각으로 잡아요.',
                        style: TextStyle(
                          fontSize: 12,
                          color: c.textMuted,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: widget.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: widget.accent.withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.play_circle_outline_rounded,
                          color: widget.accent,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '시작 시각',
                          style: TextStyle(
                            fontSize: 12,
                            color: c.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_useNow)
                      Text(
                        '지금 · ${DateFormat('M월 d일 (E) a h:mm', 'ko').format(DateTime.now())}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          height: 1.35,
                          color: c.textPrimary,
                        ),
                      )
                    else
                      Text(
                        _formatStart(previewStart),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          height: 1.4,
                          color: c.textPrimary,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: widget.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () {
                  final start = _effectiveStart;
                  Navigator.pop(
                    context,
                    StartSessionResult(
                      targetDuration: widget.targetDuration,
                      startTime: start,
                    ),
                  );
                },
                child: Text(
                  '${widget.title} 시작하기',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool selected;
  final Color accent;
  final AppPalette colors;
  final VoidCallback onTap;

  const _ModeChip({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.accent,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? accent.withValues(alpha: 0.15) : colors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? accent : colors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: selected ? accent : colors.textPrimary,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textMuted,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickerButton extends StatelessWidget {
  final IconData icon;
  final String caption;
  final String label;
  final VoidCallback onTap;
  final Color accent;
  final AppPalette colors;

  const _PickerButton({
    required this.icon,
    required this.caption,
    required this.label,
    required this.onTap,
    required this.accent,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.surfaceElevated,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      caption,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textMuted,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        height: 1.3,
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: accent.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
