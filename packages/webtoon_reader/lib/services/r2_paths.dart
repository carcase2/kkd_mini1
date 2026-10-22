/// R2 객체 키. 로컬 `webtoon/{seriesId}/{chapterId}/page_xxx` 와 맞춥니다.
class R2Paths {
  static const root = 'webtoon';

  static String seriesPrefix(String seriesId) => '$root/$seriesId/';

  static String chapterPrefix(String seriesId, String chapterId) =>
      '$root/$seriesId/$chapterId/';

  static String pageKey(String seriesId, String chapterId, String fileName) =>
      '${chapterPrefix(seriesId, chapterId)}$fileName';

  static String manifestKey(String seriesId, String chapterId) =>
      pageKey(seriesId, chapterId, 'manifest.json');

  static String coverKey(String seriesId, {String ext = 'webp'}) =>
      '${seriesPrefix(seriesId)}cover.$ext';

  static String? chapterIdFromKey(String seriesId, String key) {
    final prefix = seriesPrefix(seriesId);
    if (!key.startsWith(prefix)) return null;
    final rest = key.substring(prefix.length);
    final slash = rest.indexOf('/');
    if (slash <= 0) return null;
    return rest.substring(0, slash);
  }

  static String? fileNameFromKey(String seriesId, String chapterId, String key) {
    final prefix = chapterPrefix(seriesId, chapterId);
    if (!key.startsWith(prefix)) return null;
    final name = key.substring(prefix.length);
    if (name.isEmpty || name.contains('/')) return null;
    return name;
  }
}

class R2ObjectInfo {
  const R2ObjectInfo({required this.key, required this.size});

  final String key;
  final int size;
}

class R2ChapterRemote {
  const R2ChapterRemote({
    required this.chapterId,
    required this.pageFiles,
    this.pageCount,
  });

  final String chapterId;
  final List<String> pageFiles;
  final int? pageCount;

  int get effectivePageCount => pageCount ?? pageFiles.length;
}
