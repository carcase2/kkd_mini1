import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/chapter.dart';

class ChapterListParseResult {
  const ChapterListParseResult({
    required this.chapters,
    this.seriesTitle,
    this.coverUrl,
  });

  final List<Chapter> chapters;
  final String? seriesTitle;
  final String? coverUrl;
}

class ChapterListParser {
  ChapterListParser._();

  static ChapterListParseResult? parse(String html, String seriesUrl) {
    final uri = _parseSeriesUri(seriesUrl);
    if (uri == null) return null;

    var seriesPath = uri.path;
    if (seriesPath.endsWith('/')) {
      seriesPath = seriesPath.substring(0, seriesPath.length - 1);
    }
    final origin = uri.origin;

    final seenUrls = <String>{};
    final seenIds = <String>{};
    final byNumber = <int, Chapter>{};

    void addChapter({
      required String fullUrl,
      required int number,
      required String title,
    }) {
      if (number <= 0) return;
      var urlPath = Uri.tryParse(fullUrl)?.path ?? '';
      if (urlPath.endsWith('/')) {
        urlPath = urlPath.substring(0, urlPath.length - 1);
      }
      if (!_isChapterPath(urlPath, seriesPath)) return;

      final chapterId = _chapterPathId(urlPath);
      if (chapterId.isEmpty ||
          seenUrls.contains(fullUrl) ||
          seenIds.contains(chapterId)) {
        return;
      }

      seenUrls.add(fullUrl);
      seenIds.add(chapterId);
      byNumber[number] = Chapter(
        id: Chapter.idFromUrl(fullUrl),
        title: title.contains('화') ? title : '$number화',
        url: fullUrl,
        number: number,
      );
    }

    final document = html_parser.parse(html);
    for (final anchor in document.querySelectorAll('a.ep-row-v2-link')) {
      final href = anchor.attributes['href']?.trim();
      if (href == null || href.isEmpty || href.startsWith('#')) continue;

      final fullUrl = _absoluteUrl(origin, href);
      final row = _closestEpisodeRow(anchor);
      final titleEl = row?.querySelector('.ep-row-v2-title strong') ??
          anchor.querySelector('.ep-row-v2-title strong');
      final text = titleEl?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
      final attrNumber = int.tryParse(
        row?.attributes['data-episode-number']?.trim() ?? '',
      );
      final number = (attrNumber != null && attrNumber > 0)
          ? attrNumber
          : _parseChapterNumber(fullUrl, text);
      addChapter(fullUrl: fullUrl, number: number, title: text);
    }

    if (byNumber.isEmpty) {
      final linkRe = RegExp(
        r'class="ep-row-v2-link"[^>]*href="([^"]+)"|href="([^"]+)"[^>]*class="ep-row-v2-link"',
      );
      for (final match in linkRe.allMatches(html)) {
        final href = match.group(1) ?? match.group(2);
        if (href == null || href.startsWith('#')) continue;
        final fullUrl = _absoluteUrl(origin, href);
        final chunk = html.substring(
          match.start,
          (match.start + 1200).clamp(0, html.length),
        );
        final titleMatch = RegExp(
          r'ep-row-v2-title[\s\S]{0,200}?<strong>\s*([^<]+)',
          caseSensitive: false,
        ).firstMatch(chunk);
        final text =
            titleMatch?.group(1)?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
        final number = _parseChapterNumber(fullUrl, text);
        addChapter(fullUrl: fullUrl, number: number, title: text);
      }
    }

    if (byNumber.isEmpty) {
      final escapedPath = RegExp.escape(seriesPath);
      final fallbackRe = RegExp('href="($escapedPath/[^"#?]+)"');
      for (final match in fallbackRe.allMatches(html)) {
        final href = match.group(1);
        if (href == null) continue;
        final fullUrl = _absoluteUrl(origin, href);
        final number = _parseChapterNumber(fullUrl, '');
        addChapter(
          fullUrl: fullUrl,
          number: number,
          title: number > 0 ? '$number화' : '',
        );
      }
    }

    if (byNumber.isEmpty) return null;

    final chapters = byNumber.values.toList()
      ..sort((a, b) => a.number.compareTo(b.number));

    return ChapterListParseResult(
      chapters: chapters,
      seriesTitle: _extractSeriesTitle(html),
      coverUrl: _extractCoverUrl(html),
    );
  }

  static Uri? _parseSeriesUri(String seriesUrl) {
    var trimmed = seriesUrl.trim();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'https://$trimmed';
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty) return null;
    return uri;
  }

  static String _absoluteUrl(String origin, String href) {
    if (href.startsWith('http')) return href;
    return '$origin${href.startsWith('/') ? href : '/$href'}';
  }

  static bool _isChapterPath(String urlPath, String seriesPath) {
    if (urlPath == seriesPath) return false;
    if (urlPath.startsWith('$seriesPath/')) return true;
    if (urlPath.startsWith('$seriesPath-')) return true;
    return false;
  }

  static String _chapterPathId(String urlPath) {
    final parts = urlPath.split('/').where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? urlPath : parts.last;
  }

  static Element? _closestEpisodeRow(Element anchor) {
    Element? node = anchor;
    while (node != null) {
      if (node.localName == 'li' &&
          node.classes.any((cls) => cls.contains('ep-row'))) {
        return node;
      }
      node = node.parent;
    }
    return null;
  }

  static int _parseChapterNumberFromText(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final nums = <int>[];
    for (final match in RegExp(r'(\d+)\s*화').allMatches(compact)) {
      nums.add(int.parse(match.group(1)!));
    }
    if (nums.length == 1) return nums.first;
    final latest = RegExp(
      r'최신화\s*보기\s*\(?\s*(\d+)\s*화',
      caseSensitive: false,
    ).firstMatch(compact);
    if (latest != null) return int.parse(latest.group(1)!);
    return 0;
  }

  static int _parseChapterNumber(String url, String text) {
    final fromTitle = _parseChapterNumberFromText(text);
    if (fromTitle > 0) return fromTitle;
    final urlMatch = RegExp(r'-(\d+)(?:/)?$').firstMatch(url);
    if (urlMatch != null) return int.parse(urlMatch.group(1)!);
    final slashMatch = RegExp(r'/(\d+)(?:/)?$').firstMatch(url);
    if (slashMatch != null) return int.parse(slashMatch.group(1)!);
    return _parseChapterNumberFromText(text);
  }

  static String? _extractSeriesTitle(String html) {
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
    return null;
  }

  static String? _extractCoverUrl(String html) {
    String? best;
    var bestScore = 0;

    void consider(String? raw, int sourcePriority) {
      final url = raw?.trim().replaceAll(RegExp(r'''^['"]|['"]$'''), '');
      if (url == null || url.isEmpty) return;
      final score = _coverScore(url, sourcePriority);
      if (score > bestScore) {
        bestScore = score;
        best = url;
      }
    }

    for (final match in RegExp(
      r'<meta[^>]+property="og:image"[^>]+content="([^"]+)"',
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

    return best;
  }

  static int _coverScore(String url, int sourcePriority) {
    final lower = url.toLowerCase();
    if (lower.contains('/platforms/') ||
        lower.contains('/brand/') ||
        lower.contains('logo-full')) {
      return 0;
    }
    var score = sourcePriority;
    if (lower.contains('lezhin.com')) score += 40;
    if (RegExp(r'/comics/').hasMatch(lower)) score += 35;
    if (RegExp(r'/board_uploads/').hasMatch(lower) && sourcePriority < 80) {
      return 0;
    }
    return score;
  }
}
