import 'package:package_info_plus/package_info_plus.dart';

/// 앱 버전 문자열 (예: v1.0.8)
///
/// 기본값은 pubspec.yaml 의 version 과 맞춰 둔다.
/// PackageInfo 로드 전에는 이 값이 쓰이므로 옛 값(1.0.3 등)이 남으면
/// 업데이트 오탐이 날 수 있다.
class AppVersion {
  static String _label = 'v1.0.8';
  static String _full = '1.0.8';
  static int? _buildNumber = 13;
  static bool _loaded = false;

  /// 표시용 (v1.0.8)
  static String get label => _label;

  /// 숫자만 (1.0.8)
  static String get version => _full;

  /// 빌드 번호 (pubspec +N)
  static int? get buildNumber => _buildNumber;

  static Future<void> load() async {
    if (_loaded) return;
    try {
      final info = await PackageInfo.fromPlatform();
      final v = info.version.trim();
      if (v.isNotEmpty) {
        _full = v;
        _label = 'v$v';
      }
      _buildNumber = int.tryParse(info.buildNumber.trim()) ?? _buildNumber;
      _loaded = true;
    } catch (_) {
      // pubspec 기본값 유지
      _label = 'v1.0.8';
      _full = '1.0.8';
      _buildNumber = 13;
    }
  }
}
