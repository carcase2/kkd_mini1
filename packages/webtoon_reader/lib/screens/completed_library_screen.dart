import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../models/library_sort_mode.dart';
import '../models/series.dart';
import '../services/storage_service.dart';
import '../utils/text_search.dart';
import '../widgets/app_search_field.dart';
import '../widgets/confirm_delete_dialog.dart';
import '../widgets/highlighted_text.dart';
import '../widgets/library_sort_sheet.dart';
import '../widgets/series_cover.dart';
import '../widgets/theme_toggle_button.dart';
import '../widgets/network_status_chip.dart';
import 'series_screen.dart';

class CompletedLibraryScreen extends StatefulWidget {
  const CompletedLibraryScreen({super.key});

  @override
  State<CompletedLibraryScreen> createState() => _CompletedLibraryScreenState();
}

class _CompletedLibraryScreenState extends State<CompletedLibraryScreen> {
  final _storage = StorageService.instance;
  final _searchController = TextEditingController();
  List<Series> _seriesList = [];
  Map<String, SeriesLibraryStats> _statsById = {};
  LibrarySortMode _sortMode = StorageService.instance.completedLibrarySortMode;
  String _searchQuery = '';

  List<Series> get _visibleSeries =>
      TextSearch.filterSeries(_seriesList, _searchQuery);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    final completed = _storage.getCompletedSeries();
    final stats = SeriesLibraryStats.buildFor(completed, _storage);
    setState(() {
      _statsById = stats;
      _seriesList = SeriesListSorter.sort(
        completed,
        _storage,
        _sortMode,
        statsById: stats,
      );
    });
  }

  Future<void> _pickSortMode() async {
    final picked = await showLibrarySortSheet(
      context,
      current: _sortMode,
      modes: LibrarySortMode.completedLibraryModes,
    );
    if (picked == null || picked == _sortMode || !mounted) return;
    await _storage.setCompletedLibrarySortMode(picked);
    final completed = _storage.getCompletedSeries();
    final stats = SeriesLibraryStats.buildFor(completed, _storage);
    setState(() {
      _sortMode = picked;
      _statsById = stats;
      _seriesList = SeriesListSorter.sort(
        completed,
        _storage,
        _sortMode,
        statsById: stats,
      );
    });
  }

  Future<void> _openSeries(Series series) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SeriesScreen(series: series)),
    );
    _reload();
  }

  Future<void> _restoreToLibrary(Series series) async {
    await _storage.restoreSeriesToLibrary(series.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"${series.title}"을(를) 내 서재로 되돌렸습니다')),
    );
    _reload();
  }

  Future<void> _deleteSeries(Series series) async {
    final chapters = _storage.getChapters(series.id);
    final downloaded = chapters.where((c) => c.isDownloaded).length;

    final confirmed = await confirmDelete(
      context,
      title: '완료 만화 삭제',
      message:
          '"${series.title}"을(를) 삭제할까요?\n'
          '회차 ${chapters.length}개 · 저장 $downloaded개가 모두 삭제됩니다.',
    );
    if (!confirmed || !mounted) return;

    await _storage.deleteSeriesCompletely(series.id);
    if (mounted) _reload();
  }

  Future<void> _showSeriesActions(Series series) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.unarchive_outlined),
              title: const Text('내 서재로 되돌리기'),
              subtitle: const Text('읽는 중 목록에 다시 표시'),
              onTap: () => Navigator.pop(context, 'restore'),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_forever,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                '삭제',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    switch (action) {
      case 'restore':
        await _restoreToLibrary(series);
        break;
      case 'delete':
        await _deleteSeries(series);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('완료 (${_seriesList.length})'),
        actions: [
          const NetworkStatusChip(),
          const ThemeToggleButton(),
          IconButton(
            onPressed: _pickSortMode,
            icon: const Icon(Icons.sort_rounded),
            tooltip: '정렬',
          ),
        ],
      ),
      body: _seriesList.isEmpty
          ? _EmptyCompleted()
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: AppSearchField(
                    controller: _searchController,
                    hintText: '완료 만화 검색',
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                ),
                Expanded(
                  child: _visibleSeries.isEmpty
                      ? SearchEmptyState(query: _searchQuery)
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                          scrollCacheExtent: const ScrollCacheExtent.pixels(720),
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 16,
                                childAspectRatio: 0.48,
                              ),
                          itemCount: _visibleSeries.length,
                          itemBuilder: (context, index) {
                            final series = _visibleSeries[index];
                            final stats = _statsById[series.id];
                            return _CompletedPosterCard(
                              series: series,
                              searchQuery: _searchQuery,
                              totalChapters: stats?.chapterCount ?? 0,
                              recentReadChapter: stats?.lastReadChapterNumber,
                              onTap: () => _openSeries(series),
                              onLongPress: () => _showSeriesActions(series),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _EmptyCompleted extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: scheme.outline),
            const SizedBox(height: 16),
            Text('완료한 만화가 없어요', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '다 본 만화는 회차 화면 메뉴에서\n「완료로 이동」으로 정리할 수 있어요',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _CompletedPosterCard extends StatelessWidget {
  const _CompletedPosterCard({
    required this.series,
    required this.searchQuery,
    required this.totalChapters,
    this.recentReadChapter,
    required this.onTap,
    required this.onLongPress,
  });

  final Series series;
  final String searchQuery;
  final int totalChapters;
  final int? recentReadChapter;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  SeriesCover(
                    series: series,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.tertiary.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '완료',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onTertiary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  if (recentReadChapter != null)
                    Positioned(
                      left: 6,
                      right: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '최근 $recentReadChapter화',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            HighlightedText(
              text: series.title,
              highlight: searchQuery,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (totalChapters > 0)
              Text(
                '$totalChapters화',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
