import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class FetchCancelledException implements Exception {
  const FetchCancelledException();

  @override
  String toString() => '사용자가 취소했습니다';
}

class FetchController {
  bool _cancelled = false;
  CancelToken _dioToken = CancelToken();
  HeadlessInAppWebView? _webView;
  Completer<dynamic>? _webCompleter;

  bool get isCancelled => _cancelled;
  CancelToken get dioToken => _dioToken;

  void check() {
    if (_cancelled) throw const FetchCancelledException();
  }

  void attachWebView(HeadlessInAppWebView view, Completer<dynamic> completer) {
    _webView = view;
    _webCompleter = completer;
  }

  void detachWebView() {
    _webView = null;
    _webCompleter = null;
  }

  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;

    if (!_dioToken.isCancelled) {
      _dioToken.cancel('cancelled');
    }

    final completer = _webCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(const FetchCancelledException());
    }

    final view = _webView;
    _webView = null;
    _webCompleter = null;
    if (view != null) {
      try {
        await view.dispose();
      } catch (_) {}
    }
  }

  void reset() {
    _cancelled = false;
    _dioToken = CancelToken();
    _webView = null;
    _webCompleter = null;
  }
}
