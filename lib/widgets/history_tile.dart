import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/session.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

class SessionHistoryTile extends StatelessWidget {
  final TrackingSession session;
  final Color accent;
  final VoidCallback? onDelete;

  const SessionHistoryTile({
    super.key,
    required this.session,
    required this.accent,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isSuccess = session.status == SessionStatus.completed;
    final statusColor = isSuccess ? AppColors.success : AppColors.danger;
    final statusLabel = isSuccess ? '성공' : '실패';
    final dateFmt = DateFormat('M/d (E) HH:mm', 'ko');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isSuccess ? Icons.check_rounded : Icons.close_rounded,
              color: statusColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        formatDuration(session.elapsed, short: true),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  dateFmt.format(session.startTime),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (session.targetDuration != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '목표 ${formatTargetDuration(session.targetDuration)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: accent.withValues(alpha: 0.8),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (onDelete != null)
            IconButton(
              onPressed: onDelete,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              color: AppColors.textMuted,
            ),
        ],
      ),
    );
  }
}

class MasturbationHistoryTile extends StatelessWidget {
  final MasturbationLog log;
  final VoidCallback? onDelete;

  const MasturbationHistoryTile({
    super.key,
    required this.log,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('M월 d일 (E) a h:mm', 'ko');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.checkSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.favorite_rounded, color: AppColors.check),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  dateFmt.format(log.timestamp),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (log.note != null && log.note!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    log.note!,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (onDelete != null)
            IconButton(
              onPressed: onDelete,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              color: AppColors.textMuted,
            ),
        ],
      ),
    );
  }
}
