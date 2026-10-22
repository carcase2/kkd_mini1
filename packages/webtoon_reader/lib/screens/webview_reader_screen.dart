import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/chapter.dart';
import '../models/reading_progress.dart';
import '../services/chapter_archive_queue.dart';
import '../services/lock_service.dart';
import '../services/storage_service.dart';
import '../services/webtoon_fetcher.dart';
import '../services/webview_scripts.dart';
import '../utils/site_url.dart';
import '../utils/webview_settings.dart';
import '../widgets/lock_button.dart';
import '../widgets/lock_activity_scope.dart';

class WebViewReaderScreen extends StatefulWidget {
  const WebViewReaderScreen({
    super.key,
    required this.seriesId,
    required this.seriesTitle,
    required this.chapter,
    this.startAtTop = false,
  });

  final String seriesId;
  final String seriesTitle;
  final Chapter chapter;
  final bool startAtTop;

  @override
  State<WebViewReaderScreen> createState() => _WebViewReaderScreenState();
}

class _WebViewReaderScreenState extends State<WebViewReaderScreen> {
  final _storage = StorageService.instance;
  final _fetcher = WebtoonFetcher();
  InAppWebViewController? _controller;
  Timer? _scrollSaveTimer;
  Timer? _archiveTimer;
  Timer? _comicWatchTimer;
  var _loading = true;
  var _cloudflare = false;
  var _readerModeActive = true;
  var _restoredScroll = false;
  var _archiving = false;
  var _adAckReloadAttempted = false;
  var _recoveringAdAck = false;
  var _chapterNotFoundReloadAttempted = false;
  var _bestCapturedCount = 0;
  String? _statusMessage;
  late Chapter _chapter;
  late List<Chapter> _chapters;
  double _lastScrollY = 0;

  @override
  void initState() {
    super.initState();
    LockService.instance.beginKeepAwake();
    _chapter = widget.chapter;
    _chapters = _storage.orderedChaptersForNavigation(widget.seriesId);
    final saved = _storage.getProgress(widget.seriesId, _chapter.id);
    _lastScrollY = saved?.scrollOffset ?? 0;
    _recordReading();
  }

  void _recordReading() {
    unawaited(_flushProgress());
  }

  Future<void> _flushProgress() async {
    final y = await _readScrollY() ?? _lastScrollY;
    _lastScrollY = y;
    var completed = false;
    final controller = _controller;
    if (controller != null) {
      try {
        final contentHeight = await controller.getContentHeight();
        final scrollY = await controller.getScrollY();
        if (contentHeight != null &&
            contentHeight > 0 &&
            scrollY != null &&
            scrollY >= contentHeight * 0.9) {
          completed = true;
        }
      } catch (_) {}
    }
    await _storage.saveProgress(
      widget.seriesId,
      ReadingProgress(
        chapterId: _chapter.id,
        scrollOffset: y,
        completed: completed,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<double?> _readScrollY() async {
    final controller = _controller;
    if (controller == null) return null;
    try {
      final y = await controller.getScrollY();
      if (y != null) return y.toDouble();
    } catch (_) {}
    return null;
  }

  void _onWebScrollChanged(int x, int y) {
    recordLockActivity();
    _lastScrollY = y.toDouble();
    _scrollSaveTimer?.cancel();
    _scrollSaveTimer = Timer(const Duration(milliseconds: 450), () {
      unawaited(_flushProgress());
    });
    _scheduleArchiveCapture();
  }

  void _scheduleArchiveCapture() {
    if (_chapter.isArchived || _cloudflare) return;
    _archiveTimer?.cancel();
    _archiveTimer = Timer(const Duration(seconds: 8), () {
      unawaited(_captureAndArchive(force: false));
    });
  }

  Future<void> _captureAndArchive({required bool force}) async {
    if (_archiving) return;
    if (_chapter.isOnCloud && _chapter.isDownloaded) return;
    if (_cloudflare) return;
    final controller = _controller;
    if (controller == null) return;

    _archiving = true;
    try {
      final raw = await controller.evaluateJavascript(
        source: WebViewScripts.extractImages,
      );
      final extracted = WebtoonFetcher.parseImageExtract(raw);
      if (extracted.urls.length <= _bestCapturedCount && !force) return;
      final enoughIdle = extracted.urls.length >= 8 ||
          (extracted.pageTotal != null &&
              extracted.pageTotal! > 0 &&
              extracted.urls.length >= (extracted.pageTotal! * 0.45).ceil());
      if (!force && !enoughIdle) return;
      if (force && extracted.urls.length < 3) return;

      _bestCapturedCount = extracted.urls.length;
      ChapterArchiveQueue.instance.enqueue(
        seriesId: widget.seriesId,
        chapter: _chapter,
        imageUrls: extracted.urls,
        pageTotal: extracted.pageTotal,
      );
    } catch (e) {
      debugPrint('Web reader archive skipped: $e');
    } finally {
      _archiving = false;
    }
  }

  Future<void> _restoreScrollIfNeeded() async {
    if (_restoredScroll || widget.startAtTop) {
      _restoredScroll = true;
      return;
    }
    final target = _storage
            .getProgress(widget.seriesId, _chapter.id)
            ?.scrollOffset ??
        _lastScrollY;
    if (target <= 0) {
      _restoredScroll = true;
      return;
    }
    final controller = _controller;
    if (controller == null) return;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await controller.scrollTo(x: 0, y: target.round());
      await controller.evaluateJavascript(
        source: 'window.scrollTo(0, ${target.round()});',
      );
      _lastScrollY = target;
    } catch (_) {}
    _restoredScroll = true;
  }

  @override
  void dispose() {
    _scrollSaveTimer?.cancel();
    _archiveTimer?.cancel();
    _comicWatchTimer?.cancel();
    unawaited(_flushProgress());
    LockService.instance.endKeepAwake();
    super.dispose();
  }

  void _syncChapterFromUrl(String? url) {
    final matched = Chapter.findByPageUrl(_chapters, url);
    if (matched == null || matched.id == _chapter.id) return;
    _adAckReloadAttempted = false;
    _chapterNotFoundReloadAttempted = false;
    setState(() => _chapter = matched);
    _recordReading();
  }

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

  Future<void> _applyReaderMode() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.evaluateJavascript(source: WebViewScripts.applyReaderMode);
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _measureContent() async {
    final controller = _controller;
    if (controller == null) return null;
    try {
      final raw = await controller.evaluateJavascript(
        source: WebViewScripts.measureReaderContent,
      );
      if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      }
    } catch (_) {}
    return null;
  }

  int _metricInt(Map<String, dynamic>? metrics, String key) {
    return (metrics?[key] as num?)?.toInt() ?? 0;
  }

  bool _metricBool(Map<String, dynamic>? metrics, String key) {
    final value = metrics?[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      return value == 'true' || value == '1';
    }
    return false;
  }

  Future<void> _disableReaderMode({bool keepPreference = false}) async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.evaluateJavascript(source: WebViewScripts.disableReaderMode);
    } catch (_) {}
    if (!keepPreference && mounted) {
      setState(() => _readerModeActive = false);
    }
  }

  Future<void> _enableReaderMode() async {
    if (mounted) setState(() => _readerModeActive = true);
    final metrics = await _measureContent();
    if (!mounted) return;
    if (_metricInt(metrics, 'visibleImages') <= 0) {
      setState(() => _statusMessage = '만화가 보이면 읽기 모드로 전환합니다');
      _startComicWatch();
      return;
    }
    await _applyReaderMode();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _applyReaderMode();
    await _triggerLazyLoad();
    await _ensureReadableContent(allowFallback: true);
  }

  Future<void> _ensureReadableContent({required bool allowFallback}) async {
    final metrics = await _measureContent();
    if (!mounted) return;

    final visibleImages = _metricInt(metrics, 'visibleImages');
    final scrollHeight = _metricInt(metrics, 'scrollHeight');
    final adBlocked = _metricBool(metrics, 'adVerificationBlocked');

    if (visibleImages > 0) {
      if (_statusMessage == '본문을 찾지 못해 원본 페이지로 표시합니다' ||
          _statusMessage == '광고 확인 후 만화를 불러오는 중...') {
        setState(() => _statusMessage = '아래로 스크롤해 읽어 주세요');
      }
      return;
    }

    if (adBlocked) {
      await _recoverAdVerification();
      return;
    }

    if (allowFallback && _readerModeActive) {
      await _disableReaderMode(keepPreference: true);
      if (!mounted) return;
      setState(() {
        _statusMessage = scrollHeight < 240
            ? '페이지 본문이 비어 있습니다. 새로고침하거나 잠시 후 다시 시도해 주세요'
            : '만화 이미지를 확인하는 중...';
      });
      _startComicWatch();
    }
  }

  Future<bool> _applyReaderModeIfReady() async {
    if (!_readerModeActive) return false;
    final metrics = await _measureContent();
    if (!mounted) return false;
    if (_metricBool(metrics, 'adVerificationBlocked')) return false;
    if (_metricInt(metrics, 'visibleImages') <= 0) return false;
    await _applyReaderMode();
    if (mounted) {
      setState(() => _statusMessage = '아래로 스크롤해 읽어 주세요');
    }
    return true;
  }

  void _startComicWatch() {
    _comicWatchTimer?.cancel();
    var ticks = 0;
    _comicWatchTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      ticks++;
      unawaited(_onComicWatchTick(ticks));
    });
  }

  Future<void> _onComicWatchTick(int ticks) async {
    if (!mounted || _loading || _cloudflare) return;
    final metrics = await _measureContent();
    if (!mounted) return;

    if (_metricInt(metrics, 'visibleImages') > 0) {
      _comicWatchTimer?.cancel();
      await _applyReaderModeIfReady();
      return;
    }

    if (await _pageLooksNotFound()) {
      _comicWatchTimer?.cancel();
      if (await _recoverVisibleNotFound()) return;
    }

    if (_metricBool(metrics, 'adVerificationBlocked')) {
      _comicWatchTimer?.cancel();
      await _recoverAdVerification();
      return;
    }

    if (ticks >= 25) {
      _comicWatchTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _statusMessage = '본문을 찾지 못해 원본 페이지로 표시합니다';
      });
    }
  }

  Future<void> _waitForComicOrAdGate() async {
    // 마인드컨트롤 등 일부 만화는 광고 검증이 8~10초 걸립니다.
    for (var i = 0; i < 30; i++) {
      if (!mounted) return;
      if (await _pageLooksNotFound()) {
        await _recoverVisibleNotFound();
        return;
      }
      final metrics = await _measureContent();
      if (_metricInt(metrics, 'visibleImages') > 0) return;
      if (_metricBool(metrics, 'adVerificationBlocked')) return;
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  }

  bool _jsFlag(dynamic raw) =>
      raw == true || raw == 1 || raw?.toString() == 'true';

  Future<bool> _pageLooksNotFound() async {
    final controller = _controller;
    if (controller == null) return false;
    try {
      final raw = await controller.evaluateJavascript(
        source: WebViewScripts.isVisibleNotFoundPage,
      );
      return _jsFlag(raw);
    } catch (_) {
      return false;
    }
  }

  URLRequest _chapterRequest(String url) {
    final seriesUrl = _storage.getSeries(widget.seriesId)?.url;
    return URLRequest(
      url: WebUri(
        SiteUrl.preferAllowedHost(url),
        forceToStringRawValue: true,
      ),
      headers: {
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        if (seriesUrl != null && seriesUrl.isNotEmpty) 'Referer': seriesUrl,
      },
    );
  }

  Future<Chapter?> _resolveRemoteChapter() async {
    final series = _storage.getSeries(widget.seriesId);
    if (series == null) return null;
    try {
      final result = await _fetcher.fetchChapterListViaHttp(series.url);
      if (result == null || result.chapters.isEmpty) return null;
      for (final chapter in result.chapters) {
        if (chapter.number == _chapter.number) return chapter;
      }
      for (final chapter in result.chapters) {
        if (chapter.id == _chapter.id) return chapter;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _persistResolvedChapter(Chapter remote) async {
    final updated = _chapter.copyWith(
      id: remote.id,
      title: remote.title,
      url: remote.url,
    );
    final chapters = _storage.getChapters(widget.seriesId);
    final index = chapters.indexWhere(
      (c) => c.id == _chapter.id || c.number == _chapter.number,
    );
    if (index >= 0) {
      chapters[index] = updated;
      await _storage.saveChapters(widget.seriesId, chapters);
    } else {
      await _storage.upsertChapter(widget.seriesId, updated);
    }
    if (!mounted) return;
    setState(() {
      _chapter = updated;
      _chapters = _storage.orderedChaptersForNavigation(widget.seriesId);
    });
  }

  Future<bool> _recoverVisibleNotFound({bool fromHttp404 = false}) async {
    final controller = _controller;
    if (controller == null || _chapterNotFoundReloadAttempted) return false;
    if (!fromHttp404 && !await _pageLooksNotFound()) return false;

    _chapterNotFoundReloadAttempted = true;
    if (!mounted) return true;
    setState(() {
      _loading = true;
      _statusMessage = '회차 주소를 다시 확인하는 중...';
    });

    final remote = await _resolveRemoteChapter();
    if (!mounted) return true;
    var targetUrl = _chapter.url;
    if (remote != null) {
      if (remote.url != _chapter.url || remote.id != _chapter.id) {
        await _persistResolvedChapter(remote);
        targetUrl = remote.url;
      } else {
        targetUrl = remote.url;
      }
    }

    try {
      await controller.loadUrl(urlRequest: _chapterRequest(targetUrl));
    } catch (_) {
      await controller.reload();
    }
    return true;
  }

  Future<void> _recoverAdVerification() async {
    if (!mounted || _recoveringAdAck) return;
    _recoveringAdAck = true;
    try {
      await _disableReaderMode(keepPreference: true);
      if (!mounted) return;
      setState(() {
        _statusMessage = '광고 확인 후 만화를 불러오는 중...';
      });

      final controller = _controller;
      var clicked = false;
      if (controller != null) {
        try {
          final raw = await controller.evaluateJavascript(
            source: WebViewScripts.clickAdVerificationRetry,
          );
          clicked = raw == true || raw == 1 || raw?.toString() == 'true';
        } catch (_) {}
      }

      if (clicked) {
        await Future<void>.delayed(const Duration(seconds: 2));
        await _waitForComicOrAdGate();
        if (!mounted) return;
        if (await _applyReaderModeIfReady()) return;
      }

      final after = await _measureContent();
      if (!mounted) return;
      if (_metricInt(after, 'visibleImages') > 0) {
        await _applyReaderModeIfReady();
        return;
      }

      if (!_adAckReloadAttempted) {
        _adAckReloadAttempted = true;
        setState(() {
          _loading = true;
          _statusMessage = '광고 확인을 위해 페이지를 다시 여는 중...';
        });
        await _controller?.reload();
        return;
      }

      setState(() {
        _statusMessage = '본문을 찾지 못해 원본 페이지로 표시합니다';
      });
      _startComicWatch();
    } finally {
      _recoveringAdAck = false;
    }
  }

  Future<void> _triggerLazyLoad() async {
    final controller = _controller;
    if (controller == null) return;

    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      try {
        final raw = await controller.evaluateJavascript(
          source: WebViewScripts.readerLazyLoadScroll,
        );
        if (raw is Map && raw['done'] == true) break;
      } catch (_) {}
      if (_readerModeActive) {
        final metrics = await _measureContent();
        if (_metricInt(metrics, 'visibleImages') > 0 &&
            !_metricBool(metrics, 'adVerificationBlocked')) {
          await _applyReaderMode();
        }
      }
    }
  }

  Future<void> _refreshPageState(WebUri? loadedUrl) async {
    final controller = _controller;
    if (controller == null) return;
    _comicWatchTimer?.cancel();

    final currentUrl =
        loadedUrl?.toString() ?? (await controller.getUrl())?.toString();
    _syncChapterFromUrl(currentUrl);

    final html = await controller.getHtml();
    final cloudflare = WebViewScripts.isCloudflareHtml(html);
    final adBlocked = WebViewScripts.isAdVerificationHtml(html);

    if (!mounted) return;
    setState(() {
      _cloudflare = cloudflare;
      _loading = false;
      _statusMessage = cloudflare
          ? '보안 확인이 보이면 완료될 때까지 기다려 주세요'
          : adBlocked
              ? '광고 확인 후 만화를 불러오는 중...'
              : '만화 이미지를 확인하는 중...';
    });

    if (cloudflare) return;

    // Soft navigation이 Not Found UI를 그리면 하드 로드로 한 번 복구합니다.
    if (await _recoverVisibleNotFound()) return;
    if (!mounted) return;

    // 광고 검증이 끝나기 전에 읽기 모드를 켜면 본문 이미지가 403이 됩니다.
    await _disableReaderMode(keepPreference: true);
    await _waitForComicOrAdGate();
    if (!mounted) return;

    final metrics = await _measureContent();
    if (_metricBool(metrics, 'adVerificationBlocked') || adBlocked) {
      if (_metricInt(metrics, 'visibleImages') <= 0) {
        await _recoverAdVerification();
        if (widget.startAtTop) {
          await _scrollWebViewToTop();
        } else {
          await _restoreScrollIfNeeded();
        }
        return;
      }
    }

    if (_metricInt(metrics, 'visibleImages') > 0) {
      if (_readerModeActive) {
        await _applyReaderMode();
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await _applyReaderMode();
      }
      await _triggerLazyLoad();
      await _ensureReadableContent(allowFallback: _readerModeActive);
    } else {
      await _ensureReadableContent(allowFallback: _readerModeActive);
      if (_metricInt(await _measureContent(), 'visibleImages') <= 0) {
        _startComicWatch();
      }
    }
    if (widget.startAtTop) {
      await _scrollWebViewToTop();
    } else {
      await _restoreScrollIfNeeded();
    }
  }

  Future<void> _scrollWebViewToTop() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.scrollTo(x: 0, y: 0);
      await controller.evaluateJavascript(source: 'window.scrollTo(0, 0);');
    } catch (_) {}
  }

  Future<void> _toggleReaderMode() async {
    if (_readerModeActive) {
      await _disableReaderMode();
      if (!mounted) return;
      setState(() {
        _statusMessage = '원본 페이지로 표시합니다';
      });
      await _triggerLazyLoad();
      await _ensureReadableContent(allowFallback: false);
      return;
    }
    await _enableReaderMode();
  }

  Future<void> _openChapter(Chapter chapter) async {
    _archiveTimer?.cancel();
    await _captureAndArchive(force: true);
    await _flushProgress();
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => WebViewReaderScreen(
          seriesId: widget.seriesId,
          seriesTitle: widget.seriesTitle,
          chapter: chapter,
          startAtTop: true,
        ),
      ),
    );
  }

  Future<void> _reload() async {
    _comicWatchTimer?.cancel();
    _adAckReloadAttempted = false;
    _chapterNotFoundReloadAttempted = false;
    setState(() {
      _loading = true;
      _readerModeActive = true;
      _statusMessage = '새로고침 중...';
    });
    await _controller?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final previous = _previousChapter;
    final next = _nextChapter;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        _archiveTimer?.cancel();
        await _captureAndArchive(force: true);
        await _flushProgress();
        if (!context.mounted) return;
        Navigator.of(context).pop();
      },
      child: Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.85),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.seriesTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
            Text(
              '$_chapterIndexLabel · ${_chapter.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _readerModeActive ? '원본 페이지 보기' : '읽기 모드',
            onPressed: _controller == null || _loading ? null : _toggleReaderMode,
            icon: Icon(_readerModeActive ? Icons.web_asset_off_outlined : Icons.menu_book_outlined),
          ),
          IconButton(
            tooltip: '새로고침',
            onPressed: _controller == null ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
          const LockButton(),
        ],
      ),
      body: Column(
        children: [
          if (_statusMessage != null)
            Material(
              color: _cloudflare
                  ? Theme.of(context).colorScheme.tertiaryContainer
                  : Colors.black.withValues(alpha: 0.6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    if (_cloudflare)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(
                          Icons.shield_outlined,
                          size: 18,
                          color: Theme.of(context).colorScheme.onTertiaryContainer,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        _statusMessage!,
                        style: TextStyle(
                          fontSize: 13,
                          color: _cloudflare
                              ? Theme.of(context).colorScheme.onTertiaryContainer
                              : Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: InAppWebView(
                    initialUrlRequest: _chapterRequest(_chapter.url),
                    initialSettings: createWebViewSettings(disableContextMenu: false),
                    initialUserScripts: UnmodifiableListView([
                      UserScript(
                        source: WebViewScripts.readerModeEarlyCss,
                        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                      ),
                      UserScript(
                        source: WebViewScripts.recoverClientNotFound,
                        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                      ),
                    ]),
                  onWebViewCreated: (controller) => _controller = controller,
                  onRenderProcessGone: (controller, detail) {
                    logRenderProcessGone(controller, detail);
                    if (!mounted) return;
                    setState(() {
                      _loading = false;
                      _statusMessage =
                          '브라우저가 종료되었습니다. 새로고침 후 다시 시도해 주세요.';
                    });
                  },
                  onLoadStart: (_, _) {
                    if (!mounted) return;
                    _comicWatchTimer?.cancel();
                    setState(() {
                      _loading = true;
                      _statusMessage = '페이지 로드 중...';
                    });
                  },
                  onLoadStop: (controller, url) => _refreshPageState(url),
                  onUpdateVisitedHistory: (controller, url, _) {
                    recordLockActivity();
                    _syncChapterFromUrl(url?.toString());
                  },
                  onScrollChanged: (_, x, y) => _onWebScrollChanged(x, y),
                  onReceivedError: (_, request, error) {
                    if (!mounted) return;
                    if (shouldIgnoreWebViewError(request, error)) return;
                    setState(() {
                      _loading = false;
                      _statusMessage = '로드 오류: ${error.description}';
                    });
                  },
                  onReceivedHttpError: (controller, request, errorResponse) {
                    if (request.isForMainFrame == false) return;
                    if (errorResponse.statusCode != 404) return;
                    unawaited(_recoverVisibleNotFound(fromHttp404: true));
                  },
                ),
                ),
                if (_loading)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
          Material(
              color: Colors.black.withValues(alpha: 0.9),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: previous != null
                            ? _WebChapterNavButton(
                                icon: Icons.chevron_left_rounded,
                                label: '${previous.number}화',
                                onPressed: () => _openChapter(previous),
                                tonal: true,
                              )
                            : const SizedBox(height: 40),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          _chapterIndexLabel,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      Expanded(
                        child: next != null
                            ? _WebChapterNavButton(
                                icon: Icons.chevron_right_rounded,
                                label: '${next.number}화',
                                iconAfterLabel: true,
                                onPressed: () => _openChapter(next),
                              )
                            : const SizedBox(height: 40),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }
}

class _WebChapterNavButton extends StatelessWidget {
  const _WebChapterNavButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.iconAfterLabel = false,
    this.tonal = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool iconAfterLabel;
  final bool tonal;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );
    final iconWidget = Icon(icon, size: 20);

    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: iconAfterLabel
          ? [
              Flexible(child: text),
              const SizedBox(width: 2),
              iconWidget,
            ]
          : [
              iconWidget,
              const SizedBox(width: 2),
              Flexible(child: text),
            ],
    );

    final style = FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      minimumSize: const Size(0, 40),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );

    if (tonal) {
      return FilledButton.tonal(
        onPressed: onPressed,
        style: style.copyWith(
          foregroundColor: WidgetStateProperty.all(Colors.white),
          backgroundColor: WidgetStateProperty.all(
            Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: content,
      );
    }

    return FilledButton(
      onPressed: onPressed,
      style: style,
      child: content,
    );
  }
}
