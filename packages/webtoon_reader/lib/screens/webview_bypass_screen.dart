import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../constants.dart';
import '../models/series.dart';
import '../utils/site_url.dart';
import '../utils/webview_settings.dart';
import '../services/webview_scripts.dart';
import '../services/webtoon_fetcher.dart';

class WebViewBypassScreen extends StatefulWidget {
  const WebViewBypassScreen({
    super.key,
    required this.url,
    required this.extractJs,
    required this.hint,
  });

  final String url;
  final String extractJs;
  final String hint;

  @override
  State<WebViewBypassScreen> createState() => _WebViewBypassScreenState();
}

class _WebViewBypassScreenState extends State<WebViewBypassScreen> {
  final _fetcher = WebtoonFetcher();
  InAppWebViewController? _controller;
  var _loading = true;
  var _cloudflare = false;
  var _extracting = false;
  var _httpExtractSucceeded = false;
  var _showWebView = true;
  String? _statusMessage;
  int? _pageTotal;

  bool get _isImageExtract => widget.extractJs.contains('AWR_EXTRACT_IMAGES');
  bool get _isChapterExtract => widget.extractJs.contains('AWR_EXTRACT_CHAPTERS');
  bool get _isTitleExtract => widget.extractJs.contains('AWR_EXTRACT_TITLE');

  String get _effectiveUrl {
    var normalized = Series.normalizeUrl(widget.url);
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

  @override
  void initState() {
    super.initState();
    if (_isChapterExtract) {
      _showWebView = false;
      _loading = true;
      _statusMessage = '회차 목록 확인 중...';
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final ok = await _tryHttpChapterExtract(popOnSuccess: true);
        if (!mounted) return;
        if (ok) return;
        setState(() {
          _showWebView = true;
          _loading = true;
          _statusMessage = '브라우저로 페이지를 여는 중...';
        });
      });
    }
  }

  Future<bool> _tryHttpChapterExtract({required bool popOnSuccess}) async {
    if (_httpExtractSucceeded) return true;

    final result = await _fetcher.fetchChapterListViaHttp(_effectiveUrl);
    if (!mounted) return false;
    if (result == null || result.chapters.isEmpty) return false;
    if (!popOnSuccess) return true;

    _httpExtractSucceeded = true;
    Navigator.of(context).pop(_fetcher.encodeChapterListJson(result));
    return true;
  }

  String get _defaultReadyMessage {
    if (_isImageExtract) {
      if (_pageTotal != null && _pageTotal! > 0) {
        return '이 회차는 약 $_pageTotal장입니다. 끝까지 스크롤한 뒤 [가져오기]를 눌러 주세요';
      }
      return '만화가 보이면 끝까지 스크롤한 뒤 [가져오기]를 눌러 주세요';
    }
    if (_isChapterExtract) {
      return '제목·회차 목록이 보이면 [가져오기]를 눌러 주세요';
    }
    if (_isTitleExtract) {
      return '제목이 보이면 [가져오기]를 눌러 주세요';
    }
    return '페이지가 보이면 아래 [가져오기]를 눌러 주세요';
  }

  Future<void> _refreshPageState() async {
    final controller = _controller;
    if (controller == null) return;

    final html = await controller.getHtml();
    final cloudflare = WebViewScripts.isCloudflareHtml(html);
    final notFound = WebViewScripts.isNextNotFoundHtml(html);

    if (!mounted) return;
    setState(() {
      _cloudflare = cloudflare;
      _loading = false;
      _statusMessage = cloudflare
          ? '보안 확인이 보이면 완료될 때까지 기다려 주세요'
          : notFound
              ? '회차 목록을 HTTP로 불러오는 중...'
              : _defaultReadyMessage;
    });

    if (notFound && _isChapterExtract && !_cloudflare) {
      final ok = await _tryHttpChapterExtract(popOnSuccess: true);
      if (ok) return;
      if (!mounted || _extracting) return;
      setState(() {
        _statusMessage = 'Not Found 화면이어도 회차를 찾는 중...';
      });
      await _extract();
      return;
    }
  }

  Future<void> _detectPageTotal() async {
    final controller = _controller;
    if (controller == null || !_isImageExtract) return;
    try {
      final result = await controller.evaluateJavascript(
        source: WebViewScripts.detectPageTotal,
      );
      final map =
          Map<String, dynamic>.from(jsonDecode(result.toString()) as Map);
      final total = (map['pageTotal'] as num?)?.toInt() ?? 0;
      if (!mounted || total <= 0) return;
      setState(() {
        _pageTotal = total;
        if (!_cloudflare && !_loading) {
          _statusMessage = _defaultReadyMessage;
        }
      });
    } catch (_) {}
  }

  Future<void> _scrollImagesUntilReady(InAppWebViewController controller) async {
    await controller.evaluateJavascript(
      source: 'window.__awrCollectedUrls = []; window.__awrScrollStep = 0;',
    );

    for (var burst = 0; burst < 5; burst++) {
      await controller.evaluateJavascript(
        source: WebViewScripts.scrollToBottomViaSiteButton,
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    var lastCollected = 0;
    var stableSteps = 0;
    const maxSteps = 180;

    for (var step = 0; step < maxSteps; step++) {
      if (!mounted) return;
      setState(() {
        _statusMessage = _pageTotal != null && _pageTotal! > 0
            ? '이미지 로딩 중... ($lastCollected/$_pageTotal장)'
            : '이미지 로딩 중... (${step + 1}/$maxSteps)';
      });

      final result = await controller.evaluateJavascript(
        source: WebViewScripts.scrollCollectStep,
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));

      var collected = 0;
      try {
        final data = jsonDecode(result.toString()) as Map<String, dynamic>;
        collected = (data['collected'] as num?)?.toInt() ?? 0;
      } catch (_) {}

      if (step % 10 == 0) {
        await _detectPageTotal();
      }

      if (_pageTotal != null && _pageTotal! > 0 && collected >= _pageTotal!) {
        break;
      }

      if (collected == lastCollected) {
        stableSteps++;
      } else {
        stableSteps = 0;
      }
      lastCollected = collected;

      if (step > 40 && stableSteps >= 16) {
        if (_pageTotal == null || _pageTotal! <= 0 || collected >= _pageTotal!) {
          break;
        }
        stableSteps = 8;
      }
    }

    for (var burst = 0; burst < 5; burst++) {
      await controller.evaluateJavascript(
        source: WebViewScripts.scrollToBottomViaSiteButton,
      );
      await controller.evaluateJavascript(
        source: WebViewScripts.scrollCollectStep,
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }

    await _detectPageTotal();

    await controller.evaluateJavascript(
      source: WebViewScripts.pagerCollectAllImages,
    );
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await _detectPageTotal();
  }

  int? _pageTotalFromExtract(String rawJson) {
    try {
      dynamic decoded = jsonDecode(rawJson);
      if (decoded is String) decoded = jsonDecode(decoded);
      if (decoded is Map && decoded['pageTotal'] is num) {
        final total = (decoded['pageTotal'] as num).toInt();
        return total > 0 ? total : null;
      }
    } catch (_) {}
    return null;
  }

  int _urlCountFromExtract(String rawJson) {
    try {
      dynamic decoded = jsonDecode(rawJson);
      if (decoded is String) decoded = jsonDecode(decoded);
      if (decoded is Map && decoded['urls'] is List) {
        return (decoded['urls'] as List).length;
      }
      if (decoded is List) return decoded.length;
    } catch (_) {}
    return 0;
  }

  Future<void> _extract() async {
    final controller = _controller;
    if (controller == null || _extracting) return;

    setState(() {
      _extracting = true;
      _statusMessage = '데이터 읽는 중...';
    });

    try {
      final html = await _readCapturedHtml(controller);
      if (WebViewScripts.isCloudflareHtml(html)) {
        if (!mounted) return;
        setState(() {
          _extracting = false;
          _cloudflare = true;
          _statusMessage = '아직 보안 확인 중입니다. 잠시 후 다시 시도해 주세요.';
        });
        return;
      }

      if (_isImageExtract) {
        await _scrollImagesUntilReady(controller);
      } else if (_isChapterExtract) {
        setState(() => _statusMessage = '제목·회차 목록 읽는 중...');
        if ((html?.contains('ep-row-v2-link') ?? false)) {
          await controller.evaluateJavascript(
            source: 'window.__awrCapturedHtml = ${jsonEncode(html)};',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 800));
      }

      var result = await controller.evaluateJavascript(source: widget.extractJs);
      var text = result?.toString().trim();
      if (text == null || text.isEmpty || text == 'null') {
        if (_isChapterExtract) {
          final popped = await _tryHttpChapterExtract(popOnSuccess: true);
          if (popped) return;
        }
        if (text == null || text.isEmpty || text == 'null') {
          if (!mounted) return;
          setState(() {
            _extracting = false;
            _statusMessage = '데이터를 찾지 못했습니다. 페이지가 완전히 로드됐는지 확인해 주세요.';
          });
          return;
        }
      }

      if (_isImageExtract) {
        var urlCount = _urlCountFromExtract(text);
        var total = _pageTotalFromExtract(text) ?? _pageTotal;
        if (total != null && total > 0 && urlCount < total) {
          setState(() {
            _statusMessage = '마지막 장 찾는 중... ($urlCount/$total)';
          });
          await controller.evaluateJavascript(
            source: WebViewScripts.pagerCollectAllImages,
          );
          await Future<void>.delayed(const Duration(milliseconds: 800));
          await _detectPageTotal();

          final retryResult =
              await controller.evaluateJavascript(source: widget.extractJs);
          final retryText = retryResult?.toString().trim();
          if (retryText != null && retryText.isNotEmpty && retryText != 'null') {
            final retryCount = _urlCountFromExtract(retryText);
            if (retryCount >= urlCount) {
              text = retryText;
              urlCount = retryCount;
              total = _pageTotalFromExtract(retryText) ?? total;
            }
          }
        }

        if (total != null && total > 0 && urlCount < total) {
          if (!mounted) return;
          setState(() {
            _extracting = false;
            _pageTotal = total;
            _statusMessage =
                '$urlCount/$total장만 찾았습니다. ↓ 버튼으로 끝까지 간 뒤 다시 [가져오기]를 눌러 주세요.';
          });
          return;
        }
      }

      if (_isTitleExtract || _isChapterExtract) {
        try {
          final decoded = jsonDecode(text);
          if (_isTitleExtract && decoded is Map && (decoded['title'] as String?)?.isEmpty == true) {
            if (!mounted) return;
            setState(() {
              _extracting = false;
              _statusMessage = '제목을 찾지 못했습니다. 페이지가 완전히 로드됐는지 확인해 주세요.';
            });
            return;
          }
          if (_isChapterExtract && decoded is Map) {
            final chapters = decoded['chapters'] as List?;
            if (chapters == null || chapters.isEmpty) {
              final popped = await _tryHttpChapterExtract(popOnSuccess: true);
              if (popped) return;
              if (!mounted) return;
              setState(() {
                _extracting = false;
                _statusMessage = '회차 목록을 찾지 못했습니다. 목록이 보일 때까지 기다려 주세요.';
              });
              return;
            }
          }
        } catch (_) {}
      }

      if (!mounted) return;
      Navigator.of(context).pop(text);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _extracting = false;
        _statusMessage = '읽기 실패: $e';
      });
    }
  }

  Future<String?> _readCapturedHtml(InAppWebViewController controller) async {
    try {
      final captured = await controller.evaluateJavascript(
        source:
            'window.__awrCapturedHtml || document.documentElement.innerHTML || ""',
      );
      final text = captured?.toString().trim();
      if (text != null && text.isNotEmpty && text != 'null') {
        return text;
      }
    } catch (_) {}
    return controller.getHtml();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('브라우저로 접속'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _controller == null
                ? null
                : () {
                    setState(() {
                      _loading = true;
                      _statusMessage = '새로고침 중...';
                    });
                    _controller!.reload();
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.hint,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (_statusMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _statusMessage!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _cloudflare
                                ? Theme.of(context).colorScheme.tertiary
                                : Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                if (_showWebView)
                  InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri(_effectiveUrl)),
                    initialSettings:
                        createWebViewSettings(disableContextMenu: false),
                    initialUserScripts: createWebViewUserScripts(),
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
                      setState(() {
                        _loading = true;
                        _statusMessage = '페이지 로드 중...';
                      });
                    },
                    onLoadStop: (_, _) async {
                      await _refreshPageState();
                      await _detectPageTotal();
                    },
                    onReceivedError: (_, request, error) {
                      if (!mounted) return;
                      if (shouldIgnoreWebViewError(request, error)) return;
                      setState(() {
                        _loading = false;
                        _statusMessage = '로드 오류: ${error.description}';
                      });
                    },
                  ),
                if (_loading)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _extracting || _loading ? null : _extract,
                  icon: _extracting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                  label: Text(_extracting ? '가져오는 중...' : '이 페이지에서 가져오기'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
