import 'package:package_info_plus/package_info_plus.dart';

/// 앱 버전 문자열 (예: v1.0.1)
class AppVersion {
  static String _label = 'v1.0.3';
  static String _full = '1.0.3';
  static bool _loaded = false;

  /// 표시용 (v1.0.3)
  static String get label => _label;

  /// 숫자만 (1.0.3)
  static String get version => _full;

  static Future<void> load() async {
    if (_loaded) return;
    try {
      final info = await PackageInfo.fromPlatform();
      _full = info.version;
      _label = 'v${info.version}';
      _loaded = true;
    } catch (_) {
      // pubspec 기본값 유지
      _label = 'v1.0.3';
      _full = '1.0.3';
    }
  }
}
