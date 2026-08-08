import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/app_version.dart';

/// 원격 version.json과 비교해 업데이트 가능 여부 확인
class AppUpdateInfo {
  final String latestVersion;
  final int? latestBuild;
  final String message;
  final bool force;
  final String? playStoreUrl;
  final String? apkUrl;
  final String? downloadUrl;

  const AppUpdateInfo({
    required this.latestVersion,
    this.latestBuild,
    this.message = '',
    this.force = false,
    this.playStoreUrl,
    this.apkUrl,
    this.downloadUrl,
  });

  String get label => 'v$latestVersion';
}

class UpdateService {
  /// GitHub main 브랜치 version.json (배포 시 이 파일만 올리면 됨)
  static const checkUrl =
      'https://raw.githubusercontent.com/carcase2/kkd_mini1/main/version.json';

  static Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      final res = await http
          .get(Uri.parse(checkUrl))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;

      final map = jsonDecode(utf8.decode(res.bodyBytes));
      if (map is! Map) return null;
      final data = Map<String, dynamic>.from(map);

      final remoteVersion = (data['version'] as String?)?.trim() ?? '';
      if (remoteVersion.isEmpty) return null;

      final remoteBuild = data['build'] is int
          ? data['build'] as int
          : int.tryParse('${data['build'] ?? ''}');

      var localVersion = AppVersion.version;
      int? localBuild;
      try {
        final info = await PackageInfo.fromPlatform();
        localVersion = info.version;
        localBuild = int.tryParse(info.buildNumber);
      } catch (_) {}

      final newer = _isNewer(
        remoteVersion: remoteVersion,
        remoteBuild: remoteBuild,
        localVersion: localVersion,
        localBuild: localBuild,
      );
      if (!newer) return null;

      return AppUpdateInfo(
        latestVersion: remoteVersion,
        latestBuild: remoteBuild,
        message: (data['message'] as String?)?.trim() ?? '',
        force: data['force'] == true,
        playStoreUrl: _str(data['playStoreUrl']),
        apkUrl: _str(data['apkUrl']),
        downloadUrl: _str(data['downloadUrl']),
      );
    } catch (_) {
      return null;
    }
  }

  static String? _str(dynamic v) {
    final s = (v as String?)?.trim();
    if (s == null || s.isEmpty) return null;
    return s;
  }

  /// version 우선 비교, 같으면 build 비교
  static bool _isNewer({
    required String remoteVersion,
    required int? remoteBuild,
    required String localVersion,
    required int? localBuild,
  }) {
    final cmp = _compareSemver(remoteVersion, localVersion);
    if (cmp > 0) return true;
    if (cmp < 0) return false;
    if (remoteBuild != null && localBuild != null) {
      return remoteBuild > localBuild;
    }
    return false;
  }

  /// a > b → 1, a == b → 0, a < b → -1
  static int _compareSemver(String a, String b) {
    final pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    while (pa.length < 3) {
      pa.add(0);
    }
    while (pb.length < 3) {
      pb.add(0);
    }
    for (var i = 0; i < 3; i++) {
      if (pa[i] != pb[i]) return pa[i].compareTo(pb[i]);
    }
    return 0;
  }

  static Future<bool> openUpdate(AppUpdateInfo info) async {
    final candidates = <String?>[
      info.playStoreUrl,
      info.apkUrl,
      info.downloadUrl,
      'https://play.google.com/store/apps/details?id=com.kkd.discipline_tracker',
    ];
    for (final raw in candidates) {
      if (raw == null || raw.isEmpty) continue;
      final uri = Uri.tryParse(raw);
      if (uri == null) continue;
      if (await canLaunchUrl(uri)) {
        return launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
    return false;
  }
}
