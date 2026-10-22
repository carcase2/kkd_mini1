import '../models/chapter.dart';
import '../models/fetch_status.dart';
import '../models/webview_bypass_runner.dart';
import 'storage_service.dart';
import 'webtoon_fetcher.dart';

/// 로컬 캐시가 있으면 그걸 쓰고, 없으면 Cloudflare에서 받아 읽을 수 있게 준비합니다.
class ChapterReader {
  static Future<Chapter?> prepare({
    required String seriesId,
    required Chapter chapter,
    required WebtoonFetcher fetcher,
    void Function(FetchStatus status)? onProgress,
    WebViewBypassRunner? bypassRunner,
  }) async {
    final storage = StorageService.instance;
    var current = storage.reconcileChapterDownloads(seriesId, chapter);
    if (current.localPaths != chapter.localPaths) {
      await storage.upsertChapter(seriesId, current);
    }
    if (current.canRead) return current;
    if (!current.isOnCloud) return null;

    final saved = await fetcher.fetchChapterImagesPublic(
      seriesId,
      current,
      onProgress: onProgress,
      bypassRunner: bypassRunner,
    );
    await storage.upsertChapter(seriesId, saved);
    return saved.canRead ? saved : null;
  }
}
