import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../models/chapter.dart';
import '../models/fetch_controller.dart';
import '../models/fetch_status.dart';
import '../models/reading_progress.dart';
import '../models/series.dart';
import '../models/webview_bypass_runner.dart';
import '../services/chapter_reader.dart';
import '../services/cloud_backup_queue.dart';
import '../services/download_activity_service.dart';
import '../services/network_policy.dart';
import '../services/storage_service.dart';
import '../services/webtoon_fetcher.dart';
import '../utils/webview_bypass.dart';
import '../utils/text_search.dart';
import '../utils/storage_format.dart';
import '../widgets/add_series_dialog.dart';
import '../widgets/app_search_field.dart';
import '../widgets/chapter_tile.dart';
import '../widgets/confirm_delete_dialog.dart';
import '../widgets/fetch_progress_card.dart';
import '../widgets/lock_button.dart';
import '../widgets/series_cover.dart';
import '../widgets/series_selection_bar.dart';
import '../navigation/app_route_observer.dart';
import '../widgets/status_banner.dart';
import '../widgets/theme_toggle_button.dart';
import '../widgets/network_status_chip.dart';
import '../services/connectivity_service.dart';
import 'reader_screen.dart';
import 'webview_reader_screen.dart';

enum _ChapterListFilter { all, unread, archived, fresh }

class SeriesScreen extends StatefulWidget {
  const SeriesScreen({super.key, required this.series});

  final Series series;

  @override
  State<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends State<SeriesScreen> with RouteAware {
  final _storage = StorageService.instance;
  final _fetcher = WebtoonFetcher();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _chapterHeaderKey = GlobalKey();
  late Series _series;

  WebViewBypassRunner get _bypass => createWebViewBypassRunner(context);
  List<Chapter> _chapters = [];

  /// chapterId → scrollOffset. 빌드마다 Hive progress를 다시 읽지 않습니다.
  Map<String, double> _progressOffsets = {};
  final Set<String> _selectedIds = {};
  Set<String> _syncNewChapterIds = {};
  bool _loading = false;
  bool _downloadStatusSheetOpen = false;
  FetchStatus? _fetchStatus;
  String? _syncMessage;
  String _searchQuery = '';
  String _sortMode = StorageService.instance.chapterListSortMode;
  _ChapterListFilter _chapterFilter = _ChapterListFilter.all;
  int? _storageBytes;

  /// 헤더를 아직 측정하지 못했을 때의 추정값 (화 번호 점프용)
  static const _chapterListHeaderExtent = 520.0;
  static const _chapterTileExtent = 88.0;

  double get _chapterHeaderExtent {
    final box = _chapterHeaderKey.currentContext?.findRenderObject();
    if (box is RenderBox && box.hasSize) return box.size.height + 8;
    return _chapterListHeaderExtent;
  }

  bool _chapterMatchesFilter(Chapter chapter) {
    return switch (_chapterFilter) {
      _ChapterListFilter.all => true,
      _ChapterListFilter.unread => !_hasReadingProgress(chapter),
      _ChapterListFilter.archived => chapter.isArchived,
      _ChapterListFilter.fresh => _syncNewChapterIds.contains(chapter.id),
    };
  }

  List<Chapter> get _visibleChapters {
    final matched = TextSearch.filterChapters(_chapters, _searchQuery);
    final filtered = _chapterFilter == _ChapterListFilter.all
        ? matched
        : matched.where(_chapterMatchesFilter).toList();
    if (_sortMode == 'random') {
      final order = {
        for (final id in _storage.getChapterRandomOrder(_series.id)) id,
      };
      if (order.isEmpty) return filtered;
      final byId = {for (final c in filtered) c.id: c};
      final ordered = <Chapter>[];
      for (final id in _storage.getChapterRandomOrder(_series.id)) {
        final chapter = byId.remove(id);
        if (chapter != null) ordered.add(chapter);
      }
      ordered.addAll(
        byId.values.toList()..sort((a, b) => a.number.compareTo(b.number)),
      );
      return ordered;
    }
    if (_sortMode != 'oldest') return filtered;
    return filtered.toList()..sort((a, b) => a.number.compareTo(b.number));
  }

  Future<bool> _ensureCanDownload() async {
    final reason = await NetworkPolicy.instance.downloadBlockReason();
    if (reason == null) return true;
    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reason)));
    return false;
  }

  Future<void> _toggleChapterOrder() async {
    final next = _sortMode == 'oldest' ? 'newest' : 'oldest';
    if (_sortMode == 'random') {
      await _storage.clearChapterRandomOrder(_series.id);
    }
    await _storage.setChapterListSortMode(next);
    if (!mounted) return;
    setState(() => _sortMode = next);
  }

  Future<void> _shuffleChapterOrder() async {
    if (_chapters.isEmpty) return;
    await _storage.shuffleChapterOrder(_series.id, reshuffle: true);
    if (!mounted) return;
    setState(() => _sortMode = 'random');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('회차 순서를 섞었습니다. 이전/다음 화도 이 순서로 이동합니다.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _refreshStorageBytes() async {
    try {
      final bytes = await _storage.seriesStorageBytes(_series.id);
      if (mounted) setState(() => _storageBytes = bytes);
    } catch (_) {}
  }

  void _refreshProgressCache() {
    final map = <String, double>{};
    for (final chapter in _chapters) {
      final progress = _storage.getProgress(_series.id, chapter.id);
      if (progress != null && progress.scrollOffset > 0) {
        map[chapter.id] = progress.scrollOffset;
      }
    }
    _progressOffsets = map;
  }

  String get _downloadStatusSummary {
    final status = _fetchStatus;
    if (status == null) {
      return _loading ? '다운로드 준비 중...' : '다운로드 상태 없음';
    }
    final progress = status.overallProgress;
    if (progress != null) {
      return '${status.phaseLabel} · ${(progress * 100).round()}% · ${status.message}';
    }
    if (status.phaseLabel.isEmpty) return status.message;
    return '${status.phaseLabel} · ${status.message}';
  }

  /// 다운로드 작업을 시작하고, 상단 상태 시트/배너로 바로 이어 줍니다.
  void _beginDownloadWork() {
    setState(() {
      _loading = true;
      _fetchStatus = null;
      _syncMessage = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _loading) {
        unawaited(_showDownloadStatusSheet());
      }
    });
  }

  Future<void> _showDownloadStatusSheet() async {
    if (!mounted || _downloadStatusSheetOpen) return;
    _downloadStatusSheetOpen = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) {
          return ValueListenableBuilder<FetchStatus?>(
            valueListenable: DownloadActivityService.instance.status,
            builder: (context, globalStatus, _) {
              final status = globalStatus ?? _fetchStatus;
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '보관 상태',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (status == null)
                        Text(
                          _loading ? '준비 중...' : '진행 중인 작업이 없습니다.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        )
                      else
                        FetchProgressDock(
                          status: status,
                          onCancel: _loading
                              ? () async {
                                  await _cancelFetch();
                                  if (sheetContext.mounted) {
                                    Navigator.pop(sheetContext);
                                  }
                                }
                              : null,
                        ),
                      if (_loading && status != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          '시트를 닫아도 작업은 계속됩니다. 상단 상태 줄을 눌러 다시 열 수 있습니다.',
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
    } finally {
      _downloadStatusSheetOpen = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _series = widget.series;
    CloudBackupQueue.instance.addListener(_onCloudBackupChanged);
    _loadChapters().then((_) {
      if (mounted && _chapters.isEmpty && !_loading) {
        _refreshList();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    CloudBackupQueue.instance.removeListener(_onCloudBackupChanged);
    appRouteObserver.unsubscribe(this);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onCloudBackupChanged() {
    if (!mounted) return;
    setState(() => _chapters = _storage.getChapters(_series.id));
  }

  Future<void> _jumpToChapterNumber() async {
    if (_chapters.isEmpty) return;
    final controller = TextEditingController();
    final number = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('화 번호로 이동'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: '화 번호',
            hintText: '예: ${_chapters.first.number}',
          ),
          onSubmitted: (value) {
            final n = int.tryParse(value.trim());
            Navigator.pop(context, n);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(controller.text.trim());
              Navigator.pop(context, n);
            },
            child: const Text('이동'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (number == null || !mounted) return;

    final visible = _visibleChapters;
    var index = visible.indexWhere((c) => c.number == number);
    if (index < 0) {
      // 가장 가까운 화
      var best = 0;
      var bestDelta = 1 << 30;
      for (var i = 0; i < visible.length; i++) {
        final d = (visible[i].number - number).abs();
        if (d < bestDelta) {
          bestDelta = d;
          best = i;
        }
      }
      index = best;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$number화가 없어 ${visible[index].number}화로 이동합니다'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }

    if (!_scrollController.hasClients) return;
    final target = _chapterHeaderExtent + index * _chapterTileExtent;
    final max = _scrollController.position.maxScrollExtent;
    await _scrollController.animateTo(
      target.clamp(0.0, max),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didPopNext() {
    _reload();
  }

  Future<void> _loadChapters() async {
    // 목록을 먼저 그리고 reconcile은 백그라운드에서 맞춥니다.
    if (!mounted) return;
    setState(() {
      _chapters = _storage.getChapters(_series.id);
      _syncNewChapterIds = _storage.getSyncNewChapterIds(_series.id);
      _sortMode = _storage.chapterListSortMode;
      _refreshProgressCache();
    });
    unawaited(_refreshStorageBytes());
    unawaited(() async {
      await _storage.reconcileSeriesDownloads(_series.id);
      if (!mounted) return;
      setState(() {
        _chapters = _storage.getChapters(_series.id);
        _refreshProgressCache();
      });
      unawaited(_refreshStorageBytes());
      unawaited(_quietlyRefreshCloudInventory());
    }());
  }

  Future<void> _reload() async {
    if (!mounted) return;
    final latest = _storage.getSeries(_series.id) ?? _series;
    setState(() {
      _series = latest;
      _chapters = _storage.getChapters(_series.id);
      _syncNewChapterIds = _storage.getSyncNewChapterIds(_series.id);
      _sortMode = _storage.chapterListSortMode;
      _refreshProgressCache();
      _selectedIds.removeWhere((id) => !_chapters.any((c) => c.id == id));
    });
    unawaited(_refreshStorageBytes());
    unawaited(() async {
      await _storage.reconcileSeriesDownloads(_series.id);
      if (!mounted) return;
      setState(() {
        _chapters = _storage.getChapters(_series.id);
        _refreshProgressCache();
      });
      unawaited(_refreshStorageBytes());
    }());
  }

  Future<void> _quietlyRefreshCloudInventory() async {
    if (!ConnectivityService.instance.isOnline) return;
    try {
      final updated = await _fetcher.refreshCloudInventoryQuiet(
        seriesList: [_series],
      );
      if (!mounted || updated <= 0) return;
      setState(() {
        _chapters = _storage.getChapters(_series.id);
      });
    } catch (e) {
      debugPrint('series cloud inventory skipped: $e');
    }
  }

  List<Chapter> get _undownloadedChapters =>
      _chapters.where((c) => c.needsFirstSave).toList();

  int get _undownloadedCount => _undownloadedChapters.length;

  Future<bool> _confirmBulkDownload(int count) async {
    if (count <= 0) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('이 작품 통째로 보관'),
        content: Text(
          '미보관 $count화를 사이트에서 가져와 클라우드에 남깁니다.\n'
          '읽는 중에도 자동으로 보관되므로, 대량 보관은 필요할 때만 쓰세요.',
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

  Future<void> _downloadAllUndownloaded() async {
    if (!await _ensureCanDownload()) return;
    final targets = _undownloadedChapters;
    if (targets.isEmpty) {
      setState(() => _syncMessage = '보관할 회차가 없습니다.');
      return;
    }

    if (!await _confirmBulkDownload(targets.length)) return;

    setState(() => _selectedIds.clear());
    _beginDownloadWork();

    try {
      final result = await _fetcher.downloadAllUndownloadedChapters(
        _series,
        _chapters,
        onProgress: (status) {
          if (mounted) setState(() => _fetchStatus = status);
        },
        bypassRunner: _bypass,
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _fetchStatus = null;
          _chapters = _storage.getChapters(_series.id);
          final baseMessage =
              '클라우드 저장 · ${result.downloadedCount}/${targets.length}화';
          if (result.errors.isEmpty) {
            _syncMessage = baseMessage;
          } else {
            _syncMessage =
                '$baseMessage\n일부 실패 ${result.errors.length}건 · 이어 받기로 재시도 가능\n'
                '${result.errors.first}';
          }
        });
      }
    } on FetchCancelledException {
      _handleCancelled();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _fetchStatus = null;
          _syncMessage = '클라우드 저장 실패: $e';
        });
      }
    }
  }

  Future<void> _refreshSeriesCloudInventory() async {
    if (!await _ensureCanDownload()) return;
    _beginDownloadWork();
    try {
      final updated = await _fetcher.refreshCloudInventory(
        seriesList: [_series],
        onProgress: (status) {
          if (mounted) setState(() => _fetchStatus = status);
        },
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _fetchStatus = null;
        _chapters = _storage.getChapters(_series.id);
        _syncMessage = updated > 0
            ? '클라우드 만화 $updated화를 표시했습니다. 누르면 클라우드에서 열립니다.'
            : '이 만화의 클라우드 회차가 없거나 이미 표시되어 있습니다.';
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

  Future<void> _uploadSeriesToCloud() async {
    if (!await _ensureCanDownload()) return;
    final pending = _chapters
        .where(
          (c) =>
              c.isDownloaded &&
              (c.cloudPageCount == null ||
                  c.cloudPageCount! < c.localPaths.length),
        )
        .length;
    if (pending == 0) {
      setState(() => _syncMessage = '클라우드에 올릴 저장된 회차가 없습니다.');
      return;
    }
    _beginDownloadWork();
    try {
      final result = await _fetcher.uploadLocalChaptersToCloud(
        seriesList: [_series],
        onProgress: (status) {
          if (mounted) setState(() => _fetchStatus = status);
        },
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _fetchStatus = null;
        _chapters = _storage.getChapters(_series.id);
        final base = '클라우드 업로드 · ${result.downloadedCount}화 완료';
        _syncMessage = result.errors.isEmpty
            ? base
            : '$base\n${result.errors.first}';
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

  void _clearSelection() {
    setState(_selectedIds.clear);
  }

  Future<void> _cancelFetch() async {
    await _fetcher.cancel();
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
      _chapters = _storage.getChapters(_series.id);
    });
  }

  Future<void> _refreshList() async {
    setState(() {
      _loading = true;
      _fetchStatus = null;
      _syncMessage = null;
    });

    try {
      final result = await _fetcher.refreshSeries(
        _series,
        onProgress: (status) {
          if (mounted) setState(() => _fetchStatus = status);
        },
        bypassRunner: _bypass,
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _fetchStatus = null;
          if (result.errors.isNotEmpty) {
            _syncMessage = result.errors.first;
          } else {
            _syncMessage = result.hasNew
                ? '목록 갱신 · 새 회차 ${result.newChapterCount}개'
                : '목록·제목 갱신 완료 · ${_storage.getChapters(_series.id).length}화';
          }
          _series = _storage.getSeries(_series.id) ?? _series;
          _chapters = _storage.getChapters(_series.id);
          _syncNewChapterIds = _storage.getSyncNewChapterIds(_series.id);
        });
      }
    } on FetchCancelledException {
      _handleCancelled();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _fetchStatus = null;
          _syncMessage = '목록 불러오기 실패: $e';
        });
      }
    }
  }

  Future<void> _downloadSelected({
    bool forceBrowser = false,
    bool redownload = false,
  }) async {
    if (!await _ensureCanDownload()) return;
    final selected = _chapters
        .where((c) => _selectedIds.contains(c.id))
        .toList();
    final targets = redownload
        ? selected
              .where(
                (c) =>
                    c.isDownloaded ||
                    c.hasPartialDownload ||
                    c.localPaths.isNotEmpty,
              )
              .toList()
        : selected.where((c) => c.needsFirstSave).toList();

    if (targets.isEmpty) {
      setState(() {
        _syncMessage = redownload
            ? '다시 받을 회차를 선택해 주세요. (저장된 회차)'
            : '다운로드할 회차를 선택해 주세요.';
      });
      return;
    }

    _beginDownloadWork();

    try {
      final result = await _fetcher.downloadSelectedChapters(
        _series,
        targets,
        onProgress: (status) {
          if (mounted) setState(() => _fetchStatus = status);
        },
        bypassRunner: _bypass,
        forceBrowser: forceBrowser,
        redownload: redownload,
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _fetchStatus = null;
          _chapters = _storage.getChapters(_series.id);
          final action = redownload ? '다시 받기' : '저장';
          final baseMessage =
              '${result.downloadedCount}/${targets.length}화 $action 완료';
          if (result.errors.isEmpty) {
            _syncMessage = baseMessage;
          } else {
            _syncMessage =
                '$baseMessage\n실패 ${result.errors.length}건\n${result.errors.first}';
          }
          final savedCounts = _chapters
              .where((c) => targets.any((s) => s.id == c.id) && c.isDownloaded)
              .map((c) => c.localPaths.length)
              .toList();
          if (savedCounts.isNotEmpty) {
            final totalPages = savedCounts.reduce((a, b) => a + b);
            _syncMessage = '${_syncMessage ?? baseMessage}\n총 $totalPages장 저장됨';
          }
          if (!redownload) {
            _selectedIds.removeWhere(
              (id) => _chapters.any((c) => c.id == id && c.isDownloaded),
            );
          }
        });
      }
    } on FetchCancelledException {
      _handleCancelled();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _fetchStatus = null;
          _syncMessage = redownload ? '다시 받기 실패: $e' : '다운로드 실패: $e';
        });
      }
    }
  }

  Future<void> _redownloadChapter(Chapter chapter) async {
    if (!await _ensureCanDownload()) return;
    _beginDownloadWork();

    try {
      final saved = await _fetcher.fetchChapterImagesPublic(
        _series.id,
        chapter,
        onProgress: (status) {
          if (mounted) setState(() => _fetchStatus = status);
        },
        bypassRunner: _bypass,
        redownload: true,
      );
      await CloudBackupQueue.instance.persistAndEnqueue(
        seriesId: _series.id,
        chapter: saved,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _fetchStatus = null;
        _chapters = _storage.getChapters(_series.id);
        _syncMessage = saved.isDownloaded
            ? '${chapter.title} · ${saved.localPaths.length}장 다시 받기 완료'
            : '${chapter.title} · ${saved.localPaths.length}/${saved.imageUrls.length}장만 저장됨 · 다시 시도하세요';
      });
    } on FetchCancelledException {
      _handleCancelled();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _fetchStatus = null;
          _syncMessage = '${chapter.title} 다시 받기 실패: $e';
        });
      }
    }
  }

  Future<void> _showRelinkDialog() async {
    final input = await showRelinkSeriesDialog(
      context,
      currentUrl: _series.url,
      currentTitle: _series.title,
    );

    if (input == null || !mounted) return;

    setState(() {
      _loading = true;
      _fetchStatus = null;
      _syncMessage = null;
    });

    try {
      final updated = await _fetcher.relinkSeries(
        _series.id,
        input.url,
        customTitle: input.trimmedTitle,
        onProgress: (status) {
          if (mounted) setState(() => _fetchStatus = status);
        },
        bypassRunner: _bypass,
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _fetchStatus = null;
          _syncMessage = '링크 연결 완료 · 회차 목록 갱신됨';
          _series = updated;
          _chapters = _storage.getChapters(_series.id);
        });
      }
    } on FetchCancelledException {
      _handleCancelled();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _fetchStatus = null;
          _syncMessage = '연결 실패: $e';
        });
      }
    }
  }

  Future<void> _editTitle() async {
    final title = await showEditTitleDialog(
      context,
      currentTitle: _series.title,
    );
    if (title == null || !mounted) return;

    final updated = _series.copyWith(title: title);
    await _storage.upsertSeries(updated);
    if (mounted) {
      setState(() {
        _series = updated;
        _syncMessage = '제목이 "$title"(으)로 변경되었습니다';
      });
    }
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;

    final selected = _chapters
        .where((c) => _selectedIds.contains(c.id))
        .toList();
    final downloaded = selected.where((c) => c.isDownloaded).length;

    final confirmed = await confirmDelete(
      context,
      title: '회차 삭제',
      message:
          '선택한 ${selected.length}개 회차를 삭제할까요?'
          '${downloaded > 0 ? '\n저장된 이미지 $downloaded개도 함께 삭제됩니다.' : ''}',
    );
    if (!confirmed || !mounted) return;

    final deleted = await _storage.deleteChapters(
      _series.id,
      selected.map((c) => c.id).toList(),
    );

    if (mounted) {
      setState(() {
        _chapters = _storage.getChapters(_series.id);
        _selectedIds.clear();
        _syncMessage = '$deleted개 회차 삭제됨';
      });
    }
  }

  Future<void> _deleteSelectedDownloads() async {
    final selected = _chapters
        .where((c) => _selectedIds.contains(c.id) && c.isDownloaded)
        .toList();
    if (selected.isEmpty) {
      setState(() => _syncMessage = '저장 삭제할 회차를 선택해 주세요.');
      return;
    }

    final confirmed = await confirmDelete(
      context,
      title: '저장 삭제',
      message:
          '선택한 ${selected.length}개 회차의 저장 이미지만 삭제할까요?\n'
          '회차 목록은 유지되고 다시 다운로드할 수 있습니다.',
      confirmLabel: '저장 삭제',
    );
    if (!confirmed || !mounted) return;

    final deleted = await _storage.deleteChapterDownloads(
      _series.id,
      selected.map((c) => c.id).toList(),
    );

    if (mounted) {
      setState(() {
        _chapters = _storage.getChapters(_series.id);
        _selectedIds.clear();
        _syncMessage = '$deleted개 회차 저장 삭제됨';
      });
    }
  }

  Future<void> _deleteSeries() async {
    final downloaded = _chapters.where((c) => c.isDownloaded).length;
    final confirmed = await confirmDelete(
      context,
      title: '만화 삭제',
      message:
          '"${_series.title}"을(를) 삭제할까요?\n'
          '회차 ${_chapters.length}개 · 저장 $downloaded개가 모두 삭제됩니다.',
    );
    if (!confirmed || !mounted) return;

    await _storage.deleteSeriesCompletely(_series.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _markCompleted() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('완료로 이동'),
        content: Text(
          '"${_series.title}"을(를) 완료 목록으로 옮길까요?\n'
          '내 서재에서는 숨겨지고, 완료 화면에서 관리할 수 있습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('완료로 이동'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _storage.markSeriesCompleted(_series.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _toggleFavorite() async {
    await _storage.toggleFavorite(_series.id);
    if (!mounted) return;
    setState(() {
      _series = _storage.getSeries(_series.id) ?? _series;
    });
  }

  Future<void> _restoreToLibrary() async {
    await _storage.restoreSeriesToLibrary(_series.id);
    if (!mounted) return;
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('내 서재로 되돌렸습니다')));
  }

  Future<void> _deleteChapter(Chapter chapter) async {
    final confirmed = await confirmDelete(
      context,
      title: '회차 삭제',
      message:
          '${chapter.title}을(를) 삭제할까요?'
          '${chapter.isDownloaded ? '\n저장된 이미지도 함께 삭제됩니다.' : ''}',
    );
    if (!confirmed || !mounted) return;

    await _storage.deleteChapters(_series.id, [chapter.id]);
    if (mounted) {
      setState(() {
        _chapters = _storage.getChapters(_series.id);
        _selectedIds.remove(chapter.id);
        _syncMessage = '${chapter.number}화 삭제됨';
      });
    }
  }

  void _selectSyncNew() {
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(
          _chapters
              .where((c) => _syncNewChapterIds.contains(c.id))
              .map((c) => c.id),
        );
    });
  }

  Future<void> _clearSyncNewBadge(Chapter chapter) async {
    if (!_syncNewChapterIds.contains(chapter.id)) return;
    await _storage.clearSyncNewChapter(_series.id, chapter.id);
    if (!mounted) return;
    setState(() => _syncNewChapterIds.remove(chapter.id));
  }

  Future<Chapter?> _downloadChapter(
    Chapter chapter, {
    bool forceBrowser = false,
    bool redownload = false,
  }) async {
    if (!await _ensureCanDownload()) return null;
    _beginDownloadWork();

    try {
      final saved = await _fetcher.fetchChapterImagesPublic(
        _series.id,
        chapter,
        onProgress: (status) {
          if (mounted) setState(() => _fetchStatus = status);
        },
        bypassRunner: _bypass,
        redownload: redownload,
        forceBrowser: forceBrowser,
      );
      await CloudBackupQueue.instance.persistAndEnqueue(
        seriesId: _series.id,
        chapter: saved,
      );
      if (!mounted) return saved;
      setState(() {
        _loading = false;
        _fetchStatus = null;
        _chapters = _storage.getChapters(_series.id);
        _syncMessage = saved.isDownloaded || saved.localPaths.isNotEmpty
            ? '${chapter.title} · ${saved.localPaths.length}장 Cloudflare에 저장 중'
            : '${chapter.title} · ${saved.localPaths.length}장 일부 저장 · 이어 받기 가능';
      });
      return saved;
    } on FetchCancelledException {
      _handleCancelled();
      return null;
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _fetchStatus = null;
          _syncMessage = '${chapter.title} 저장 실패: $e';
        });
      }
      return null;
    }
  }

  Future<void> _openWebReader(
    Chapter chapter, {
    bool startAtTop = false,
  }) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WebViewReaderScreen(
          seriesId: _series.id,
          seriesTitle: _series.title,
          chapter: chapter,
          startAtTop: startAtTop,
        ),
      ),
    );
    _reload();
  }

  Future<void> _openChapter(Chapter chapter, {bool startAtTop = false}) async {
    await _clearSyncNewBadge(chapter);

    var current = _chapters.firstWhere(
      (c) => c.id == chapter.id,
      orElse: () => chapter,
    );
    final reconciled = _storage.reconcileChapterDownloads(_series.id, current);
    if (reconciled.localPaths != current.localPaths) {
      await _storage.upsertChapter(_series.id, reconciled);
      if (mounted) {
        setState(() => _chapters = _storage.getChapters(_series.id));
      }
      current = reconciled;
    }

    if (current.canOpen) {
      if (!current.canRead) {
        final prepared = await _openCloudChapter(current);
        if (prepared == null) return;
        current = prepared;
      }
      await _openLocalReader(current, startAtTop: startAtTop);
      return;
    }

    if (!mounted) return;
    if (!ConnectivityService.instance.isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('오프라인입니다. 보관되지 않은 회차는 웹으로 열 수 없습니다.')),
      );
      return;
    }
    await _openWebReader(current, startAtTop: startAtTop);
  }

  Future<Chapter?> _openCloudChapter(Chapter current) async {
    if (!ConnectivityService.instance.isOnline) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('오프라인입니다. 클라우드 회차를 열려면 인터넷이 필요합니다.')),
      );
      return null;
    }
    if (!mounted) return null;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  '${current.title} 여는 중',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    try {
      final prepared = await ChapterReader.prepare(
        seriesId: _series.id,
        chapter: current,
        fetcher: _fetcher,
        bypassRunner: _bypass,
      );
      return prepared;
    } on FetchCancelledException {
      return null;
    } catch (e) {
      if (mounted) {
        setState(() => _syncMessage = '${current.title} 열기 실패: $e');
      }
      return null;
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        setState(() => _chapters = _storage.getChapters(_series.id));
      }
    }
  }

  Future<void> _openLocalReader(
    Chapter chapter, {
    bool startAtTop = false,
  }) async {
    final current = _chapters.firstWhere(
      (c) => c.id == chapter.id,
      orElse: () => chapter,
    );
    if (!current.canRead || !mounted) return;

    if (current.hasPartialDownload) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${current.localPaths.length}/${current.effectiveExpectedPageCount ?? current.imageUrls.length}장만 저장됨',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(
          seriesId: _series.id,
          chapter: current,
          startAtTop: startAtTop,
        ),
      ),
    );
    _reload();
  }

  Future<void> _resumeChapter(Chapter chapter) async {
    if (!await _ensureCanDownload()) return;
    _beginDownloadWork();

    try {
      final saved = await _fetcher.fetchChapterImagesPublic(
        _series.id,
        chapter,
        onProgress: (status) {
          if (mounted) setState(() => _fetchStatus = status);
        },
        bypassRunner: _bypass,
      );
      await CloudBackupQueue.instance.persistAndEnqueue(
        seriesId: _series.id,
        chapter: saved,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _fetchStatus = null;
        _chapters = _storage.getChapters(_series.id);
        _syncMessage = saved.isDownloaded
            ? '${chapter.title} · ${saved.localPaths.length}장 이어 받기 완료'
            : '${chapter.title} · ${saved.localPaths.length}/${saved.imageUrls.length}장 저장 · 다시 이어 받기 가능';
      });
    } on FetchCancelledException {
      _handleCancelled();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _fetchStatus = null;
          _syncMessage = '${chapter.title} 이어 받기 실패: $e';
        });
      }
    }
  }

  Chapter? _continueChapter() {
    return _storage.getContinueTarget(_series.id)?.chapter;
  }

  bool _continueStartsAtTop() {
    return _storage.getContinueTarget(_series.id)?.startAtTop ?? false;
  }

  bool _continueIsNextAfterCompleted() {
    return _storage.getContinueTarget(_series.id)?.isNextAfterCompleted ??
        false;
  }

  Chapter? _firstChapter() {
    if (_chapters.isEmpty) return null;
    var first = _chapters.first;
    for (final chapter in _chapters) {
      if (chapter.number < first.number) first = chapter;
    }
    return first;
  }

  Future<void> _openFromBeginning() async {
    final first = _firstChapter();
    if (first == null) return;

    await _storage.saveProgress(
      _series.id,
      ReadingProgress(
        chapterId: first.id,
        scrollOffset: 0,
        updatedAt: DateTime.now(),
      ),
    );
    await _openChapter(first);
  }

  bool _hasReadingProgress(Chapter chapter) {
    return (_progressOffsets[chapter.id] ?? 0) > 0;
  }

  Future<void> _scrollToContinueChapter() async {
    final target = _continueChapter();
    if (target == null) return;
    if (_chapterFilter != _ChapterListFilter.all &&
        !_chapterMatchesFilter(target)) {
      setState(() => _chapterFilter = _ChapterListFilter.all);
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted || !_scrollController.hasClients) return;
    final index = _visibleChapters.indexWhere((c) => c.id == target.id);
    if (index < 0) return;
    final offset = _chapterHeaderExtent + index * _chapterTileExtent;
    final max = _scrollController.position.maxScrollExtent;
    await _scrollController.animateTo(
      offset.clamp(0.0, max),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _bottomSheetList({required List<Widget> children}) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }

  Future<void> _showChapterMenu(Chapter chapter) async {
    final isDownloaded = chapter.isDownloaded;
    final isPartial = chapter.hasPartialDownload;

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _bottomSheetList(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              chapter.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          if (isDownloaded || isPartial)
            ListTile(
              leading: const Icon(Icons.menu_book_rounded),
              title: Text(
                isPartial ? '저장본 읽기 (${chapter.localPaths.length}장)' : '저장본 읽기',
              ),
              onTap: () => Navigator.pop(context, 'read_local'),
            ),
          ListTile(
            leading: const Icon(Icons.language_rounded),
            title: const Text('웹으로 읽기'),
            subtitle: const Text('광고 숨김 · 인터넷 필요'),
            onTap: () => Navigator.pop(context, 'web_read'),
          ),
          if (!chapter.isOnCloud)
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('이 회차 보관'),
              onTap: () => Navigator.pop(context, 'download'),
            ),
          if (chapter.canRead && (isPartial || isDownloaded))
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: Text(
                isPartial
                    ? '이어 받기 · ${chapter.localPaths.length}/${chapter.imageUrls.length}장'
                    : '이어 받기',
              ),
              onTap: () => Navigator.pop(context, 'resume'),
            ),
          if (isDownloaded || isPartial)
            ListTile(
              leading: const Icon(Icons.refresh_rounded),
              title: const Text('다시 받기'),
              onTap: () => Navigator.pop(context, 'redownload'),
            ),
          if (!isDownloaded && !isPartial)
            ListTile(
              leading: const Icon(Icons.open_in_browser_rounded),
              title: const Text('브라우저로 보관'),
              onTap: () => Navigator.pop(context, 'browser_download'),
            ),
          if (isDownloaded)
            ListTile(
              leading: const Icon(Icons.folder_off_outlined),
              title: const Text('저장만 삭제'),
              onTap: () => Navigator.pop(context, 'delete_download'),
            ),
          ListTile(
            leading: Icon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              '회차 삭제',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () => Navigator.pop(context, 'delete'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'read_local':
        await _openLocalReader(chapter);
        break;
      case 'web_read':
        await _openWebReader(chapter);
        break;
      case 'download':
        await _downloadChapter(chapter);
        break;
      case 'browser_download':
        await _downloadChapter(chapter, forceBrowser: true);
        break;
      case 'resume':
        await _resumeChapter(chapter);
        break;
      case 'redownload':
        await _redownloadChapter(chapter);
        break;
      case 'delete_download':
        setState(() => _selectedIds.add(chapter.id));
        await _deleteSelectedDownloads();
        break;
      case 'delete':
        await _deleteChapter(chapter);
        break;
    }
  }

  Future<void> _showSelectionMoreSheet() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _bottomSheetList(
        children: [
          ListTile(
            leading: const Icon(Icons.open_in_browser_rounded),
            title: const Text('브라우저로 다운로드'),
            onTap: () => Navigator.pop(context, 'browser'),
          ),
          ListTile(
            leading: const Icon(Icons.folder_off_outlined),
            title: const Text('저장 삭제'),
            onTap: () => Navigator.pop(context, 'delete_download'),
          ),
          ListTile(
            leading: Icon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              '회차 삭제',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () => Navigator.pop(context, 'delete'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'browser':
        await _downloadSelected(forceBrowser: true);
        break;
      case 'delete_download':
        await _deleteSelectedDownloads();
        break;
      case 'delete':
        await _deleteSelected();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final continueChapter = _continueChapter();
    final firstChapter = _firstChapter();
    final downloadedCount = _chapters.where((c) => c.isArchived).length;
    final totalCount = _chapters.length;
    final selectedCount = _chapters
        .where((c) => _selectedIds.contains(c.id))
        .length;
    final redownloadableCount = _chapters
        .where(
          (c) =>
              _selectedIds.contains(c.id) &&
              (c.isDownloaded ||
                  c.hasPartialDownload ||
                  c.localPaths.isNotEmpty),
        )
        .length;
    final hasSelection = selectedCount > 0;
    final syncNewCount = _syncNewChapterIds.length;

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Text(
          _series.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        actions: [
          if (!_loading) const NetworkStatusChip(iconOnly: true),
          if (!_loading) const ThemeToggleButton(),
          if (_loading)
            IconButton(
              onPressed: _showDownloadStatusSheet,
              icon: const Icon(Icons.downloading_rounded),
              tooltip: '다운로드 상태',
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'refresh':
                  if (!_loading) _refreshList();
                  break;
                case 'edit_title':
                  _editTitle();
                  break;
                case 'relink':
                  _showRelinkDialog();
                  break;
                case 'mark_completed':
                  _markCompleted();
                  break;
                case 'toggle_favorite':
                  _toggleFavorite();
                  break;
                case 'restore_library':
                  _restoreToLibrary();
                  break;
                case 'archive_all':
                  _downloadAllUndownloaded();
                  break;
                case 'cloud_inventory':
                  _refreshSeriesCloudInventory();
                  break;
                case 'cloud_upload':
                  _uploadSeriesToCloud();
                  break;
                case 'delete_series':
                  _deleteSeries();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'refresh',
                enabled: !_loading,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.refresh_rounded),
                  title: Text('회차 목록 새로고침'),
                ),
              ),
              if (_undownloadedCount > 0)
                PopupMenuItem(
                  value: 'archive_all',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: const Text('이 작품 통째로 보관'),
                    subtitle: Text('미보관 $_undownloadedCount화'),
                  ),
                ),
              const PopupMenuItem(
                value: 'cloud_inventory',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.cloud_queue_rounded),
                  title: Text('클라우드 만화 확인'),
                ),
              ),
              const PopupMenuItem(
                value: 'cloud_upload',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.cloud_upload_outlined),
                  title: Text('로컬 파일을 클라우드에 올리기'),
                ),
              ),
              const PopupMenuItem(
                value: 'edit_title',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit_outlined),
                  title: Text('제목 수정'),
                ),
              ),
              const PopupMenuItem(
                value: 'relink',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.link_rounded),
                  title: Text('링크 수정'),
                ),
              ),
              PopupMenuItem(
                value: 'toggle_favorite',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _series.isFavorite
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: _series.isFavorite ? Colors.amber : null,
                  ),
                  title: Text(_series.isFavorite ? '즐겨찾기 해제' : '즐겨찾기 추가'),
                ),
              ),
              if (_series.isCompleted)
                const PopupMenuItem(
                  value: 'restore_library',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.unarchive_outlined),
                    title: Text('내 서재로 되돌리기'),
                  ),
                )
              else
                const PopupMenuItem(
                  value: 'mark_completed',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.check_circle_outline),
                    title: Text('완료로 이동'),
                  ),
                ),
              PopupMenuItem(
                value: 'delete_series',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_forever, color: Colors.red),
                  title: Text('만화 삭제', style: TextStyle(color: Colors.red)),
                ),
              ),
            ],
          ),
          const LockButton(),
        ],
        bottom: _loading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(36),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: InkWell(
                    onTap: _showDownloadStatusSheet,
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
                              _downloadStatusSummary,
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
      // 다운로드 진행은 상단 배너/상태 시트로 보고, 하단은 선택 바에만 사용합니다.
      bottomNavigationBar: hasSelection && !_loading
          ? SeriesSelectionBar(
              selectedCount: selectedCount,
              redownloadableCount: redownloadableCount,
              onDownload: () => _downloadSelected(),
              onRedownload: () => _downloadSelected(redownload: true),
              onMore: _showSelectionMoreSheet,
              onClear: _clearSelection,
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _refreshList,
        child: CustomScrollView(
          controller: _scrollController,
          scrollCacheExtent: const ScrollCacheExtent.pixels(480),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  key: _chapterHeaderKey,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const OfflineBanner(),
                    _SeriesStatsCard(
                      series: _series,
                      archived: downloadedCount,
                      total: totalCount,
                      lastRefreshed: _series.lastRefreshedAt,
                      syncNewCount: syncNewCount,
                      storageLabel: _storageBytes != null
                          ? formatBytes(_storageBytes!)
                          : null,
                    ),
                    if (_series.isCompleted) ...[
                      const SizedBox(height: 12),
                      Material(
                        color: Theme.of(
                          context,
                        ).colorScheme.tertiaryContainer.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(12),
                        child: ListTile(
                          leading: Icon(
                            Icons.check_circle_outline,
                            color: Theme.of(context).colorScheme.tertiary,
                          ),
                          title: const Text('완료한 만화'),
                          subtitle: const Text('내 서재에는 표시되지 않습니다'),
                          trailing: TextButton(
                            onPressed: _loading ? null : _restoreToLibrary,
                            child: const Text('되돌리기'),
                          ),
                        ),
                      ),
                    ],
                    if (continueChapter != null || firstChapter != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          if (continueChapter != null)
                            Expanded(
                              child: _ContinueReadingCard(
                                chapter: continueChapter,
                                enabled: !_loading,
                                nextAfterCompleted:
                                    _continueIsNextAfterCompleted(),
                                onTap: () => _openChapter(
                                  continueChapter,
                                  startAtTop: _continueStartsAtTop(),
                                ),
                              ),
                            ),
                          if (firstChapter != null &&
                              firstChapter.id != continueChapter?.id) ...[
                            if (continueChapter != null)
                              const SizedBox(width: 8),
                            if (continueChapter == null)
                              Expanded(
                                child: _StartFromBeginningButton(
                                  enabled: !_loading,
                                  expanded: true,
                                  onTap: _openFromBeginning,
                                ),
                              )
                            else
                              _StartFromBeginningButton(
                                enabled: !_loading,
                                onTap: _openFromBeginning,
                              ),
                          ],
                        ],
                      ),
                    ],
                    if (_syncMessage != null) ...[
                      const SizedBox(height: 12),
                      StatusBanner(
                        message: _syncMessage!,
                        onDismiss: () => setState(() => _syncMessage = null),
                      ),
                    ],
                    if (syncNewCount > 0 || hasSelection) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (syncNewCount > 0)
                            FilterChip(
                              avatar: Icon(
                                Icons.fiber_new_rounded,
                                size: 18,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              label: Text('새 회차 $syncNewCount'),
                              onSelected: _loading
                                  ? null
                                  : (_) => _selectSyncNew(),
                            ),
                          if (hasSelection)
                            ActionChip(
                              avatar: const Icon(Icons.close, size: 18),
                              label: Text('$selectedCount개 해제'),
                              onPressed: _loading ? null : _clearSelection,
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    AppSearchField(
                      controller: _searchController,
                      hintText: '회차 번호·제목 검색',
                      enabled: !_loading,
                      onChanged: (value) =>
                          setState(() => _searchQuery = value),
                    ),
                    const SizedBox(height: 12),
                    _ChapterFilterBar(
                      filter: _chapterFilter,
                      unreadCount: _chapters
                          .where((c) => !_hasReadingProgress(c))
                          .length,
                      archivedCount: _chapters
                          .where((c) => c.isArchived)
                          .length,
                      freshCount: syncNewCount,
                      enabled: !_loading,
                      onSelected: (filter) =>
                          setState(() => _chapterFilter = filter),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          '회차',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        if (_searchQuery.trim().isNotEmpty)
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(
                                '${_visibleChapters.length}개',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ),
                        if (syncNewCount > 0)
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(
                                '새 $syncNewCount화',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ),
                        if (totalCount > 0)
                          Text(
                            '$totalCount화',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        IconButton(
                          onPressed: _loading ? null : _toggleChapterOrder,
                          tooltip: _sortMode == 'oldest' ? '최신순으로' : '오래된 순으로',
                          icon: Icon(
                            _sortMode == 'oldest'
                                ? Icons.arrow_upward_rounded
                                : Icons.arrow_downward_rounded,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          onPressed: _loading || _chapters.isEmpty
                              ? null
                              : _shuffleChapterOrder,
                          tooltip: _sortMode == 'random' ? '다시 섞기' : '랜덤 순서로',
                          icon: Icon(
                            Icons.shuffle_rounded,
                            color: _sortMode == 'random'
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        if (continueChapter != null && totalCount > 6)
                          IconButton(
                            onPressed: _loading
                                ? null
                                : _scrollToContinueChapter,
                            tooltip: '읽는 화로 이동',
                            icon: Icon(
                              Icons.my_location_rounded,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        if (totalCount > 8)
                          IconButton(
                            onPressed: _loading ? null : _jumpToChapterNumber,
                            tooltip: '화 번호로 이동',
                            icon: const Icon(Icons.tag_rounded),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _sortMode == 'random'
                          ? '랜덤 순 · 탭해서 바로 읽기'
                          : _sortMode == 'oldest'
                          ? '오래된 순 · 탭해서 바로 읽기'
                          : '최신순 · 탭해서 바로 읽기',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            if (_chapters.isEmpty && !_loading)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverToBoxAdapter(
                  child: _EmptyChapterList(onRefresh: _refreshList),
                ),
              )
            else if (_visibleChapters.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    children: [
                      SearchEmptyState(
                        query: _searchQuery,
                        label: _chapterFilter == _ChapterListFilter.unread
                            ? '안 읽은 회차가 없습니다'
                            : _chapterFilter == _ChapterListFilter.archived
                            ? '보관한 회차가 없습니다'
                            : _chapterFilter == _ChapterListFilter.fresh
                            ? '새 회차가 없습니다'
                            : '일치하는 회차가 없습니다',
                      ),
                      if (_chapterFilter != _ChapterListFilter.all ||
                          _searchQuery.trim().isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                              _chapterFilter = _ChapterListFilter.all;
                            });
                          },
                          icon: const Icon(Icons.filter_alt_off_outlined),
                          label: const Text('필터 초기화'),
                        ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, hasSelection ? 96 : 28),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final chapter = _visibleChapters[index];
                      final hasProgress = _hasReadingProgress(chapter);
                      final isLastRead = continueChapter?.id == chapter.id;
                      return Dismissible(
                        key: ValueKey(chapter.id),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) async {
                          await _deleteChapter(chapter);
                          return false;
                        },
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.error,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.delete_outline,
                            color: Colors.white,
                          ),
                        ),
                        child: ChapterTile(
                          chapter: chapter,
                          searchQuery: _searchQuery,
                          isSelected: _selectedIds.contains(chapter.id),
                          showCheckbox: hasSelection,
                          isSyncNew: _syncNewChapterIds.contains(chapter.id),
                          isLastRead: isLastRead,
                          hasReadingProgress: hasProgress,
                          enabled: !_loading,
                          onToggleSelect: () {
                            setState(() {
                              if (_selectedIds.contains(chapter.id)) {
                                _selectedIds.remove(chapter.id);
                              } else {
                                _selectedIds.add(chapter.id);
                              }
                            });
                          },
                          onOpen: () => _openChapter(chapter),
                          onMore: () => _showChapterMenu(chapter),
                        ),
                      );
                    },
                    childCount: _visibleChapters.length,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChapterFilterBar extends StatelessWidget {
  const _ChapterFilterBar({
    required this.filter,
    required this.unreadCount,
    required this.archivedCount,
    required this.freshCount,
    required this.enabled,
    required this.onSelected,
  });

  final _ChapterListFilter filter;
  final int unreadCount;
  final int archivedCount;
  final int freshCount;
  final bool enabled;
  final ValueChanged<_ChapterListFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    if (unreadCount == 0 &&
        archivedCount == 0 &&
        freshCount == 0 &&
        filter == _ChapterListFilter.all) {
      return const SizedBox.shrink();
    }

    Widget chip({
      required _ChapterListFilter value,
      required String label,
      IconData? icon,
    }) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
          avatar: icon == null ? null : Icon(icon, size: 18),
          label: Text(label),
          selected: filter == value,
          onSelected: enabled
              ? (selected) =>
                    onSelected(selected ? value : _ChapterListFilter.all)
              : null,
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (filter != _ChapterListFilter.all)
            chip(value: _ChapterListFilter.all, label: '전체'),
          if (unreadCount > 0 || filter == _ChapterListFilter.unread)
            chip(
              value: _ChapterListFilter.unread,
              label: unreadCount > 0 ? '안 읽음 $unreadCount' : '안 읽음',
              icon: Icons.mark_email_unread_outlined,
            ),
          if (archivedCount > 0 || filter == _ChapterListFilter.archived)
            chip(
              value: _ChapterListFilter.archived,
              label: archivedCount > 0 ? '보관 $archivedCount' : '보관',
              icon: Icons.inventory_2_outlined,
            ),
          if (freshCount > 0 || filter == _ChapterListFilter.fresh)
            chip(
              value: _ChapterListFilter.fresh,
              label: freshCount > 0 ? '새 회차 $freshCount' : '새 회차',
              icon: Icons.fiber_new_rounded,
            ),
        ],
      ),
    );
  }
}

class _SeriesStatsCard extends StatelessWidget {
  const _SeriesStatsCard({
    required this.series,
    required this.archived,
    required this.total,
    this.lastRefreshed,
    this.syncNewCount = 0,
    this.storageLabel,
  });

  final Series series;
  final int archived;
  final int total;
  final DateTime? lastRefreshed;
  final int syncNewCount;
  final String? storageLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SeriesCover(
              series: series,
              width: 72,
              height: 96,
              borderRadius: BorderRadius.circular(14),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    series.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    total == 0 ? '회차 목록 없음' : '$total화',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    archived > 0 ? '보관 $archived화' : '탭하면 바로 읽습니다',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (syncNewCount > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      '새 회차 $syncNewCount화',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (lastRefreshed != null)
                    Text(
                      '목록 ${_formatDate(lastRefreshed!)}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  if (storageLabel != null)
                    Text(
                      storageLabel!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime time) {
    final local = time.toLocal();
    return '${local.month}/${local.day} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _ContinueReadingCard extends StatelessWidget {
  const _ContinueReadingCard({
    required this.chapter,
    required this.onTap,
    required this.enabled,
    this.nextAfterCompleted = false,
  });

  final Chapter chapter;
  final VoidCallback onTap;
  final bool enabled;
  final bool nextAfterCompleted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = nextAfterCompleted
        ? '다음 화 이어 읽기 · ${chapter.number}화'
        : '이어 읽기 · ${chapter.number}화';
    return Material(
      color: scheme.primary,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              Icon(
                Icons.play_circle_fill_rounded,
                color: scheme.onPrimary,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      chapter.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onPrimary.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: scheme.onPrimary,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartFromBeginningButton extends StatelessWidget {
  const _StartFromBeginningButton({
    required this.onTap,
    required this.enabled,
    this.expanded = false,
  });

  final VoidCallback onTap;
  final bool enabled;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: enabled ? onTap : null,
      style: OutlinedButton.styleFrom(
        minimumSize: Size(expanded ? double.infinity : 88, 52),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      icon: const Icon(Icons.first_page_rounded, size: 20),
      label: Text(expanded ? '처음부터' : '처음'),
    );
  }
}

class _EmptyChapterList extends StatelessWidget {
  const _EmptyChapterList({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            Icons.menu_book_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          const Text('회차 목록이 없습니다', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('회차 목록 불러오기'),
          ),
        ],
      ),
    );
  }
}
