import 'package:html/parser.dart' as html_parser;

class CatalogWork {
  const CatalogWork({
    required this.url,
    required this.title,
    this.coverUrl,
  });

  final String url;
  final String title;
  final String? coverUrl;
}

/// 뉴토끼 목록 HTML에서 만화·웹툰 카드를 읽습니다.
class CatalogParser {
  CatalogParser._();

  static List<CatalogWork> parse(String html, String pageUrl) {
    final base = Uri.tryParse(pageUrl);
    if (base == null || base.host.isEmpty) return const [];
    final document = html_parser.parse(html);
    final seen = <String>{};
    final works = <CatalogWork>[];

    for (final anchor in document.querySelectorAll('a')) {
      final href = anchor.attributes['href']?.trim() ?? '';
      if (href.isEmpty || href.startsWith('#')) continue;
      if (!href.contains('/manhwa/') && !href.contains('/webtoon/')) continue;

      final resolved = base.resolve(href);
      final parts = resolved.pathSegments.where((s) => s.isNotEmpty).toList();
      if (parts.length != 2) continue;
      if (parts.first != 'manhwa' && parts.first != 'webtoon') continue;
      if (parts[1] == 'updates' || parts[1] == 'new') continue;

      final url = Uri(
        scheme: resolved.scheme.isEmpty ? 'https' : resolved.scheme,
        host: resolved.host,
        port: resolved.hasPort ? resolved.port : null,
        path: '/${parts.first}/${parts[1]}',
      ).toString();
      if (!seen.add(url)) continue;

      final subject = anchor
          .querySelector('.subject')
          ?.text
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final alt = anchor.querySelector('img')?.attributes['alt']?.trim();
      final title = (subject != null && subject.isNotEmpty) ? subject : (alt ?? '');
      if (title.length < 2 || title.startsWith('http')) continue;

      final src = anchor.querySelector('img')?.attributes['src']?.trim();
      final cover = (src != null && src.startsWith('http')) ? src : null;
      works.add(CatalogWork(url: url, title: title, coverUrl: cover));
    }
    return works;
  }
}
