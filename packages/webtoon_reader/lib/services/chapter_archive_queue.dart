import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/chapter.dart';
import 'lock_service.dart';
import 'storage_service.dart';
import 'webtoon_fetcher.dart';

/// 웹으로 읽는 동안 모은 이미지 URL을 뒤에서 보관합니다.
class ChapterArchiveQueue extends ChangeNotifier {
  ChapterArchiveQueue._();

  static final instance = ChapterArchiveQueue._();

  final _fetcher = WebtoonFetcher();
  final _storage = StorageService.instance;
  final _pending = <String, _ArchiveJob>{};
  final _order = <String>[];
  bool _running = false;
  String? _currentLabel;

  bool get isRunning => _running || _order.isNotEmpty;
  int get pendingCount => _order.length + (_running ? 1 : 0);
  String? get currentLabel => _currentLabel;

  void enqueue({
    required String seriesId,
    required Chapter chapter,
    required List<String> imageUrls,
    int? pageTotal,
  }) {
    if (imageUrls.isEmpty) return;
    if (chapter.isOnCloud || chapter.isDownloaded) return;

    final key = _key(seriesId, chapter.id);
    final existing = _pending[key];
    if (existing != null && existing.imageUrls.length >= imageUrls.length) {
      return;
    }
    if (!_pending.containsKey(key)) {
      _order.add(key);
    }
    _pending[key] = _ArchiveJob(
      seriesId: seriesId,
      chapter: chapter,
      imageUrls: List<String>.from(imageUrls),
      pageTotal: pageTotal,
    );
    notifyListeners();
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_running) return;
    _running = true;
    LockService.instance.beginKeepAwake();
    notifyListeners();
    try {
      while (_order.isNotEmpty) {
        final key = _order.removeAt(0);
        final job = _pending.remove(key);
        if (job == null) continue;

        final latest = _latestChapter(job.seriesId, job.chapter);
        if (latest.isOnCloud && latest.isDownloaded) continue;

        _currentLabel = latest.title;
        notifyListeners();

        try {
          await _fetcher.archiveFromKnownUrls(
            seriesId: job.seriesId,
            chapter: latest,
            imageUrls: job.imageUrls.length >= latest.imageUrls.length
                ? job.imageUrls
                : latest.imageUrls,
            pageTotal: job.pageTotal ?? latest.sitePageTotal,
          );
        } catch (e, st) {
          debugPrint('Chapter archive failed: $e\n$st');
        }
      }
    } finally {
      _running = false;
      _currentLabel = null;
      LockService.instance.endKeepAwake();
      notifyListeners();
    }
  }

  Chapter _latestChapter(String seriesId, Chapter queued) {
    for (final chapter in _storage.getChapters(seriesId)) {
      if (chapter.id == queued.id) return chapter;
    }
    return queued;
  }

  static String _key(String seriesId, String chapterId) =>
      '$seriesId::$chapterId';
}

class _ArchiveJob {
  const _ArchiveJob({
    required this.seriesId,
    required this.chapter,
    required this.imageUrls,
    this.pageTotal,
  });

  final String seriesId;
  final Chapter chapter;
  final List<String> imageUrls;
  final int? pageTotal;
}
