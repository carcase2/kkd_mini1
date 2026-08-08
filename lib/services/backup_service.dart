import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/app_state.dart';

/// 로컬 백업 파일 정보
class LocalBackupInfo {
  final String path;
  final String name;
  final DateTime modifiedAt;
  final int sizeBytes;

  const LocalBackupInfo({
    required this.path,
    required this.name,
    required this.modifiedAt,
    required this.sizeBytes,
  });
}

/// 파일로 내보내기 / 불러오기 / 데이터 변경 시 자동 백업
class BackupService {
  static const _maxLocalBackups = 15;
  /// 연속 저장 시 백업 과다 생성 방지 (최소 간격)
  static const _minAutoBackupGap = Duration(minutes: 2);

  static Future<Directory> _backupDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/backups');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static String _stamp(DateTime when) {
    return when
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
  }

  /// 앱 내부 저장소에 백업 파일 저장 + 마지막 백업 시각 기록
  static Future<File> saveLocalBackup(
    AppState state, {
    String prefix = 'backup',
  }) async {
    final json = await state.exportBackupJson();
    final dir = await _backupDir();
    final now = DateTime.now();
    final file = File('${dir.path}/${prefix}_${_stamp(now)}.json');
    await file.writeAsString(json, flush: true);

    // 최신 바로가기
    await File('${dir.path}/latest.json').writeAsString(json, flush: true);

    await _pruneOldBackups(dir);
    await state.markBackupCompleted(now);
    return file;
  }

  static Future<void> _pruneOldBackups(Directory dir) async {
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) {
          final name = f.uri.pathSegments.last;
          return name.endsWith('.json') && name != 'latest.json';
        })
        .toList();
    files.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    for (var i = _maxLocalBackups; i < files.length; i++) {
      try {
        await files[i].delete();
      } catch (_) {}
    }
  }

  /// 단식·금욕·독서 등 데이터가 바뀐 뒤 호출 (디바운스 후 AppState에서 호출)
  /// 짧은 시간에 여러 번 바뀌면 최소 간격으로 한 번만 저장
  static Future<bool> backupAfterDataChange(AppState state) async {
    if (!state.autoBackupEnabled) return false;
    final last = state.lastBackupAt;
    if (last != null &&
        DateTime.now().difference(last) < _minAutoBackupGap) {
      return false;
    }
    await saveLocalBackup(state, prefix: 'auto');
    return true;
  }

  /// @Deprecated 호환용 — 데이터 변경 백업으로 대체됨
  static Future<bool> maybeAutoBackup(AppState state) async {
    return backupAfterDataChange(state);
  }

  /// 로컬 백업 목록 (최신순)
  static Future<List<LocalBackupInfo>> listLocalBackups() async {
    final dir = await _backupDir();
    if (!await dir.exists()) return [];

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) {
          final name = f.uri.pathSegments.last;
          return name.endsWith('.json') && name != 'latest.json';
        })
        .map((f) {
          final stat = f.statSync();
          return LocalBackupInfo(
            path: f.path,
            name: f.uri.pathSegments.last,
            modifiedAt: stat.modified,
            sizeBytes: stat.size,
          );
        })
        .toList();
    files.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return files;
  }

  /// JSON 파일 생성 후 시스템 공유 시트 열기 (+ 로컬에도 저장)
  static Future<void> exportToFile(AppState state) async {
    final file = await saveLocalBackup(state, prefix: 'export');
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: '절제 앱 백업',
        text: '절제 앱 데이터 백업 파일입니다.',
      ),
    );
  }

  /// 로컬 백업 파일에서 복원
  static Future<void> importFromLocalPath(
    AppState state,
    String path,
  ) async {
    final text = await File(path).readAsString();
    if (text.trim().isEmpty) {
      throw FormatException('파일을 읽을 수 없습니다.');
    }
    await state.importBackupJson(text);
  }

  /// JSON 파일 선택 후 불러오기. 취소 시 null, 성공 시 true.
  static Future<bool?> importFromFile(AppState state) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.single;
    String? text;
    if (file.bytes != null) {
      text = utf8.decode(file.bytes!);
    } else if (file.path != null) {
      text = await File(file.path!).readAsString();
    }
    if (text == null || text.trim().isEmpty) {
      throw FormatException('파일을 읽을 수 없습니다.');
    }

    await state.importBackupJson(text);
    return true;
  }
}
