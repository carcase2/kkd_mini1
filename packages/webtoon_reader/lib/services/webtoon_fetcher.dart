import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../constants.dart';
import '../models/chapter.dart';
import '../models/fetch_controller.dart';
import '../models/fetch_status.dart';
import '../models/series.dart';
import '../models/sync_result.dart';
import '../models/webview_bypass_runner.dart';
import 'storage_service.dart';
import 'chapter_list_parser.dart';
import 'webview_scripts.dart';
import 'lock_service.dart';
import 'cloud_backup_queue.dart';
import 'download_activity_service.dart';
import 'r2_webtoon_store.dart';
import '../utils/site_url.dart';
import '../utils/webview_settings.dart';

class WebtoonFetcher {
  WebtoonFetcher({StorageService? storage, R2WebtoonStore? cloudStore})
      : _storage = storage ?? StorageService.instance,
        _cloudStore = cloudStore ?? R2WebtoonStore.instance;

  static const _minPanelFileBytes = 8192;
  /// 회차 이미지 동시 다운로드 수. 사이트/CDN 부담과 속도 균형.
  static const _imageDownloadConcurrency = 6;

  final StorageService _storage;
  final R2WebtoonStore _cloudStore;
  FetchController? _active;

  Future<void> cancel() async => _active?.cancel();

  FetchController _startOperation() {
    final controller = FetchController();
    _active = controller;
    return controller;
  }

  void _endOperation(FetchController controller) {
    if (identical(_active, controller)) {
      _active = null;
    }
  }

  Future<T> _runGuarded<T>(Future<T> Function(FetchController controller) fn) async {
    final controller = _startOperation();
    LockService.instance.beginKeepAwake();
    DownloadActivityService.instance.beginOperation();
    try {
      return await fn(controller);
    } on FetchCancelledException {
      rethrow;
    } finally {
      LockService.instance.endKeepAwake();
      DownloadActivityService.instance.endOperation();
      _endOperation(controller);
    }
  }
  final Dio _dio = Dio(
    BaseOptions(
      headers: {'User-Agent': AppConstants.userAgent},
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
    ),
  );

  Future<Series> registerSeries(
    String url, {
    String? customTitle,
    void Function(FetchStatus status)? onProgress,
    WebViewBypassRunner? bypassRunner,
  }) async {
    return _runGuarded((controller) async {
      final resolved = await _resolveSeriesUrl(
        url,
        controller: controller,
        onProgress: onProgress,
      );
      final normalized = resolved.url;
      final id = Series.idFromUrl(normalized);
      final existing = _storage.getSeries(id);
      final userTitle = customTitle?.trim();

      if (userTitle != null && userTitle.isNotEmpty) {
        String? coverUrl;
        try {
          final meta = await fetchSeriesMetaViaHttp(normalized);
          coverUrl = meta?.coverUrl?.trim();
        } catch (_) {}
        if (coverUrl == null || coverUrl.isEmpty) {
          try {
            _emit(onProgress, FetchPhase.parsing, '대표 이미지 확인 중...');
            final titleJson = await _runInWebView(
              normalized,
              WebViewScripts.extractTitle,
              controller: controller,
              onProgress: onProgress,
              phase: FetchPhase.parsing,
              parsingMessage: '대표 이미지 확인 중...',
              bypassRunner: bypassRunner,
              operationTimeout: const Duration(seconds: 30),
            );
            controller.check();
            final titleMap =
                Map<String, dynamic>.from(jsonDecode(titleJson) as Map);
            coverUrl = (titleMap['coverUrl'] as String?)?.trim();
          } catch (_) {}
        }

        return _registerAndSyncChapters(
          series: await _saveRegisteredSeries(
            normalized: normalized,
            id: id,
            existing: existing,
            title: userTitle,
            coverUrl: coverUrl,
            referer: normalized,
            controller: controller,
          ),
          controller: controller,
          onProgress: onProgress,
          bypassRunner: bypassRunner,
          prefetchedChapters: resolved.chapters,
        );
      }

      _emit(onProgress, FetchPhase.connecting, '제목 불러오는 중...');
      String title = id;
      String? coverUrl;
      try {
        final meta = await fetchSeriesMetaViaHttp(normalized);
        title = _normalizeTitle(meta?.title, id);
        coverUrl = meta?.coverUrl?.trim();
      } catch (_) {}

      if (title == id) {
        final titleJson = await _runInWebView(
          normalized,
          WebViewScripts.extractTitle,
          controller: controller,
          onProgress: onProgress,
          phase: FetchPhase.parsing,
          parsingMessage: '제목 확인 중...',
          bypassRunner: bypassRunner,
        );
        controller.check();
        final titleMap = Map<String, dynamic>.from(jsonDecode(titleJson) as Map);
        title = _normalizeTitle(titleMap['title'] as String?, id);
        coverUrl ??= (titleMap['coverUrl'] as String?)?.trim();
      }

      return _registerAndSyncChapters(
        series: await _saveRegisteredSeries(
          normalized: normalized,
          id: id,
          existing: existing,
          title: title,
          coverUrl: coverUrl,
          referer: normalized,
          controller: controller,
        ),
        controller: controller,
        onProgress: onProgress,
        bypassRunner: bypassRunner,
        prefetchedChapters: resolved.chapters,
      );
    });
  }

  Future<Series> _registerAndSyncChapters({
    required Series series,
    required FetchController controller,
    void Function(FetchStatus status)? onProgress,
    WebViewBypassRunner? bypassRunner,
    ChapterListFetchResult? prefetchedChapters,
  }) async {
    final sync = await syncChapterList(
      series,
      controller: controller,
      onProgress: onProgress,
      bypassRunner: bypassRunner,
      prefetchedChapters: prefetchedChapters,
    );
    if (sync.errors.isNotEmpty) {
      debugPrint('Chapter sync after register: ${sync.errors.first}');
    }
    return _storage.getSeries(series.id) ?? series;
  }

  Future<Series> _saveRegisteredSeries({
    required String normalized,
    required String id,
    required Series? existing,
    required String title,
    String? coverUrl,
    String? referer,
    FetchController? controller,
  }) async {
    var series =
        (existing ?? Series(id: id, url: normalized, title: title)).copyWith(
      url: normalized,
      title: title,
      addedAt: existing?.addedAt ?? DateTime.now(),
    );
    if (coverUrl != null && coverUrl.isNotEmpty) {
      final coverPath = await _cacheSeriesCover(
        id,
        coverUrl,
        referer: referer ?? normalized,
        controller: controller,
      );
      series = series.copyWith(
        coverUrl: coverUrl,
        coverPath: coverPath ?? existing?.coverPath,
      );
    }
    await _storage.upsertSeries(series);
    return _storage.getSeries(id) ?? series;
  }

  String _normalizeTitle(String? raw, String fallbackId) {
    final title = raw?.trim();
    if (title == null || title.isEmpty) return fallbackId;
    if (title.startsWith('u-tt-') || title.startsWith('tt-')) return fallbackId;
    return title;
  }

  Future<Series> addSeriesFromUrl(
    String url, {
    String? customTitle,
    void Function(FetchStatus status)? onProgress,
    WebViewBypassRunner? bypassRunner,
  }) {
    return registerSeries(
      url,
      customTitle: customTitle,
      onProgress: onProgress,
      bypassRunner: bypassRunner,
    );
  }

  Future<Series> relinkSeries(
    String seriesId,
    String newUrl, {
    String? customTitle,
    void Function(FetchStatus status)? onProgress,
    WebViewBypassRunner? bypassRunner,
  }) {
    return _runGuarded((controller) async {
      final existing = _storage.getSeries(seriesId);
      if (existing == null) {
        throw Exception('만화를 찾을 수 없습니다.');
      }

      final normalized = Series.normalizeUrl(newUrl);
      final userTitle = customTitle?.trim();
      var title = userTitle?.isNotEmpty == true ? userTitle! : existing.title;

      final resolved = await _resolveSeriesUrl(
        normalized,
        controller: controller,
        onProgress: onProgress,
      );
      final workingUrl = resolved.url;

      if (userTitle == null || userTitle.isEmpty) {
        _emit(onProgress, FetchPhase.connecting, '새 링크 연결 중...');
        final titleJson = await _runInWebView(
          workingUrl,
          WebViewScripts.extractTitle,
          controller: controller,
          onProgress: onProgress,
          phase: FetchPhase.parsing,
          parsingMessage: '제목 확인 중...',
          bypassRunner: bypassRunner,
        );
        controller.check();
        final titleMap = Map<String, dynamic>.from(jsonDecode(titleJson) as Map);
        title = titleMap['title'] as String? ?? existing.title;
        final coverUrl = titleMap['coverUrl'] as String?;
        var updated = existing.copyWith(url: workingUrl, title: title);
        if (coverUrl != null && coverUrl.isNotEmpty) {
          final coverPath = await _cacheSeriesCover(
            seriesId,
            coverUrl,
            referer: workingUrl,
            controller: controller,
          );
          updated = updated.copyWith(
            coverUrl: coverUrl,
            coverPath: coverPath ?? existing.coverPath,
          );
        }
        await _storage.upsertSeries(updated);
      } else {
        _emit(onProgress, FetchPhase.connecting, '"$title" 링크 연결 중...');
        final updated = existing.copyWith(url: workingUrl, title: title);
        await _storage.upsertSeries(updated);
      }

      final current = _storage.getSeries(seriesId) ?? existing;

      await syncChapterList(
        current,
        controller: controller,
        onProgress: onProgress,
        relink: true,
        bypassRunner: bypassRunner,
        prefetchedChapters: resolved.chapters,
      );
      return _storage.getSeries(seriesId) ?? current;
    });
  }

  Future<Series> autoRepairSeriesUrl(
    String seriesId, {
    void Function(FetchStatus status)? onProgress,
    WebViewBypassRunner? bypassRunner,
  }) async {
    final existing = _storage.getSeries(seriesId);
    if (existing == null) {
      throw Exception('만화를 찾을 수 없습니다.');
    }
    final repairedUrl = await _guessRepairedSeriesUrl(existing.url);
    if (repairedUrl == null) {
      throw Exception(
        '자동 복구에 실패했습니다. 링크 수정에서 전체 주소를 입력해 주세요.',
      );
    }
    return relinkSeries(
      seriesId,
      repairedUrl,
      onProgress: onProgress,
      bypassRunner: bypassRunner,
    );
  }

  Future<SyncResult> syncChapterList(
    Series series, {
    required FetchController controller,
    void Function(FetchStatus status)? onProgress,
    bool relink = false,
    WebViewBypassRunner? bypassRunner,
    ChapterListFetchResult? prefetchedChapters,
  }) async {
    final localBefore = _storage.getChapters(series.id);

    try {
      controller.check();
      _emit(
        onProgress,
        FetchPhase.parsing,
        '${series.title} 회차 목록 확인 중...',
      );
      final remoteChapters = prefetchedChapters ??
          await fetchChapterList(
            series,
            controller: controller,
            onProgress: onProgress,
            bypassRunner: bypassRunner,
          );
      controller.check();
      if (remoteChapters.chapters.isEmpty) {
        return SyncResult(
          errors: [
            '${series.title}: 회차를 찾지 못했습니다. '
            '${_seriesUrlRepairHint(series.url) ?? '링크를 확인해 주세요.'}',
          ],
        );
      }

      var updatedSeries = series;
      final chapterUrl = remoteChapters.chapters.first.url;
      final safeChapterUrl = SiteUrl.preferAllowedHost(chapterUrl);
      final resolvedSeriesUrl =
          Series.parentSeriesUrlFromChapterUrl(safeChapterUrl);
      if (resolvedSeriesUrl != null &&
          resolvedSeriesUrl != updatedSeries.url) {
        updatedSeries = updatedSeries.copyWith(url: resolvedSeriesUrl);
      }
      final chapterHost = Uri.tryParse(safeChapterUrl)?.host;
      final seriesHost = Uri.tryParse(updatedSeries.url)?.host;
      if (chapterHost != null &&
          seriesHost != null &&
          chapterHost.isNotEmpty &&
          chapterHost != seriesHost &&
          !AppConstants.blockedFetchHosts.contains(chapterHost)) {
        updatedSeries = updatedSeries.copyWith(
          url: SiteUrl.rewriteHost(
            updatedSeries.url,
            seriesHost,
            'https://$chapterHost',
          ),
        );
      }
      // Host error 나는 미러(sbxh10 등)로 저장되지 않게 강제 교정합니다.
      final safeSeriesUrl = SiteUrl.preferAllowedHost(updatedSeries.url);
      if (safeSeriesUrl != updatedSeries.url) {
        updatedSeries = updatedSeries.copyWith(url: safeSeriesUrl);
      }
      final fetchedTitle = remoteChapters.seriesTitle;
      if (fetchedTitle != null && fetchedTitle.isNotEmpty) {
        final normalizedTitle = _normalizeTitle(fetchedTitle, series.id);
        if (normalizedTitle != series.id && normalizedTitle != series.title) {
          updatedSeries = updatedSeries.copyWith(title: normalizedTitle);
        }
      }
      var coverUrl = remoteChapters.coverUrl?.trim();
      if (coverUrl == null || coverUrl.isEmpty) {
        try {
          final meta = await fetchSeriesMetaViaHttp(updatedSeries.url);
          coverUrl = meta?.coverUrl?.trim();
        } catch (_) {}
      }
      if (coverUrl == null || coverUrl.isEmpty) {
        try {
          final titleJson = await _runInWebView(
            updatedSeries.url,
            WebViewScripts.extractTitle,
            controller: controller,
            onProgress: onProgress,
            phase: FetchPhase.parsing,
            parsingMessage: '대표 이미지 확인 중...',
            bypassRunner: bypassRunner,
            operationTimeout: const Duration(seconds: 30),
          );
          controller.check();
          final titleMap =
              Map<String, dynamic>.from(jsonDecode(titleJson) as Map);
          coverUrl = (titleMap['coverUrl'] as String?)?.trim();
        } catch (_) {}
      }

      if (coverUrl != null && coverUrl.isNotEmpty) {
        final previousCoverUrl = updatedSeries.coverUrl?.trim();
        final coverPath = await _cacheSeriesCover(
          series.id,
          coverUrl,
          referer: updatedSeries.url,
          controller: controller,
        );
        final coverUrlChanged =
            previousCoverUrl == null ||
            previousCoverUrl.isEmpty ||
            previousCoverUrl != coverUrl;
        updatedSeries = updatedSeries.copyWith(
          coverUrl: coverUrl,
          coverPath: coverPath,
          clearCoverPath: coverPath == null && coverUrlChanged,
        );
      } else if (updatedSeries.coverUrl != null &&
          updatedSeries.coverUrl!.isNotEmpty &&
          !_coverFileExists(updatedSeries.coverPath)) {
        final coverPath = await _cacheSeriesCover(
          series.id,
          updatedSeries.coverUrl!,
          referer: updatedSeries.url,
          controller: controller,
        );
        if (coverPath != null) {
          updatedSeries = updatedSeries.copyWith(coverPath: coverPath);
        }
      }

      final merged = _mergeChapters(
        remoteChapters.chapters,
        localBefore,
        relink: relink,
      );
      final newCount = _countNewChapters(
        localBefore,
        merged,
        relink: relink,
      );
      final newIds = localBefore.isEmpty
          ? <String>[]
          : _newChapterIds(localBefore, merged, relink: relink);
      if (newIds.isNotEmpty) {
        await _storage.addSyncNewChapters(series.id, newIds);
      }

      await _storage.saveChapters(series.id, merged);
      await _storage.upsertSeries(
        updatedSeries.copyWith(lastRefreshedAt: DateTime.now()),
      );

      _emit(
        onProgress,
        FetchPhase.done,
        updatedSeries.title != series.title
            ? '제목·회차 갱신 · ${merged.length}화'
            : '회차 ${merged.length}개 · 새 회차 $newCount개',
      );

      return SyncResult(
        newChapterCount: newCount,
        newChaptersBySeries: {series.id: newCount},
        newChapterIds: newIds,
      );
    } on FetchCancelledException {
      _emit(onProgress, FetchPhase.cancelled, '목록 불러오기 취소됨');
      rethrow;
    } catch (e) {
      _emit(onProgress, FetchPhase.error, e.toString());
      return SyncResult(errors: ['${series.title}: $e']);
    }
  }

  Future<SyncResult> downloadSelectedChapters(
    Series series,
    List<Chapter> chapters, {
    void Function(FetchStatus status)? onProgress,
    WebViewBypassRunner? bypassRunner,
    bool forceBrowser = false,
    bool redownload = false,
    bool skipBrowserFallback = false,
  }) {
    return _runGuarded((controller) async {
      final toDownload = redownload
          ? chapters.toList()
          : chapters.where((c) => !c.isOnCloud).toList();
      if (toDownload.isEmpty) {
        return const SyncResult();
      }
      toDownload.sort((a, b) => a.number.compareTo(b.number));

      var downloaded = 0;
      final errors = <String>[];
      for (var i = 0; i < toDownload.length; i++) {
        controller.check();
        var chapter = toDownload[i];
        _emit(
          onProgress,
          FetchPhase.downloading,
          redownload ? '${chapter.title} · 다시 받는 중' : chapter.title,
          chapterCurrent: i + 1,
          chapterTotal: toDownload.length,
        );
        try {
          if (!redownload && chapter.canRead && !chapter.isOnCloud) {
            await CloudBackupQueue.instance.persistAndEnqueue(
              seriesId: series.id,
              chapter: chapter,
            );
            downloaded++;
            continue;
          }
          final saved = await fetchChapterImages(
            series.id,
            chapter,
            controller: controller,
            onProgress: onProgress,
            chapterCurrent: i + 1,
            chapterTotal: toDownload.length,
            bypassRunner: bypassRunner,
            forceBrowser: forceBrowser,
            redownload: redownload,
            skipBrowserFallback: skipBrowserFallback,
          );
          await CloudBackupQueue.instance.persistAndEnqueue(
            seriesId: series.id,
            chapter: saved,
          );
          if (saved.isDownloaded) {
            downloaded++;
          } else if (saved.hasPartialDownload || saved.localPaths.isNotEmpty) {
            errors.add(
              '${chapter.title}: ${saved.localPaths.length}/${saved.imageUrls.length}장만 저장 · 이어 받기 가능',
            );
          }
        } on FetchCancelledException {
          _emit(
            onProgress,
            FetchPhase.cancelled,
            '$downloaded/${toDownload.length}화 저장 후 취소됨',
            chapterCurrent: i + 1,
            chapterTotal: toDownload.length,
          );
          rethrow;
        } catch (e, st) {
          debugPrint('Download failed: $e\n$st');
          errors.add('${chapter.title}: $e');
          _emit(
            onProgress,
            FetchPhase.error,
            '${chapter.title} 실패: $e',
            chapterCurrent: i + 1,
            chapterTotal: toDownload.length,
          );
        }
      }

      _emit(
        onProgress,
        FetchPhase.done,
        '$downloaded/${toDownload.length}화 저장 완료',
        chapterCurrent: toDownload.length,
        chapterTotal: toDownload.length,
      );

      return SyncResult(downloadedCount: downloaded, errors: errors);
    });
  }

  Future<ChapterListFetchResult> fetchChapterList(
    Series series, {
    required FetchController controller,
    void Function(FetchStatus status)? onProgress,
    WebViewBypassRunner? bypassRunner,
  }) async {
    controller.check();
    _emit(
      onProgress,
      FetchPhase.parsing,
      '회차·제목 확인 중...',
    );

    ChapterListFetchResult? result;
    var seriesUrl = _normalizeChapterFetchUrl(series.url);
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
      }
      controller.check();
      result = await fetchChapterListViaHttp(seriesUrl);
      if (result != null && result.chapters.isNotEmpty) {
        return result;
      }
    }

    controller.check();
    _emit(onProgress, FetchPhase.parsing, '회차 목록 확인 중...');
    result = await _fetchChapterListViaHeadless(
      seriesUrl,
      controller: controller,
      onProgress: onProgress,
    );
    if (result != null && result.chapters.isNotEmpty) {
      return result;
    }

    final probeHtml = await _fetchHtmlRaw(seriesUrl);
    final cloudflare =
        probeHtml != null && WebViewScripts.isCloudflareHtml(probeHtml);

    if ((result == null || result.chapters.isEmpty) && bypassRunner != null) {
      controller.check();
      _emit(
        onProgress,
        cloudflare ? FetchPhase.cloudflare : FetchPhase.parsing,
        cloudflare
            ? '브라우저에서 회차 목록을 확인해 주세요'
            : '회차 목록을 다시 확인하는 중...',
      );
      final js = WebViewScripts.extractChapters(seriesUrl);
      final bypassJson = await bypassRunner(
        seriesUrl,
        js,
        '회차 목록이 보이면 [가져오기]를 눌러 주세요',
      );
      controller.check();
      if (bypassJson != null && bypassJson.isNotEmpty) {
        final bypassResult = _parseChapterListJson(bypassJson);
        if (bypassResult.chapters.isNotEmpty) {
          return bypassResult;
        }
      }
    }

    return result ?? const ChapterListFetchResult(chapters: []);
  }

  /// WebView가 Next.js 404로 바뀌어도 SSR HTML에는 회차가 남아 있어 HTTP로 먼저 시도합니다.
  Future<ChapterListFetchResult?> fetchChapterListViaHttp(String seriesUrl) async {
    final normalized = _normalizeChapterFetchUrl(seriesUrl);
    final tried = <String>{};
    for (final url in _chapterFetchUrlCandidates(normalized)) {
      if (!tried.add(url)) continue;
      final result = await _fetchChapterListFromUrl(url);
      if (result != null && result.chapters.isNotEmpty) {
        return result;
      }
    }
    return null;
  }

  String _normalizeChapterFetchUrl(String seriesUrl) {
    var normalized = Series.normalizeUrl(seriesUrl);
    final host = Uri.tryParse(normalized)?.host;
    if (host != null && AppConstants.blockedFetchHosts.contains(host)) {
      normalized = SiteUrl.rewriteHost(
        normalized,
        host,
        AppConstants.defaultSiteOrigin,
      );
    }
    return normalized;
  }

  Future<_ResolvedSeriesUrl> _resolveSeriesUrl(
    String url, {
    required FetchController controller,
    void Function(FetchStatus status)? onProgress,
  }) async {
    controller.check();
    _emit(onProgress, FetchPhase.parsing, '회차 목록 확인 중...');
    final result = await fetchChapterListViaHttp(url);
    controller.check();
    if (result == null || result.chapters.isEmpty) {
      final normalized = Series.normalizeUrl(url);
      throw Exception(
        '유효한 만화 페이지가 아닙니다. '
        '${_seriesUrlRepairHint(normalized) ?? '회차 목록이 있는 시리즈 주소인지 확인해 주세요.'}',
      );
    }

    final resolvedUrl = SiteUrl.preferAllowedHost(
      Series.parentSeriesUrlFromChapterUrl(result.chapters.first.url) ??
          _normalizeChapterFetchUrl(Series.normalizeUrl(url)),
    );
    return _ResolvedSeriesUrl(url: resolvedUrl, chapters: result);
  }

  String? _seriesUrlRepairHint(String url) {
    if (Series.isLikelyTruncatedSlug(url)) {
      return '저장된 링크가 잘려 있습니다. 메뉴 → 링크 수정에서 전체 주소(예: .../u-lz-checkup_x-95cc6771)를 입력해 주세요.';
    }
    return null;
  }

  Future<String?> _guessRepairedSeriesUrl(String url) async {
    final normalized = Series.normalizeUrl(url);
    final uri = Uri.tryParse(normalized);
    if (uri == null) return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < 2 || segments.first != 'webtoon') return null;
    final prefix = segments[1];
    if (prefix.isEmpty) return null;

    var best = prefix;
    Uri bestUri = uri;
    final pattern = RegExp(
      '"sourceWorkId":"(${RegExp.escape(prefix)}[^"]+)"',
      caseSensitive: false,
    );
    for (final candidateUrl in _chapterFetchUrlCandidates(normalized)) {
      final html = await _fetchHtmlRaw(candidateUrl);
      if (html == null || html.isEmpty) continue;
      for (final match in pattern.allMatches(html)) {
        final found = match.group(1)?.trim();
        if (found == null || found.length <= best.length) continue;
        best = found;
        bestUri = Uri.tryParse(candidateUrl) ?? uri;
      }
    }

    if (best == prefix) return null;
    return Uri(
      scheme: bestUri.scheme,
      host: bestUri.host,
      port: bestUri.hasPort ? bestUri.port : null,
      path: '/webtoon/$best',
    ).toString();
  }

  Future<ChapterListFetchResult?> _fetchChapterListFromUrl(String url) async {
    final html = await _fetchHtmlRaw(url);
    if (html == null || html.isEmpty) return null;
    if (WebViewScripts.isCloudflareHtml(html)) return null;

    var result = _parseChapterListFromHtml(html, url);
    if (result != null && result.chapters.isNotEmpty) {
      return result;
    }

    final canonical = _extractCanonicalSeriesUrl(html, url);
    if (canonical != null &&
        canonical != url &&
        _isAllowedChapterFetchUrl(canonical)) {
      final canonicalHtml = await _fetchHtmlRaw(canonical);
      if (canonicalHtml != null &&
          canonicalHtml.isNotEmpty &&
          !WebViewScripts.isCloudflareHtml(canonicalHtml)) {
        result = _parseChapterListFromHtml(canonicalHtml, canonical);
        if (result != null && result.chapters.isNotEmpty) {
          return result;
        }
      }
    }

    return result;
  }

  List<String> _chapterFetchUrlCandidates(String seriesUrl) {
    final normalized = Series.normalizeUrl(seriesUrl);
    final seriesUri = Uri.tryParse(normalized);
    final seriesHost = seriesUri?.host;
    if (seriesHost == null || seriesHost.isEmpty) {
      return [normalized];
    }

    final ordered = <String>[];
    final seen = <String>{};
    void add(String url) {
      if (seen.add(url)) ordered.add(url);
    }

    final priorityOrigins = <String>[
      AppConstants.defaultSiteOrigin,
      for (final origin in AppConstants.chapterFetchOrigins)
        if (origin != AppConstants.defaultSiteOrigin) origin,
      _safeSiteOrigin(),
    ];

    for (final origin in priorityOrigins) {
      final host = SiteUrl.hostOf(origin);
      if (host == null || host.isEmpty) continue;
      if (AppConstants.blockedFetchHosts.contains(host)) continue;
      add(
        host == seriesHost
            ? normalized
            : SiteUrl.rewriteHost(normalized, seriesHost, origin),
      );
    }

    if (AppConstants.blockedFetchHosts.contains(seriesHost)) {
      add(normalized);
    } else if (!seen.contains(normalized)) {
      add(normalized);
    }

    return ordered;
  }

  String _safeSiteOrigin() {
    try {
      return _storage.siteOrigin;
    } catch (_) {
      return AppConstants.defaultSiteOrigin;
    }
  }

  bool _isAllowedChapterFetchUrl(String url) {
    final host = Uri.tryParse(url)?.host;
    if (host == null || host.isEmpty) return false;
    if (AppConstants.blockedFetchHosts.contains(host)) return false;
    if (host == Uri.tryParse(AppConstants.defaultSiteOrigin)?.host) return true;
    for (final origin in AppConstants.chapterFetchOrigins) {
      if (host == Uri.tryParse(origin)?.host) return true;
    }
    final siteHost = Uri.tryParse(_safeSiteOrigin())?.host;
    return siteHost != null && siteHost == host;
  }

  String? _extractCanonicalSeriesUrl(String html, String fallbackUrl) {
    final match = RegExp(
      r'<link[^>]+rel="canonical"[^>]+href="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(html);
    final canonical = match?.group(1)?.trim();
    if (canonical == null || canonical.isEmpty) return null;
    return Series.normalizeUrl(canonical);
  }

  Future<({String? title, String? coverUrl})?> fetchSeriesMetaViaHttp(
    String seriesUrl,
  ) async {
    for (final url in _chapterFetchUrlCandidates(seriesUrl)) {
      final html = await _fetchHtmlRaw(url);
      if (html == null || html.isEmpty) continue;
      if (WebViewScripts.isCloudflareHtml(html)) continue;
      return (
        title: _extractSeriesTitleFromHtml(html),
        coverUrl: _extractCoverUrlFromHtml(html),
      );
    }
    return null;
  }

  String encodeChapterListJson(ChapterListFetchResult result) {
    return jsonEncode({
      'title': result.seriesTitle,
      'coverUrl': result.coverUrl,
      'chapters': result.chapters
          .map(
            (ch) => {
              'url': ch.url,
              'title': ch.title,
              'number': ch.number,
              'publishedLabel': ch.publishedLabel,
            },
          )
          .toList(),
    });
  }

  Future<String?> _fetchHtmlRaw(String url) async {
    final fromDio = await _fetchHtmlRawDio(url);
    if (fromDio != null && fromDio.isNotEmpty) {
      return fromDio;
    }
    return _fetchHtmlRawHttpClient(url);
  }

  Future<String?> _fetchHtmlRawDio(String url) async {
    try {
      final response = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          headers: {
            'User-Agent': AppConstants.userAgent,
            'Referer': url,
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7',
          },
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      final status = response.statusCode ?? 0;
      if (status != 200) return null;
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) return null;
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _fetchHtmlRawHttpClient(String url) async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.userAgent = AppConstants.userAgent;
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('Referer', url);
      request.headers.set(
        'Accept',
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      );
      request.headers.set(
        'Accept-Language',
        'ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7',
      );
      final response = await request.close();
      if (response.statusCode != 200) return null;
      final bytes = await response.fold<List<int>>(
        <int>[],
        (previous, element) => previous..addAll(element),
      );
      if (bytes.isEmpty) return null;
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  Future<ChapterListFetchResult?> _fetchChapterListViaHeadless(
    String seriesUrl, {
    required FetchController controller,
    void Function(FetchStatus status)? onProgress,
  }) async {
    final tried = <String>{};
    for (final url in _chapterFetchUrlCandidates(seriesUrl)) {
      if (!tried.add(url)) continue;
      controller.check();
      final html = await _fetchHtmlViaHeadless(
        url,
        controller: controller,
        onProgress: onProgress,
      );
      if (html == null || html.isEmpty) continue;
      if (WebViewScripts.isCloudflareHtml(html)) continue;
      final parsed = _parseChapterListFromHtml(html, url);
      if (parsed != null && parsed.chapters.isNotEmpty) {
        return parsed;
      }
    }
    return null;
  }

  Future<String?> _fetchHtmlViaHeadless(
    String url, {
    required FetchController controller,
    void Function(FetchStatus status)? onProgress,
  }) async {
    HeadlessInAppWebView? headless;
    final completer = Completer<String?>();

    headless = HeadlessInAppWebView(
      initialSettings: createWebViewSettings(),
      initialUserScripts: createWebViewUserScripts(),
      initialUrlRequest: URLRequest(url: WebUri(url)),
      onLoadStop: (controllerView, _) async {
        if (completer.isCompleted || controller.isCancelled) return;

        final html = await _readWebViewHtml(controllerView);
        if (html == null || html.isEmpty) return;
        if (WebViewScripts.isCloudflareHtml(html)) return;
        if (!html.contains('ep-row-v2-link')) {
          final path = Uri.tryParse(url)?.path ?? '';
          if (path.isEmpty || !html.contains(path)) return;
        }
        if (!completer.isCompleted) {
          completer.complete(html);
        }
      },
      onReceivedError: (_, _, _) {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      },
    );

    controller.attachWebView(headless, completer);
    await headless.run();
    try {
      return await completer.future.timeout(
        const Duration(seconds: 40),
        onTimeout: () => null,
      );
    } on FetchCancelledException {
      rethrow;
    } finally {
      controller.detachWebView();
      try {
        await headless.dispose();
      } catch (_) {}
    }
  }

  Future<String?> _readWebViewHtml(InAppWebViewController controllerView) async {
    try {
      final captured = await controllerView.evaluateJavascript(
        source:
            'window.__awrCapturedHtml || document.documentElement.innerHTML || ""',
      );
      final text = captured?.toString().trim();
      if (text != null && text.isNotEmpty && text != 'null') {
        return text;
      }
    } catch (_) {}
    return controllerView.getHtml();
  }

  ChapterListFetchResult? _parseChapterListFromHtml(
    String html,
    String seriesUrl,
  ) {
    final parsed = ChapterListParser.parse(html, seriesUrl);
    if (parsed == null || parsed.chapters.isEmpty) return null;

    return ChapterListFetchResult(
      chapters: _dedupeChapters(parsed.chapters)
        ..sort((a, b) => a.number.compareTo(b.number)),
      seriesTitle: parsed.seriesTitle ?? _extractSeriesTitleFromHtml(html),
      coverUrl: parsed.coverUrl ?? _extractCoverUrlFromHtml(html),
    );
  }

  String? _extractSeriesTitleFromHtml(String html) {
    final og = RegExp(
      r'<meta[^>]+property="og:title"[^>]+content="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(html);
    if (og != null) {
      return og
          .group(1)!
          .replaceAll(RegExp(r'\s*\|.*$'), '')
          .trim();
    }
    final h1 = RegExp(
      r'<h1[^>]*class="[^"]*hero[^"]*"[^>]*>([^<]+)',
      caseSensitive: false,
    ).firstMatch(html);
    return h1?.group(1)?.trim();
  }

  String? _extractCoverUrlFromHtml(String html) {
    String? best;
    var bestScore = 0;

    void consider(String? raw, int sourcePriority) {
      final url = raw?.trim();
      if (url == null || url.isEmpty) return;
      final cleaned = url.replaceAll(RegExp(r'''^['"]|['"]$'''), '');
      final score = _seriesCoverScore(cleaned, sourcePriority);
      if (score > bestScore) {
        bestScore = score;
        best = cleaned;
      }
    }

    for (final match in RegExp(
      r'<meta[^>]+property="og:image"[^>]+content="([^"]+)"',
      caseSensitive: false,
    ).allMatches(html)) {
      consider(match.group(1), 100);
    }
    for (final match in RegExp(
      r'<meta[^>]+content="([^"]+)"[^>]+property="og:image"',
      caseSensitive: false,
    ).allMatches(html)) {
      consider(match.group(1), 100);
    }

    for (final match in RegExp(
      r'class="[^"]*hero-v2-thumb[^"]*"[^>]*>[\s\S]{0,500}?<img[^>]+src="([^"]+)"',
      caseSensitive: false,
    ).allMatches(html)) {
      consider(match.group(1), 98);
    }

    for (final match in RegExp(
      r'hero-bg:url\(([^)]+)\)',
      caseSensitive: false,
    ).allMatches(html)) {
      consider(match.group(1), 90);
    }

    for (final match in RegExp(
      r'<link[^>]+rel="preload"[^>]+href="([^"]+)"',
      caseSensitive: false,
    ).allMatches(html)) {
      final chunk = match.group(0) ?? '';
      if (!RegExp(r'as=["\x27]image["\x27]', caseSensitive: false).hasMatch(chunk)) {
        continue;
      }
      consider(match.group(1), 50);
    }

    return best;
  }

  int _seriesCoverScore(String url, int sourcePriority) {
    final lower = url.toLowerCase();
    if (_isAdCoverUrl(url)) return 0;

    var score = sourcePriority;
    if (lower.contains('webtoon_uploads')) score += 40;
    if (RegExp(r'/thumbs?/|/black/thumbs/').hasMatch(lower)) score += 40;
    if (lower.contains('lezhin.com') &&
        RegExp(r'\.(webp|jpe?g|png|gif|avif)').hasMatch(lower)) {
      score += 40;
    }
    if (RegExp(r'/comics/').hasMatch(lower)) score += 35;
    if (RegExp(r'/board_uploads/').hasMatch(lower)) {
      // preload에 섞인 광고 배너는 제외, og/hero-bg 등 신뢰 소스만 허용
      if (sourcePriority < 80) return 0;
      score += 20;
    }
    if (RegExp(r'\.(webp|jpe?g|png|gif|avif)').hasMatch(lower)) score += 5;
    return score;
  }

  bool _isAdCoverUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('/platforms/') ||
        lower.contains('/brand/') ||
        lower.contains('logo-full') ||
        lower.contains('favicon') ||
        lower.contains('googletagmanager') ||
        lower.contains('doubleclick') ||
        lower.contains('googlesyndication') ||
        lower.contains('googleads') ||
        lower.contains('adsterra') ||
        lower.contains('adservice') ||
        RegExp(r'/ads/').hasMatch(lower);
  }

  ChapterListFetchResult _parseChapterListJson(String json) {
    final decoded = jsonDecode(json);
    String? seriesTitle;
    String? coverUrl;
    List<dynamic> rawList;

    if (decoded is Map) {
      seriesTitle = decoded['title'] as String?;
      coverUrl = decoded['coverUrl'] as String?;
      rawList = decoded['chapters'] as List<dynamic>? ?? const [];
    } else if (decoded is List) {
      rawList = decoded;
    } else {
      throw Exception('회차 목록 형식 오류');
    }

    final chapters = _dedupeChapters(
      rawList.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        final chapterUrl = map['url'] as String;
        return Chapter(
          id: Chapter.idFromUrl(chapterUrl),
          title: map['title'] as String? ?? 'Episode ${map['number']}',
          url: chapterUrl,
          number: map['number'] as int? ?? 0,
          publishedLabel: (map['publishedLabel'] as String?)?.trim(),
        );
      }).toList(),
    );

    return ChapterListFetchResult(
      chapters: chapters,
      seriesTitle: seriesTitle?.trim(),
      coverUrl: coverUrl?.trim(),
    );
  }

  bool _coverFileExists(String? coverPath) {
    if (coverPath == null || coverPath.isEmpty) return false;
    return File(coverPath).existsSync();
  }

  Future<String?> _cacheSeriesCover(
    String seriesId,
    String coverUrl, {
    required String referer,
    FetchController? controller,
  }) async {
    try {
      controller?.check();
      final dir = _storage.seriesDir(seriesId);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final ext = _extensionFromUrl(coverUrl);
      final file = _storage.seriesCoverFile(seriesId, ext: ext);
      for (final oldExt in const ['webp', 'jpg', 'jpeg', 'png', 'gif', 'avif']) {
        final oldFile = _storage.seriesCoverFile(seriesId, ext: oldExt);
        if (oldFile.path != file.path && await oldFile.exists()) {
          await oldFile.delete();
        }
      }

      final cookieHeader = await _buildCookieHeader(referer, coverUrl);
      final refererForImage = _coverRefererForUrl(coverUrl, referer);

      final response = await _dio.get<List<int>>(
        coverUrl,
        cancelToken: controller?.dioToken,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 60),
          validateStatus: (status) => status != null && status < 400,
          headers: {
            'User-Agent': AppConstants.userAgent,
            'Referer': refererForImage,
            'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
            if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
          },
        ),
      );

      final bytes = response.data ?? [];
      if (bytes.length < 1024) return null;

      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (e, st) {
      debugPrint('Cover download failed: $e\n$st');
      return null;
    }
  }

  String _coverRefererForUrl(String coverUrl, String pageReferer) {
    final host = Uri.tryParse(coverUrl)?.host.toLowerCase() ?? '';
    if (host.contains('lezhin.com')) {
      return 'https://www.lezhin.com/';
    }
    return pageReferer;
  }

  Future<Chapter> fetchChapterImages(
    String seriesId,
    Chapter chapter, {
    required FetchController controller,
    void Function(FetchStatus status)? onProgress,
    int? chapterCurrent,
    int? chapterTotal,
    WebViewBypassRunner? bypassRunner,
    bool forceBrowser = false,
    bool redownload = false,
    bool skipBrowserFallback = false,
  }) async {
    controller.check();
    if (redownload &&
        (chapter.isDownloaded ||
            chapter.hasPartialDownload ||
            chapter.localPaths.isNotEmpty ||
            chapter.imageUrls.isNotEmpty)) {
      await _storage.deleteChapterDownloads(seriesId, [chapter.id]);
      chapter = _chapterAfterClearingDownloads(seriesId, chapter);
    }

    if (!forceBrowser && !redownload && chapter.isOnCloud) {
      final fromCloud = await _tryDownloadFromCloud(
        seriesId,
        chapter,
        controller: controller,
        onProgress: onProgress,
        chapterCurrent: chapterCurrent,
        chapterTotal: chapterTotal,
      );
      if (fromCloud != null) return fromCloud;
    }

    // 이어받기: 이미 확보한 이미지 URL이 있으면 WebView 스크롤을 건너뜁니다.
    final canReuseUrls =
        !forceBrowser && !redownload && chapter.imageUrls.isNotEmpty;

    late List<String> imageUrls;
    int? pageTotal = chapter.sitePageTotal;

    if (canReuseUrls) {
      imageUrls = List<String>.from(chapter.imageUrls);
      _emit(
        onProgress,
        FetchPhase.downloading,
        '${chapter.title} · 저장된 URL ${imageUrls.length}장 · 이어 받기',
        chapterCurrent: chapterCurrent,
        chapterTotal: chapterTotal,
        imageCurrent: chapter.localPaths.length,
        imageTotal: imageUrls.length,
      );
    } else {
      _emit(
        onProgress,
        FetchPhase.parsing,
        '${chapter.title} · 이미지 찾는 중...',
        chapterCurrent: chapterCurrent,
        chapterTotal: chapterTotal,
      );
      final String json;
      if (forceBrowser) {
        if (bypassRunner == null) {
          throw Exception('브라우저 다운로드를 사용할 수 없습니다.');
        }
        _emit(
          onProgress,
          FetchPhase.cloudflare,
          '브라우저 화면에서 직접 확인해 주세요',
          chapterCurrent: chapterCurrent,
          chapterTotal: chapterTotal,
        );
        final result = await bypassRunner(
          chapter.url,
          WebViewScripts.extractImages,
          '${chapter.title} · 끝까지 스크롤 후 [가져오기]',
        );
        controller.check();
        if (result == null || result.isEmpty) {
          throw const FetchCancelledException();
        }
        json = result;
      } else {
        json = await _runInWebView(
          chapter.url,
          WebViewScripts.extractImages,
          controller: controller,
          onProgress: onProgress,
          phase: FetchPhase.parsing,
          parsingMessage: '${chapter.title} · 페이지 분석 중...',
          chapterCurrent: chapterCurrent,
          chapterTotal: chapterTotal,
          bypassRunner: bypassRunner,
          allowBrowserFallback: false,
          operationTimeout: const Duration(minutes: 5),
        );
      }
      controller.check();
      imageUrls = _parseImageUrls(json);
      pageTotal = _parsePageTotal(json) ?? pageTotal;

      if (!skipBrowserFallback &&
          pageTotal != null &&
          imageUrls.length < pageTotal &&
          bypassRunner != null &&
          !forceBrowser) {
        _emit(
          onProgress,
          FetchPhase.cloudflare,
          '이미지 ${imageUrls.length}/$pageTotal장 · 브라우저에서 이어서 찾기',
          chapterCurrent: chapterCurrent,
          chapterTotal: chapterTotal,
        );
        final retryJson = await bypassRunner(
          chapter.url,
          WebViewScripts.extractImages,
          '${chapter.title} · 끝까지 스크롤 후 [가져오기] (약 $pageTotal장)',
        );
        controller.check();
        if (retryJson != null && retryJson.isNotEmpty) {
          imageUrls = _parseImageUrls(retryJson);
          pageTotal = _parsePageTotal(retryJson) ?? pageTotal;
        }
      } else if (!skipBrowserFallback &&
          bypassRunner != null &&
          !forceBrowser &&
          imageUrls.length < 10 &&
          (pageTotal == null || imageUrls.length < pageTotal)) {
        _emit(
          onProgress,
          FetchPhase.cloudflare,
          '이미지 ${imageUrls.length}장만 찾음 · 브라우저에서 다시 시도',
          chapterCurrent: chapterCurrent,
          chapterTotal: chapterTotal,
        );
        final retryJson = await bypassRunner(
          chapter.url,
          WebViewScripts.extractImages,
          '${chapter.title} · 끝까지 스크롤한 뒤 [가져오기]',
        );
        controller.check();
        if (retryJson != null && retryJson.isNotEmpty) {
          final retryUrls = _parseImageUrls(retryJson);
          if (retryUrls.length > imageUrls.length) {
            imageUrls = retryUrls;
            pageTotal = _parsePageTotal(retryJson) ?? pageTotal;
          }
        }
      }
    }

    if (imageUrls.isEmpty) {
      throw Exception('이미지를 찾지 못했습니다. Cloudflare 확인이 필요할 수 있습니다.');
    }

    if (pageTotal != null && imageUrls.length < pageTotal) {
      _emit(
        onProgress,
        FetchPhase.parsing,
        '이미지 ${imageUrls.length}/$pageTotal장만 찾았습니다 · 있는 장부터 저장합니다',
        chapterCurrent: chapterCurrent,
        chapterTotal: chapterTotal,
      );
    }

    _emit(
      onProgress,
      FetchPhase.downloading,
      '${chapter.title} · ${imageUrls.length}장 저장 중...',
      chapterCurrent: chapterCurrent,
      chapterTotal: chapterTotal,
      imageCurrent: 0,
      imageTotal: imageUrls.length,
    );
    final downloadResult = await _downloadImages(
      seriesId,
      chapter.id,
      imageUrls,
      controller: controller,
      referer: chapter.url,
      onProgress: (current, total) {
        _emit(
          onProgress,
          FetchPhase.downloading,
          '${chapter.title} · $current/$total장',
          chapterCurrent: chapterCurrent,
          chapterTotal: chapterTotal,
          imageCurrent: current,
          imageTotal: total,
        );
      },
    );

    if (downloadResult.localPaths.isEmpty) {
      final pageHint = pageTotal != null ? ' (사이트 표시: $pageTotal장)' : '';
      throw Exception(
        '이미지 ${imageUrls.length}개를 받았지만 저장된 장이 없습니다$pageHint. '
        '브라우저로 다시 시도해 주세요.',
      );
    }

    final savedCount = downloadResult.localPaths.length;
    final expected = pageTotal != null && pageTotal > imageUrls.length
        ? pageTotal
        : (pageTotal ?? imageUrls.length);
    final pageHint = pageTotal != null ? ' · 사이트 $pageTotal장' : '';
    final incomplete = savedCount < expected;

    _emit(
      onProgress,
      FetchPhase.downloading,
      incomplete
          ? '${chapter.title} · $savedCount/$expected장 저장됨 (빠진 장 있음)$pageHint'
          : '${chapter.title} · $savedCount장 저장 완료$pageHint',
      chapterCurrent: chapterCurrent,
      chapterTotal: chapterTotal,
      imageCurrent: savedCount,
      imageTotal: expected,
    );

    final resolvedUrls = Chapter.finalizeImageUrlsAfterDownload(
      imageUrls,
      downloadResult.localPaths,
    );

    return chapter.copyWith(
      imageUrls: resolvedUrls,
      localPaths: downloadResult.localPaths,
      sitePageTotal: pageTotal ?? chapter.sitePageTotal,
      fetchedAt: DateTime.now(),
    );
  }

  Future<Chapter?> _tryDownloadFromCloud(
    String seriesId,
    Chapter chapter, {
    required FetchController controller,
    void Function(FetchStatus status)? onProgress,
    int? chapterCurrent,
    int? chapterTotal,
  }) async {
    try {
      _emit(
        onProgress,
        FetchPhase.downloading,
        '${chapter.title} · 클라우드 확인 중',
        chapterCurrent: chapterCurrent,
        chapterTotal: chapterTotal,
      );
      final downloaded = await _cloudStore.downloadChapter(
        seriesId: seriesId,
        chapter: chapter,
        controller: controller,
        onProgress: (current, total) {
          _emit(
            onProgress,
            FetchPhase.downloading,
            '${chapter.title} · 클라우드 $current/$total장',
            chapterCurrent: chapterCurrent,
            chapterTotal: chapterTotal,
            imageCurrent: current,
            imageTotal: total,
          );
        },
      );
      if (downloaded == null || downloaded.localPaths.isEmpty) return null;
      if (!downloaded.isDownloaded && downloaded.localPaths.length < 3) {
        return null;
      }
      _emit(
        onProgress,
        FetchPhase.downloading,
        '${chapter.title} · 클라우드에서 ${downloaded.localPaths.length}장 받음',
        chapterCurrent: chapterCurrent,
        chapterTotal: chapterTotal,
        imageCurrent: downloaded.localPaths.length,
        imageTotal: downloaded.localPaths.length,
      );
      await _maybeDownloadCoverFromCloud(seriesId);
      return downloaded;
    } on FetchCancelledException {
      rethrow;
    } catch (e, st) {
      debugPrint('R2 chapter download skipped: $e\n$st');
      return null;
    }
  }

  Future<Chapter> _uploadChapterToCloud(
    String seriesId,
    Chapter chapter, {
    required FetchController controller,
    void Function(FetchStatus status)? onProgress,
    int? chapterCurrent,
    int? chapterTotal,
  }) async {
    if (controller.isCancelled) return chapter;
    if (chapter.localPaths.isEmpty) return chapter;
    try {
      _emit(
        onProgress,
        FetchPhase.downloading,
        '${chapter.title} · 클라우드에 올리는 중',
        chapterCurrent: chapterCurrent,
        chapterTotal: chapterTotal,
        imageCurrent: 0,
        imageTotal: chapter.localPaths.length,
      );
      final cover = _storage.seriesCoverFile(seriesId);
      final uploaded = await _cloudStore.uploadChapter(
        seriesId: seriesId,
        chapter: chapter,
        controller: controller,
        coverFile: await cover.exists() ? cover : null,
        onProgress: (current, total) {
          _emit(
            onProgress,
            FetchPhase.downloading,
            '${chapter.title} · 클라우드 $current/$total장 업로드',
            chapterCurrent: chapterCurrent,
            chapterTotal: chapterTotal,
            imageCurrent: current,
            imageTotal: total,
          );
        },
      );
      return uploaded;
    } on FetchCancelledException {
      return chapter;
    } catch (e, st) {
      debugPrint('R2 chapter upload failed: $e\n$st');
      return chapter;
    }
  }

  Future<void> _maybeDownloadCoverFromCloud(String seriesId) async {
    final series = _storage.getSeries(seriesId);
    if (series == null) return;
    if (series.coverPath != null &&
        series.coverPath!.isNotEmpty &&
        File(series.coverPath!).existsSync()) {
      return;
    }
    try {
      final path = await _cloudStore.downloadCover(seriesId);
      if (path == null) return;
      await _storage.upsertSeries(series.copyWith(coverPath: path));
    } catch (e) {
      debugPrint('R2 cover download skipped: $e');
    }
  }

  Future<SyncResult> uploadLocalChaptersToCloud({
    List<Series>? seriesList,
    void Function(FetchStatus status)? onProgress,
  }) {
    return _runGuarded((controller) async {
      final targets = seriesList ?? _storage.getAllSeries();
      final work = <({Series series, List<Chapter> chapters})>[];
      for (final series in targets) {
        final chapters = _storage
            .getChapters(series.id)
            .where(
              (c) =>
                  c.isDownloaded &&
                  (c.cloudPageCount == null ||
                      c.cloudPageCount! < c.localPaths.length),
            )
            .toList()
          ..sort((a, b) => a.number.compareTo(b.number));
        if (chapters.isNotEmpty) {
          work.add((series: series, chapters: chapters));
        }
      }
      if (work.isEmpty) {
        _emit(onProgress, FetchPhase.done, '클라우드에 올릴 로컬 만화가 없습니다');
        return const SyncResult();
      }

      var uploaded = 0;
      final errors = <String>[];
      final seriesTotal = work.length;
      for (var s = 0; s < work.length; s++) {
        controller.check();
        final item = work[s];
        for (var i = 0; i < item.chapters.length; i++) {
          controller.check();
          final chapter = item.chapters[i];
          _emit(
            onProgress,
            FetchPhase.downloading,
            '${item.series.title} · ${chapter.title} 업로드',
            seriesCurrent: s + 1,
            seriesTotal: seriesTotal,
            chapterCurrent: i + 1,
            chapterTotal: item.chapters.length,
          );
          try {
            final saved = await _uploadChapterToCloud(
              item.series.id,
              chapter,
              controller: controller,
              onProgress: (status) {
                onProgress?.call(
                  status.copyWith(
                    seriesCurrent: s + 1,
                    seriesTotal: seriesTotal,
                    chapterCurrent: i + 1,
                    chapterTotal: item.chapters.length,
                  ),
                );
              },
              chapterCurrent: i + 1,
              chapterTotal: item.chapters.length,
            );
            await _storage.upsertChapter(item.series.id, saved);
            if (saved.isOnCloud) uploaded++;
          } on FetchCancelledException {
            _emit(
              onProgress,
              FetchPhase.cancelled,
              '$uploaded화 업로드 후 취소됨',
              seriesCurrent: s + 1,
              seriesTotal: seriesTotal,
            );
            rethrow;
          } catch (e, st) {
            debugPrint('Cloud upload failed: $e\n$st');
            errors.add('${item.series.title} · ${chapter.title}: $e');
          }
        }
      }
      _emit(
        onProgress,
        FetchPhase.done,
        '$uploaded화 클라우드 업로드 완료',
        seriesCurrent: seriesTotal,
        seriesTotal: seriesTotal,
      );
      return SyncResult(downloadedCount: uploaded, errors: errors);
    });
  }

  Future<int> refreshCloudInventory({
    List<Series>? seriesList,
    void Function(FetchStatus status)? onProgress,
  }) {
    return _runGuarded((controller) async {
      final targets = seriesList ?? _storage.getAllSeries();
      var updated = 0;
      for (var i = 0; i < targets.length; i++) {
        controller.check();
        final series = targets[i];
        _emit(
          onProgress,
          FetchPhase.parsing,
          '${series.title} 클라우드 목록 (${i + 1}/${targets.length})',
          seriesCurrent: i + 1,
          seriesTotal: targets.length,
        );
        try {
          final remote = await _cloudStore.listSeriesChapters(
            series.id,
            cancelToken: controller.dioToken,
          );
          updated += await _cloudStore.applyInventory(series.id, remote);
        } catch (e) {
          debugPrint('Cloud inventory ${series.id} failed: $e');
        }
      }
      _emit(
        onProgress,
        FetchPhase.done,
        '클라우드 목록 갱신 · $updated화',
      );
      return updated;
    });
  }

  /// UI를 막지 않고 클라우드 회차 표시만 맞춥니다.
  Future<int> refreshCloudInventoryQuiet({
    List<Series>? seriesList,
  }) async {
    final targets = seriesList ?? _storage.getAllSeries();
    var updated = 0;
    for (final series in targets) {
      try {
        final remote = await _cloudStore.listSeriesChapters(series.id);
        updated += await _cloudStore.applyInventory(series.id, remote);
      } catch (e) {
        debugPrint('Quiet cloud inventory ${series.id} failed: $e');
      }
    }
    return updated;
  }

  Future<String> _runInWebView(
    String url,
    String js, {
    required FetchController controller,
    void Function(FetchStatus status)? onProgress,
    FetchPhase phase = FetchPhase.connecting,
    String? parsingMessage,
    int? chapterCurrent,
    int? chapterTotal,
    WebViewBypassRunner? bypassRunner,
    bool allowBrowserFallback = true,
    Duration operationTimeout = const Duration(seconds: 45),
  }) async {
    try {
      return await _runHeadlessWebView(
        url,
        js,
        controller: controller,
        onProgress: onProgress,
        phase: phase,
        parsingMessage: parsingMessage,
        chapterCurrent: chapterCurrent,
        chapterTotal: chapterTotal,
      ).timeout(
        operationTimeout,
        onTimeout: () => throw Exception('자동 읽기 시간 초과'),
      );
    } on FetchCancelledException {
      rethrow;
    } catch (_) {
      if (!allowBrowserFallback || bypassRunner == null) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 800));
      controller.check();
      _emit(
        onProgress,
        FetchPhase.cloudflare,
        '브라우저 화면에서 직접 확인해 주세요',
        chapterCurrent: chapterCurrent,
        chapterTotal: chapterTotal,
      );
      final result = await bypassRunner(
        url,
        js,
        parsingMessage ?? '페이지가 보이면 [가져오기]를 눌러 주세요',
      );
      controller.check();
      if (result == null || result.isEmpty) {
        throw const FetchCancelledException();
      }
      return result;
    }
  }

  Future<String> _runHeadlessWebView(
    String url,
    String js, {
    required FetchController controller,
    void Function(FetchStatus status)? onProgress,
    FetchPhase phase = FetchPhase.connecting,
    String? parsingMessage,
    int? chapterCurrent,
    int? chapterTotal,
  }) async {
    HeadlessInAppWebView? headless;
    final completer = Completer<String>();
    var challengePassed = false;
    final started = DateTime.now();
    Timer? elapsedTimer;

    void tickElapsed() {
      if (controller.isCancelled) return;
      final elapsed = DateTime.now().difference(started);
      if (challengePassed) {
        _emit(
          onProgress,
          FetchPhase.cloudflare,
          '보안 확인 통과 · 페이지 로드 중...',
          elapsed: elapsed,
          chapterCurrent: chapterCurrent,
          chapterTotal: chapterTotal,
        );
      } else {
        _emit(
          onProgress,
          FetchPhase.cloudflare,
          '잠시만 기다려 주세요',
          elapsed: elapsed,
          chapterCurrent: chapterCurrent,
          chapterTotal: chapterTotal,
        );
      }
    }

    _emit(
      onProgress,
      FetchPhase.connecting,
      parsingMessage ?? '페이지 연결 중...',
      chapterCurrent: chapterCurrent,
      chapterTotal: chapterTotal,
    );

    elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!completer.isCompleted) tickElapsed();
    });

    headless = HeadlessInAppWebView(
      initialSettings: createWebViewSettings(),
      initialUserScripts: createWebViewUserScripts(),
      initialUrlRequest: URLRequest(url: WebUri(url)),
      onLoadStop: (controllerView, loadedUrl) async {
        if (completer.isCompleted || controller.isCancelled) return;

        final html = await _readWebViewHtml(controllerView);
        if (WebViewScripts.isCloudflareHtml(html)) {
          if (!challengePassed) {
            challengePassed = true;
            tickElapsed();
          }
          return;
        }

        if (js.contains('AWR_EXTRACT_CHAPTERS') && (html?.isNotEmpty ?? false)) {
          await controllerView.evaluateJavascript(
            source: 'window.__awrCapturedHtml = ${jsonEncode(html)};',
          );
        }

        _emit(
          onProgress,
          phase,
          parsingMessage ?? '데이터 읽는 중...',
          elapsed: DateTime.now().difference(started),
          chapterCurrent: chapterCurrent,
          chapterTotal: chapterTotal,
        );

        final isImageExtract = js.contains('AWR_EXTRACT_IMAGES');
        final isChapterExtract = js.contains('AWR_EXTRACT_CHAPTERS');
        if (isImageExtract) {
          await _autoScrollHeadless(
            controllerView,
            controller: controller,
            isSessionActive: () => !controller.isCancelled && !completer.isCompleted,
          );
        } else if (isChapterExtract) {
          await _autoScrollEpisodeListHeadless(
            controllerView,
            controller: controller,
            isSessionActive: () => !controller.isCancelled && !completer.isCompleted,
          );
        }
        await Future<void>.delayed(
          Duration(milliseconds: isImageExtract ? 2000 : (isChapterExtract ? 2500 : 1200)),
        );
        if (controller.isCancelled) return;

        var result = await controllerView.evaluateJavascript(source: js);
        if (controller.isCancelled) return;

        if (isImageExtract && result != null && result.toString().isNotEmpty) {
          var resultText = result.toString();
          var pageTotal = _parsePageTotal(resultText);
          var imageUrls = _parseImageUrls(resultText);
          if (pageTotal != null &&
              pageTotal > 0 &&
              imageUrls.length < pageTotal) {
            await _runPagerCollectionHeadless(
              controllerView,
              controller: controller,
              isSessionActive: () =>
                  !controller.isCancelled && !completer.isCompleted,
              expectedTotal: pageTotal,
            );
            await _retryPagerTailHeadless(
              controllerView,
              controller: controller,
              pageTotal: pageTotal,
              isSessionActive: () =>
                  !controller.isCancelled && !completer.isCompleted,
            );
            await Future<void>.delayed(const Duration(milliseconds: 1500));
            if (controller.isCancelled) return;
            final retryResult =
                await controllerView.evaluateJavascript(source: js);
            if (retryResult != null && retryResult.toString().isNotEmpty) {
              final retryUrls = _parseImageUrls(retryResult.toString());
              if (retryUrls.length > imageUrls.length) {
                result = retryResult;
              }
            }
          }
        }

        if (result == null || result.toString().isEmpty) {
          if (!completer.isCompleted) {
            completer.completeError(Exception('페이지에서 데이터를 읽지 못했습니다.'));
          }
          return;
        }
        if (!completer.isCompleted) {
          completer.complete(result.toString());
        }
      },
      onReceivedError: (controllerView, request, error) {
        if (!completer.isCompleted && !controller.isCancelled) {
          completer.completeError(Exception('로드 실패: ${error.description}'));
        }
      },
    );

    controller.attachWebView(headless, completer);
    await headless.run();
    try {
      return await completer.future.timeout(
        const Duration(minutes: 4),
        onTimeout: () => throw Exception('페이지 로드 시간 초과 (4분)'),
      );
    } on FetchCancelledException {
      rethrow;
    } finally {
      elapsedTimer.cancel();
      controller.detachWebView();
      try {
        await headless.dispose();
      } catch (_) {}
    }
  }

  Future<int?> _readPageTotalFromView(InAppWebViewController controllerView) async {
    try {
      final result = await controllerView.evaluateJavascript(
        source: WebViewScripts.detectPageTotal,
      );
      final map = jsonDecode(result.toString()) as Map<String, dynamic>;
      final total = (map['pageTotal'] as num?)?.toInt() ?? 0;
      return total > 0 ? total : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, int>> _runPagerCollectStep(
    InAppWebViewController controllerView,
  ) async {
    try {
      final result = await controllerView.evaluateJavascript(
        source: WebViewScripts.pagerCollectStep,
      );
      final map = jsonDecode(result.toString()) as Map<String, dynamic>;
      return {
        'collected': (map['collected'] as num?)?.toInt() ?? 0,
        'current': (map['current'] as num?)?.toInt() ?? 0,
        'total': (map['total'] as num?)?.toInt() ?? 0,
      };
    } catch (_) {
      return const {'collected': 0, 'current': 0, 'total': 0};
    }
  }

  Future<void> _runPagerCollectionHeadless(
    InAppWebViewController controllerView, {
    required FetchController controller,
    bool Function()? isSessionActive,
    int? expectedTotal,
  }) async {
    for (var burst = 0; burst < 10; burst++) {
      if (isSessionActive != null && !isSessionActive()) return;
      await controllerView.evaluateJavascript(source: WebViewScripts.pagerClickUp);
      await Future<void>.delayed(const Duration(milliseconds: 180));
    }

    var pageTotal = expectedTotal ?? await _readPageTotalFromView(controllerView);
    var lastCurrent = -1;
    var stale = 0;
    var collected = 0;
    final maxPagerSteps = pageTotal != null && pageTotal > 0
        ? pageTotal + 20
        : 250;

    for (var step = 0; step < maxPagerSteps; step++) {
      if (isSessionActive != null && !isSessionActive()) return;

      final state = await _runPagerCollectStep(controllerView);
      collected = state['collected'] ?? 0;
      final current = state['current'] ?? 0;
      final total = state['total'] ?? 0;

      if (total > 0) {
        pageTotal = total;
      }

      final target = pageTotal ?? (total > 0 ? total : 0);
      final atLastPage = total > 0 && current >= total;

      if (target > 0 && collected >= target) {
        await Future<void>.delayed(const Duration(milliseconds: 900));
        final settle = await _runPagerCollectStep(controllerView);
        collected = settle['collected'] ?? collected;
        break;
      }

      if (atLastPage) {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        var settle = await _runPagerCollectStep(controllerView);
        collected = settle['collected'] ?? collected;
        if (target > 0 && collected < target) {
          await Future<void>.delayed(const Duration(milliseconds: 900));
          settle = await _runPagerCollectStep(controllerView);
          collected = settle['collected'] ?? collected;
        }
        break;
      }

      await controllerView.evaluateJavascript(source: WebViewScripts.pagerClickDown);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      controller.check();

      if (current == lastCurrent) {
        stale++;
      } else {
        stale = 0;
      }
      lastCurrent = current;

      if (stale > 35) break;
    }

    pageTotal ??= await _readPageTotalFromView(controllerView);
    if (pageTotal != null && pageTotal > 0 && collected < pageTotal) {
      await _retryPagerTailHeadless(
        controllerView,
        controller: controller,
        pageTotal: pageTotal,
        isSessionActive: isSessionActive,
      );
    }
  }

  Future<void> _retryPagerTailHeadless(
    InAppWebViewController controllerView, {
    required FetchController controller,
    required int pageTotal,
    bool Function()? isSessionActive,
  }) async {
    for (var burst = 0; burst < 5; burst++) {
      if (isSessionActive != null && !isSessionActive()) return;
      await controllerView.evaluateJavascript(
        source: WebViewScripts.scrollToBottomViaSiteButton,
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    var lastCurrent = -1;
    for (var step = 0; step < pageTotal + 20; step++) {
      if (isSessionActive != null && !isSessionActive()) return;

      final state = await _runPagerCollectStep(controllerView);
      final collected = state['collected'] ?? 0;
      final current = state['current'] ?? 0;
      final total = state['total'] ?? 0;

      if (collected >= pageTotal) return;
      if (total > 0 && current >= total) {
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        final retry = await _runPagerCollectStep(controllerView);
        if ((retry['collected'] ?? 0) >= pageTotal) return;
        await Future<void>.delayed(const Duration(milliseconds: 1000));
        await _runPagerCollectStep(controllerView);
        return;
      }

      await controllerView.evaluateJavascript(source: WebViewScripts.pagerClickDown);
      await Future<void>.delayed(const Duration(milliseconds: 650));
      controller.check();

      if (current == lastCurrent && step > pageTotal) break;
      lastCurrent = current;
    }

    for (var pass = 0; pass < 3; pass++) {
      if (isSessionActive != null && !isSessionActive()) return;
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      final state = await _runPagerCollectStep(controllerView);
      if ((state['collected'] ?? 0) >= pageTotal) return;
    }
  }

  Future<void> _autoScrollEpisodeListHeadless(
    InAppWebViewController controllerView, {
    required FetchController controller,
    bool Function()? isSessionActive,
  }) async {
    var lastNodes = 0;
    var stableSteps = 0;

    for (var step = 0; step < 24; step++) {
      if (isSessionActive != null && !isSessionActive()) return;

      final result = await controllerView.evaluateJavascript(
        source: WebViewScripts.scrollEpisodeListStep,
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));
      controller.check();

      var episodeNodes = 0;
      try {
        final data = jsonDecode(result.toString()) as Map<String, dynamic>;
        episodeNodes = (data['episodeNodes'] as num?)?.toInt() ?? 0;
      } catch (_) {}

      if (episodeNodes > 0 && episodeNodes == lastNodes) {
        stableSteps++;
      } else {
        stableSteps = 0;
      }
      lastNodes = episodeNodes;

      if (episodeNodes > 0 && stableSteps >= 3) break;
    }
  }

  Future<void> _autoScrollHeadless(
    InAppWebViewController controllerView, {
    required FetchController controller,
    bool Function()? isSessionActive,
  }) async {
    await controllerView.evaluateJavascript(
      source: 'window.__awrCollectedUrls = []; window.__awrScrollStep = 0;',
    );

    for (var burst = 0; burst < 5; burst++) {
      if (isSessionActive != null && !isSessionActive()) return;
      await controllerView.evaluateJavascript(
        source: WebViewScripts.scrollToBottomViaSiteButton,
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    var pageTotal = await _readPageTotalFromView(controllerView);
    const minScrollSteps = 12;
    var lastY = -1;
    var lastCollected = 0;
    var stableSteps = 0;
    var noGrowthSteps = 0;

    for (var step = 0; step < 150; step++) {
      if (isSessionActive != null && !isSessionActive()) return;

      final result = await controllerView.evaluateJavascript(
        source: WebViewScripts.scrollCollectStep,
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      controller.check();

      var currentHeight = 0;
      var currentY = 0;
      var collected = 0;
      try {
        final data = jsonDecode(result.toString()) as Map<String, dynamic>;
        currentHeight = (data['height'] as num?)?.toInt() ?? 0;
        currentY = (data['y'] as num?)?.toInt() ?? 0;
        collected = (data['collected'] as num?)?.toInt() ?? 0;
      } catch (_) {}

      if (step % 8 == 0) {
        pageTotal ??= await _readPageTotalFromView(controllerView);
      }

      if (pageTotal != null && pageTotal > 0 && collected >= pageTotal) {
        break;
      }

      final atBottom = currentHeight > 0 && currentY >= currentHeight - 50;
      final stuck = currentY == lastY;
      lastY = currentY;

      if (atBottom && stuck && collected == lastCollected) {
        stableSteps++;
      } else {
        stableSteps = 0;
      }

      if (collected > lastCollected) {
        noGrowthSteps = 0;
      } else if (step > 10) {
        noGrowthSteps++;
      }
      lastCollected = collected;

      if (step + 1 < minScrollSteps) continue;

      final targetMet = pageTotal != null &&
          pageTotal > 0 &&
          collected >= pageTotal;
      if (targetMet) break;

      if (step > 20 && atBottom && stuck && stableSteps >= 4) {
        if (pageTotal == null || pageTotal <= 0 || collected >= pageTotal) {
          break;
        }
        stableSteps = 0;
      }
      if (atBottom && noGrowthSteps >= 16) {
        if (pageTotal == null || pageTotal <= 0 || collected >= pageTotal) {
          break;
        }
        noGrowthSteps = 8;
      }
    }

    for (var burst = 0; burst < 5; burst++) {
      if (isSessionActive != null && !isSessionActive()) return;
      await controllerView.evaluateJavascript(
        source: WebViewScripts.scrollToBottomViaSiteButton,
      );
      await controllerView.evaluateJavascript(
        source: WebViewScripts.scrollCollectStep,
      );
      await Future<void>.delayed(const Duration(milliseconds: 800));
      controller.check();
    }

    await _runPagerCollectionHeadless(
      controllerView,
      controller: controller,
      isSessionActive: isSessionActive,
      expectedTotal: pageTotal,
    );
  }

  void _emit(
    void Function(FetchStatus status)? onProgress,
    FetchPhase phase,
    String message, {
    Duration elapsed = Duration.zero,
    int? seriesCurrent,
    int? seriesTotal,
    int? chapterCurrent,
    int? chapterTotal,
    int? imageCurrent,
    int? imageTotal,
  }) {
    final next = FetchStatus(
      phase: phase,
      message: message,
      elapsed: elapsed,
      seriesCurrent: seriesCurrent,
      seriesTotal: seriesTotal,
      chapterCurrent: chapterCurrent,
      chapterTotal: chapterTotal,
      imageCurrent: imageCurrent,
      imageTotal: imageTotal,
    );
    DownloadActivityService.instance.update(next);
    LockService.instance.recordActivity();
    onProgress?.call(next);
  }

  Future<_ImageDownloadResult> _downloadImages(
    String seriesId,
    String chapterId,
    List<String> imageUrls, {
    required FetchController controller,
    required String referer,
    void Function(int current, int total)? onProgress,
  }) async {
    final dir = _storage.chapterDir(seriesId, chapterId);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // 회차 단위로 쿠키를 1회 수집해 이미지마다 CookieManager 왕복을 줄입니다.
    final cookieHeader = await _buildCookieHeaderForUrls(referer, imageUrls);

    final failedIndices = <int>[];
    var completed = 0;
    final total = imageUrls.length;

    Future<void> downloadIndex(
      int i, {
      int maxAttempts = 3,
      int retryDelayMs = 600,
      bool forceRedownload = false,
    }) async {
      controller.check();
      final saved = await _downloadPanelAtIndex(
        dir: dir,
        index: i,
        url: imageUrls[i],
        referer: referer,
        controller: controller,
        cookieHeader: cookieHeader,
        maxAttempts: maxAttempts,
        retryDelayMs: retryDelayMs,
        forceRedownload: forceRedownload,
      );
      completed++;
      onProgress?.call(completed, total);
      if (!saved) {
        failedIndices.add(i);
      }
    }

    await _runWithConcurrency(
      total,
      _imageDownloadConcurrency,
      downloadIndex,
    );

    if (failedIndices.isNotEmpty) {
      final retryTargets = List<int>.from(failedIndices)..sort();
      failedIndices.clear();
      // 재시도 패스는 완료 카운트를 다시 세지 않고 개별 인덱스 진행만 표시합니다.
      await _runWithConcurrency(
        retryTargets.length,
        _imageDownloadConcurrency,
        (slot) async {
          final i = retryTargets[slot];
          controller.check();
          onProgress?.call(i + 1, total);
          final saved = await _downloadPanelAtIndex(
            dir: dir,
            index: i,
            url: imageUrls[i],
            referer: referer,
            controller: controller,
            cookieHeader: cookieHeader,
            maxAttempts: 8,
            retryDelayMs: 1500,
            forceRedownload: true,
          );
          if (!saved) {
            failedIndices.add(i);
            debugPrint(
              'Image still missing after retry pass: ${imageUrls[i]}',
            );
          }
        },
      );
    }

    final localPaths = await _collectSortedPagePaths(dir);
    return _ImageDownloadResult(
      localPaths: localPaths,
      failedCount: imageUrls.length - localPaths.length,
      totalRequested: imageUrls.length,
    );
  }

  /// [count]개 작업을 최대 [concurrency]개 동시 실행합니다.
  Future<void> _runWithConcurrency(
    int count,
    int concurrency,
    Future<void> Function(int index) work,
  ) async {
    if (count <= 0) return;
    final workers = concurrency.clamp(1, count);
    var next = 0;

    Future<void> worker() async {
      while (true) {
        final i = next;
        next++;
        if (i >= count) return;
        await work(i);
      }
    }

    await Future.wait(List.generate(workers, (_) => worker()));
  }

  Future<bool> _downloadPanelAtIndex({
    required Directory dir,
    required int index,
    required String url,
    required String referer,
    required FetchController controller,
    String cookieHeader = '',
    int maxAttempts = 3,
    int retryDelayMs = 600,
    bool forceRedownload = false,
  }) async {
    final ext = _extensionFromUrl(url);
    final filePath =
        '${dir.path}/page_${(index + 1).toString().padLeft(3, '0')}.$ext';
    final file = File(filePath);

    if (!forceRedownload && await _isValidPanelFile(file)) {
      return true;
    }

    if (forceRedownload && await file.exists()) {
      final length = await file.length();
      if (length < _minPanelFileBytes) {
        await file.delete();
      }
    }

    final bytes = await _downloadImageBytes(
      url,
      referer: referer,
      controller: controller,
      cookieHeader: cookieHeader,
      maxAttempts: maxAttempts,
      retryDelayMs: retryDelayMs,
    );
    if (bytes == null) {
      return false;
    }

    if (!_isValidPanelBytes(bytes, url)) {
      debugPrint('Skipped invalid panel bytes: $url');
      return false;
    }

    // 패널 다량 저장 시 fsync 비용이 커서 flush는 생략합니다.
    await file.writeAsBytes(bytes);
    return _isValidPanelFile(file);
  }

  Future<bool> _isValidPanelFile(File file) async {
    if (!await file.exists()) return false;
    return await file.length() >= _minPanelFileBytes;
  }

  Future<List<String>> _collectSortedPagePaths(Directory dir) async {
    if (!await dir.exists()) return const [];

    final files = <File>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith('page_')) continue;
      files.add(entity);
    }

    files.sort((a, b) => a.path.compareTo(b.path));

    final paths = <String>[];
    for (final file in files) {
      if (await _isValidPanelFile(file)) {
        paths.add(file.path);
      }
    }
    return paths;
  }

  Future<Uint8List?> _downloadImageBytes(
    String url, {
    required String referer,
    required FetchController controller,
    String cookieHeader = '',
    int maxAttempts = 3,
    int retryDelayMs = 600,
  }) async {
    var resolvedCookie = cookieHeader;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      controller.check();
      try {
        // 캐시가 비어 있을 때만 폴백 조회 (표지 등 단일 다운로드 경로).
        if (resolvedCookie.isEmpty) {
          resolvedCookie = await _buildCookieHeader(referer, url);
        }
        final response = await _dio.get<List<int>>(
          url,
          cancelToken: controller.dioToken,
          options: Options(
            responseType: ResponseType.bytes,
            receiveTimeout: const Duration(seconds: 90),
            headers: {
              'User-Agent': AppConstants.userAgent,
              'Referer': referer,
              'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
              'Accept-Language': 'ko-KR,ko;q=0.9',
              if (resolvedCookie.isNotEmpty) 'Cookie': resolvedCookie,
            },
          ),
        );

        final bytes = Uint8List.fromList(response.data ?? []);
        if (bytes.length >= _minPanelFileBytes) {
          return bytes;
        }
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) {
          throw const FetchCancelledException();
        }
        debugPrint(
          'Image attempt ${attempt + 1}/$maxAttempts failed: $url -> ${e.message}',
        );
        if (attempt < maxAttempts - 1) {
          await Future<void>.delayed(
            Duration(milliseconds: retryDelayMs * (attempt + 1)),
          );
        }
      }
    }
    return null;
  }

  bool _isValidPanelBytes(Uint8List bytes, String url) {
    if (_isComicCdnUrl(url)) return true;
    return bytes.length >= Chapter.minPanelFileBytes;
  }

  bool _isComicCdnUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('/webtoon_uploads/')) return true;
    return RegExp(
      r'/(?:comic|webtoon|toon|episode|uploads?|data|img)/[^?#]+\.(?:webp|jpe?g|png|gif)',
    ).hasMatch(lower);
  }

  int? _parsePageTotal(String rawJson) => parseExtractedPageTotal(rawJson);

  List<String> _parseImageUrls(String rawJson) =>
      parseExtractedImageUrls(rawJson);

  static ({List<String> urls, int? pageTotal}) parseImageExtract(dynamic raw) {
    if (raw == null) return (urls: const [], pageTotal: null);
    if (raw is Map) {
      return (
        urls: _urlsFromDecoded(raw),
        pageTotal: _pageTotalFromDecoded(raw),
      );
    }
    final text = raw.toString().trim();
    if (text.isEmpty || text == 'null') {
      return (urls: const [], pageTotal: null);
    }
    return (
      urls: parseExtractedImageUrls(text),
      pageTotal: parseExtractedPageTotal(text),
    );
  }

  static int? parseExtractedPageTotal(String rawJson) {
    try {
      dynamic decoded = jsonDecode(rawJson);
      if (decoded is String) {
        decoded = jsonDecode(decoded);
      }
      return _pageTotalFromDecoded(decoded);
    } catch (_) {}
    return null;
  }

  static List<String> parseExtractedImageUrls(String rawJson) {
    try {
      dynamic decoded = jsonDecode(rawJson);
      if (decoded is String) {
        decoded = jsonDecode(decoded);
      }
      return _urlsFromDecoded(decoded);
    } catch (_) {
      return const [];
    }
  }

  static int? _pageTotalFromDecoded(dynamic decoded) {
    if (decoded is Map && decoded['pageTotal'] is num) {
      final total = (decoded['pageTotal'] as num).toInt();
      return total > 0 ? total : null;
    }
    return null;
  }

  static List<String> _urlsFromDecoded(dynamic decoded) {
    if (decoded is Map && decoded['urls'] is List) {
      return (decoded['urls'] as List).map((e) => '$e').toList();
    }
    if (decoded is List) {
      return decoded.map((e) => '$e').toList();
    }
    return const [];
  }

  /// 웹뷰에서 이미 모은 URL만으로 로컬·R2 보관합니다. 별도 페이지 스크랩은 하지 않습니다.
  Future<Chapter?> archiveFromKnownUrls({
    required String seriesId,
    required Chapter chapter,
    required List<String> imageUrls,
    int? pageTotal,
  }) async {
    if (imageUrls.isEmpty) return null;
    if (chapter.isOnCloud && chapter.isDownloaded) return chapter;

    final controller = FetchController();
    final downloadResult = await _downloadImages(
      seriesId,
      chapter.id,
      imageUrls,
      controller: controller,
      referer: chapter.url,
    );
    if (downloadResult.localPaths.isEmpty) return null;

    final resolvedUrls = Chapter.finalizeImageUrlsAfterDownload(
      imageUrls.length >= chapter.imageUrls.length
          ? imageUrls
          : chapter.imageUrls,
      downloadResult.localPaths,
    );
    final saved = chapter.copyWith(
      imageUrls: resolvedUrls,
      localPaths: downloadResult.localPaths,
      sitePageTotal: pageTotal ?? chapter.sitePageTotal,
      fetchedAt: DateTime.now(),
    );
    await CloudBackupQueue.instance.persistAndEnqueue(
      seriesId: seriesId,
      chapter: saved,
    );
    return saved;
  }

  Future<String> _buildCookieHeader(String referer, [String? resourceUrl]) {
    return _buildCookieHeaderForUrls(
      referer,
      resourceUrl == null ? const [] : [resourceUrl],
    );
  }

  /// referer + 이미지 URL 호스트들의 쿠키를 한 번에 모읍니다.
  Future<String> _buildCookieHeaderForUrls(
    String referer,
    List<String> resourceUrls,
  ) async {
    final origins = <String>{};
    void addOrigin(String? url) {
      if (url == null || url.isEmpty) return;
      origins.add(url);
      final uri = Uri.tryParse(url);
      if (uri != null && uri.host.isNotEmpty) {
        origins.add('${uri.scheme}://${uri.host}/');
      }
    }

    addOrigin(referer);
    // CDN 호스트는 보통 소수이므로 앞쪽 URL만 샘플해도 대부분 커버됩니다.
    final sampleLimit = resourceUrls.length < 12 ? resourceUrls.length : 12;
    for (var i = 0; i < sampleLimit; i++) {
      addOrigin(resourceUrls[i]);
    }
    if (resourceUrls.length > sampleLimit) {
      addOrigin(resourceUrls.last);
      final mid = resourceUrls.length ~/ 2;
      addOrigin(resourceUrls[mid]);
    }

    final parts = <String>[];
    final seenNames = <String>{};
    for (final origin in origins) {
      try {
        final cookies =
            await CookieManager.instance().getCookies(url: WebUri(origin));
        for (final cookie in cookies) {
          if (seenNames.add(cookie.name)) {
            parts.add('${cookie.name}=${cookie.value}');
          }
        }
      } catch (_) {}
    }
    return parts.join('; ');
  }

  String _extensionFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final path = uri?.path.toLowerCase() ?? url.toLowerCase();
    if (path.endsWith('.png')) return 'png';
    if (path.endsWith('.webp')) return 'webp';
    if (path.endsWith('.gif')) return 'gif';
    return 'jpg';
  }

  /// True only for app-invented `/webtoon/{seriesId}-{n}` URLs.
  /// Real site slugs like `/webtoon/18968/tt-Mind_Control-25` are NOT synthetic
  /// (case-sensitive path; lowercasing or replacing them causes Not Found).
  bool _isSyntheticChapterUrl(String url) {
    final path = Uri.parse(url).path;
    return RegExp(r'^/webtoon/[^/]+-\d+/?$').hasMatch(path);
  }

  Chapter _preferChapter(Chapter? existing, Chapter candidate) {
    if (existing == null) return candidate;
    if (_isSyntheticChapterUrl(existing.url) &&
        !_isSyntheticChapterUrl(candidate.url)) {
      return candidate.copyWith(
        publishedLabel: candidate.publishedLabel ?? existing.publishedLabel,
      );
    }
    if ((existing.publishedLabel == null || existing.publishedLabel!.isEmpty) &&
        candidate.publishedLabel != null &&
        candidate.publishedLabel!.isNotEmpty) {
      return existing.copyWith(publishedLabel: candidate.publishedLabel);
    }
    return existing;
  }

  List<Chapter> _dedupeChapters(List<Chapter> chapters) {
    final byNumber = <int, Chapter>{};

    for (final chapter in chapters) {
      if (chapter.number <= 0) continue;
      byNumber[chapter.number] =
          _preferChapter(byNumber[chapter.number], chapter);
    }

    final deduped = byNumber.values.toList()
      ..sort((a, b) => b.number.compareTo(a.number));
    return deduped;
  }

  List<Chapter> _mergeChapters(
    List<Chapter> remoteChapters,
    List<Chapter> localChapters, {
    bool relink = false,
  }) {
    final dedupedRemote = _dedupeChapters(remoteChapters);
    final localById = {for (final c in localChapters) c.id: c};
    final localByNumber = {for (final c in localChapters) c.number: c};

    return dedupedRemote.map((remote) {
      final local = localById[remote.id] ??
          (relink ? localByNumber[remote.number] : null);
      if (local == null) return remote;
      return remote.copyWith(
        imageUrls:
            local.imageUrls.isNotEmpty ? local.imageUrls : remote.imageUrls,
        localPaths: local.localPaths,
        fetchedAt: local.fetchedAt,
        publishedLabel: remote.publishedLabel ?? local.publishedLabel,
      );
    }).toList();
  }

  int _countNewChapters(
    List<Chapter> localBefore,
    List<Chapter> merged, {
    bool relink = false,
  }) {
    return _newChapterIds(localBefore, merged, relink: relink).length;
  }

  List<String> _newChapterIds(
    List<Chapter> localBefore,
    List<Chapter> merged, {
    bool relink = false,
  }) {
    if (!relink) {
      final beforeIds = localBefore.map((c) => c.id).toSet();
      return merged
          .where((c) => !beforeIds.contains(c.id))
          .map((c) => c.id)
          .toList();
    }
    return merged
        .where((remote) {
          return !localBefore.any(
            (local) => local.id == remote.id || local.number == remote.number,
          );
        })
        .map((c) => c.id)
        .toList();
  }

  Future<SyncResult> refreshSeries(
    Series series, {
    void Function(FetchStatus status)? onProgress,
    bool relink = false,
    WebViewBypassRunner? bypassRunner,
  }) {
    return _runGuarded((controller) async {
      return syncChapterList(
        series,
        controller: controller,
        onProgress: onProgress,
        relink: relink,
        bypassRunner: bypassRunner,
      );
    });
  }

  Future<SyncResult> refreshAllSeries({
    List<Series>? seriesList,
    void Function(FetchStatus status)? onProgress,
    WebViewBypassRunner? bypassRunner,
  }) {
    return _runGuarded((controller) async {
      final targets = seriesList ?? _storage.getAllSeries();
      if (targets.isEmpty) {
        return const SyncResult();
      }

      var total = const SyncResult();
      for (var i = 0; i < targets.length; i++) {
        controller.check();
        final series = targets[i];
        _emit(
          onProgress,
          FetchPhase.parsing,
          '${series.title} 목록 확인 (${i + 1}/${targets.length})',
        );
        final result = await syncChapterList(
          series,
          controller: controller,
          onProgress: onProgress,
          bypassRunner: bypassRunner,
        );
        total = total.merge(result);
      }

      _emit(
        onProgress,
        FetchPhase.done,
        '${targets.length}개 · 새 회차 ${total.newChapterCount}개',
      );
      return total;
    });
  }

  Future<Chapter> fetchChapterImagesPublic(
    String seriesId,
    Chapter chapter, {
    void Function(FetchStatus status)? onProgress,
    WebViewBypassRunner? bypassRunner,
    bool forceBrowser = false,
    bool redownload = false,
    bool skipBrowserFallback = false,
  }) {
    return _runGuarded(
      (controller) => fetchChapterImages(
        seriesId,
        chapter,
        controller: controller,
        onProgress: onProgress,
        bypassRunner: bypassRunner,
        forceBrowser: forceBrowser,
        redownload: redownload,
        skipBrowserFallback: skipBrowserFallback,
      ),
    );
  }

  Future<SyncResult> downloadAllUndownloadedChapters(
    Series series,
    List<Chapter> chapters, {
    void Function(FetchStatus status)? onProgress,
    WebViewBypassRunner? bypassRunner,
  }) {
    final targets = chapters.where((c) => !c.isOnCloud).toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    return downloadSelectedChapters(
      series,
      targets,
      onProgress: onProgress,
      bypassRunner: bypassRunner,
      skipBrowserFallback: true,
    );
  }

  Future<SyncResult> downloadBatchUndownloaded(
    List<Series> seriesList, {
    void Function(FetchStatus status)? onProgress,
    WebViewBypassRunner? bypassRunner,
  }) {
    return _runGuarded((controller) async {
      final workItems = <({Series series, List<Chapter> chapters})>[];
      for (final series in seriesList) {
        final chapters = _storage
            .getChapters(series.id)
            .where((c) => !c.isOnCloud)
            .toList()
          ..sort((a, b) => a.number.compareTo(b.number));
        if (chapters.isNotEmpty) {
          workItems.add((series: series, chapters: chapters));
        }
      }

      if (workItems.isEmpty) {
        return const SyncResult();
      }

      var downloaded = 0;
      final errors = <String>[];
      final seriesTotal = workItems.length;

      for (var s = 0; s < workItems.length; s++) {
        controller.check();
        final item = workItems[s];
        final toDownload = item.chapters;

        for (var i = 0; i < toDownload.length; i++) {
          controller.check();
          final chapter = toDownload[i];
          _emit(
            onProgress,
            FetchPhase.downloading,
            '${item.series.title} · ${chapter.title}',
            seriesCurrent: s + 1,
            seriesTotal: seriesTotal,
            chapterCurrent: i + 1,
            chapterTotal: toDownload.length,
          );
          try {
            final saved = await fetchChapterImages(
              item.series.id,
              chapter,
              controller: controller,
              onProgress: (status) {
                onProgress?.call(
                  status.copyWith(
                    seriesCurrent: s + 1,
                    seriesTotal: seriesTotal,
                    chapterCurrent: i + 1,
                    chapterTotal: toDownload.length,
                  ),
                );
              },
              chapterCurrent: i + 1,
              chapterTotal: toDownload.length,
              bypassRunner: bypassRunner,
              skipBrowserFallback: true,
            );
            await CloudBackupQueue.instance.persistAndEnqueue(
              seriesId: item.series.id,
              chapter: saved,
            );
            if (saved.isDownloaded) {
              downloaded++;
            } else if (saved.hasPartialDownload || saved.localPaths.isNotEmpty) {
              errors.add(
                '${item.series.title} · ${chapter.title}: '
                '${saved.localPaths.length}/${saved.imageUrls.length}장만 저장 · 이어 받기 가능',
              );
            }
          } on FetchCancelledException {
            _emit(
              onProgress,
              FetchPhase.cancelled,
              '$downloaded화 저장 후 취소됨',
              seriesCurrent: s + 1,
              seriesTotal: seriesTotal,
              chapterCurrent: i + 1,
              chapterTotal: toDownload.length,
            );
            rethrow;
          } catch (e, st) {
            debugPrint('Batch download failed: $e\n$st');
            errors.add('${item.series.title} · ${chapter.title}: $e');
            _emit(
              onProgress,
              FetchPhase.error,
              '${item.series.title} · ${chapter.title} 실패: $e',
              seriesCurrent: s + 1,
              seriesTotal: seriesTotal,
              chapterCurrent: i + 1,
              chapterTotal: toDownload.length,
            );
          }
        }
      }

      _emit(
        onProgress,
        FetchPhase.done,
        '$downloaded화 저장 완료',
        seriesCurrent: seriesTotal,
        seriesTotal: seriesTotal,
      );

      return SyncResult(downloadedCount: downloaded, errors: errors);
    });
  }

  Chapter _chapterAfterClearingDownloads(String seriesId, Chapter chapter) {
    return _storage
            .getChapters(seriesId)
            .where((c) => c.id == chapter.id)
            .firstOrNull ??
        chapter.copyWith(
          imageUrls: const [],
          localPaths: const [],
          fetchedAt: null,
        );
  }
}

class _ResolvedSeriesUrl {
  const _ResolvedSeriesUrl({required this.url, required this.chapters});

  final String url;
  final ChapterListFetchResult chapters;
}

class ChapterListFetchResult {
  const ChapterListFetchResult({
    required this.chapters,
    this.seriesTitle,
    this.coverUrl,
  });

  final List<Chapter> chapters;
  final String? seriesTitle;
  final String? coverUrl;
}

class _ImageDownloadResult {
  const _ImageDownloadResult({
    required this.localPaths,
    required this.failedCount,
    required this.totalRequested,
  });

  final List<String> localPaths;
  final int failedCount;
  final int totalRequested;
}
