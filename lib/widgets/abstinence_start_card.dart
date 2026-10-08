import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/abstinence_benefits.dart';

/// 금욕 시작 전 안내와 시작 버튼. 목표 시간은 없다.
class AbstinenceStartCard extends StatelessWidget {
  final Color accent;
  final Color soft;
  final VoidCallback onStartNow;
  final VoidCallback onStartPast;

  const AbstinenceStartCard({
    super.key,
    required this.accent,
    required this.soft,
    required this.onStartNow,
    required this.onStartPast,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final preview = abstinenceMilestones
        .where((m) => m.from.inDays >= 1)
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
            '지금 시작',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '며칠이 되든 그 시간으로 이어져요. 1일, 7일, 30일, 그 이상도 구간마다 변화가 바뀝니다.',
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
                final mark = preview[index];
                return _PreviewDay(
                  label: abstinenceMarkLabel(mark.from),
                  title: mark.title,
                  accent: accent,
                  soft: soft,
                );
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
              '금욕 시작',
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

class _PreviewDay extends StatelessWidget {
  final String label;
  final String title;
  final Color accent;
  final Color soft;

  const _PreviewDay({
    required this.label,
    required this.title,
    required this.accent,
    required this.soft,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: accent,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 4),
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
