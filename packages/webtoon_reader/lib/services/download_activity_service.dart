import 'package:flutter/foundation.dart';

import '../models/fetch_status.dart';

/// 앱 전역 다운로드/동기화 진행 상태를 공유합니다.
class DownloadActivityService {
  DownloadActivityService._();
  static final DownloadActivityService instance = DownloadActivityService._();

  final ValueNotifier<FetchStatus?> status = ValueNotifier<FetchStatus?>(null);
  final ValueNotifier<int> pendingJobs = ValueNotifier<int>(0);
  int _activeOps = 0;
  Future<void> Function()? _openQueue;

  void beginOperation() {
    _activeOps++;
  }

  void update(FetchStatus next) {
    if (_activeOps <= 0) return;
    status.value = next;
  }

  void endOperation() {
    if (_activeOps > 0) _activeOps--;
    if (_activeOps == 0) {
      status.value = null;
    }
  }

  void setPendingJobs(int count) {
    if (pendingJobs.value == count) return;
    pendingJobs.value = count;
  }

  void registerOpenQueue(Future<void> Function() opener) {
    _openQueue = opener;
  }

  void unregisterOpenQueue(Future<void> Function() opener) {
    if (identical(_openQueue, opener)) {
      _openQueue = null;
    }
  }

  Future<void> openQueue() async {
    await _openQueue?.call();
  }
}

