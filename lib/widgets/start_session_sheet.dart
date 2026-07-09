import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import '../utils/format.dart';

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
  return showModalBottomSheet<StartSessionResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceElevated,
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
    _customStart = DateTime.now();
  }

  DateTime get _effectiveStart => _useNow ? DateTime.now() : _customStart;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _customStart,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(
            primary: widget.accent,
            surface: AppColors.surfaceElevated,
          ),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;
    setState(() {
      _customStart = DateTime(
        date.year,
        date.month,
        date.day,
        _customStart.hour,
        _customStart.minute,
      );
      if (_customStart.isAfter(DateTime.now())) {
        _customStart = DateTime.now();
      }
    });
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_customStart),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(
            primary: widget.accent,
            surface: AppColors.surfaceElevated,
          ),
        ),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;
    setState(() {
      _customStart = DateTime(
        _customStart.year,
        _customStart.month,
        _customStart.day,
        time.hour,
        time.minute,
      );
      if (_customStart.isAfter(DateTime.now())) {
        _customStart = DateTime.now();
      }
    });
  }

  String _formatStart(DateTime dt) {
    return DateFormat('M월 d일 (E)\na h:mm', 'ko').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final targetLabel = formatTargetDuration(widget.targetDuration);
    final media = MediaQuery.of(context);
    // 안드로이드 3버튼 네비게이션 바 + 키보드
    final navBar = media.viewPadding.bottom;
    final keyboard = media.viewInsets.bottom;
    final maxSheetHeight = media.size.height * 0.92;

    return Padding(
      // 시스템 네비게이션 바 높이만큼 시트 전체를 위로
      padding: EdgeInsets.only(bottom: navBar),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight - navBar),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            16,
            24,
            keyboard + 40, // 버튼 아래 여유 공간
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
              const SizedBox(height: 18),
              Text(
                '${widget.title} 시작',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
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
              const Text(
                '시작 시각',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
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
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
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
                      ),
                      const SizedBox(height: 10),
                      _PickerButton(
                        icon: Icons.access_time_rounded,
                        caption: '시간',
                        label:
                            DateFormat('a h시 mm분', 'ko').format(_customStart),
                        onTap: _pickTime,
                        accent: widget.accent,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '선택한 시각부터 경과 시간이 계산됩니다',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              // 하단 시작 시각 요약 — overflow 방지
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
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_useNow)
                      Text(
                        '지금 · ${DateFormat('M월 d일 (E) a h:mm', 'ko').format(DateTime.now())}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          height: 1.35,
                        ),
                      )
                    else
                      Text(
                        _formatStart(_customStart),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: widget.accent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(
                    context,
                    StartSessionResult(
                      targetDuration: widget.targetDuration,
                      startTime: _effectiveStart,
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
              // 네비 바/제스처 영역과 겹치지 않도록 하단 여백
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
  final VoidCallback onTap;

  const _ModeChip({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? accent.withValues(alpha: 0.15) : AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? accent : AppColors.border,
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
                  color: selected ? accent : AppColors.textPrimary,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
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

  const _PickerButton({
    required this.icon,
    required this.caption,
    required this.label,
    required this.onTap,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
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
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        height: 1.3,
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
