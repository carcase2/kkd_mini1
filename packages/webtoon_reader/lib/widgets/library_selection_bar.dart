import 'package:flutter/material.dart';

class LibrarySelectionBar extends StatelessWidget {
  const LibrarySelectionBar({
    super.key,
    required this.selectedSeriesCount,
    required this.pendingChapterCount,
    required this.onDownload,
    required this.onClear,
  });

  final int selectedSeriesCount;
  final int pendingChapterCount;
  final VoidCallback onDownload;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canDownload = pendingChapterCount > 0;

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
                    '$selectedSeriesCount개 만화 선택',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const Spacer(),
                  TextButton(onPressed: onClear, child: const Text('해제')),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: canDownload ? onDownload : null,
                  icon: const Icon(Icons.inventory_2_outlined, size: 20),
                  label: Text(
                    canDownload
                        ? '이 만화 보관 · $pendingChapterCount화'
                        : '보관할 회차 없음',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
