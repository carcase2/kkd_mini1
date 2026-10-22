import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/chapter.dart';
import 'lock_service.dart';
import 'r2_webtoon_store.dart';
import 'storage_service.dart';

/// 이 기기에 저장된 회차를 Cloudflare R2에 뒤에서 올립니다.
/// 저장하기는 로컬이 끝나는 즉시 완료되고, 백업은 이 큐가 처리합니다.
class CloudBackupQueue extends ChangeNotifier {
  CloudBackupQueue._();

  static final instance = CloudBackupQueue._();

  final _store = R2WebtoonStore.instance;
  final _storage = StorageService.instance;
  final _pending = <String, _BackupJob>{};
  final _order = <String>[];
  bool _running = false;
  String? _currentLabel;

  bool get isRunning => _running || _order.isNotEmpty;
  int get pendingCount => _order.length + (_running ? 1 : 0);
  String? get currentLabel => _currentLabel;

  Future<void> persistAndEnqueue({
    required String seriesId,
    required Chapter chapter,
  }) async {
    await _storage.upsertChapter(seriesId, chapter);
    enqueue(seriesId: seriesId, chapter: chapter);
  }

  void enqueue({required String seriesId, required Chapter chapter}) {
    if (!chapter.needsCloudBackup) return;
    final key = _key(seriesId, chapter.id);
    if (!_pending.containsKey(key)) {
      _order.add(key);
    }
    _pending[key] = _BackupJob(seriesId: seriesId, chapter: chapter);
    notifyListeners();
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_running) return;
    _running = true;
    LockService.instance.beginKeepAwake();
    try {
      while (_order.isNotEmpty) {
        final key = _order.removeAt(0);
        final job = _pending.remove(key);
        if (job == null) continue;

        final latest = _chapterToUpload(job.seriesId, job.chapter);
        if (!latest.needsCloudBackup) continue;

        _currentLabel = latest.title;
        notifyListeners();

        try {
          final uploaded = await _store.uploadChapter(
            seriesId: job.seriesId,
            chapter: latest,
          );
          await _storage.upsertChapter(job.seriesId, uploaded);
        } catch (e, st) {
          debugPrint('Cloud backup failed: $e\n$st');
        }
      }
    } finally {
      _running = false;
      _currentLabel = null;
      LockService.instance.endKeepAwake();
      notifyListeners();
    }
  }

  Chapter _chapterToUpload(String seriesId, Chapter queued) {
    for (final chapter in _storage.getChapters(seriesId)) {
      if (chapter.id != queued.id) continue;
      if (chapter.localPaths.length >= queued.localPaths.length) {
        return chapter;
      }
    }
    return queued;
  }

  static String _key(String seriesId, String chapterId) =>
      '$seriesId::$chapterId';
}

class _BackupJob {
  const _BackupJob({required this.seriesId, required this.chapter});

  final String seriesId;
  final Chapter chapter;
}
