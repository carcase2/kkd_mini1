import 'package:connectivity_plus/connectivity_plus.dart';

import 'storage_service.dart';

/// Wi‑Fi 전용 다운로드 등 네트워크 정책.
class NetworkPolicy {
  NetworkPolicy._();
  static final NetworkPolicy instance = NetworkPolicy._();

  final Connectivity _connectivity = Connectivity();

  Future<bool> isOnWifi() async {
    final results = await _connectivity.checkConnectivity();
    if (results.isEmpty) return false;
    return results.any((r) => r == ConnectivityResult.wifi);
  }

  /// 오프라인이거나 Wi‑Fi 전용인데 셀룰러면 메시지 반환. 통과 시 null.
  Future<String?> downloadBlockReason() async {
    final results = await _connectivity.checkConnectivity();
    if (results.isEmpty ||
        results.every((r) => r == ConnectivityResult.none)) {
      return '오프라인입니다. 저장된 만화만 볼 수 있습니다.';
    }
    if (!StorageService.instance.wifiOnlyDownload) return null;
    final wifi = results.any((r) => r == ConnectivityResult.wifi);
    if (!wifi) {
      return 'Wi‑Fi에서만 받기로 설정되어 있습니다.\nWi‑Fi에 연결하거나 설정에서 해제해 주세요.';
    }
    return null;
  }
}
