import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  /// 닫기 기억용 키 (버전+빌드)
  String get dismissKey => '$latestVersion+${latestBuild ?? 0}';
}

class UpdateService {
  /// GitHub main 브랜치 version.json (배포 시 이 파일만 올리면 됨)
  static const checkUrl =
      'https://raw.githubusercontent.com/carcase2/kkd_mini1/main/version.json';

  static const _dismissedKey = 'update_dismissed_for';

  static Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      // 캐시로 옛 version.json이 남지 않도록 쿼리 추가
      final uri = Uri.parse(checkUrl).replace(
        queryParameters: {'t': '${DateTime.now().millisecondsSinceEpoch}'},
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;

      final map = jsonDecode(utf8.decode(res.bodyBytes));
      if (map is! Map) return null;
      final data = Map<String, dynamic>.from(map);

      final remoteVersion = (data['version'] as String?)?.trim() ?? '';
      if (remoteVersion.isEmpty) return null;

      final remoteBuild = data['build'] is int
          ? data['build'] as int
          : int.tryParse('${data['build'] ?? ''}');

      // PackageInfo 우선, 실패 시 AppVersion (main에서 load됨)
      await AppVersion.load();
      var localVersion = AppVersion.version;
      int? localBuild = AppVersion.buildNumber;
      try {
        final info = await PackageInfo.fromPlatform();
        final v = info.version.trim();
        if (v.isNotEmpty) localVersion = v;
        localBuild = int.tryParse(info.buildNumber.trim()) ?? localBuild;
      } catch (_) {}

      final newer = _isNewer(
        remoteVersion: remoteVersion,
        remoteBuild: remoteBuild,
        localVersion: localVersion,
        localBuild: localBuild,
      );
      if (!newer) return null;

      final info = AppUpdateInfo(
        latestVersion: remoteVersion,
        latestBuild: remoteBuild,
        message: (data['message'] as String?)?.trim() ?? '',
        force: data['force'] == true,
        playStoreUrl: _str(data['playStoreUrl']),
        apkUrl: _str(data['apkUrl']),
        downloadUrl: _str(data['downloadUrl']),
      );

      // 선택 업데이트는 닫아 두면 같은 버전에 대해 다시 안 띄움
      if (!info.force && await isDismissed(info)) {
        return null;
      }

      return info;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> isDismissed(AppUpdateInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_dismissedKey) == info.dismissKey;
  }

  static Future<void> dismiss(AppUpdateInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dismissedKey, info.dismissKey);
  }

  static String? _str(dynamic v) {
    final s = (v as String?)?.trim();
    if (s == null || s.isEmpty) return null;
    return s;
  }

  /// version 우선 비교, 같으면 build 비교.
  /// 로컬이 원격과 같거나 더 새면 false.
  static bool _isNewer({
    required String remoteVersion,
    required int? remoteBuild,
    required String localVersion,
    required int? localBuild,
  }) {
    final cmp = _compareSemver(remoteVersion, localVersion);
    if (cmp > 0) return true; // remote 더 새음
    if (cmp < 0) return false; // local 더 새음
    // 버전 문자열 동일 → 빌드 번호
    if (remoteBuild != null && localBuild != null) {
      return remoteBuild > localBuild;
    }
    // 빌드 정보 부족하면 업데이트 없음으로 간주 (오탐 방지)
    return false;
  }

  /// a > b → 1, a == b → 0, a < b → -1
  static int _compareSemver(String a, String b) {
    final pa = a.split('.').map((e) => int.tryParse(e.trim()) ?? 0).toList();
    final pb = b.split('.').map((e) => int.tryParse(e.trim()) ?? 0).toList();
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
