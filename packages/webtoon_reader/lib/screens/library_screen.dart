import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../models/library_sort_mode.dart';
import '../models/add_series_input.dart';
import '../models/fetch_controller.dart';
import '../models/fetch_status.dart';
import '../models/series.dart';
import '../models/sync_result.dart';
import '../models/webview_bypass_runner.dart';
import '../services/chapter_reader.dart';
import '../services/storage_service.dart';
import '../services/supabase_sync_service.dart';
import '../services/webtoon_fetcher.dart';
import '../services/download_activity_service.dart';
import '../services/network_policy.dart';
import '../services/connectivity_service.dart';
import '../utils/webview_bypass.dart';
import '../utils/text_search.dart';
import '../utils/storage_format.dart';
import '../widgets/add_series_dialog.dart';
import '../widgets/app_search_field.dart';
import '../widgets/confirm_delete_dialog.dart';
import '../widgets/fetch_progress_card.dart';
import '../widgets/highlighted_text.dart';
import '../widgets/library_selection_bar.dart';
import '../widgets/library_sort_sheet.dart';
import '../widgets/lock_button.dart';
import '../widgets/migrate_site_dialog.dart';
import '../widgets/series_cover.dart';
import '../widgets/status_banner.dart';
import '../widgets/theme_toggle_button.dart';
import '../widgets/network_status_chip.dart';
import '../services/theme_mode_service.dart';
import '../models/chapter.dart';
import 'series_screen.dart';
import 'browse_catalog_screen.dart';
import 'completed_library_screen.dart';
import 'reader_screen.dart';
import 'webview_reader_screen.dart';

enum _LibraryRefreshScope { emptyOnly, all }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _storage = StorageService.instance;
  final _fetcher = WebtoonFetcher();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  bool _showScrollTop = false;

  WebViewBypassRunner get _bypass => createWebViewBypassRunner(context);
  List<Series> _seriesList = [];

  /// 시리즈별 회차/읽기 요약. 빌드마다 Hive를 다시 읽지 않습니다.
  Map<String, SeriesLibraryStats> _statsById = {};
  final Set<String> _selectedSeriesIds = {};
  bool _loading = false;
  bool _queueSheetOpen = false;
  FetchStatus? _fetchStatus;
  String? _syncMessage;
  LibrarySortMode _sortMode = StorageService.instance.librarySortMode;
  String _searchQuery = '';
  bool _showEmptyChaptersOnly = false;
  bool _showFavoritesOnly = false;
  DateTime? _lastBackupAt;
  int? _lastBackupSeriesCount;
  final List<_SeriesDownloadJob> _downloadJobs = [];
  bool _queueRunning = false;
  bool _wifiOnly = StorageService.instance.wifiOnlyDownload;
  int? _totalStorageBytes;
  bool _reconcileRunning = false;

  bool get _hasSelection => _selectedSeriesIds.isNotEmpty;

  List<Series> get _favoriteSeries =>
      _seriesList.where((s) => s.isFavorite).toList();

  int get _favoriteSeriesCount => _favoriteSeries.length;

  List<Series> get _seriesWithEmptyChapters => _seriesList
      .where((s) => (_statsById[s.id]?.hasEmptyChapters ?? true))
      .toList();

  int get _emptyChapterSeriesCount => _seriesWithEmptyChapters.length;

  List<Series> get _visibleSeries {
    var base = _seriesList;
    if (_showFavoritesOnly) {
      base = base.where((s) => s.isFavorite).toList();
    }
    if (_showEmptyChaptersOnly) {
      base = base
          .where((s) => _statsById[s.id]?.hasEmptyChapters ?? true)
          .toList();
    }
    return TextSearch.filterSeries(base, _searchQuery);
  }

  SeriesLibraryStats _statsFor(String seriesId) {
    return _statsById[seriesId] ??
        const SeriesLibraryStats(
          chapterCount: 0,
          downloadedCount: 0,
          pendingCount: 0,
        );
  }

  void _rebuildStatsAndSort(List<Series> active) {
    _statsById = SeriesLibraryStats.buildFor(active, _storage);
    _seriesList = SeriesListSorter.sort(
      active,
      _storage,
      _sortMode,
      statsById: _statsById,
    );
  }

  int _pendingChapterCountForSeries(String seriesId) {
    return _statsFor(seriesId).pendingCount;
  }

  int get _totalPendingChapters {
    var total = 0;
    for (final series in _seriesList) {
      total += _pendingChapterCountForSeries(series.id);
    }
    return total;
  }

  int get _selectedPendingChapters {
    var total = 0;
    for (final id in _selectedSeriesIds) {
      total += _pendingChapterCountForSeries(id);
    }
    return total;
  }

  List<Series> get _seriesWithPending => _seriesList
      .where((s) => _pendingChapterCountForSeries(s.id) > 0)
      .toList();

  int get _queuePendingCount =>
      _downloadJobs.where((j) => !j.isDone && !j.isCancelled).length;

  bool get _hasQueueActivity => _queuePendingCount > 0 || _queueRunning;

  _SeriesDownloadJob? get _runningJob {
    for (final job in _downloadJobs) {
      if (job.isRunning) return job;
    }
    return null;
  }

  String get _queueSummaryText {
    final running = _runningJob;
    if (running == null) {
      return _queuePendingCount > 0
          ? '다운로드 대기 $_queuePendingCount개'
          : '다운로드 대기열 없음';
    }
    final percent = ((running.progress ?? 0) * 100).round();
    return '${running.series.title} · $percent%';
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onLibraryScroll);
    DownloadActivityService.instance.registerOpenQueue(_showDownloadQueueSheet);
    _reload();
  }

  @override
  void dispose() {
    DownloadActivityService.instance.unregisterOpenQueue(
      _showDownloadQueueSheet,
    );
    _scrollController.removeListener(_onLibraryScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onLibraryScroll() {
    final show = _scrollController.hasClients && _scrollController.offset > 520;
    if (show == _showScrollTop || !mounted) return;
    setState(() => _showScrollTop = show);
  }

  void _scrollLibraryToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  List<Series> _recentSeries({String? excludeId, int limit = 8}) {
    final ranked =
        <Series>[
          for (final series in _seriesList)
            if (series.id != excludeId &&
                _statsFor(series.id).lastReadAt != null)
              series,
        ]..sort((a, b) {
          final at = _statsFor(a.id).lastReadAt!;
          final bt = _statsFor(b.id).lastReadAt!;
          return bt.compareTo(at);
        });
    if (ranked.length <= limit) return ranked;
    return ranked.sublist(0, limit);
  }

  /// 전체 시리즈 디스크 reconcile은 앱 세션당 1회만 수행합니다.
  static bool _didFullReconcileThisSession = false;

  /// 클라우드 회차 표시는 앱 세션당 1회만 맞춥니다.
  static bool _didCloudInventoryThisSession = false;

  /// 시리즈 화면에서 돌아온 직후 해당 시리즈만 reconcile합니다.
  String? _pendingReconcileSeriesId;

  Future<void> _reload({String? preferReconcileSeriesId}) async {
    final focusId = preferReconcileSeriesId ?? _pendingReconcileSeriesId;
    _pendingReconcileSeriesId = null;

    // UI를 먼저 그리고, reconcile은 백그라운드로 돌립니다.
    if (!mounted) return;
    final active = _storage.getActiveSeries();
    final completedCount = _storage.getCompletedSeries().length;
    final backupInfo = await _storage.latestBackupInfo();
    if (!mounted) return;
    setState(() {
      _rebuildStatsAndSort(active);
      _wifiOnly = _storage.wifiOnlyDownload;
      _lastBackupAt = backupInfo?.createdAt;
      _lastBackupSeriesCount = backupInfo?.seriesCount;
      if (active.isEmpty && completedCount > 0) {
        _syncMessage = '완료한 만화 $completedCount개가 있습니다. 상단 메뉴에서 확인해 주세요.';
      }
    });
    unawaited(_refreshStorageBytes());

    if (focusId != null) {
      unawaited(_reconcileInBackground(focusId: focusId));
    } else if (!_didFullReconcileThisSession) {
      _didFullReconcileThisSession = true;
      unawaited(_reconcileInBackground());
    }
    if (!_didCloudInventoryThisSession) {
      _didCloudInventoryThisSession = true;
      unawaited(_quietlyRefreshCloudInventory());
    }
  }

  Future<void> _quietlyRefreshCloudInventory() async {
    if (!ConnectivityService.instance.isOnline) return;
    try {
      final updated = await _fetcher.refreshCloudInventoryQuiet();
      if (!mounted || updated <= 0) return;
      setState(() {
        _rebuildStatsAndSort(_storage.getActiveSeries());
      });
    } catch (e) {
      debugPrint('library cloud inventory skipped: $e');
    }
  }

  Future<void> _refreshStorageBytes() async {
    try {
      final bytes = await _storage.totalWebtoonStorageBytes();
      if (mounted) setState(() => _totalStorageBytes = bytes);
    } catch (_) {}
  }

  Future<void> _reconcileInBackground({String? focusId}) async {
    if (_reconcileRunning) return;
    _reconcileRunning = true;
    try {
      if (focusId != null) {
        await _storage.reconcileSeriesDownloads(focusId);
      } else {
        await _storage.reconcileAllSeriesDownloads();
      }
      if (!mounted) return;
      setState(() {
        _rebuildStatsAndSort(_storage.getActiveSeries());
      });
      unawaited(_refreshStorageBytes());
    } catch (e) {
      debugPrint('background reconcile failed: $e');
    } finally {
      _reconcileRunning = false;
    }
  }

  Future<bool> _ensureCanDownload() async {
    final reason = await NetworkPolicy.instance.downloadBlockReason();
    if (reason == null) return true;
    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reason)));
    return false;
  }

  Future<void> _toggleWifiOnly() async {
    final next = !_wifiOnly;
    await _storage.setWifiOnlyDownload(next);
    if (!mounted) return;
    setState(() {
      _wifiOnly = next;
      _syncMessage = next ? 'Wi‑Fi에서만 받기가 켜졌습니다' : 'Wi‑Fi에서만 받기가 꺼졌습니다';
    });
  }

  String get _backupMenuSubtitle {
    final at = _lastBackupAt;
    if (at == null) return '최근 백업 없음';
    final local = at.toLocal();
    final stamp =
        '${local.year}.${local.month.toString().padLeft(2, '0')}.${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    final count = _lastBackupSeriesCount;
    return count == null ? '최근 $stamp' : '최근 $stamp · $count개';
  }

  String _formatBackupInfo(({int seriesCount, DateTime? createdAt}) info) {
    final at = info.createdAt?.toLocal();
    if (at == null) return '${info.seriesCount}개';
    final stamp =
        '${at.year}.${at.month.toString().padLeft(2, '0')}.${at.day.toString().padLeft(2, '0')} '
        '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    return '$stamp · ${info.seriesCount}개';
  }

  Future<void> _pickSortMode() async {
    final picked = await showLibrarySortSheet(
      context,
      current: _sortMode,
      modes: LibrarySortMode.activeLibraryModes,
    );
    if (picked == null || picked == _sortMode || !mounted) return;
    await _storage.setLibrarySortMode(picked);
    setState(() {
      _sortMode = picked;
      _rebuildStatsAndSort(_storage.getActiveSeries());
    });
  }

  Future<void> _cancelFetch() async {
    await _fetcher.cancel();
  }

  Future<void> _showDownloadQueueSheet() async {
    if (!mounted || _queueSheetOpen) return;
    _queueSheetOpen = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) {
          // status/pendingJobs 갱신 시 시트 내용도 같이 갱신합니다.
          return ValueListenableBuilder<FetchStatus?>(
            valueListenable: DownloadActivityService.instance.status,
            builder: (context, status, _) {
              return ValueListenableBuilder<int>(
                valueListenable: DownloadActivityService.instance.pendingJobs,
                builder: (context, pendingJobs, _) {
                  final active = _downloadJobs.where((j) => !j.isDone).toList();
                  return SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '다운로드 큐',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (status != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              status.phaseLabel.isEmpty
                                  ? status.message
                                  : '${status.phaseLabel} · ${status.message}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            if (status.overallProgress != null) ...[
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: status.overallProgress,
                                  minHeight: 6,
                                ),
                              ),
                            ],
                          ],
                          const SizedBox(height: 8),
                          if (active.isEmpty)
                            Text(
                              '진행 중인 다운로드가 없습니다.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            )
                          else
                            ...active.map(
                              (job) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  job.isRunning
                                      ? Icons.downloading_rounded
                                      : Icons.schedule_rounded,
                                ),
                                title: Text(
                                  job.series.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  job.isRunning
                                      ? '${((job.progress ?? 0) * 100).round()}% · ${job.statusMessage ?? '다운로드 중'}'
                                      : '대기 중',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: IconButton(
                                  onPressed: () =>
                                      _cancelSeriesJob(job.series.id),
                                  icon: const Icon(Icons.cancel_outlined),
                                  tooltip: '이 만화 취소',
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: () => unawaited(
                                  _enqueueSeriesJobs(
                                    _seriesWithPending,
                                    label: '전체',
                                    openQueue: false,
                                  ),
                                ),
                                icon: const Icon(Icons.playlist_add_rounded),
                                label: const Text('나머지 미보관 만화 추가'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: _visibleSeries.isEmpty
                                    ? null
                                    : () => unawaited(
                                        _enqueueSeriesJobs(
                                          _visibleSeries,
                                          label: '보이는 목록',
                                          openQueue: false,
                                        ),
                                      ),
                                icon: const Icon(Icons.visibility_outlined),
                                label: const Text('보이는 만화 추가'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: () {
                                  Navigator.pop(sheetContext);
                                  unawaited(_openBrowseCatalog());
                                },
                                icon: const Icon(Icons.explore_outlined),
                                label: const Text('다른 만화 추가'),
                              ),
                            ],
                          ),
                          if (active.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              '시트를 닫아도 다운로드는 계속됩니다. 상단 상태 줄을 눌러 다시 열 수 있습니다.',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      );
    } finally {
      _queueSheetOpen = false;
    }
  }

  Future<void> _enqueueSeriesJobs(
    List<Series> candidates, {
    required String label,
    bool openQueue = true,
  }) async {
    if (!await _ensureCanDownload()) return;
    final queuedIds = _downloadJobs
        .where((j) => !j.isDone && !j.isCancelled)
        .map((j) => j.series.id)
        .toSet();
    final targets = candidates
        .where((s) => _pendingChapterCountForSeries(s.id) > 0)
        .where((s) => !queuedIds.contains(s.id))
        .toList();
    if (targets.isEmpty) {
      if (!mounted) return;
      setState(() => _syncMessage = '$label 다운로드에 추가할 만화가 없습니다.');
      return;
    }
    if (!mounted) return;
    setState(() {
      _downloadJobs.addAll(targets.map(_SeriesDownloadJob.new));
      _syncMessage = '${targets.length}개 만화를 다운로드 큐에 추가했습니다.';
    });
    DownloadActivityService.instance.setPendingJobs(_queuePendingCount);
    if (!_queueRunning) {
      unawaited(_runDownloadQueue());
    }
    if (openQueue && mounted) {
      await _showDownloadQueueSheet();
    }
  }

  Future<void> _cancelSeriesJob(String seriesId) async {
    final idx = _downloadJobs.indexWhere(
      (j) => j.series.id == seriesId && !j.isDone && !j.isCancelled,
    );
    if (idx < 0) return;
    final job = _downloadJobs[idx];
    if (job.isRunning) {
      await _fetcher.cancel();
      return;
    }
    if (!mounted) return;
    setState(() {
      _downloadJobs[idx] = job.copyWith(isCancelled: true);
    });
  }

  Future<void> _runDownloadQueue() async {
    if (_queueRunning) return;
    _queueRunning = true;
    if (mounted) {
      setState(() => _fetchStatus = null);
    }
    while (true) {
      final nextIndex = _downloadJobs.indexWhere(
        (j) => !j.isDone && !j.isCancelled && !j.isRunning,
      );
      if (nextIndex < 0) break;
      var next = _downloadJobs[nextIndex];
      if (!mounted) break;
      setState(() {
        _downloadJobs[nextIndex] = next.copyWith(isRunning: true);
      });
      try {
        final result = await _fetcher.downloadAllUndownloadedChapters(
          next.series,
          _storage.getChapters(next.series.id),
          onProgress: (status) {
            final progress = status.overallProgress;
            if (!mounted) return;
            setState(() {
              _fetchStatus = status;
              final liveIndex = _downloadJobs.indexWhere(
                (j) => j.series.id == next.series.id && j.isRunning,
              );
              if (liveIndex >= 0) {
                _downloadJobs[liveIndex] = _downloadJobs[liveIndex].copyWith(
                  progress: progress,
                  statusMessage: status.message,
                );
              }
            });
          },
          bypassRunner: _bypass,
        );
        if (!mounted) break;
        setState(() {
          final liveIndex = _downloadJobs.indexWhere(
            (j) => j.series.id == next.series.id && j.isRunning,
          );
          if (liveIndex >= 0) {
            _downloadJobs[liveIndex] = _downloadJobs[liveIndex].copyWith(
              isRunning: false,
              isDone: true,
              downloadedCount: result.downloadedCount,
              statusMessage: result.errors.isEmpty
                  ? '완료'
                  : '일부 실패 ${result.errors.length}건',
            );
          }
        });
      } on FetchCancelledException {
        if (!mounted) break;
        setState(() {
          final liveIndex = _downloadJobs.indexWhere(
            (j) => j.series.id == next.series.id && j.isRunning,
          );
          if (liveIndex >= 0) {
            _downloadJobs[liveIndex] = _downloadJobs[liveIndex].copyWith(
              isRunning: false,
              isCancelled: true,
              statusMessage: '취소됨',
            );
          }
        });
      } catch (e) {
        if (!mounted) break;
        setState(() {
          final liveIndex = _downloadJobs.indexWhere(
            (j) => j.series.id == next.series.id && j.isRunning,
          );
          if (liveIndex >= 0) {
            _downloadJobs[liveIndex] = _downloadJobs[liveIndex].copyWith(
              isRunning: false,
              isDone: true,
              statusMessage: '실패: $e',
            );
          }
        });
      }
      await _reload();
    }
    if (!mounted) return;
    final done = _downloadJobs.where((j) => j.isDone).length;
    final cancelled = _downloadJobs.where((j) => j.isCancelled).length;
    setState(() {
      _queueRunning = false;
      _fetchStatus = null;
      _selectedSeriesIds.clear();
      _syncMessage = '다운로드 큐 완료 · 완료 $done개, 취소 $cancelled개';
      _downloadJobs.removeWhere((j) => j.isDone || j.isCancelled);
    });
  }

  void _handleCancelled() {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _fetchStatus = const FetchStatus(
        phase: FetchPhase.cancelled,
        message: '불러오기가 취소되었습니다',
      );
      _syncMessage = '취소됨 · 이미 저장된 회차는 유지됩니다';
      _rebuildStatsAndSort(_storage.getActiveSeries());
    });
  }

  Future<void> _requestRefresh() async {
    if (_loading || _seriesList.isEmpty) return;

    final scope = await _confirmRefresh();
    if (scope == null || !mounted) return;
    await _refreshAll(scope);
  }

  Future<_LibraryRefreshScope?> _confirmRefresh() async {
    final active = _storage.getActiveSeries();
    final emptyCount = active
        .where((s) => _storage.getChapters(s.id).isEmpty)
        .length;
    final totalCount = active.length;

    return showDialog<_LibraryRefreshScope>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('목록 새로고침'),
        content: const Text(
          '사이트에서 회차 목록을 다시 불러옵니다.\n'
          '시간이 걸릴 수 있으며, 진행 중 취소할 수 있습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: emptyCount == 0
                ? null
                : () => Navigator.pop(context, _LibraryRefreshScope.emptyOnly),
            child: Text('회차 없는 만화만 ($emptyCount)'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _LibraryRefreshScope.all),
            child: Text('전체 ($totalCount)'),
          ),
        ],
      ),
    );
  }

  List<Series> _refreshTargets(_LibraryRefreshScope scope) {
    final active = _storage.getActiveSeries();
    return switch (scope) {
      _LibraryRefreshScope.all => active,
      _LibraryRefreshScope.emptyOnly =>
        active.where((s) => _storage.getChapters(s.id).isEmpty).toList(),
    };
  }

  Future<void> _refreshAll(_LibraryRefreshScope scope) async {
    final targets = _refreshTargets(scope);
    if (targets.isEmpty) {
      setState(() => _syncMessage = '회차 목록이 없는 만화가 없습니다');
      return;
    }

    setState(() {
      _loading = true;
      _fetchStatus = null;
      _syncMessage = null;
    });

    try {
      final result = await _fetcher.refreshAllSeries(
        seriesList: targets,
        onProgress: (status) {
          if (mounted) setState(() => _fetchStatus = status);
        },
        bypassRunner: _bypass,
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _fetchStatus = null;
          _syncMessage = _formatSyncResult(result);
          _rebuildStatsAndSort(_storage.getActiveSeries());
        });
      }
    } on FetchCancelledException {
      _handleCancelled();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _fetchStatus = null;
          _syncMessage = '동기화 실패: $e';
        });
      }
    }
  }

  Future<void> _openCompletedLibrary() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CompletedLibraryScreen()),
    );
    _reload();
  }

  Future<void> _showMigrateSiteDialog() async {
    final result = await showMigrateSiteDialog(context);
    if (!mounted || result == null) return;

    final message = result.hasChanges
        ? '사이트 주소 변경 완료 · 만화 ${result.seriesUpdated}개 · 회차 ${result.chaptersUpdated}개'
        : '변경할 주소가 없었습니다 · 만화 찾기 주소만 ${result.newOrigin} 으로 설정됨';

    setState(() => _syncMessage = message);
  }

  Future<void> _toggleFavorite(Series series) async {
    await _storage.toggleFavorite(series.id);
    if (!mounted) return;
    setState(() => _rebuildStatsAndSort(_storage.getActiveSeries()));
  }

  Future<void> _showDiagnostics() async {
    final all = _storage.getAllSeries();
    final active = _storage.getActiveSeries();
    final completed = _storage.getCompletedSeries();
    final favorites = _storage.getFavoriteSeries();
    final backupInfo = await _storage.latestBackupInfo();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('진단 정보'),
        content: Text(
          '전체 만화: ${all.length}\n'
          '내 서재(활성): ${active.length}\n'
          '완료한 만화: ${completed.length}\n'
          '즐겨찾기: ${favorites.length}\n'
          '현재 화면 목록: ${_seriesList.length}\n'
          '필터 적용 후: ${_visibleSeries.length}\n'
          '즐겨찾기 필터: ${_showFavoritesOnly ? 'ON' : 'OFF'}\n'
          '회차 없음 필터: ${_showEmptyChaptersOnly ? 'ON' : 'OFF'}\n'
          '검색어: ${_searchQuery.trim().isEmpty ? '(없음)' : _searchQuery.trim()}\n'
          '네트워크: ${ConnectivityService.instance.detailLabel}\n'
          '최근 백업: ${backupInfo == null ? '없음' : _formatBackupInfo(backupInfo)}',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Future<void> _createBackup() async {
    final result = await _storage.createLatestBackup();
    final backupInfo = await _storage.latestBackupInfo();
    if (!mounted) return;
    setState(() {
      _lastBackupAt = backupInfo?.createdAt;
      _lastBackupSeriesCount = backupInfo?.seriesCount ?? result.seriesCount;
      final stamp = _formatBackupInfo((
        seriesCount: _lastBackupSeriesCount ?? result.seriesCount,
        createdAt: _lastBackupAt,
      ));
      _syncMessage = '백업 생성 완료 · $stamp\n${result.path}';
    });
  }

  Future<void> _syncCloudNow() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _syncMessage = null;
    });
    try {
      final applied = await _storage.syncWithCloud();
      await _reload();
      ThemeModeService.instance.load();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _syncMessage = applied
            ? '목록·읽기 위치만 맞췄습니다. 만화 이미지는 저장하기와 별개입니다.'
            : '목록·읽기 위치만 올렸습니다. 만화 파일은 저장하기/클라우드에 올리기로 저장됩니다.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _syncMessage = '클라우드 동기화 실패: $e';
      });
    }
  }

  Future<void> _refreshCloudInventory() async {
    if (!await _ensureCanDownload()) return;
    if (_loading) return;
    setState(() {
      _loading = true;
      _fetchStatus = null;
      _syncMessage = null;
    });
    try {
      final updated = await _fetcher.refreshCloudInventory(
        onProgress: (status) {
          if (mounted) setState(() => _fetchStatus = status);
        },
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _fetchStatus = null;
        _rebuildStatsAndSort(_storage.getActiveSeries());
        _syncMessage = updated > 0
            ? '클라우드 만화 $updated화를 표시했습니다. 누르면 클라우드에서 열립니다.'
            : '클라우드에서 새로 표시할 회차가 없습니다.';
      });
    } on FetchCancelledException {
      _handleCancelled();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _fetchStatus = null;
        _syncMessage = '클라우드 확인 실패: $e';
      });
    }
  }

  Future<void> _uploadLocalComicsToCloud() async {
    if (!await _ensureCanDownload()) return;
    if (_loading) return;
    var pending = 0;
    for (final series in _storage.getAllSeries()) {
      pending += _storage
          .getChapters(series.id)
          .where(
            (c) =>
                c.isDownloaded &&
                (c.cloudPageCount == null ||
                    c.cloudPageCount! < c.localPaths.length),
          )
          .length;
    }
    if (pending == 0) {
      setState(() => _syncMessage = '클라우드에 올릴 저장된 만화가 없습니다.');
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('클라우드에 만화 올리기'),
        content: Text(
          '기기에 저장된 회차 $pending화를 Cloudflare에 올립니다.\n'
          '다른 기기나 재설치 후에도 오프라인용으로 받을 수 있습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('올리기'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _loading = true;
      _fetchStatus = null;
      _syncMessage = null;
    });
    try {
      final result = await _fetcher.uploadLocalChaptersToCloud(
        onProgress: (status) {
          if (mounted) setState(() => _fetchStatus = status);
        },
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _fetchStatus = null;
        _rebuildStatsAndSort(_storage.getActiveSeries());
        final base = '클라우드 업로드 · ${result.downloadedCount}화 완료';
        _syncMessage = result.errors.isEmpty
            ? base
            : '$base\n일부 실패 ${result.errors.length}건\n${result.errors.first}';
      });
    } on FetchCancelledException {
      _handleCancelled();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _fetchStatus = null;
        _syncMessage = '클라우드 업로드 실패: $e';
      });
    }
  }

  Future<void> _signOutCloud() async {
    final email = SupabaseSyncService.instance.email ?? '계정';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('로그아웃'),
        content: Text(
          '$email 에서 로그아웃합니다.\n'
          '이 기기의 데이터는 남지만, 다시 로그인해야 클라우드 동기화를 사용할 수 있습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await SupabaseSyncService.instance.signOut();
  }

  Future<void> _restoreBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('백업 복원'),
        content: const Text(
          '최근 백업 파일로 현재 데이터를 덮어씁니다.\n'
          '현재 서재/회차/읽기 기록이 백업 내용으로 교체됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('복원'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _loading = true;
      _fetchStatus = null;
      _syncMessage = null;
    });
    try {
      final restored = await _storage.restoreLatestBackup();
      await _reload();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _syncMessage =
            '백업 복원 완료 · 만화 ${restored.seriesCount}개, 회차 그룹 ${restored.chapterGroups}개';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _syncMessage = '백업 복원 실패: $e';
      });
    }
  }

  Future<void> _recoverLibraryFromLocalData() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _fetchStatus = null;
      _syncMessage = null;
    });
    try {
      final recovered = await _storage.recoverMissingSeriesFromChapters();
      var refreshed = 0;
      for (var i = 0; i < recovered.length; i++) {
        final series = recovered[i];
        try {
          await _fetcher.refreshSeries(
            series,
            onProgress: (status) {
              if (!mounted) return;
              setState(() {
                _fetchStatus = status.copyWith(
                  message: '${status.message} (${i + 1}/${recovered.length})',
                );
              });
            },
            bypassRunner: _bypass,
          );
          refreshed++;
        } catch (_) {
          // 일부 실패해도 복구된 시리즈는 유지합니다.
        }
      }
      await _reload();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _fetchStatus = null;
        _syncMessage = recovered.isNotEmpty
            ? '로컬 복구 완료 · ${recovered.length}개 등록, $refreshed개 제목/목록 갱신'
            : '복구할 로컬 챕터 데이터가 없습니다';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _syncMessage = '로컬 복구 실패: $e';
      });
    }
  }

  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _showEmptyChaptersOnly = false;
      _showFavoritesOnly = false;
      _selectedSeriesIds.clear();
    });
  }

  Future<void> _repairSeriesLink(Series series) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _fetchStatus = null;
      _syncMessage = null;
    });
    try {
      final updated = await _fetcher.autoRepairSeriesUrl(
        series.id,
        onProgress: (status) {
          if (mounted) setState(() => _fetchStatus = status);
        },
        bypassRunner: _bypass,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _fetchStatus = null;
        _rebuildStatsAndSort(_storage.getActiveSeries());
        _syncMessage = '"${updated.title}" 링크 자동 복구 완료';
      });
    } on FetchCancelledException {
      _handleCancelled();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _fetchStatus = null;
        _syncMessage = '자동 복구 실패: $e';
      });
    }
  }

  Future<void> _showLibraryMenu() async {
    final completedCount = _storage.getCompletedSeries().length;
    final favoriteCount = _favoriteSeriesCount;
    final totalPending = _totalPendingChapters;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.86;
        void close(String value) => Navigator.pop(sheetContext, value);
        Widget section(String label) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(
              label,
              style: Theme.of(sheetContext).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
          );
        }

        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                section('서재'),
                ListTile(
                  leading: const Icon(Icons.sort_rounded),
                  title: Text('정렬 · ${_sortMode.label}'),
                  onTap: () => close('sort'),
                ),
                ListTile(
                  leading: const Icon(Icons.star_rounded),
                  title: Text(
                    favoriteCount > 0 ? '좋아하는 만화 ($favoriteCount)' : '좋아하는 만화',
                  ),
                  onTap: () => close('favorites'),
                ),
                ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(
                    completedCount > 0 ? '완료한 만화 ($completedCount)' : '완료한 만화',
                  ),
                  onTap: () => close('completed'),
                ),
                ListTile(
                  leading: const Icon(Icons.filter_alt_off_outlined),
                  title: const Text('필터 초기화'),
                  onTap: () => close('reset_filters'),
                ),
                section('가져오기'),
                ListTile(
                  leading: const Icon(Icons.explore_outlined),
                  title: const Text('만화 찾기'),
                  onTap: () => close('browse'),
                ),
                ListTile(
                  leading: const Icon(Icons.add_rounded),
                  title: const Text('링크로 추가'),
                  onTap: () => close('add'),
                ),
                ListTile(
                  leading: const Icon(Icons.sync_rounded),
                  title: const Text('전체 목록 새로고침'),
                  onTap: () => close('refresh'),
                ),
                if (totalPending > 0)
                  ListTile(
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: const Text('미보관 회차 일괄 저장'),
                    subtitle: Text('$totalPending화 · 시간이 걸릴 수 있음'),
                    onTap: () => close('archive_all'),
                  ),
                ListTile(
                  leading: Icon(
                    _wifiOnly ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                  ),
                  title: Text(
                    _wifiOnly ? 'Wi‑Fi에서만 받기 · 켜짐' : 'Wi‑Fi에서만 받기 · 꺼짐',
                  ),
                  subtitle: _totalStorageBytes != null
                      ? Text('저장 공간 ${formatBytes(_totalStorageBytes!)}')
                      : const Text('셀룰러 데이터 절약'),
                  onTap: () => close('wifi_only'),
                ),
                section('클라우드'),
                ListTile(
                  leading: const Icon(Icons.cloud_sync_rounded),
                  title: const Text('목록 동기화'),
                  subtitle: const Text('만화 파일이 아니라 목록·읽기 위치만'),
                  onTap: () => close('cloud_sync'),
                ),
                ListTile(
                  leading: const Icon(Icons.cloud_queue_rounded),
                  title: const Text('클라우드 만화 확인'),
                  subtitle: const Text('R2에 올라간 회차 표시'),
                  onTap: () => close('cloud_inventory'),
                ),
                ListTile(
                  leading: const Icon(Icons.cloud_upload_outlined),
                  title: const Text('클라우드에 만화 올리기'),
                  subtitle: const Text('저장된 회차를 Cloudflare에 백업'),
                  onTap: () => close('cloud_upload'),
                ),
                ListTile(
                  leading: const Icon(Icons.save_outlined),
                  title: const Text('백업 생성'),
                  subtitle: Text(_backupMenuSubtitle),
                  onTap: () => close('backup_create'),
                ),
                ListTile(
                  leading: const Icon(Icons.settings_backup_restore_rounded),
                  title: const Text('백업 복원'),
                  onTap: () => close('backup_restore'),
                ),
                section('관리'),
                ListTile(
                  leading: const Icon(Icons.language_outlined),
                  title: const Text('사이트 주소 일괄 변경'),
                  onTap: () => close('migrate'),
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('진단 정보'),
                  onTap: () => close('diagnostics'),
                ),
                ListTile(
                  leading: const Icon(Icons.restore_rounded),
                  title: const Text('로컬 데이터로 복구'),
                  onTap: () => close('recover_local'),
                ),
                const Divider(height: 20),
                ListTile(
                  leading: Icon(
                    Icons.logout_rounded,
                    color: Theme.of(sheetContext).colorScheme.error,
                  ),
                  title: Text(
                    '로그아웃',
                    style: TextStyle(
                      color: Theme.of(sheetContext).colorScheme.error,
                    ),
                  ),
                  onTap: () => close('cloud_sign_out'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null || !mounted) return;
    await _onLibraryMenuSelected(selected);
  }

  Future<void> _onLibraryMenuSelected(String value) async {
    switch (value) {
      case 'sort':
        await _pickSortMode();
        break;
      case 'refresh':
        await _requestRefresh();
        break;
      case 'completed':
        await _openCompletedLibrary();
        break;
      case 'favorites':
        setState(() => _showFavoritesOnly = true);
        break;
      case 'wifi_only':
        await _toggleWifiOnly();
        break;
      case 'reset_filters':
        _resetFilters();
        break;
      case 'diagnostics':
        await _showDiagnostics();
        break;
      case 'recover_local':
        await _recoverLibraryFromLocalData();
        break;
      case 'backup_create':
        await _createBackup();
        break;
      case 'backup_restore':
        await _restoreBackup();
        break;
      case 'cloud_sync':
        await _syncCloudNow();
        break;
      case 'cloud_inventory':
        await _refreshCloudInventory();
        break;
      case 'cloud_upload':
        await _uploadLocalComicsToCloud();
        break;
      case 'cloud_sign_out':
        await _signOutCloud();
        break;
      case 'migrate':
        await _showMigrateSiteDialog();
        break;
      case 'browse':
        await _openBrowseCatalog();
        break;
      case 'archive_all':
        await _downloadBatch(allSeries: true);
        break;
      case 'add':
        await _showAddDialog();
        break;
      case 'pending':
        _selectSeriesWithPending();
        break;
    }
  }

  Future<void> _showAddDialog() async {
    final input = await showAddSeriesDialog(context);
    if (input == null || !mounted) return;
    await _addSeries(input);
  }

  Future<void> _openBrowseCatalog() async {
    final existingIds = _storage.getAllSeries().map((s) => s.id).toSet();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BrowseCatalogScreen(
          existingSeriesIds: existingIds,
          onAddSeries: (url, title) async {
            final series = await _fetcher.registerSeries(
              url,
              customTitle: title.isNotEmpty ? title : null,
              bypassRunner: _bypass,
            );
            existingIds.add(series.id);
            if (!mounted) return;
            setState(() {
              _rebuildStatsAndSort(_storage.getActiveSeries());
              _syncMessage = '"${series.title}" 서재에 추가됨';
            });
          },
        ),
      ),
    );
    _reload();
  }

  Future<void> _addSeries(AddSeriesInput input) async {
    final needsTitleFetch = input.trimmedTitle == null;

    if (needsTitleFetch) {
      setState(() {
        _loading = true;
        _fetchStatus = null;
        _syncMessage = null;
      });
    }

    try {
      final series = await _fetcher.registerSeries(
        input.url,
        customTitle: input.trimmedTitle,
        onProgress: needsTitleFetch
            ? (status) {
                if (mounted) setState(() => _fetchStatus = status);
              }
            : null,
        bypassRunner: _bypass,
      );
      if (!mounted) return;

      setState(() {
        _loading = false;
        _fetchStatus = null;
        _syncMessage = '"${series.title}" 추가됨 · 회차 목록 불러오는 중...';
        _rebuildStatsAndSort(_storage.getActiveSeries());
      });

      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => SeriesScreen(series: series)),
      );
      _reload();
    } on FetchCancelledException {
      _handleCancelled();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _fetchStatus = null;
          _syncMessage = '추가 실패: $e';
        });
      }
    }
  }

  String _formatSyncResult(SyncResult result) {
    if (result.errors.isNotEmpty && !result.hasNew) {
      return result.errors.join('\n');
    }
    final buffer = StringBuffer();
    if (result.hasNew) {
      buffer.write('전체 새 회차 ${result.newChapterCount}개 발견');
    } else {
      buffer.write('새 회차 없음');
    }
    buffer.write(' · 각 만화에서 선택 다운로드하세요');
    if (result.errors.isNotEmpty) {
      buffer.write('\n${result.errors.length}개 오류');
    }
    return buffer.toString();
  }

  Future<void> _deleteSeries(Series series) async {
    final chapters = _storage.getChapters(series.id);
    final downloaded = chapters.where((c) => c.isDownloaded).length;

    final confirmed = await confirmDelete(
      context,
      title: '만화 삭제',
      message:
          '"${series.title}"을(를) 삭제할까요?\n'
          '회차 ${chapters.length}개 · 저장 $downloaded개가 모두 삭제됩니다.',
    );
    if (!confirmed || !mounted) return;

    await _storage.deleteSeriesCompletely(series.id);
    if (mounted) {
      setState(() {
        _rebuildStatsAndSort(_storage.getActiveSeries());
        _syncMessage = '"${series.title}" 삭제됨';
      });
    }
  }

  Future<void> _openSeries(Series series) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SeriesScreen(series: series)),
    );
    _pendingReconcileSeriesId = series.id;
    await _reload(preferReconcileSeriesId: series.id);
  }

  /// 전역 최근 읽기 또는 해당 시리즈의 최근 회차를 엽니다.
  /// 완료된 화는 다음 화부터 이어 갑니다.
  Future<void> _continueReading({Series? series}) async {
    Series? targetSeries = series;
    Chapter? chapter;
    var startAtTop = false;

    if (targetSeries != null) {
      final cont = _storage.getContinueTarget(targetSeries.id);
      if (cont != null) {
        chapter = cont.chapter;
        startAtTop = cont.startAtTop;
      }
    } else {
      final lastSeriesId = _storage.lastSeriesId;
      if (lastSeriesId != null) {
        targetSeries = _storage.getSeries(lastSeriesId);
        if (targetSeries != null && !targetSeries.isCompleted) {
          final cont = _storage.getContinueTarget(lastSeriesId);
          if (cont != null) {
            chapter = cont.chapter;
            startAtTop = cont.startAtTop;
          }
        }
      }
      if (targetSeries == null || chapter == null) {
        for (final s in _seriesList) {
          final cont = _storage.getContinueTarget(s.id);
          if (cont != null) {
            targetSeries = s;
            chapter = cont.chapter;
            startAtTop = cont.startAtTop;
            break;
          }
        }
      }
    }

    if (targetSeries == null || chapter == null || !mounted) {
      if (mounted) {
        setState(() => _syncMessage = '이어서 읽을 회차가 없습니다.');
      }
      return;
    }

    final seriesId = targetSeries.id;
    var current = _storage.reconcileChapterDownloads(seriesId, chapter);
    if (current.localPaths != chapter.localPaths) {
      await _storage.upsertChapter(seriesId, current);
    }

    if (!mounted) return;
    if (current.canOpen) {
      if (!current.canRead) {
        if (!await _ensureCanDownload()) return;
        setState(() {
          _loading = true;
          _fetchStatus = null;
        });
        try {
          final prepared = await ChapterReader.prepare(
            seriesId: seriesId,
            chapter: current,
            fetcher: _fetcher,
            onProgress: (status) {
              if (mounted) setState(() => _fetchStatus = status);
            },
            bypassRunner: _bypass,
          );
          if (!mounted) return;
          setState(() {
            _loading = false;
            _fetchStatus = null;
          });
          if (prepared == null) return;
          current = prepared;
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _fetchStatus = null;
            _syncMessage = '클라우드에서 열기 실패: $e';
          });
          return;
        }
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReaderScreen(
            seriesId: seriesId,
            chapter: current,
            startAtTop: startAtTop,
          ),
        ),
      );
    } else if (current.url.isNotEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WebViewReaderScreen(
            seriesId: seriesId,
            seriesTitle: targetSeries!.title,
            chapter: current,
            startAtTop: startAtTop,
          ),
        ),
      );
    } else {
      await _openSeries(targetSeries);
      return;
    }
    _pendingReconcileSeriesId = seriesId;
    await _reload(preferReconcileSeriesId: seriesId);
  }

  ({Series series, Chapter chapter, bool startAtTop, bool nextAfterCompleted})?
  _globalContinueTarget() {
    final lastSeriesId = _storage.lastSeriesId;
    if (lastSeriesId != null) {
      final series = _storage.getSeries(lastSeriesId);
      if (series != null && !series.isCompleted) {
        final cont = _storage.getContinueTarget(lastSeriesId);
        if (cont != null) {
          return (
            series: series,
            chapter: cont.chapter,
            startAtTop: cont.startAtTop,
            nextAfterCompleted: cont.isNextAfterCompleted,
          );
        }
      }
    }
    for (final s in _seriesList) {
      final cont = _storage.getContinueTarget(s.id);
      if (cont != null) {
        return (
          series: s,
          chapter: cont.chapter,
          startAtTop: cont.startAtTop,
          nextAfterCompleted: cont.isNextAfterCompleted,
        );
      }
    }
    return null;
  }

  void _toggleSeriesSelection(Series series) {
    setState(() {
      if (_selectedSeriesIds.contains(series.id)) {
        _selectedSeriesIds.remove(series.id);
      } else {
        _selectedSeriesIds.add(series.id);
      }
    });
  }

  void _startSelection(Series series) {
    setState(() => _selectedSeriesIds.add(series.id));
  }

  void _selectSeriesWithPending() {
    setState(() {
      _selectedSeriesIds
        ..clear()
        ..addAll(_seriesWithPending.map((s) => s.id));
    });
  }

  void _selectAllSeries() {
    setState(() {
      _selectedSeriesIds
        ..clear()
        ..addAll(_visibleSeries.map((s) => s.id));
    });
  }

  void _clearSelection() {
    setState(_selectedSeriesIds.clear);
  }

  Future<bool> _confirmBatchDownload({
    required int seriesCount,
    required int chapterCount,
    required bool allSeries,
  }) async {
    if (chapterCount <= 0) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(allSeries ? '미보관 회차 일괄 저장' : '선택한 만화 보관'),
        content: Text(
          allSeries
              ? '아직 클라우드에 없는 $chapterCount화를 $seriesCount개 만화에서 가져옵니다.\n'
                    '읽는 중에도 자동 보관되므로 대량은 필요할 때만 쓰세요.'
              : '선택한 $seriesCount개 만화에서 미보관 $chapterCount화를 가져옵니다.\n'
                    '이미 클라우드에 있는 회차는 건너뜁니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('시작'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _downloadBatch({bool allSeries = false}) async {
    if (!await _ensureCanDownload()) return;
    final targets = allSeries
        ? _seriesWithPending
        : _seriesList.where((s) => _selectedSeriesIds.contains(s.id)).toList();

    final chapterCount = allSeries
        ? _totalPendingChapters
        : _selectedPendingChapters;

    if (targets.isEmpty || chapterCount == 0) {
      setState(() {
        _syncMessage = allSeries ? '보관할 회차가 없습니다.' : '선택한 만화에 보관할 회차가 없습니다.';
      });
      return;
    }

    if (!await _confirmBatchDownload(
      seriesCount: targets.length,
      chapterCount: chapterCount,
      allSeries: allSeries,
    )) {
      return;
    }
    await _enqueueSeriesJobs(
      targets,
      label: allSeries ? '전체 클라우드 저장' : '선택한 만화만 저장',
    );
    if (!mounted) return;
    setState(() {
      if (allSeries) _selectedSeriesIds.clear();
    });
  }

  Future<void> _saveOneSeries(Series series) async {
    if (!await _ensureCanDownload()) return;
    final pending = _pendingChapterCountForSeries(series.id);
    if (pending <= 0) {
      setState(() => _syncMessage = '${series.title} · 이미 클라우드에 있습니다.');
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('이 만화 보관'),
        content: Text(
          '${series.title}\n미보관 $pending화를 클라우드에 남깁니다.\n'
          '읽는 중에도 자동 보관되므로 필요할 때만 쓰세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('시작'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _enqueueSeriesJobs([series], label: series.title);
  }

  @override
  Widget build(BuildContext context) {
    final pendingJobs = _queuePendingCount;
    if (DownloadActivityService.instance.pendingJobs.value != pendingJobs) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          DownloadActivityService.instance.setPendingJobs(_queuePendingCount);
        }
      });
    }
    final visibleSeries = _visibleSeries;
    final selectedPending = _selectedPendingChapters;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _hasSelection
              ? '${_selectedSeriesIds.length}개 선택'
              : _showFavoritesOnly
              ? '좋아하는 만화'
              : 'COAD',
        ),
        actions: [
          if (!_hasSelection) const NetworkStatusChip(),
          if (!_hasSelection) const ThemeToggleButton(),
          IconButton(
            onPressed: _showDownloadQueueSheet,
            tooltip: _hasQueueActivity ? '다운로드 큐 확인' : '다운로드 큐',
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.downloading_rounded),
                if (_queuePendingCount > 0)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.error,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$_queuePendingCount',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onError,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (!_loading && !_hasSelection)
            IconButton(
              onPressed: _showLibraryMenu,
              tooltip: '더보기',
              icon: const Icon(Icons.more_vert_rounded),
            ),
          if (_hasSelection && !_loading)
            IconButton(
              onPressed: _selectSeriesWithPending,
              icon: const Icon(Icons.filter_alt_outlined),
              tooltip: '미보관 만화 선택',
            ),
          const LockButton(),
        ],
        bottom: _hasQueueActivity
            ? PreferredSize(
                preferredSize: const Size.fromHeight(36),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: InkWell(
                    onTap: _showDownloadQueueSheet,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _queueSummaryText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '열기',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            : null,
      ),
      floatingActionButton: _libraryFab(),
      // 큐 다운로드는 상단 배너/시트로, 목록 새로고침 등만 하단 진행 표시.
      bottomNavigationBar: _loading && !_queueRunning && _fetchStatus != null
          ? FetchProgressDock(status: _fetchStatus!, onCancel: _cancelFetch)
          : _hasSelection && !_queueRunning
          ? LibrarySelectionBar(
              selectedSeriesCount: _selectedSeriesIds.length,
              pendingChapterCount: selectedPending,
              onDownload: () => _downloadBatch(),
              onClear: _clearSelection,
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _requestRefresh,
        child: CustomScrollView(
          controller: _scrollController,
          scrollCacheExtent: const ScrollCacheExtent.pixels(720),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: OfflineBanner(),
              ),
            ),
            if (_syncMessage != null)
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
            if (_syncMessage != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                sliver: SliverToBoxAdapter(
                  child: StatusBanner(
                    message: _syncMessage!,
                    onDismiss: () => setState(() => _syncMessage = null),
                  ),
                ),
              ),
            if (_seriesList.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...() {
                        final cont = _globalContinueTarget();
                        final recent = _recentSeries(
                          excludeId: cont?.series.id,
                        );
                        final canOpen = !_loading && !_hasSelection;
                        return <Widget>[
                          if (cont != null) ...[
                            _ContinueReadingBanner(
                              series: cont.series,
                              chapter: cont.chapter,
                              nextAfterCompleted: cont.nextAfterCompleted,
                              enabled: canOpen,
                              onContinue: () => unawaited(_continueReading()),
                              onOpenSeries: () =>
                                  unawaited(_openSeries(cont.series)),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (recent.isNotEmpty) ...[
                            _RecentReadRail(
                              series: recent,
                              chapterNumber: (series) =>
                                  _statsFor(series.id).lastReadChapterNumber,
                              enabled: canOpen,
                              onOpen: (series) =>
                                  unawaited(_continueReading(series: series)),
                              onOpenSeries: (series) =>
                                  unawaited(_openSeries(series)),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ];
                      }(),
                      _LibrarySummaryBar(
                        seriesCount: visibleSeries.length,
                        totalSeries: _seriesList.length,
                        favoritesOnly: _showFavoritesOnly,
                        storageLabel: _totalStorageBytes != null
                            ? formatBytes(_totalStorageBytes!)
                            : null,
                      ),
                      const SizedBox(height: 12),
                      AppSearchField(
                        controller: _searchController,
                        hintText: '제목으로 검색',
                        enabled: !_loading,
                        onChanged: (value) =>
                            setState(() => _searchQuery = value),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ActionChip(
                                avatar: const Icon(
                                  Icons.sort_rounded,
                                  size: 18,
                                ),
                                label: Text(_sortMode.label),
                                onPressed: _loading ? null : _pickSortMode,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                avatar: Icon(
                                  _showFavoritesOnly
                                      ? Icons.star_rounded
                                      : Icons.star_outline_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  _favoriteSeriesCount > 0
                                      ? '즐겨찾기 $_favoriteSeriesCount'
                                      : '즐겨찾기',
                                ),
                                selected: _showFavoritesOnly,
                                onSelected: _loading
                                    ? null
                                    : (selected) {
                                        setState(
                                          () => _showFavoritesOnly = selected,
                                        );
                                      },
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(
                                  _emptyChapterSeriesCount > 0
                                      ? '회차 없음 $_emptyChapterSeriesCount'
                                      : '회차 없음',
                                ),
                                selected: _showEmptyChaptersOnly,
                                onSelected: _loading
                                    ? null
                                    : (selected) {
                                        setState(
                                          () =>
                                              _showEmptyChaptersOnly = selected,
                                        );
                                      },
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ActionChip(
                                avatar: const Icon(
                                  Icons.select_all_rounded,
                                  size: 18,
                                ),
                                label: const Text('전체 선택'),
                                onPressed: _loading ? null : _selectAllSeries,
                              ),
                            ),
                            if (_hasSelection ||
                                _showFavoritesOnly ||
                                _showEmptyChaptersOnly ||
                                _searchQuery.trim().isNotEmpty)
                              ActionChip(
                                avatar: const Icon(
                                  Icons.filter_alt_off_outlined,
                                  size: 18,
                                ),
                                label: const Text('필터 해제'),
                                onPressed: _resetFilters,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                  ),
                ),
              ),
            if (_seriesList.isEmpty && !_loading)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyLibrary(
                  onAdd: _showAddDialog,
                  onBrowse: _openBrowseCatalog,
                ),
              )
            else if (visibleSeries.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    children: [
                      SearchEmptyState(
                        query: _searchQuery,
                        label: _searchQuery.trim().isNotEmpty
                            ? '검색 결과가 없습니다'
                            : _showFavoritesOnly
                            ? '즐겨찾기한 만화가 없습니다'
                            : '회차 목록이 없는 만화가 없습니다',
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _resetFilters,
                        icon: const Icon(Icons.filter_alt_off_outlined),
                        label: const Text('필터 초기화'),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  _hasSelection ? 24 : 104,
                ),
                sliver: _buildSeriesGridSliver(visibleSeries),
              ),
          ],
        ),
      ),
    );
  }

  Widget? _libraryFab() {
    final showBrowse = !_hasSelection && !(_loading && !_queueRunning);
    if (!_showScrollTop && !showBrowse) return null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_showScrollTop)
          FloatingActionButton.small(
            heroTag: 'library-scroll-top',
            tooltip: '맨 위로',
            onPressed: _scrollLibraryToTop,
            child: const Icon(Icons.keyboard_arrow_up_rounded),
          ),
        if (_showScrollTop && showBrowse) const SizedBox(height: 12),
        if (showBrowse)
          FloatingActionButton.extended(
            heroTag: 'library-browse',
            onPressed: _openBrowseCatalog,
            icon: const Icon(Icons.explore_outlined),
            label: const Text('만화 찾기'),
          ),
      ],
    );
  }

  Widget _buildSeriesGridSliver(List<Series> visible) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final columns = width >= 1100
            ? 5
            : width >= 840
            ? 4
            : width >= 560
            ? 3
            : 2;
        const spacing = 12.0;
        final cardWidth = (width - spacing * (columns - 1)) / columns;
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: 16,
            mainAxisExtent: cardWidth * 1.42 + 68,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final series = visible[index];
              final stats = _statsFor(series.id);
              final isSelected = _selectedSeriesIds.contains(series.id);
              return _LibraryPosterCard(
                series: series,
                searchQuery: _searchQuery,
                totalChapters: stats.chapterCount,
                recentReadChapter: stats.lastReadChapterNumber,
                isSelected: isSelected,
                showSelection: _hasSelection,
                onTap: () {
                  if (_hasSelection) {
                    if (_loading) return;
                    _toggleSeriesSelection(series);
                  } else {
                    _openSeries(series);
                  }
                },
                onLongPress: _loading
                    ? null
                    : () {
                        if (_hasSelection) {
                          _toggleSeriesSelection(series);
                        } else {
                          _startSelection(series);
                        }
                      },
                onContinue:
                    !_loading &&
                        !_hasSelection &&
                        stats.lastReadChapterNumber != null
                    ? () => unawaited(_continueReading(series: series))
                    : null,
                onSaveCloud: stats.pendingCount > 0 && !_loading
                    ? () => unawaited(_saveOneSeries(series))
                    : null,
                onDelete: () => _deleteSeries(series),
                onToggleFavorite: () => _toggleFavorite(series),
                onRepairLink: Series.isLikelyTruncatedSlug(series.url)
                    ? () => _repairSeriesLink(series)
                    : null,
              );
            },
            childCount: visible.length,
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: true,
          ),
        );
      },
    );
  }
}

class _LibrarySummaryBar extends StatelessWidget {
  const _LibrarySummaryBar({
    required this.seriesCount,
    required this.totalSeries,
    required this.favoritesOnly,
    this.storageLabel,
  });

  final int seriesCount;
  final int totalSeries;
  final bool favoritesOnly;
  final String? storageLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = favoritesOnly
        ? '즐겨찾기 $seriesCount'
        : seriesCount == totalSeries
        ? '$totalSeries작품'
        : '$seriesCount / $totalSeries';
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
      child: Row(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          if (storageLabel != null) ...[
            const SizedBox(width: 8),
            Text(
              storageLabel!,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onAdd, required this.onBrowse});

  final VoidCallback onAdd;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Column(
        children: [
          Icon(Icons.auto_stories_outlined, size: 64, color: scheme.outline),
          const SizedBox(height: 16),
          Text(
            '아직 만화가 없어요',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            '만화 찾기 또는 링크로 추가해 보세요',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('링크로 추가'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onBrowse,
            icon: const Icon(Icons.explore_outlined),
            label: const Text('만화 찾기'),
          ),
        ],
      ),
    );
  }
}

class _ContinueReadingBanner extends StatelessWidget {
  const _ContinueReadingBanner({
    required this.series,
    required this.chapter,
    required this.enabled,
    required this.onContinue,
    required this.onOpenSeries,
    this.nextAfterCompleted = false,
  });

  final Series series;
  final Chapter chapter;
  final bool enabled;
  final bool nextAfterCompleted;
  final VoidCallback onContinue;
  final VoidCallback onOpenSeries;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = nextAfterCompleted ? '다음 화 이어 읽기' : '이어서 읽기';
    return Material(
      color: scheme.primary,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onContinue : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
            children: [
              SeriesCover(
                series: series,
                width: 48,
                height: 64,
                borderRadius: BorderRadius.circular(10),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onPrimary.withValues(alpha: 0.82),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      series.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      nextAfterCompleted
                          ? '${chapter.number}화부터'
                          : chapter.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onPrimary.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: enabled ? onOpenSeries : null,
                tooltip: '목록 보기',
                color: scheme.onPrimary,
                icon: const Icon(Icons.list_rounded),
              ),
              Icon(
                Icons.play_circle_fill_rounded,
                color: scheme.onPrimary,
                size: 34,
              ),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryPosterCard extends StatelessWidget {
  const _LibraryPosterCard({
    required this.series,
    required this.searchQuery,
    required this.totalChapters,
    this.recentReadChapter,
    required this.isSelected,
    required this.showSelection,
    required this.onTap,
    required this.onLongPress,
    this.onContinue,
    this.onSaveCloud,
    required this.onDelete,
    required this.onToggleFavorite,
    this.onRepairLink,
  });

  final Series series;
  final String searchQuery;
  final int totalChapters;
  final int? recentReadChapter;
  final bool isSelected;
  final bool showSelection;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onContinue;
  final VoidCallback? onSaveCloud;
  final VoidCallback onDelete;
  final VoidCallback onToggleFavorite;
  final VoidCallback? onRepairLink;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showRepairBadge = Series.isLikelyTruncatedSlug(series.url);
    final recentBottom = showRepairBadge ? 32.0 : 8.0;

    final isLight = Theme.of(context).brightness == Brightness.light;

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
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(
                      alpha: isLight ? 0.8 : 0.55,
                    ),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(17),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      SeriesCover(
                        series: series,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.02),
                                Colors.black.withValues(alpha: 0.45),
                              ],
                              stops: const [0.55, 1],
                            ),
                          ),
                        ),
                      ),
                      if (isSelected)
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: scheme.primary,
                                width: 3,
                              ),
                              color: scheme.primary.withValues(alpha: 0.18),
                            ),
                          ),
                        ),
                      if (!showSelection && !isSelected)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Material(
                            color: Colors.black.withValues(alpha: 0.45),
                            shape: const CircleBorder(),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: onToggleFavorite,
                              customBorder: const CircleBorder(),
                              child: SizedBox(
                                width: 36,
                                height: 36,
                                child: Icon(
                                  series.isFavorite
                                      ? Icons.star_rounded
                                      : Icons.star_outline_rounded,
                                  color: series.isFavorite
                                      ? Colors.amber
                                      : Colors.white70,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (showSelection || isSelected)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Material(
                            color: isSelected
                                ? scheme.primary
                                : Colors.black.withValues(alpha: 0.45),
                            shape: const CircleBorder(),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                isSelected
                                    ? Icons.check_rounded
                                    : Icons.circle_outlined,
                                color: isSelected
                                    ? scheme.onPrimary
                                    : Colors.white70,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Material(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: PopupMenuButton<String>(
                            icon: const Icon(
                              Icons.more_horiz,
                              color: Colors.white,
                              size: 20,
                            ),
                            padding: EdgeInsets.zero,
                            onSelected: (v) {
                              if (v == 'continue') onContinue?.call();
                              if (v == 'save_cloud') onSaveCloud?.call();
                              if (v == 'delete') onDelete();
                            },
                            itemBuilder: (context) => [
                              if (onContinue != null)
                                const PopupMenuItem(
                                  value: 'continue',
                                  child: Row(
                                    children: [
                                      Icon(Icons.play_arrow_rounded, size: 20),
                                      SizedBox(width: 8),
                                      Text('이어서 읽기'),
                                    ],
                                  ),
                                ),
                              if (onSaveCloud != null)
                                const PopupMenuItem(
                                  value: 'save_cloud',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.inventory_2_outlined,
                                        size: 20,
                                      ),
                                      SizedBox(width: 8),
                                      Text('이 만화 보관'),
                                    ],
                                  ),
                                ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.delete_outline,
                                      color: scheme.error,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '삭제',
                                      style: TextStyle(color: scheme.error),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (recentReadChapter != null)
                        Positioned(
                          left: 8,
                          right: 40,
                          bottom: recentBottom,
                          child: Material(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              onTap: onContinue,
                              borderRadius: BorderRadius.circular(10),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 5,
                                ),
                                child: Text(
                                  onContinue != null
                                      ? '이어보기 · $recentReadChapter화'
                                      : '최근 $recentReadChapter화',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (showRepairBadge)
                        Positioned(
                          left: 6,
                          bottom: 6,
                          child: Material(
                            color: scheme.error.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              onTap: onRepairLink,
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: Text(
                                  '링크 확인',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: scheme.onError,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            HighlightedText(
              text: series.title,
              highlight: searchQuery,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.25,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              totalChapters > 0
                  ? (recentReadChapter != null
                        ? '$totalChapters화 · $recentReadChapter화까지'
                        : '$totalChapters화')
                  : '탭해서 회차 불러오기',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentReadRail extends StatelessWidget {
  const _RecentReadRail({
    required this.series,
    required this.chapterNumber,
    required this.enabled,
    required this.onOpen,
    required this.onOpenSeries,
  });

  final List<Series> series;
  final int? Function(Series series) chapterNumber;
  final bool enabled;
  final ValueChanged<Series> onOpen;
  final ValueChanged<Series> onOpenSeries;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '최근 본 작품',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: series.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final item = series[index];
              final number = chapterNumber(item);
              return SizedBox(
                width: 74,
                child: InkWell(
                  onTap: enabled ? () => onOpen(item) : null,
                  onLongPress: enabled ? () => onOpenSeries(item) : null,
                  borderRadius: BorderRadius.circular(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            SeriesCover(
                              series: item,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            if (number != null)
                              Positioned(
                                left: 4,
                                right: 4,
                                bottom: 4,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.62),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    child: Text(
                                      '$number화',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SeriesDownloadJob {
  const _SeriesDownloadJob(
    this.series, {
    this.progress,
    this.statusMessage,
    this.isRunning = false,
    this.isDone = false,
    this.isCancelled = false,
    this.downloadedCount = 0,
  });

  final Series series;
  final double? progress;
  final String? statusMessage;
  final bool isRunning;
  final bool isDone;
  final bool isCancelled;
  final int downloadedCount;

  _SeriesDownloadJob copyWith({
    double? progress,
    String? statusMessage,
    bool? isRunning,
    bool? isDone,
    bool? isCancelled,
    int? downloadedCount,
  }) {
    return _SeriesDownloadJob(
      series,
      progress: progress ?? this.progress,
      statusMessage: statusMessage ?? this.statusMessage,
      isRunning: isRunning ?? this.isRunning,
      isDone: isDone ?? this.isDone,
      isCancelled: isCancelled ?? this.isCancelled,
      downloadedCount: downloadedCount ?? this.downloadedCount,
    );
  }
}
