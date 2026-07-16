import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/format.dart';

class TimerRing extends StatelessWidget {
  final Duration elapsed;
  final Duration? target;
  final Color color;
  final double size;
  final String? label;

  /// true면 링만 / 짧은 시간만 표시 (홈 카드 등 작은 영역)
  final bool compact;

  const TimerRing({
    super.key,
    required this.elapsed,
    this.target,
    required this.color,
    this.size = 220,
    this.label,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final isSmall = compact || size < 120;
    final progress = target == null || target!.inSeconds == 0
        ? null
        : elapsed.inSeconds / target!.inSeconds;
    // 링은 한 바퀴(100%)까지만 채우고, 숫자는 110%처럼 초과 표시
    final ringProgress = progress?.clamp(0.0, 1.0);

    final pad = isSmall ? size * 0.12 : 24.0;
    final timeStyle = TextStyle(
      fontSize: isSmall ? size * 0.14 : (size > 180 ? 28.0 : 22.0),
      fontWeight: FontWeight.w800,
      color: c.textPrimary,
      letterSpacing: isSmall ? 0 : 1,
      height: 1.1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(
              progress: ringProgress,
              color: color,
              trackColor: c.border,
              overtime: progress != null && progress > 1.0,
            ),
          ),
          Padding(
            padding: EdgeInsets.all(pad),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (label != null && !isSmall) ...[
                    Text(
                      label!,
                      style: TextStyle(
                        fontSize: 13,
                        color: c.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    // 작은 링: 짧은 표기
                    isSmall
                        ? formatDurationTiny(elapsed == Duration.zero
                            ? const Duration(seconds: 1)
                            : elapsed)
                        : formatDurationCompact(elapsed),
                    style: timeStyle,
                    maxLines: 1,
                  ),
                  if (!isSmall && target != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '목표 ${formatTargetDuration(target)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: color.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                    ),
                    if (progress != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        progress > 1.0
                            ? '${(progress * 100).toStringAsFixed(0)}% 완료'
                            : '${(progress * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              progress > 1.0 ? FontWeight.w700 : FontWeight.w400,
                          color: progress > 1.0 ? color : c.textMuted,
                        ),
                        maxLines: 1,
                      ),
                    ],
                  ] else if (!isSmall && target == null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '자유 모드',
                      style: TextStyle(
                        fontSize: 12,
                        color: c.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double? progress;
  final Color color;
  final Color trackColor;
  final bool overtime;

  _RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    this.overtime = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.06;
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.width - stroke) / 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    final sweep =
        progress == null ? math.pi * 2 : math.pi * 2 * progress!;

    final ringColor = overtime ? AppColors.success : color;

    final gradient = SweepGradient(
      startAngle: -math.pi / 2,
      endAngle: -math.pi / 2 + math.pi * 2,
      colors: [
        ringColor.withValues(alpha: 0.4),
        ringColor,
        ringColor.withValues(alpha: 0.9),
      ],
      stops: const [0.0, 0.5, 1.0],
      transform: const GradientRotation(-math.pi / 2),
    );

    final progressPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    if (progress == null) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
    } else {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        sweep,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.overtime != overtime;
  }
}
