import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../utils/fasting_benefits.dart';
import '../utils/format.dart';

/// 진행 중 단식: 지금 단계의 시간과 장점, 다음 시간
class FastingStageCard extends StatefulWidget {
  final Duration elapsed;
  final Color accent;
  final Color soft;

  const FastingStageCard({
    super.key,
    required this.elapsed,
    required this.accent,
    required this.soft,
  });

  @override
  State<FastingStageCard> createState() => _FastingStageCardState();
}

class _FastingStageCardState extends State<FastingStageCard> {
  int? _seenHour;

  @override
  void initState() {
    super.initState();
    _seenHour = widget.elapsed.inHours;
  }

  @override
  void didUpdateWidget(covariant FastingStageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hour = widget.elapsed.inHours;
    if (_seenHour != null && hour > _seenHour!) {
      HapticFeedback.mediumImpact();
    }
    _seenHour = hour;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final snap = fastingBenefitsFor(widget.elapsed);
    final current = snap.current;
    final next = snap.next;
    final marks =
        fastingMilestones.where((m) => m.from > Duration.zero).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: widget.accent.withValues(alpha: 0.28)),
        boxShadow: appCardShadow(c),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fastingHourHeadline(widget.elapsed),
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              height: 1.15,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            current.title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: widget.accent,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            current.benefits,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          _HourTimeline(
            marks: marks,
            elapsed: widget.elapsed,
            currentFrom: current.from,
            accent: widget.accent,
            soft: widget.soft,
          ),
          if (next == null) ...[
            const SizedBox(height: 14),
            Text(
              '이 구간을 넘어도 시간은 계속 쌓입니다.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: widget.accent,
              ),
            ),
          ] else ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: c.chipBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.flag_rounded, size: 18, color: widget.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '다음 ${next.from.inHours}시간 · ${next.title}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          snap.untilNext == null
                              ? next.summary
                              : '${formatDuration(snap.untilNext!, short: true)} 후 · ${next.summary}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: widget.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            '개인차가 큰 일반적인 설명이며 의료·진단 목적이 아닙니다.',
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

class _HourTimeline extends StatefulWidget {
  final List<FastingMilestone> marks;
  final Duration elapsed;
  final Duration currentFrom;
  final Color accent;
  final Color soft;

  const _HourTimeline({
    required this.marks,
    required this.elapsed,
    required this.currentFrom,
    required this.accent,
    required this.soft,
  });

  @override
  State<_HourTimeline> createState() => _HourTimelineState();
}

class _HourTimelineState extends State<_HourTimeline> {
  final _controller = ScrollController();
  int? _alignedTo;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _alignToCurrent() {
    final index = widget.marks.indexWhere((m) => m.from == widget.currentFrom);
    if (index < 0 || !_controller.hasClients) return;
    final max = _controller.position.maxScrollExtent;
    if (max == 0 && index > 0) return;
    if (_alignedTo == index) return;
    _alignedTo = index;
    final target = (index * 72.0 - 24).clamp(0.0, max);
    if (_controller.offset != target) {
      _controller.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _alignToCurrent());

    return SizedBox(
      height: 36,
      child: ListView.separated(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        itemCount: widget.marks.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final mark = widget.marks[index];
          final reached = widget.elapsed >= mark.from;
          final current = mark.from == widget.currentFrom && reached;
          final bg = current
              ? widget.accent
              : reached
                  ? widget.soft
                  : c.surface;
          final fg = current
              ? Colors.white
              : reached
                  ? widget.accent
                  : c.textMuted;
          return Container(
            width: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: reached ? widget.accent : c.border,
                width: current ? 0 : 1,
              ),
            ),
            child: Text(
              '${mark.from.inHours}시간',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 단식 시작 전 안내와 시작 버튼
class FastingStartCard extends StatelessWidget {
  final Color accent;
  final Color soft;
  final VoidCallback onStartNow;
  final VoidCallback onStartPast;

  const FastingStartCard({
    super.key,
    required this.accent,
    required this.soft,
    required this.onStartNow,
    required this.onStartPast,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final preview = fastingMilestones
        .where((m) => m.from.inHours >= 12)
        .toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
        boxShadow: appCardShadow(c),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '식사했다면 지금 시작',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '몇 시간이 되든 그 시간으로 이어져요. 12시간, 24시간, 48시간, 그 이상도 구간마다 장점이 바뀝니다.',
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: preview.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final hours = preview[index].from.inHours;
                return _PreviewHour(hours: hours, accent: accent, soft: soft);
              },
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: onStartNow,
            child: const Text(
              '단식 시작',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
          Center(
            child: TextButton(
              onPressed: onStartPast,
              child: Text(
                '지난 시각부터 시작',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewHour extends StatelessWidget {
  final int hours;
  final Color accent;
  final Color soft;

  const _PreviewHour({
    required this.hours,
    required this.accent,
    required this.soft,
  });

  @override
  Widget build(BuildContext context) {
    final title = fastingMilestoneAtHours(hours)?.title ?? '';
    return Container(
      width: 76,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$hours',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: accent,
              height: 1.0,
            ),
          ),
          Text(
            '시간',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: accent,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: AppPalette.of(context).textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
