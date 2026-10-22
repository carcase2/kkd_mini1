import 'package:flutter/material.dart';

class SeriesSelectionBar extends StatelessWidget {
  const SeriesSelectionBar({
    super.key,
    required this.selectedCount,
    required this.redownloadableCount,
    required this.onDownload,
    required this.onRedownload,
    required this.onMore,
    required this.onClear,
  });

  final int selectedCount;
  final int redownloadableCount;
  final VoidCallback onDownload;
  final VoidCallback onRedownload;
  final VoidCallback onMore;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    '$selectedCount개 선택',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const Spacer(),
                  TextButton(onPressed: onClear, child: const Text('해제')),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: onDownload,
                      icon: const Icon(Icons.download_rounded, size: 20),
                      label: const Text('보관'),
                    ),
                  ),
                  if (redownloadableCount > 0) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onRedownload,
                        child: const Text('다시'),
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    onPressed: onMore,
                    icon: const Icon(Icons.more_horiz),
                    tooltip: '더보기',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
