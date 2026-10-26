import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../constants.dart';
import '../services/catalog_parser.dart';
import '../utils/site_url.dart';

enum _CatalogLane { manhwa, webtoon }

/// 서재가 비어 있을 때 사이트 목록을 앱 안에 바로 보여 줍니다.
class LiveCatalog extends StatefulWidget {
  const LiveCatalog({
    super.key,
    required this.siteOrigin,
    required this.onOpen,
  });

  final String siteOrigin;
  final Future<void> Function(CatalogWork work) onOpen;

  @override
  State<LiveCatalog> createState() => _LiveCatalogState();
}

class _LiveCatalogState extends State<LiveCatalog> {
  final _dio = Dio();
  _CatalogLane _lane = _CatalogLane.manhwa;
  List<CatalogWork> _works = const [];
  bool _loading = true;
  String? _error;
  String? _openingUrl;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _dio.close(force: true);
    super.dispose();
  }

  String get _origin => SiteUrl.normalizeOrigin(
        widget.siteOrigin.trim().isEmpty
            ? AppConstants.defaultSiteOrigin
            : widget.siteOrigin,
      );

  String get _pageUrl {
    final origin = _origin;
    return _lane == _CatalogLane.manhwa
        ? '$origin/manhwa'
        : '$origin/ing?cat=adult&sort=hot';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _dio.get<List<int>>(
        _pageUrl,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          headers: {
            'User-Agent': AppConstants.userAgent,
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'ko-KR,ko;q=0.9',
          },
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      final status = response.statusCode ?? 0;
      final bytes = response.data;
      if (status != 200 || bytes == null || bytes.isEmpty) {
        throw Exception('목록 응답이 비어 있습니다 ($status)');
      }
      final html = utf8.decode(bytes, allowMalformed: true);
      final works = CatalogParser.parse(html, _pageUrl);
      if (!mounted) return;
      setState(() {
        _works = works;
        _loading = false;
        _error = works.isEmpty ? '이 목록에서 만화를 찾지 못했습니다' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _works = const [];
        _loading = false;
        _error = '만화 목록을 불러오지 못했습니다';
      });
    }
  }

  Future<void> _open(CatalogWork work) async {
    if (_openingUrl != null) return;
    setState(() => _openingUrl = work.url);
    try {
      await widget.onOpen(work);
    } finally {
      if (mounted) setState(() => _openingUrl = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              SegmentedButton<_CatalogLane>(
                segments: const [
                  ButtonSegment(value: _CatalogLane.manhwa, label: Text('만화')),
                  ButtonSegment(value: _CatalogLane.webtoon, label: Text('웹툰')),
                ],
                selected: {_lane},
                onSelectionChanged: (next) {
                  final lane = next.first;
                  if (lane == _lane) return;
                  setState(() => _lane = lane);
                  unawaited(_load());
                },
              ),
              const Spacer(),
              IconButton(
                tooltip: '다시 불러오기',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Expanded(child: _body(scheme)),
      ],
    );
  }

  Widget _body(ColorScheme scheme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('다시 시도')),
            ],
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 14,
        childAspectRatio: 0.58,
      ),
      itemCount: _works.length,
      itemBuilder: (context, index) {
        final work = _works[index];
        final opening = _openingUrl == work.url;
        return InkWell(
          onTap: opening ? null : () => unawaited(_open(work)),
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: work.coverUrl == null
                            ? Icon(Icons.auto_stories_outlined, color: scheme.outline)
                            : Image.network(
                                work.coverUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Icon(
                                  Icons.broken_image_outlined,
                                  color: scheme.outline,
                                ),
                              ),
                      ),
                      if (opening)
                        const ColoredBox(
                          color: Color(0x66000000),
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                work.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        );
      },
    );
  }
}
