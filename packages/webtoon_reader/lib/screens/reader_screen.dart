import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../models/chapter.dart';
import '../models/fetch_status.dart';
import '../models/reading_progress.dart';
import '../models/webview_bypass_runner.dart';
import '../services/chapter_reader.dart';
import '../services/cloud_backup_queue.dart';
import '../services/lock_service.dart';
import '../services/connectivity_service.dart';
import '../services/network_policy.dart';
import '../services/storage_service.dart';
import '../services/webtoon_fetcher.dart';
import '../theme/app_theme.dart';
import '../utils/webview_bypass.dart';
import '../widgets/content_protection.dart';
import '../widgets/lock_button.dart';
import '../widgets/network_status_chip.dart';
import '../widgets/lock_activity_scope.dart';
import 'webview_reader_screen.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.seriesId,
    required this.chapter,
    this.startAtTop = false,
  });

  final String seriesId;
  final Chapter chapter;
  final bool startAtTop;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _scrollController = ScrollController(keepScrollOffset: false);
  final _storage = StorageService.instance;
  final _fetcher = WebtoonFetcher();
  Timer? _saveTimer;
  Timer? _chromeTimer;
  Timer? _pageUpdateTimer;
  Timer? _aspectSaveTimer;
  bool _restored = false;
  bool _showChrome = true;
  int _currentPage = 1;
  final _chromeVisible = ValueNotifier<bool>(true);
  final _pageIndex = ValueNotifier<int>(1);
  final _jumpingToEnd = ValueNotifier<bool>(false);
  late final Listenable _chromeListenable = Listenable.merge([
    _chromeVisible,
    _pageIndex,
    _jumpingToEnd,
  ]);
  late Chapter _chapter;
  late List<Chapter> _chapters;
  late List<GlobalKey> _itemKeys;
  late List<double> _aspectRatios;
  final _endMarkerKey = GlobalKey();
  bool _scrollToBottomRunning = false;
  bool _resumingDownload = false;
  bool _autoAdvanced = false;
  double _lastScrollOffset = 0;
  int? _pendingRestorePage;
  double _pendingRestoreFraction = 0;
  double? _pendingLegacyOffset;
  final Set<int> _precacheQueued = {};
  Timer? _aspectLayoutTimer;
  bool _aspectLayoutDirty = false;

  /// 페이지 번호 setState를 스크롤 프레임마다 하지 않도록 쓰로틀합니다.
  static const _pageUpdateThrottle = Duration(milliseconds: 120);
  static const _precacheBehind = 1;
  static const _precacheAhead = 2;
  static const _precacheMaxInFlight = 2;
  int _precacheInFlight = 0;
  static const _endMarkerHeight = 220.0;
  static const _defaultAspect = 1.35;

  List<String> get _paths => _chapter.localPaths;

  WebViewBypassRunner get _bypass => createWebViewBypassRunner(context);

  Chapter? get _previousChapter {
    if (_storage.chapterListSortMode == 'random') {
      return Chapter.findAdjacentInOrder(
        _chapters,
        _chapter,
        delta: -1,
        canNavigate: (c) => c.canNavigate,
      );
    }
    return Chapter.findPreviousByNumber(
      _chapters,
      _chapter,
      canNavigate: (c) => c.canNavigate,
    );
  }

  Chapter? get _nextChapter {
    if (_storage.chapterListSortMode == 'random') {
      return Chapter.findAdjacentInOrder(
        _chapters,
        _chapter,
        delta: 1,
        canNavigate: (c) => c.canNavigate,
      );
    }
    return Chapter.findNextByNumber(
      _chapters,
      _chapter,
      canNavigate: (c) => c.canNavigate,
    );
  }

  String get _chapterIndexLabel {
    final total = _chapters.length;
    if (total <= 0) return '${_chapter.number}화';
    return '${_chapter.number} / $total화';
  }

  @override
  void initState() {
    super.initState();
    LockService.instance.beginKeepAwake();
    _chapters = _storage.orderedChaptersForNavigation(widget.seriesId);
    _chapter = _storage.reconcileChapterDownloads(
      widget.seriesId,
      widget.chapter,
    );
    if (_chapter.localPaths != widget.chapter.localPaths) {
      unawaited(_storage.upsertChapter(widget.seriesId, _chapter));
    }
    _itemKeys = List.generate(_paths.length, (_) => GlobalKey());
    _aspectRatios = Chapter.alignAspectRatios(
      _chapter.pageAspectRatios,
      _paths.length,
    );
    _scrollController.addListener(_onScroll);
    _recordReadingSession();
    if (widget.startAtTop) {
      _restored = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToTop());
      Future<void>.delayed(
        const Duration(milliseconds: 250),
        _enforceTopIfNeeded,
      );
      Future<void>.delayed(
        const Duration(milliseconds: 900),
        _enforceTopIfNeeded,
      );
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _restoreProgress());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _precacheAround(0);
    });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _recordReadingSession() {
    unawaited(_flushProgress());
  }

  void _onImageLoaded(int index, double aspectRatio) {
    if (!mounted) return;
    var aspectChanged = false;
    if (index >= 0 && index < _aspectRatios.length && aspectRatio > 0.05) {
      final prev = _aspectRatios[index];
      if ((prev - aspectRatio).abs() > 0.01) {
        _aspectRatios[index] = aspectRatio;
        aspectChanged = true;
        _scheduleAspectPersist();
        if (_pendingRestorePage != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _tryApplyPendingRestore();
          });
        }
      }
    }
    if (aspectChanged) {
      // 장마다 setState하면 스크롤이 끊깁니다. 짧게 모아서 한 번만 레이아웃합니다.
      _aspectLayoutDirty = true;
      _aspectLayoutTimer ??= Timer(const Duration(milliseconds: 80), () {
        _aspectLayoutTimer = null;
        if (!mounted || !_aspectLayoutDirty) return;
        _aspectLayoutDirty = false;
        setState(() {});
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateCurrentPage();
        _precacheAround(index);
      }
    });
  }

  void _scheduleAspectPersist() {
    _aspectSaveTimer?.cancel();
    _aspectSaveTimer = Timer(const Duration(seconds: 2), () {
      unawaited(_persistAspectRatios());
    });
  }

  Future<void> _persistAspectRatios() async {
    if (!mounted || _paths.isEmpty) return;
    final known = _aspectRatios.where((r) => r > 0.05).length;
    if (known == 0) return;
    final aligned = Chapter.alignAspectRatios(_aspectRatios, _paths.length);
    if (_listEqualsDouble(aligned, _chapter.pageAspectRatios)) return;
    _chapter = _chapter.copyWith(pageAspectRatios: aligned);
    await _storage.upsertChapter(widget.seriesId, _chapter);
  }

  bool _listEqualsDouble(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 0.001) return false;
    }
    return true;
  }

  double _pageExtent(int index, double width) {
    if (index < 0 || index >= _paths.length) return _endMarkerHeight;
    final ratio = index < _aspectRatios.length ? _aspectRatios[index] : 0.0;
    if (ratio > 0.05) return width * ratio;
    return width * _defaultAspect;
  }

  double _offsetForPage(int pageIndex, double width, {double fraction = 0}) {
    var offset = 0.0;
    final last = pageIndex.clamp(0, _paths.length);
    for (var i = 0; i < last; i++) {
      offset += _pageExtent(i, width);
    }
    if (pageIndex >= 0 && pageIndex < _paths.length) {
      offset += _pageExtent(pageIndex, width) * fraction.clamp(0.0, 1.0);
    }
    return offset;
  }

  void _precacheAround(int center) {
    if (!mounted || _paths.isEmpty) return;
    final start = (center - _precacheBehind).clamp(0, _paths.length - 1);
    final end = (center + _precacheAhead).clamp(0, _paths.length - 1);
    final width = MediaQuery.sizeOf(context).width;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (width * dpr).round().clamp(1, 4096);

    final order = <int>[];
    for (var i = center; i <= end; i++) {
      order.add(i);
    }
    for (var i = center - 1; i >= start; i--) {
      order.add(i);
    }

    for (final i in order) {
      if (_precacheInFlight >= _precacheMaxInFlight) return;
      if (_precacheQueued.contains(i)) continue;
      _precacheQueued.add(i);
      _precacheInFlight++;
      final provider = ResizeImage(
        FileImage(File(_paths[i])),
        width: cacheWidth,
      );
      unawaited(
        precacheImage(provider, context)
            .then<void>(
              (_) {},
              onError: (_) {
                _precacheQueued.remove(i);
              },
            )
            .whenComplete(() {
              if (_precacheInFlight > 0) _precacheInFlight--;
            }),
      );
    }
  }

  void _setPage(int page) {
    if (_currentPage == page) return;
    _currentPage = page;
    _pageIndex.value = page;
  }

  void _setChrome(bool value) {
    if (_showChrome == value) return;
    _showChrome = value;
    _chromeVisible.value = value;
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _chromeTimer?.cancel();
    _pageUpdateTimer?.cancel();
    _aspectSaveTimer?.cancel();
    _aspectLayoutTimer?.cancel();
    unawaited(_persistAspectRatios());
    unawaited(_flushProgress());
    _scrollController.dispose();
    _chromeVisible.dispose();
    _pageIndex.dispose();
    _jumpingToEnd.dispose();
    LockService.instance.endKeepAwake();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _onScroll() {
    recordLockActivity();
    if (_scrollController.hasClients) {
      _lastScrollOffset = _scrollController.offset;
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _saveProgress);
    _schedulePageUpdate();
    _scheduleHideChrome();
    _maybeAutoAdvance();
  }

  void _schedulePageUpdate() {
    if (_pageUpdateTimer?.isActive ?? false) return;
    _pageUpdateTimer = Timer(_pageUpdateThrottle, () {
      if (mounted) {
        _updateCurrentPage();
        _precacheAround(_currentPage - 1);
      }
    });
  }

  void _updateCurrentPage() {
    if (!_scrollController.hasClients || _paths.isEmpty) return;

    final width = MediaQuery.sizeOf(context).width;
    final offset = _scrollController.offset;
    final viewport = _scrollController.position.viewportDimension;
    final center = offset + viewport * 0.4;

    var accumulated = 0.0;
    var page = 1;
    for (var i = 0; i < _paths.length; i++) {
      final extent = _pageExtent(i, width);
      if (accumulated + extent > center) {
        page = i + 1;
        break;
      }
      accumulated += extent;
      page = i + 1;
    }

    final fromKeys = _pageIndexFromItemKeys(sampleAround: page - 1);
    if (fromKeys != null) {
      page = (fromKeys + 1).clamp(1, _paths.length);
    }

    if (page != _currentPage) _setPage(page);
  }

  /// [sampleAround] 근처의 빌드된 항목만 검사해 페이지를 보정합니다.
  int? _pageIndexFromItemKeys({int sampleAround = 0}) {
    if (!_scrollController.hasClients || _itemKeys.isEmpty) return null;

    final scrollOffset = _scrollController.offset;
    final viewportCenter =
        scrollOffset + _scrollController.position.viewportDimension * 0.4;

    final start = (sampleAround - 4).clamp(0, _itemKeys.length - 1);
    final end = (sampleAround + 6).clamp(0, _itemKeys.length - 1);

    var bestIndex = sampleAround.clamp(0, _itemKeys.length - 1);
    var found = false;

    for (var i = start; i <= end; i++) {
      final ctx = _itemKeys[i].currentContext;
      if (ctx == null) continue;
      final renderObject = ctx.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) continue;

      final viewport = RenderAbstractViewport.maybeOf(renderObject);
      if (viewport == null) continue;

      final revealed = viewport.getOffsetToReveal(renderObject, 0);
      if (revealed.offset <= viewportCenter + 1) {
        bestIndex = i;
        found = true;
      }
    }

    return found ? bestIndex : null;
  }

  (int pageIndex, double fraction) _pageAnchorFromOffset(double offset) {
    if (_paths.isEmpty) return (0, 0);
    final width = MediaQuery.sizeOf(context).width;
    var remaining = offset;
    for (var i = 0; i < _paths.length; i++) {
      final extent = _pageExtent(i, width);
      if (remaining <= extent || i == _paths.length - 1) {
        final fraction = extent > 0
            ? (remaining / extent).clamp(0.0, 1.0)
            : 0.0;
        return (i, fraction);
      }
      remaining -= extent;
    }
    return (_paths.length - 1, 1.0);
  }

  bool _isNearEnd() {
    if (!_scrollController.hasClients || _paths.isEmpty) return false;
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return _currentPage >= _paths.length;
    return _scrollController.offset >= max - 80;
  }

  void _maybeAutoAdvance() {
    if (_autoAdvanced || widget.startAtTop && !_restored) return;
    if (!_isNearEnd()) return;
    final next = _nextChapter;
    if (next == null) return;
    // 완료 플래그만 먼저 저장. 자동 이동은 끝 마커 버튼/이어 읽기에서 처리.
  }

  Future<void> _scrollToBottom() async {
    if (!_scrollController.hasClients ||
        _paths.isEmpty ||
        _scrollToBottomRunning) {
      return;
    }
    _scrollToBottomRunning = true;
    _jumpingToEnd.value = true;
    _setChrome(true);
    _scheduleHideChrome();

    try {
      final width = MediaQuery.sizeOf(context).width;
      final estimate = _offsetForPage(_paths.length, width);
      if (_scrollController.hasClients) {
        final currentMax = _scrollController.position.maxScrollExtent;
        final ceiling = currentMax > estimate ? currentMax : estimate;
        _scrollController.jumpTo(estimate.clamp(0.0, ceiling));
      }

      for (var attempt = 0; attempt < 24; attempt++) {
        if (!mounted || !_scrollController.hasClients) return;

        final max = _scrollController.position.maxScrollExtent;
        _scrollController.jumpTo(max);
        await WidgetsBinding.instance.endOfFrame;

        final endCtx = _endMarkerKey.currentContext;
        if (endCtx != null && endCtx.mounted) {
          await Scrollable.ensureVisible(
            endCtx,
            alignment: 1.0,
            duration: Duration.zero,
          );
          await WidgetsBinding.instance.endOfFrame;
        }

        if (!mounted || !_scrollController.hasClients) return;
        final newMax = _scrollController.position.maxScrollExtent;
        final newOffset = _scrollController.offset;
        final atBottom = newOffset >= newMax - 12;
        final maxStable = (newMax - max).abs() < 2;

        if (atBottom && maxStable) break;

        await Future<void>.delayed(
          Duration(milliseconds: attempt < 6 ? 48 : 80),
        );
      }

      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      _updateCurrentPage();
      _setPage(_paths.length);
    } finally {
      _scrollToBottomRunning = false;
      _jumpingToEnd.value = false;
    }
  }

  void _scheduleHideChrome() {
    _chromeTimer?.cancel();
    _chromeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) _setChrome(false);
    });
  }

  void _toggleChrome() {
    _setChrome(!_showChrome);
    if (_showChrome) {
      _scheduleHideChrome();
    } else {
      _chromeTimer?.cancel();
    }
  }

  /// 위·아래를 탭하면 한 화면씩 이동합니다. 더 갈 곳이 없으면 메뉴를 엽니다.
  void _onReaderTapUp(TapUpDetails details) {
    final height = MediaQuery.sizeOf(context).height;
    final y = details.localPosition.dy;
    if (y < height * 0.2) {
      if (!_pageViewport(-1)) _toggleChrome();
      return;
    }
    if (y > height * 0.68) {
      if (!_pageViewport(1)) _toggleChrome();
      return;
    }
    _toggleChrome();
  }

  bool _pageViewport(int direction) {
    if (!_scrollController.hasClients) return false;
    final position = _scrollController.position;
    final delta = position.viewportDimension * 0.88 * direction;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < 12) return false;
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
    return true;
  }

  Future<void> _openChapter(Chapter chapter, {bool startAtTop = true}) async {
    await _flushProgress();
    if (!mounted) return;
    var target = chapter;
    if (!target.canRead && target.isOnCloud) {
      setState(() => _resumingDownload = true);
      try {
        final prepared = await ChapterReader.prepare(
          seriesId: widget.seriesId,
          chapter: target,
          fetcher: _fetcher,
          bypassRunner: _bypass,
        );
        if (prepared == null || !mounted) return;
        target = prepared;
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('클라우드에서 열기 실패: $e')));
        return;
      } finally {
        if (mounted) setState(() => _resumingDownload = false);
      }
    }
    if (!mounted) return;
    if (target.canRead) {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ReaderScreen(
            seriesId: widget.seriesId,
            chapter: target,
            startAtTop: startAtTop,
          ),
        ),
      );
      return;
    }
    if (target.url.isEmpty) return;
    if (!ConnectivityService.instance.isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('오프라인입니다. 보관되지 않은 회차는 웹으로 열 수 없습니다.')),
      );
      return;
    }
    final series = _storage.getSeries(widget.seriesId);
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => WebViewReaderScreen(
          seriesId: widget.seriesId,
          seriesTitle: series?.title ?? '',
          chapter: target,
          startAtTop: startAtTop,
        ),
      ),
    );
  }

  void _jumpToTop() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _setPage(1);
    unawaited(
      _storage.saveProgress(
        widget.seriesId,
        ReadingProgress(
          chapterId: _chapter.id,
          scrollOffset: 0,
          pageIndex: 0,
          pageFraction: 0,
          completed: false,
          updatedAt: DateTime.now(),
        ),
      ),
    );
  }

  void _enforceTopIfNeeded() {
    if (!mounted || !widget.startAtTop || !_scrollController.hasClients) return;
    if (_scrollController.offset > 2) {
      _scrollController.jumpTo(0);
      _setPage(1);
    }
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
    _setChrome(true);
    _setPage(1);
    _scheduleHideChrome();
  }

  void _jumpToPage(int pageOneBased) {
    if (!_scrollController.hasClients || _paths.isEmpty) return;
    final index = (pageOneBased - 1).clamp(0, _paths.length - 1);
    final width = MediaQuery.sizeOf(context).width;
    final target = _offsetForPage(index, width);
    final max = _scrollController.position.maxScrollExtent;
    _scrollController.jumpTo(target.clamp(0.0, max));
    _setPage(index + 1);
    _setChrome(true);
    _precacheAround(index);
    _scheduleHideChrome();
    unawaited(_flushProgress());
  }

  void _saveProgress() {
    unawaited(_flushProgress());
  }

  Future<void> _flushProgress() async {
    final saved = _storage.getProgress(widget.seriesId, _chapter.id);
    final offset = _scrollController.hasClients
        ? _scrollController.offset
        : (_lastScrollOffset > 0
              ? _lastScrollOffset
              : saved?.scrollOffset ?? 0);

    int? pageIndex;
    var pageFraction = 0.0;
    if (_paths.isNotEmpty) {
      if (_scrollController.hasClients || _lastScrollOffset > 0) {
        final anchor = _pageAnchorFromOffset(offset);
        pageIndex = anchor.$1;
        pageFraction = anchor.$2;
      } else if (saved?.pageIndex != null) {
        pageIndex = saved!.pageIndex;
        pageFraction = saved.pageFraction;
      }
    }

    var completed = false;
    if (_paths.isNotEmpty && pageIndex != null) {
      final ratio = (pageIndex + pageFraction) / _paths.length;
      completed =
          ratio >= StorageService.completedPageProgress ||
          (_scrollController.hasClients && _isNearEnd());
    } else if (saved?.completed == true) {
      completed = true;
    }

    await _storage.saveProgress(
      widget.seriesId,
      ReadingProgress(
        chapterId: _chapter.id,
        scrollOffset: offset,
        pageIndex: pageIndex,
        pageFraction: pageFraction,
        completed: completed,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _restoreProgress() async {
    if (_restored) return;

    final saved = _storage.getProgress(widget.seriesId, _chapter.id);
    if (saved == null) {
      _restored = true;
      return;
    }

    if (saved.hasPageAnchor && saved.pageIndex! > 0 ||
        (saved.hasPageAnchor && saved.pageFraction > 0)) {
      _pendingRestorePage = saved.pageIndex!.clamp(0, _paths.length - 1);
      _pendingRestoreFraction = saved.pageFraction.clamp(0.0, 1.0);
      _tryApplyPendingRestore();
      // 레이아웃 안정 후 한 번 더
      Future<void>.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _tryApplyPendingRestore(force: true);
      });
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _tryApplyPendingRestore(force: true);
      });
      return;
    }

    if (saved.scrollOffset <= 0) {
      _restored = true;
      return;
    }

    _pendingLegacyOffset = saved.scrollOffset;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    _tryApplyPendingRestore(force: true);
  }

  void _tryApplyPendingRestore({bool force = false}) {
    if (_restored && !force) return;
    if (!_scrollController.hasClients || _paths.isEmpty) return;

    final width = MediaQuery.sizeOf(context).width;
    double target;

    if (_pendingRestorePage != null) {
      // 복원 지점 이전 컷의 실측 비율이 어느 정도 있을 때만 (또는 force)
      final need = _pendingRestorePage!;
      var known = 0;
      for (var i = 0; i < need && i < _aspectRatios.length; i++) {
        if (_aspectRatios[i] > 0.05) known++;
      }
      if (!force && need > 2 && known < (need * 0.4).ceil()) {
        return;
      }
      target = _offsetForPage(
        _pendingRestorePage!,
        width,
        fraction: _pendingRestoreFraction,
      );
    } else if (_pendingLegacyOffset != null) {
      target = _pendingLegacyOffset!;
    } else {
      return;
    }

    final max = _scrollController.position.maxScrollExtent;
    final clamped = target.clamp(0.0, max > 0 ? max : target);
    _scrollController.jumpTo(clamped);
    _updateCurrentPage();
    if (force || _pendingRestorePage == null) {
      _restored = true;
      _pendingRestorePage = null;
      _pendingLegacyOffset = null;
    }
  }

  Future<void> _openWebReader() async {
    final series = _storage.getSeries(widget.seriesId);
    if (_chapter.url.isEmpty || !mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => WebViewReaderScreen(
          seriesId: widget.seriesId,
          seriesTitle: series?.title ?? '',
          chapter: _chapter,
        ),
      ),
    );
  }

  Future<void> _resumeDownload() async {
    if (_resumingDownload) return;
    final blocked = await NetworkPolicy.instance.downloadBlockReason();
    if (blocked != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(blocked)));
      return;
    }

    setState(() => _resumingDownload = true);
    try {
      final saved = await _fetcher.fetchChapterImagesPublic(
        widget.seriesId,
        _chapter,
        onProgress: (status) {
          // 상태 배너는 전역 다운로드 칩으로 표시됩니다.
          if (status.phase == FetchPhase.error && mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(status.message)));
          }
        },
        bypassRunner: _bypass,
      );
      await CloudBackupQueue.instance.persistAndEnqueue(
        seriesId: widget.seriesId,
        chapter: saved,
      );
      if (!mounted) return;
      setState(() {
        _chapter = saved;
        _itemKeys = List.generate(saved.localPaths.length, (_) => GlobalKey());
        _aspectRatios = Chapter.alignAspectRatios(
          saved.pageAspectRatios,
          saved.localPaths.length,
        );
        _precacheQueued.clear();
        _precacheInFlight = 0;
        _resumingDownload = false;
      });
      _precacheAround(_currentPage - 1);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              saved.isDownloaded
                  ? '이어 받기 완료 · ${saved.localPaths.length}장'
                  : '일부 저장 · ${saved.localPaths.length}장',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _resumingDownload = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('이어 받기 실패: $e')));
      }
    }
  }

  Future<void> _goToNextAfterFinish() async {
    _autoAdvanced = true;
    await _storage.saveProgress(
      widget.seriesId,
      ReadingProgress(
        chapterId: _chapter.id,
        scrollOffset: _scrollController.hasClients
            ? _scrollController.offset
            : _lastScrollOffset,
        pageIndex: _paths.isEmpty ? null : _paths.length - 1,
        pageFraction: 1,
        completed: true,
        updatedAt: DateTime.now(),
      ),
    );
    final next = _nextChapter;
    if (next != null) {
      await _openChapter(next, startAtTop: true);
    }
  }

  Widget _buildReaderChrome({
    required int savedCount,
    required int? expectedCount,
    required bool showIncompleteHint,
    required int overlayTotal,
    required Chapter? previous,
    required Chapter? next,
  }) {
    return ListenableBuilder(
      listenable: _chromeListenable,
      builder: (context, _) {
        if (!_chromeVisible.value) return const SizedBox.shrink();
        final page = _pageIndex.value;
        final jumping = _jumpingToEnd.value;
        final top = MediaQuery.paddingOf(context).top + kToolbarHeight + 8;
        return Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AppBar(
                backgroundColor: Colors.black.withValues(alpha: 0.72),
                foregroundColor: Colors.white,
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _chapter.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _chapterIndexLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
                actions: const [
                  NetworkStatusChip(compact: true, light: true, iconOnly: true),
                  LockButton(),
                  SizedBox(width: 8),
                ],
              ),
            ),
            Positioned(
              right: 12,
              top: top,
              child: _ReaderJumpButton(
                icon: Icons.keyboard_arrow_up_rounded,
                label: '맨 위',
                onPressed: _scrollToTop,
              ),
            ),
            if (showIncompleteHint)
              Positioned(
                left: 16,
                right: 88,
                top: top,
                child: _PartialSaveBanner(
                  saved: savedCount,
                  total: expectedCount ?? savedCount,
                  resuming: _resumingDownload,
                  onResume: () => unawaited(_resumeDownload()),
                ),
              ),
            Positioned(
              left: 12,
              right: 12,
              bottom: MediaQuery.paddingOf(context).bottom + 8,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _ReaderJumpButton(
                    icon: jumping
                        ? Icons.hourglass_top_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    label: jumping ? '이동 중' : '맨 아래',
                    onPressed: jumping ? null : _scrollToBottom,
                  ),
                  if (savedCount > 0) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: _ReaderOverlay(
                        current: page,
                        total: overlayTotal,
                        savedCount: savedCount,
                        onScrub: savedCount > 1
                            ? (target) => _jumpToPage(target)
                            : null,
                      ),
                    ),
                  ],
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      '위·아래 탭은 한 화면 · 가운데 탭은 메뉴',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: _ReaderChapterBar(
                      previous: previous,
                      next: next,
                      label: _chapterIndexLabel,
                      onPrevious: previous == null
                          ? null
                          : () => unawaited(_openChapter(previous)),
                      onNext: next == null
                          ? null
                          : () => unawaited(_goToNextAfterFinish()),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final paths = _paths;
    final savedCount = paths.length;
    final expectedCount = _chapter.effectiveExpectedPageCount;
    final isPartial = _chapter.hasPartialDownload;
    final showIncompleteHint =
        isPartial || (expectedCount != null && expectedCount > savedCount);
    final overlayTotal = expectedCount ?? savedCount;
    final previous = _previousChapter;
    final next = _nextChapter;
    final width = MediaQuery.sizeOf(context).width;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _flushProgress();
        if (!context.mounted) return;
        Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: AppTheme.readerBackground,
        extendBodyBehindAppBar: true,
        body: paths.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('저장된 이미지가 없습니다.'),
                      if (_chapter.url.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _openWebReader,
                          icon: const Icon(Icons.language_rounded),
                          label: const Text('웹으로 읽기'),
                        ),
                      ],
                    ],
                  ),
                ),
              )
            : Stack(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: _onReaderTapUp,
                    child: ListView.builder(
                      key: ValueKey('reader-${_chapter.id}'),
                      controller: _scrollController,
                      padding: EdgeInsets.zero,
                      addAutomaticKeepAlives: false,
                      addRepaintBoundaries: true,
                      // 다음 컷을 미리 만들어 빠른 스크롤에서도 빈 화면이 덜 보이게 합니다.
                      scrollCacheExtent: ScrollCacheExtent.pixels(width * 2.2),
                      // 실측 비율이 있으면 정확한 extent, 없으면 기본 비율.
                      itemExtentBuilder: (index, dimensions) {
                        if (index >= paths.length) return _endMarkerHeight;
                        return _pageExtent(index, width);
                      },
                      itemCount: paths.length + 1,
                      itemBuilder: (context, index) {
                        if (index == paths.length) {
                          return KeyedSubtree(
                            key: _endMarkerKey,
                            child: _ReaderEndMarker(
                              savedCount: savedCount,
                              expectedCount: expectedCount,
                              showIncompleteHint: showIncompleteHint,
                              nextChapter: next,
                              resuming: _resumingDownload,
                              onOpenNext: next == null
                                  ? null
                                  : () => unawaited(_goToNextAfterFinish()),
                              onResumeDownload: showIncompleteHint
                                  ? () => unawaited(_resumeDownload())
                                  : null,
                            ),
                          );
                        }
                        final file = File(paths[index]);
                        return KeyedSubtree(
                          key: _itemKeys[index],
                          child: _ReaderPageImage(
                            file: file,
                            pageNumber: index + 1,
                            aspectHint: index < _aspectRatios.length
                                ? _aspectRatios[index]
                                : 0,
                            onLoaded: (aspect) => _onImageLoaded(index, aspect),
                          ),
                        );
                      },
                    ),
                  ),
                  _buildReaderChrome(
                    savedCount: savedCount,
                    expectedCount: expectedCount,
                    showIncompleteHint: showIncompleteHint,
                    overlayTotal: overlayTotal,
                    previous: previous,
                    next: next,
                  ),
                ],
              ),
      ),
    );
  }
}

class _ReaderPageImage extends StatefulWidget {
  const _ReaderPageImage({
    required this.file,
    required this.pageNumber,
    required this.onLoaded,
    this.aspectHint = 0,
  });

  final File file;
  final int pageNumber;
  final void Function(double aspectRatio) onLoaded;
  final double aspectHint;

  @override
  State<_ReaderPageImage> createState() => _ReaderPageImageState();
}

class _ReaderPageImageState extends State<_ReaderPageImage> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageInfo? _info;
  int? _cacheWidth;
  String? _resolvedPath;
  bool _failed = false;
  bool _notifiedLoaded = false;

  void _notifyLoadedOnce(double aspect) {
    if (_notifiedLoaded) return;
    _notifiedLoaded = true;
    widget.onLoaded(aspect);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant _ReaderPageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      _notifiedLoaded = false;
      _failed = false;
      _info = null;
      _resolveImage(force: true);
    }
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  void _stopListening() {
    final stream = _stream;
    final listener = _listener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _stream = null;
    _listener = null;
  }

  /// 화면 너비로 한 번만 디코드합니다. 크기 측정용 두 번째 디코드를 하지 않습니다.
  void _resolveImage({bool force = false}) {
    if (!mounted) return;
    final width = MediaQuery.sizeOf(context).width;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (width * dpr).round().clamp(1, 4096);
    if (!force &&
        _stream != null &&
        _cacheWidth == cacheWidth &&
        _resolvedPath == widget.file.path) {
      return;
    }
    _stopListening();
    _cacheWidth = cacheWidth;
    _resolvedPath = widget.file.path;
    final provider = ResizeImage(FileImage(widget.file), width: cacheWidth);
    final stream = provider.resolve(createLocalImageConfiguration(context));
    _stream = stream;
    final listener = ImageStreamListener(
      (info, sync) {
        if (!mounted) return;
        final w = info.image.width;
        final h = info.image.height;
        _failed = false;
        _info = info;
        if (!sync) setState(() {});
        _notifyLoadedOnce(w > 0 ? h / w : 1.35);
      },
      onError: (error, stack) {
        if (!mounted) return;
        _failed = true;
        _info = null;
        _notifyLoadedOnce(1.35);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      },
    );
    _listener = listener;
    stream.addListener(listener);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final placeholderHeight = widget.aspectHint > 0.05
        ? width * widget.aspectHint
        : width * 1.35;
    final image = _info?.image;

    final Widget child;
    if (_failed) {
      child = Container(
        color: Colors.grey.shade900,
        alignment: Alignment.center,
        child: Text(
          '이미지 ${widget.pageNumber} 로드 실패',
          style: const TextStyle(color: Colors.white70),
        ),
      );
    } else if (image == null) {
      child = const ColoredBox(color: Color(0xFF0A0A0A));
    } else {
      child = RawImage(
        image: image,
        width: width,
        height: placeholderHeight,
        fit: BoxFit.fitWidth,
        alignment: Alignment.topCenter,
        filterQuality: FilterQuality.low,
      );
    }

    return ProtectedContent(
      child: SizedBox(width: width, height: placeholderHeight, child: child),
    );
  }
}

class _ReaderChapterBar extends StatelessWidget {
  const _ReaderChapterBar({
    required this.label,
    required this.onPrevious,
    required this.onNext,
    this.previous,
    this.next,
  });

  final Chapter? previous;
  final Chapter? next;
  final String label;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xE6121212),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: previous == null
                  ? const SizedBox(height: 40)
                  : TextButton.icon(
                      onPressed: onPrevious,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.chevron_left_rounded),
                      label: Text('${previous!.number}화'),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            Expanded(
              child: next == null
                  ? const SizedBox(height: 40)
                  : TextButton.icon(
                      onPressed: onNext,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.chevron_right_rounded),
                      iconAlignment: IconAlignment.end,
                      label: Text('${next!.number}화'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderJumpButton extends StatelessWidget {
  const _ReaderJumpButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 26),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReaderEndMarker extends StatelessWidget {
  const _ReaderEndMarker({
    required this.savedCount,
    required this.expectedCount,
    required this.showIncompleteHint,
    this.nextChapter,
    this.onOpenNext,
    this.onResumeDownload,
    this.resuming = false,
  });

  final int savedCount;
  final int? expectedCount;
  final bool showIncompleteHint;
  final Chapter? nextChapter;
  final VoidCallback? onOpenNext;
  final VoidCallback? onResumeDownload;
  final bool resuming;

  @override
  Widget build(BuildContext context) {
    final expected = expectedCount;
    final incomplete =
        showIncompleteHint && expected != null && expected > savedCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
      child: Column(
        children: [
          Icon(
            incomplete
                ? Icons.warning_amber_rounded
                : Icons.check_circle_outline,
            color: incomplete ? Colors.amber : Colors.white54,
            size: 28,
          ),
          const SizedBox(height: 10),
          Text(
            incomplete
                ? '저장된 마지막 장 · $savedCount/$expected장'
                : '저장된 마지막 장 · $savedCount장',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: incomplete ? Colors.amber.shade200 : Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (incomplete) ...[
            const SizedBox(height: 6),
            const Text(
              '여기 아래는 받지 않은 장입니다.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            if (onResumeDownload != null) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: resuming ? null : onResumeDownload,
                icon: resuming
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_rounded),
                label: Text(resuming ? '받는 중...' : '이어 받기'),
              ),
            ],
          ] else ...[
            const SizedBox(height: 6),
            const Text(
              '스크롤이 여기서 끝나면 저장된 전체입니다.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
          if (nextChapter != null && onOpenNext != null) ...[
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onOpenNext,
              icon: const Icon(Icons.skip_next_rounded),
              label: Text('다음 화 · ${nextChapter!.number}화'),
            ),
          ],
        ],
      ),
    );
  }
}

class _PartialSaveBanner extends StatelessWidget {
  const _PartialSaveBanner({
    required this.saved,
    required this.total,
    required this.onResume,
    this.resuming = false,
  });

  final int saved;
  final int total;
  final VoidCallback onResume;
  final bool resuming;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.amber.shade900.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '일부 저장 · $saved/$total장',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton(
              onPressed: resuming ? null : onResume,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(resuming ? '받는 중' : '이어 받기'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderOverlay extends StatelessWidget {
  const _ReaderOverlay({
    required this.current,
    required this.total,
    required this.savedCount,
    this.onScrub,
  });

  final int current;
  final int total;
  final int savedCount;
  final void Function(int page)? onScrub;

  @override
  Widget build(BuildContext context) {
    final isPartial = savedCount < total;
    final maxPage = savedCount.clamp(1, total);
    final progress = total > 0 ? current / total : 0.0;
    final sliderValue = current.clamp(1, maxPage).toDouble();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  isPartial
                      ? '$current / $savedCount ($total장 중)'
                      : '$current / $total',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${(progress * 100).round()}%',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            if (onScrub != null && maxPage > 1) ...[
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 7,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
                  activeTrackColor: Theme.of(context).colorScheme.primary,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
                  thumbColor: Colors.white,
                ),
                child: Slider(
                  min: 1,
                  max: maxPage.toDouble(),
                  divisions: maxPage - 1,
                  value: sliderValue,
                  onChanged: (v) => onScrub!(v.round()),
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 4),
            ],
          ],
        ),
      ),
    );
  }
}
