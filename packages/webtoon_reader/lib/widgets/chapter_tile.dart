import 'package:flutter/material.dart';

import '../models/chapter.dart';
import '../utils/text_search.dart';
import 'highlighted_text.dart';

class ChapterTile extends StatelessWidget {
  const ChapterTile({
    super.key,
    required this.chapter,
    required this.isSelected,
    required this.hasReadingProgress,
    this.isSyncNew = false,
    this.isLastRead = false,
    this.searchQuery = '',
    required this.onToggleSelect,
    required this.onOpen,
    required this.onMore,
    this.enabled = true,
    this.showCheckbox = false,
  });

  final Chapter chapter;
  final bool isSelected;
  final bool hasReadingProgress;
  final bool isSyncNew;
  final bool isLastRead;
  final String searchQuery;
  final bool enabled;
  final bool showCheckbox;
  final VoidCallback onToggleSelect;
  final VoidCallback onOpen;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final archived = chapter.isArchived;
    final accent = isSyncNew
        ? scheme.error
        : isLastRead
        ? scheme.primary
        : archived
        ? scheme.tertiary
        : scheme.outline;

    final meta = <String>[
      if (chapter.publishedLabel != null && chapter.publishedLabel!.isNotEmpty)
        chapter.publishedLabel!,
      if (isLastRead) '이어 읽기',
      if (hasReadingProgress && !isLastRead) '읽는 중',
      if (archived) '보관됨',
      if (chapter.hasPartialDownload) chapter.downloadStatusLabel,
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: isSelected
            ? scheme.primaryContainer.withValues(alpha: 0.35)
            : isLastRead
            ? scheme.primaryContainer.withValues(alpha: 0.22)
            : isSyncNew
            ? scheme.errorContainer.withValues(alpha: 0.22)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: !enabled
              ? null
              : showCheckbox
              ? onToggleSelect
              : onOpen,
          onLongPress: enabled ? onToggleSelect : null,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
            child: Row(
              children: [
                if (showCheckbox)
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: Checkbox(
                      value: isSelected,
                      onChanged: enabled ? (_) => onToggleSelect() : null,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                _EpisodeBadge(
                  number: chapter.number,
                  color: accent,
                  filled: isLastRead || isSyncNew || archived,
                  showNew: isSyncNew,
                  searchQuery: searchQuery,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      HighlightedText(
                        text: chapter.title,
                        highlight: searchQuery,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          meta.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: isLastRead
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                                fontWeight: isLastRead
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  onPressed: enabled ? onMore : null,
                  icon: const Icon(Icons.more_horiz, size: 22),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EpisodeBadge extends StatelessWidget {
  const _EpisodeBadge({
    required this.number,
    required this.color,
    required this.filled,
    this.showNew = false,
    this.searchQuery = '',
  });

  final int number;
  final Color color;
  final bool filled;
  final bool showNew;
  final String searchQuery;

  bool get _numberHighlighted {
    return TextSearch.matches('$number', searchQuery) ||
        TextSearch.matches('$number화', searchQuery);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? color.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _numberHighlighted
                  ? Theme.of(context).colorScheme.primary
                  : color.withValues(alpha: filled ? 0.5 : 0.28),
              width: _numberHighlighted ? 2 : 1,
            ),
          ),
          child: Text(
            '$number',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              letterSpacing: -0.4,
              color: _numberHighlighted
                  ? Theme.of(context).colorScheme.primary
                  : filled
                  ? color
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (showNew)
          Positioned(
            right: -4,
            top: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'N',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
