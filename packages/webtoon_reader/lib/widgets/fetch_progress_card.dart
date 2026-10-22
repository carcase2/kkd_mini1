import 'dart:async';

import 'package:flutter/material.dart';

import '../models/fetch_status.dart';

/// 하단에 고정되는 다운로드/불러오기 진행 표시.
class FetchProgressDock extends StatefulWidget {
  const FetchProgressDock({
    super.key,
    required this.status,
    this.onCancel,
  });

  final FetchStatus status;
  final VoidCallback? onCancel;

  @override
  State<FetchProgressDock> createState() => _FetchProgressDockState();
}

class _FetchProgressDockState extends State<FetchProgressDock> {
  Timer? _ticker;
  DateTime _lastUpdateAt = DateTime.now();
  String _lastStatusKey = '';

  @override
  void initState() {
    super.initState();
    _lastStatusKey = _statusKey(widget.status);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant FetchProgressDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextKey = _statusKey(widget.status);
    if (nextKey != _lastStatusKey) {
      _lastStatusKey = nextKey;
      _lastUpdateAt = DateTime.now();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _statusKey(FetchStatus s) {
    return [
      s.phase.name,
      s.message,
      s.seriesCurrent,
      s.seriesTotal,
      s.chapterCurrent,
      s.chapterTotal,
      s.imageCurrent,
      s.imageTotal,
      s.elapsed.inSeconds,
    ].join('|');
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final onCancel = widget.onCancel;
    final scheme = Theme.of(context).colorScheme;
    final progress = status.overallProgress;
    final elapsed = status.elapsed.inSeconds;
    final canCancel = onCancel != null &&
        status.phase != FetchPhase.done &&
        status.phase != FetchPhase.cancelled &&
        status.phase != FetchPhase.error;

    final message = status.phaseLabel.isEmpty
        ? status.message
        : '${status.phaseLabel} · ${status.message}';

    final details = <String>[
      if (status.seriesCurrent != null && status.seriesTotal != null)
        '만화 ${status.seriesCurrent}/${status.seriesTotal}',
      if (status.chapterCurrent != null && status.chapterTotal != null)
        '회차 ${status.chapterCurrent}/${status.chapterTotal}',
      if (status.imageCurrent != null && status.imageTotal != null)
        '이미지 ${status.imageCurrent}/${status.imageTotal}장',
      if (elapsed > 0) '경과 $elapsed초',
      if (progress != null && progress > 0 && elapsed > 10)
        '예상 남은 ${((elapsed / progress) - elapsed).round()}초',
    ];

    final isActive = canCancel;
    final staleSeconds = DateTime.now().difference(_lastUpdateAt).inSeconds;

    return Material(
      elevation: 12,
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (status.phase == FetchPhase.cancelled)
                    Icon(Icons.cancel_outlined, color: scheme.error, size: 22)
                  else if (status.phase == FetchPhase.error)
                    Icon(Icons.error_outline, color: scheme.error, size: 22)
                  else if (status.phase == FetchPhase.done)
                    Icon(Icons.check_circle_outline, color: scheme.primary, size: 22)
                  else
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: scheme.primary,
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  if (canCancel)
                    TextButton(
                      onPressed: onCancel,
                      child: const Text('취소'),
                    ),
                ],
              ),
              if (details.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  details.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
              if (isActive) ...[
                const SizedBox(height: 4),
                Text(
                  staleSeconds >= 15
                      ? '진행 업데이트 $staleSeconds초 없음 · 네트워크가 느릴 수 있습니다'
                      : '최근 업데이트 $staleSeconds초 전',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: staleSeconds >= 15
                            ? scheme.error
                            : scheme.onSurfaceVariant,
                      ),
                ),
              ],
              if (status.phase == FetchPhase.cloudflare && elapsed > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '보안 확인은 보통 10~60초 걸립니다',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
              if (progress != null && canCancel) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${(progress * 100).round()}%',
                    style: Theme.of(context).textTheme.labelSmall,
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

class FetchProgressCard extends StatelessWidget {
  const FetchProgressCard({
    super.key,
    required this.status,
    this.onCancel,
  });

  final FetchStatus status;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return FetchProgressDock(status: status, onCancel: onCancel);
  }
}
