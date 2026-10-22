import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/series.dart';
import '../services/storage_service.dart';
import '../services/webview_scripts.dart';
import '../utils/webview_settings.dart';
import '../widgets/lock_button.dart';
import '../widgets/lock_activity_scope.dart';

class BrowseCatalogScreen extends StatefulWidget {
  const BrowseCatalogScreen({
    super.key,
    required this.existingSeriesIds,
    required this.onAddSeries,
  });

  final Set<String> existingSeriesIds;
  final Future<void> Function(String url, String title) onAddSeries;

  @override
  State<BrowseCatalogScreen> createState() => _BrowseCatalogScreenState();
}

class _BrowseCatalogScreenState extends State<BrowseCatalogScreen> {
  final _storage = StorageService.instance;
  InAppWebViewController? _controller;
  var _loading = true;
  var _page = 1;
  var _maxPage = 1;
  String? _statusMessage;
  final _addingIds = <String>{};

  Uri get _baseUri => Uri.parse(_storage.browseCatalogUrl);

  String get _currentUrl {
    final params = Map<String, String>.from(_baseUri.queryParameters);
    if (_page > 1) {
      params['page'] = '$_page';
    } else {
      params.remove('page');
    }
    return _baseUri.replace(queryParameters: params).toString();
  }

  @override
  void initState() {
    super.initState();
    _page = int.tryParse(_baseUri.queryParameters['page'] ?? '') ?? 1;
  }

  Future<void> _syncExistingIdsToWebView() async {
    final controller = _controller;
    if (controller == null) return;
    final idsJson = jsonEncode(widget.existingSeriesIds.toList());
    await controller.evaluateJavascript(
      source: 'window.__awrExistingSeriesIds = new Set($idsJson);',
    );
  }

  Future<void> _refreshAddButtons() async {
    await _syncExistingIdsToWebView();
    final controller = _controller;
    if (controller == null) return;
    await controller.evaluateJavascript(
      source:
          'window.__awrInjectBrowseButtons && window.__awrInjectBrowseButtons();',
    );
  }

  Future<void> _applyBrowseMode() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await _syncExistingIdsToWebView();
      await controller.evaluateJavascript(
        source: WebViewScripts.applyBrowseMode,
      );
      await controller.evaluateJavascript(
        source: WebViewScripts.injectBrowseAddButtons,
      );
      await controller.evaluateJavascript(
        source:
            'window.__awrInjectBrowseButtons && window.__awrInjectBrowseButtons();',
      );
    } catch (_) {}
  }

  Future<void> _refreshPageMeta() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      final result = await controller.evaluateJavascript(
        source: WebViewScripts.extractBrowseSeries,
      );
      final text = result?.toString().trim();
      if (text == null || text.isEmpty || text == 'null') return;
      final map = Map<String, dynamic>.from(jsonDecode(text) as Map);
      final page = (map['page'] as num?)?.toInt() ?? _page;
      final maxPage = (map['maxPage'] as num?)?.toInt() ?? page;
      if (!mounted) return;
      setState(() {
        _page = page > 0 ? page : _page;
        _maxPage = maxPage >= _page ? maxPage : _page;
      });
    } catch (_) {}
  }

  Future<void> _onPageReady() async {
    final controller = _controller;
    if (controller == null) return;

    final html = await controller.getHtml();
    if (WebViewScripts.isCloudflareHtml(html)) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusMessage = '보안 확인이 보이면 완료될 때까지 기다려 주세요';
      });
      return;
    }

    await _applyBrowseMode();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _applyBrowseMode();
    await _refreshPageMeta();

    if (!mounted) return;
    setState(() {
      _loading = false;
      _statusMessage = '포스터 오른쪽 + 버튼으로 서재에 추가';
    });
  }

  Future<void> _loadUrl(String url) async {
    setState(() {
      _loading = true;
      _statusMessage = '페이지 로드 중...';
    });
    await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  void _goPage(int page) {
    if (page < 1) return;
    setState(() => _page = page);
    _loadUrl(_currentUrl);
  }

  Future<void> _handleAdd(
    String url,
    String title, {
    bool? alreadyExists,
  }) async {
    final normalized = Series.normalizeUrl(url);
    if (normalized.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('올바른 만화 링크가 아닙니다')));
      return;
    }
    final id = Series.idFromUrl(normalized);
    if (alreadyExists == true ||
        widget.existingSeriesIds.contains(id) ||
        _addingIds.contains(id)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('이미 서재에 있는 만화입니다')));
      await _refreshAddButtons();
      return;
    }

    setState(() => _addingIds.add(id));
    try {
      await widget.onAddSeries(normalized, title.trim());
      widget.existingSeriesIds.add(id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('"$title" 서재에 추가됨')));
      await _refreshAddButtons();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('추가 실패: $e')));
    } finally {
      if (mounted) setState(() => _addingIds.remove(id));
    }
  }

  Future<void> _showExtractedList() async {
    final controller = _controller;
    if (controller == null) return;

    setState(() => _statusMessage = '목록 읽는 중...');
    final result = await controller.evaluateJavascript(
      source: WebViewScripts.extractBrowseSeries,
    );
    if (!mounted) return;

    final text = result?.toString().trim();
    if (text == null || text.isEmpty || text == 'null') {
      setState(() => _statusMessage = '만화 목록을 찾지 못했습니다');
      return;
    }

    final map = Map<String, dynamic>.from(jsonDecode(text) as Map);
    final raw = map['series'] as List? ?? [];
    final items = raw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((e) => (e['url'] as String?)?.isNotEmpty == true)
        .toList();

    if (items.isEmpty) {
      setState(() => _statusMessage = '이 페이지에서 만화를 찾지 못했습니다');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                '이 페이지 만화 ${items.length}개',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final url = item['url'] as String;
                  final title = (item['title'] as String?) ?? url;
                  final cover = item['coverUrl'] as String?;
                  final id = Series.idFromUrl(url);
                  final exists = widget.existingSeriesIds.contains(id);
                  final adding = _addingIds.contains(id);

                  return ListTile(
                    leading: cover != null && cover.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              cover,
                              width: 44,
                              height: 58,
                              fit: BoxFit.cover,
                              cacheWidth:
                                  (44 * MediaQuery.devicePixelRatioOf(context))
                                      .round()
                                      .clamp(1, 256),
                              cacheHeight:
                                  (58 * MediaQuery.devicePixelRatioOf(context))
                                      .round()
                                      .clamp(1, 320),
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.image),
                            ),
                          )
                        : const Icon(Icons.auto_stories_outlined),
                    title: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: exists ? const Text('서재에 있음') : null,
                    trailing: exists
                        ? const Icon(Icons.check_circle_outline)
                        : adding
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () async {
                              Navigator.pop(context);
                              await _handleAdd(url, title);
                            },
                          ),
                    onTap: exists || adding
                        ? null
                        : () async {
                            Navigator.pop(context);
                            await _handleAdd(url, title);
                          },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (mounted) {
      setState(() => _statusMessage = '포스터 오른쪽 + 버튼으로 서재에 추가');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('만화 찾기'),
        actions: [
          IconButton(
            tooltip: '목록에서 추가',
            onPressed: _loading ? null : _showExtractedList,
            icon: const Icon(Icons.playlist_add_rounded),
          ),
          IconButton(
            tooltip: '새로고침',
            onPressed: _controller == null ? null : () => _loadUrl(_currentUrl),
            icon: const Icon(Icons.refresh),
          ),
          const LockButton(),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (_statusMessage != null)
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  _statusMessage!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(_currentUrl)),
                  initialSettings: createWebViewSettings(
                    disableContextMenu: false,
                  ),
                  initialUserScripts: UnmodifiableListView([
                    UserScript(
                      source: WebViewScripts.browseModeEarlyCss,
                      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                    ),
                  ]),
                  onWebViewCreated: (controller) {
                    _controller = controller;
                    controller.addJavaScriptHandler(
                      handlerName: 'awrBrowseAdd',
                      callback: (args) async {
                        if (args.isEmpty) return;
                        try {
                          final map = Map<String, dynamic>.from(
                            jsonDecode(args.first.toString()) as Map,
                          );
                          final url = map['url'] as String?;
                          final title = map['title'] as String? ?? '';
                          final alreadyExists = map['alreadyExists'] == true;
                          if (url == null || url.isEmpty) return;
                          await _handleAdd(
                            url,
                            title,
                            alreadyExists: alreadyExists,
                          );
                        } catch (_) {}
                      },
                    );
                  },
                  onLoadStart: (_, _) {
                    if (!mounted) return;
                    setState(() {
                      _loading = true;
                      _statusMessage = '페이지 로드 중...';
                    });
                  },
                  onLoadStop: (_, _) => _onPageReady(),
                  onScrollChanged: (_, _, _) => recordLockActivity(),
                  onReceivedError: (_, request, error) {
                    if (!mounted) return;
                    if (shouldIgnoreWebViewError(request, error)) return;
                    setState(() {
                      _loading = false;
                      _statusMessage = '로드 오류: ${error.description}';
                    });
                  },
                ),
                if (_loading) const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Material(
              elevation: 8,
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: '이전 페이지',
                      onPressed: _loading || _page <= 1
                          ? null
                          : () => _goPage(_page - 1),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Text(
                        '$_page페이지${_maxPage > _page ? ' / ~$_maxPage' : ''}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: '다음 페이지',
                      onPressed: _loading ? null : () => _goPage(_page + 1),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
