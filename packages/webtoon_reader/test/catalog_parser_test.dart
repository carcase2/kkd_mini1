import 'package:flutter_test/flutter_test.dart';
import 'package:webtoon_reader/services/catalog_parser.dart';

void main() {
  test('reads manhwa cards and skips menu links', () {
    const html = '''
    <a href="/manhwa/updates">업데이트</a>
    <a href="/manhwa" class="nav">만화</a>
    <div class="card-grid">
      <a href="/manhwa/24365" class="card">
        <img alt="광고 https://zxc.bet/tokkis" src="https://cdn.example/a.webp">
        <p class="subject">전생했는데 제7왕자</p>
      </a>
      <a href="/manhwa/24365" class="card">
        <p class="subject">전생했는데 제7왕자</p>
      </a>
      <a href="/webtoon/17970" class="card">
        <img alt="다른 작품" src="https://cdn.example/b.webp">
      </a>
    </div>
    ''';

    final works = CatalogParser.parse(html, 'https://sbxh9.com/manhwa');

    expect(works.map((w) => w.url).toList(), [
      'https://sbxh9.com/manhwa/24365',
      'https://sbxh9.com/webtoon/17970',
    ]);
    expect(works.first.title, '전생했는데 제7왕자');
    expect(works.first.coverUrl, 'https://cdn.example/a.webp');
    expect(works.last.title, '다른 작품');
  });
}
