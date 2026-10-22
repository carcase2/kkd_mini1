import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// 앱 전역 온라인/오프라인 상태.
class ConnectivityService extends ChangeNotifier {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  List<ConnectivityResult> _results = const [ConnectivityResult.none];
  bool _ready = false;

  bool get isReady => _ready;
  bool get isOnline =>
      _results.isNotEmpty && _results.any((r) => r != ConnectivityResult.none);
  bool get isWifi => _results.any((r) => r == ConnectivityResult.wifi);
  bool get isCellular =>
      _results.any((r) => r == ConnectivityResult.mobile);

  String get statusLabel => isOnline ? '온라인' : '오프라인';

  String get detailLabel {
    if (!isOnline) return '오프라인 · 저장된 만화만 볼 수 있습니다';
    if (isWifi) return '온라인 · Wi‑Fi';
    if (isCellular) return '온라인 · 셀룰러';
    return '온라인';
  }

  Future<void> init() async {
    if (_ready) return;
    try {
      _results = await _connectivity.checkConnectivity();
    } catch (e) {
      debugPrint('Connectivity init failed: $e');
      _results = const [ConnectivityResult.none];
    }
    _sub = _connectivity.onConnectivityChanged.listen((results) {
      _apply(results);
    });
    _ready = true;
    notifyListeners();
  }

  Future<void> refresh() async {
    try {
      _apply(await _connectivity.checkConnectivity());
    } catch (e) {
      debugPrint('Connectivity refresh failed: $e');
    }
  }

  void _apply(List<ConnectivityResult> results) {
    final next = results.isEmpty ? const [ConnectivityResult.none] : results;
    final changed = next.length != _results.length ||
        next.asMap().entries.any((e) => _results[e.key] != e.value);
    _results = next;
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
