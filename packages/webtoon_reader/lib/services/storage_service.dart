import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants.dart';
import '../models/chapter.dart';
import '../models/reading_progress.dart';
import '../models/series.dart';
import '../models/library_sort_mode.dart';
import '../models/site_migration_result.dart';
import '../utils/site_url.dart';
import 'supabase_sync_service.dart';

class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  static const _seriesBox = 'series';
  static const _chaptersBox = 'chapters';
  static const _progressBox = 'progress';
  static const _metaBox = 'meta';
  static const backupAppId = 'apartment_webtoon_reader';

  late Box<dynamic> _series;
  late Box<dynamic> _chapters;
  late Box<dynamic> _progress;
  late Box<dynamic> _meta;
  late Directory _rootDir;
  static const _latestBackupFileName = 'webtoon_backup_latest.json';
  static const _autoBackupInterval = Duration(minutes: 30);
  static const _cloudSyncDebounce = Duration(seconds: 5);
  bool _autoBackupRunning = false;
  Timer? _cloudSyncTimer;
  bool _cloudSyncInFlight = false;
  bool _cloudSyncQueued = false;

  Future<void> init() async {
    await Hive.initFlutter();
    _series = await Hive.openBox(_seriesBox);
    _chapters = await Hive.openBox(_chaptersBox);
    _progress = await Hive.openBox(_progressBox);
    _meta = await Hive.openBox(_metaBox);
    _rootDir = await getApplicationDocumentsDirectory();
    await _migrateLegacyData();
    await _rewriteBlockedHostsInStorage();
    unawaited(_autoBackupIfDue());
  }

  /// 이미 저장된 sbxh10 등 Host error 미러 주소를 기본 사이트로 고칩니다.
  Future<void> _rewriteBlockedHostsInStorage() async {
    var seriesChanged = false;
    final seriesList = getAllSeries().map((series) {
      final safeUrl = SiteUrl.preferAllowedHost(series.url);
      if (safeUrl == series.url) return series;
      seriesChanged = true;
      return series.copyWith(url: safeUrl);
    }).toList();
    if (seriesChanged) {
      await _series.put('all', seriesList.map((s) => s.toMap()).toList());
    }

    final site = _meta.get('siteOrigin') as String?;
    if (site != null && site.trim().isNotEmpty) {
      final host = SiteUrl.hostOf(site);
      if (host != null && AppConstants.blockedFetchHosts.contains(host)) {
        await _meta.put('siteOrigin', SiteUrl.normalizeOrigin(site));
      }
    }

    for (final key in _chapters.keys) {
      if (key is! String) continue;
      final chapters = getChapters(key);
      if (chapters.isEmpty) continue;
      var changed = false;
      final next = chapters.map((chapter) {
        final safeUrl = SiteUrl.preferAllowedHost(chapter.url);
        if (safeUrl == chapter.url) return chapter;
        changed = true;
        return chapter.copyWith(url: safeUrl);
      }).toList();
      if (changed) {
        await _chapters.put(key, next.map((c) => c.toMap()).toList());
      }
    }
  }

  Future<void> _migrateLegacyData() async {
    if (getAllSeries().isNotEmpty) return;

    final legacyChapters = _chapters.get(AppConstants.legacySeriesId);
    if (legacyChapters == null) return;

    final series = Series(
      id: AppConstants.legacySeriesId,
      title: AppConstants.legacySeriesTitle,
      url: AppConstants.legacySeriesUrl,
      addedAt: DateTime.now(),
      lastRefreshedAt: _meta.get('lastRefreshedAt') != null
          ? DateTime.fromMillisecondsSinceEpoch(_meta.get('lastRefreshedAt') as int)
          : null,
    );
    await saveAllSeries([series]);
  }

  Directory seriesDir(String seriesId) {
    return Directory(p.join(_rootDir.path, 'webtoon', seriesId));
  }

  Directory chapterDir(String seriesId, String chapterId) {
    return Directory(
      p.join(_rootDir.path, 'webtoon', seriesId, chapterId),
    );
  }

  File seriesCoverFile(String seriesId, {String ext = 'webp'}) {
    return File(p.join(seriesDir(seriesId).path, 'cover.$ext'));
  }

  Future<void> _deleteDirectoryIfExists(Directory dir) async {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<void> _deleteChapterProgress(String seriesId, String chapterId) async {
    await _progress.delete(_progressKey(seriesId, chapterId));
    await _progress.delete(chapterId);
  }

  Future<void> deleteSeriesCompletely(String seriesId) async {
    final chapters = getChapters(seriesId);
    for (final chapter in chapters) {
      await _deleteChapterProgress(seriesId, chapter.id);
    }
    await _deleteDirectoryIfExists(seriesDir(seriesId));
    await removeSeries(seriesId);

    if (lastSeriesId == seriesId) {
      await _meta.delete('lastSeriesId');
      await _meta.delete('lastChapterId');
      await _meta.delete('lastUpdatedAt');
    }
  }

  Future<int> deleteChapters(String seriesId, List<String> chapterIds) async {
    if (chapterIds.isEmpty) return 0;

    final chapters = getChapters(seriesId);
    final remaining = <Chapter>[];
    var deleted = 0;

    for (final chapter in chapters) {
      if (chapterIds.contains(chapter.id)) {
        await _deleteDirectoryIfExists(chapterDir(seriesId, chapter.id));
        await _deleteChapterProgress(seriesId, chapter.id);
        deleted++;
      } else {
        remaining.add(chapter);
      }
    }

    await saveChapters(seriesId, remaining);
    await clearSyncNewChapters(seriesId, chapterIds);

    if (lastSeriesId == seriesId &&
        lastChapterId != null &&
        chapterIds.contains(lastChapterId)) {
      await _meta.delete('lastChapterId');
      await _meta.delete('lastUpdatedAt');
    }

    return deleted;
  }

  Future<int> deleteChapterDownloads(String seriesId, List<String> chapterIds) async {
    if (chapterIds.isEmpty) return 0;

    final chapters = getChapters(seriesId);
    var deleted = 0;

    for (var i = 0; i < chapters.length; i++) {
      if (!chapterIds.contains(chapters[i].id)) continue;
      await _deleteDirectoryIfExists(chapterDir(seriesId, chapters[i].id));
      await _deleteChapterProgress(seriesId, chapters[i].id);
      chapters[i] = chapters[i].copyWith(
        imageUrls: const [],
        localPaths: const [],
        fetchedAt: null,
      );
      deleted++;
    }

    await saveChapters(seriesId, chapters);
    return deleted;
  }

  List<Series> getAllSeries() {
    final raw = _series.get('all');
    if (raw is! List) return [];
    return raw
        .map((e) => Series.fromMap(Map<dynamic, dynamic>.from(e as Map)))
        .toList()
      ..sort((a, b) {
        final aTime = a.addedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.addedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
  }

  List<Series> getActiveSeries() =>
      getAllSeries().where((s) => !s.isCompleted).toList();

  List<Series> getFavoriteSeries() =>
      getActiveSeries().where((s) => s.isFavorite).toList();

  Future<void> toggleFavorite(String seriesId) async {
    final series = getSeries(seriesId);
    if (series == null) return;
    await upsertSeries(series.copyWith(isFavorite: !series.isFavorite));
  }

  List<Series> getCompletedSeries() {
    final completed = getAllSeries().where((s) => s.isCompleted).toList()
      ..sort((a, b) {
        final aTime = a.completedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.completedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
    return completed;
  }

  Future<void> markSeriesCompleted(String seriesId) async {
    final series = getSeries(seriesId);
    if (series == null || series.isCompleted) return;
    await upsertSeries(series.copyWith(completedAt: DateTime.now()));
  }

  Future<void> restoreSeriesToLibrary(String seriesId) async {
    final series = getSeries(seriesId);
    if (series == null || !series.isCompleted) return;
    await upsertSeries(series.copyWith(clearCompletedAt: true));
  }

  Series? getSeries(String seriesId) {
    for (final series in getAllSeries()) {
      if (series.id == seriesId) return series;
    }
    return null;
  }

  Future<void> saveAllSeries(List<Series> seriesList) async {
    await _series.put('all', seriesList.map((s) => s.toMap()).toList());
    unawaited(_autoBackupIfDue());
    _queueCloudSync();
  }

  Future<void> upsertSeries(Series series) async {
    final safeUrl = SiteUrl.preferAllowedHost(series.url);
    final toSave =
        safeUrl == series.url ? series : series.copyWith(url: safeUrl);
    final all = getAllSeries();
    final index = all.indexWhere((s) => s.id == toSave.id);
    if (index >= 0) {
      all[index] = toSave;
    } else {
      all.insert(0, toSave);
    }
    await saveAllSeries(all);
  }

  Future<void> removeSeries(String seriesId) async {
    final all = getAllSeries().where((s) => s.id != seriesId).toList();
    await saveAllSeries(all);
    await _chapters.delete(seriesId);
  }

  File _latestBackupFile() => File(p.join(_rootDir.path, _latestBackupFileName));

  /// 클라우드/로컬 백업용 전체 스냅샷 (JSON 맵)
  Map<String, dynamic> exportBackup() {
    final lastMs = _meta.get('lastUpdatedAt');
    final exportedAt = lastMs is int
        ? DateTime.fromMillisecondsSinceEpoch(lastMs).toUtc()
        : DateTime.now().toUtc();
    return <String, dynamic>{
      'app': backupAppId,
      'version': 1,
      'exportedAt': exportedAt.toIso8601String(),
      'createdAt': exportedAt.toIso8601String(),
      'series': _jsonSafe((_series.get('all') as List?) ?? const []),
      'chapters': _jsonSafe({
        for (final key in _chapters.keys)
          if (key is String) key: _chapters.get(key),
      }),
      'progress': _jsonSafe({
        for (final key in _progress.keys)
          if (key is String) key: _progress.get(key),
      }),
      'meta': _jsonSafe({
        for (final key in _meta.keys)
          if (key is String) key: _meta.get(key),
      }),
    };
  }

  /// 백업 JSON으로 Hive 전체 덮어쓰기. 이미지 파일은 포함되지 않습니다.
  Future<void> importBackup(Map<String, dynamic> root) async {
    final app = root['app'];
    if (app != null && app != backupAppId) {
      throw FormatException('지원하지 않는 백업 파일입니다.');
    }
    final series = (root['series'] as List?) ?? const [];
    final chapters = Map<String, dynamic>.from(
      (root['chapters'] as Map?) ?? const {},
    );
    final progress = Map<String, dynamic>.from(
      (root['progress'] as Map?) ?? const {},
    );
    final meta = Map<String, dynamic>.from((root['meta'] as Map?) ?? const {});

    await _series.clear();
    await _chapters.clear();
    await _progress.clear();
    await _meta.clear();

    await _series.put('all', series);
    for (final entry in chapters.entries) {
      await _chapters.put(entry.key, entry.value);
    }
    for (final entry in progress.entries) {
      await _progress.put(entry.key, entry.value);
    }
    for (final entry in meta.entries) {
      await _meta.put(entry.key, entry.value);
    }
  }

  /// 데이터 변경 후 debounce 클라우드 push
  void _queueCloudSync() {
    final cloud = SupabaseSyncService.instance;
    if (!cloud.isReady || !cloud.isLoggedIn) return;
    _cloudSyncTimer?.cancel();
    _cloudSyncTimer = Timer(_cloudSyncDebounce, () {
      unawaited(pushToCloud());
    });
  }

  /// 즉시 클라우드에 업로드. 성공 여부 반환.
  Future<bool> pushToCloud() async {
    final cloud = SupabaseSyncService.instance;
    if (!cloud.isReady || !cloud.isLoggedIn) return false;
    if (_cloudSyncInFlight) {
      _cloudSyncQueued = true;
      return false;
    }
    _cloudSyncInFlight = true;
    try {
      var ok = await cloud.push(exportBackup());
      while (_cloudSyncQueued) {
        _cloudSyncQueued = false;
        ok = await cloud.push(exportBackup());
      }
      return ok;
    } catch (_) {
      return false;
    } finally {
      _cloudSyncInFlight = false;
    }
  }

  /// 앱이 백그라운드로 갈 때 debounce를 기다리지 않고 바로 올립니다.
  Future<void> flushCloudSync() async {
    _cloudSyncTimer?.cancel();
    _cloudSyncTimer = null;
    await pushToCloud();
  }

  /// 로그인 직후·앱 시작 시: 원격/로컬 중 최신으로 맞춤. 원격 적용 시 true.
  Future<bool> syncWithCloud() async {
    final cloud = SupabaseSyncService.instance;
    if (!cloud.isReady) await cloud.init();
    if (!cloud.isReady || !cloud.isLoggedIn) return false;
    try {
      return await cloud.syncAfterLocalLoad(this);
    } catch (_) {
      return false;
    }
  }

  dynamic _jsonSafe(dynamic value) {
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    if (value is List) {
      return value.map(_jsonSafe).toList();
    }
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _jsonSafe(entry.value),
      };
    }
    return value.toString();
  }

  Future<({String path, int seriesCount})> createLatestBackup() async {
    final now = DateTime.now();
    final payload = exportBackup();
    // 로컬 파일 백업은 기기 시각 createdAt 유지
    payload['createdAt'] = now.toIso8601String();
    final file = _latestBackupFile();
    await file.writeAsString(jsonEncode(payload), flush: true);
    await _meta.put('lastAutoBackupAtMs', now.millisecondsSinceEpoch);
    _queueCloudSync();
    return (path: file.path, seriesCount: getAllSeries().length);
  }

  Future<void> _autoBackupIfDue() async {
    if (_autoBackupRunning) return;
    final now = DateTime.now();
    final lastMs = _meta.get('lastAutoBackupAtMs') as int?;
    if (lastMs != null) {
      final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
      if (now.difference(last) < _autoBackupInterval) return;
    }

    _autoBackupRunning = true;
    try {
      await createLatestBackup();
      await _meta.put('lastAutoBackupAtMs', now.millisecondsSinceEpoch);
    } catch (_) {
      // 자동 백업 실패는 사용자 흐름을 막지 않습니다.
    } finally {
      _autoBackupRunning = false;
    }
  }

  Future<({int seriesCount, DateTime? createdAt})?> latestBackupInfo() async {
    final file = _latestBackupFile();
    if (!await file.exists()) return null;
    final text = await file.readAsString();
    final decoded = jsonDecode(text);
    if (decoded is! Map) return null;
    final map = Map<String, dynamic>.from(decoded);
    final series = map['series'] as List? ?? const [];
    final createdRaw = map['createdAt'] as String?;
    return (
      seriesCount: series.length,
      createdAt: createdRaw != null ? DateTime.tryParse(createdRaw) : null,
    );
  }

  Future<({int seriesCount, int chapterGroups})> restoreLatestBackup() async {
    final file = _latestBackupFile();
    if (!await file.exists()) {
      throw Exception('백업 파일이 없습니다. 먼저 백업을 생성해 주세요.');
    }
    final text = await file.readAsString();
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw Exception('백업 파일 형식이 올바르지 않습니다.');
    }
    final map = Map<String, dynamic>.from(decoded);
    await importBackup(map);
    final series = (map['series'] as List?) ?? const [];
    final chapters = Map<String, dynamic>.from(
      (map['chapters'] as Map?) ?? const {},
    );
    _queueCloudSync();
    return (seriesCount: series.length, chapterGroups: chapters.length);
  }

  Future<List<Series>> recoverMissingSeriesFromChapters() async {
    final all = getAllSeries();
    final existingIds = all.map((s) => s.id).toSet();
    final recoveredSeries = <Series>[];

    for (final key in _chapters.keys) {
      if (key is! String || key.isEmpty) continue;
      if (existingIds.contains(key)) continue;
      final chapters = getChapters(key);
      if (chapters.isEmpty) continue;

      final chapterUrl = chapters.first.url;
      final recoveredUrl =
          Series.parentSeriesUrlFromChapterUrl(chapterUrl) ??
              '$siteOrigin/webtoon/$key';
      final recovered = Series(
        id: key,
        title: key,
        url: recoveredUrl,
        addedAt: DateTime.now(),
        lastRefreshedAt: DateTime.now(),
      );
      all.add(recovered);
      existingIds.add(key);
      recoveredSeries.add(recovered);
    }

    if (recoveredSeries.isNotEmpty) {
      await saveAllSeries(all);
    }
    return recoveredSeries;
  }

  List<String> scanChapterPagePaths(String seriesId, String chapterId) {
    final dir = chapterDir(seriesId, chapterId);
    if (!dir.existsSync()) return const [];

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('page_'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    return files
        .where((f) => f.lengthSync() >= Chapter.minPanelFileBytes)
        .map((f) => f.path)
        .toList();
  }

  /// 동기 디스크 스캔 없이 경로만 맞출 때 사용. 앱 시작 시 UI를 막지 않기 위함.
  Future<List<String>> scanChapterPagePathsAsync(
    String seriesId,
    String chapterId,
  ) async {
    final dir = chapterDir(seriesId, chapterId);
    if (!await dir.exists()) return const [];

    final files = <File>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      if (!p.basename(entity.path).startsWith('page_')) continue;
      files.add(entity);
    }
    files.sort((a, b) => a.path.compareTo(b.path));

    final paths = <String>[];
    for (final file in files) {
      try {
        if (await file.length() >= Chapter.minPanelFileBytes) {
          paths.add(file.path);
        }
      } catch (_) {}
    }
    return paths;
  }

  Chapter reconcileChapterDownloads(String seriesId, Chapter chapter) {
    final diskPaths = scanChapterPagePaths(seriesId, chapter.id);
    return _applyReconciledPaths(chapter, diskPaths);
  }

  Future<Chapter> reconcileChapterDownloadsAsync(
    String seriesId,
    Chapter chapter,
  ) async {
    final diskPaths = await scanChapterPagePathsAsync(seriesId, chapter.id);
    return _applyReconciledPaths(chapter, diskPaths);
  }

  Chapter _applyReconciledPaths(Chapter chapter, List<String> diskPaths) {
    if (diskPaths.isEmpty) {
      if (chapter.localPaths.isEmpty) return chapter;
      return chapter.copyWith(localPaths: const [], pageAspectRatios: const []);
    }

    var updated = chapter;
    if (diskPaths.length != chapter.localPaths.length ||
        !_pathsEqual(diskPaths, chapter.localPaths)) {
      updated = updated.copyWith(
        localPaths: diskPaths,
        pageAspectRatios: Chapter.alignAspectRatios(
          chapter.pageAspectRatios,
          diskPaths.length,
        ),
      );
    }

    return updated;
  }

  bool _pathsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _chapterDownloadsChanged(Chapter before, Chapter after) {
    return !_pathsEqual(before.localPaths, after.localPaths) ||
        before.imageUrls.length != after.imageUrls.length ||
        !_pathsEqual(before.imageUrls, after.imageUrls);
  }

  Future<bool> reconcileSeriesDownloads(String seriesId) async {
    final chapters = getChapters(seriesId);
    if (chapters.isEmpty) return false;

    var changed = false;
    final updated = <Chapter>[];
    for (final chapter in chapters) {
      // 비동기 스캔으로 메인 isolate 블로킹을 줄입니다.
      final reconciled = await reconcileChapterDownloadsAsync(seriesId, chapter);
      if (_chapterDownloadsChanged(chapter, reconciled)) changed = true;
      updated.add(reconciled);
    }

    if (changed) {
      await saveChapters(seriesId, updated);
    }
    return changed;
  }

  /// 시리즈 목록을 순차 reconcile. 한 시리즈마다 yield 해 UI 프레임을 양보합니다.
  Future<void> reconcileAllSeriesDownloads({
    void Function(int done, int total)? onProgress,
  }) async {
    final all = getAllSeries();
    final total = all.length;
    for (var i = 0; i < total; i++) {
      try {
        await reconcileSeriesDownloads(all[i].id);
      } catch (_) {}
      onProgress?.call(i + 1, total);
      // 프레임 양보
      await Future<void>.delayed(Duration.zero);
    }
  }

  List<Chapter> getChapters(String seriesId) {
    final raw = _chapters.get(seriesId);
    if (raw is! List) return [];
    return raw
        .map((e) => Chapter.fromMap(Map<dynamic, dynamic>.from(e as Map)))
        .toList()
      ..sort((a, b) => b.number.compareTo(a.number));
  }

  Future<void> saveChapters(String seriesId, List<Chapter> chapters) async {
    final sanitized = chapters
        .map((chapter) {
          final safeUrl = SiteUrl.preferAllowedHost(chapter.url);
          if (safeUrl == chapter.url) return chapter;
          return chapter.copyWith(url: safeUrl);
        })
        .toList();
    await _chapters.put(
      seriesId,
      sanitized.map((c) => c.toMap()).toList(),
    );
    unawaited(_autoBackupIfDue());
    _queueCloudSync();
  }

  Future<void> upsertChapter(String seriesId, Chapter chapter) async {
    final chapters = getChapters(seriesId);
    final index = chapters.indexWhere((c) => c.id == chapter.id);
    if (index >= 0) {
      chapters[index] = chapter;
    } else {
      chapters.add(chapter);
    }
    chapters.sort((a, b) => b.number.compareTo(a.number));
    await saveChapters(seriesId, chapters);
  }

  String _progressKey(String seriesId, String chapterId) =>
      '$seriesId::$chapterId';

  ReadingProgress? getProgress(String seriesId, String chapterId) {
    final raw = _progress.get(_progressKey(seriesId, chapterId));
    if (raw == null) {
      final legacy = _progress.get(chapterId);
      if (legacy == null) return null;
      return ReadingProgress.fromMap(Map<dynamic, dynamic>.from(legacy as Map));
    }
    return ReadingProgress.fromMap(Map<dynamic, dynamic>.from(raw as Map));
  }

  ReadingProgress? getLastReadProgress() {
    final lastSeriesId = _meta.get('lastSeriesId') as String?;
    final lastChapterId = _meta.get('lastChapterId') as String?;
    if (lastSeriesId == null || lastChapterId == null) return null;
    return getProgress(lastSeriesId, lastChapterId);
  }

  String? get lastSeriesId => _meta.get('lastSeriesId') as String?;
  String? get lastChapterId => _meta.get('lastChapterId') as String?;

  Future<void> saveProgress(
    String seriesId,
    ReadingProgress progress, {
    bool allowAutoBackup = false,
  }) async {
    final existing = getProgress(seriesId, progress.chapterId);
    if (existing != null && existing.isSameAnchor(progress)) {
      if (lastSeriesId == seriesId && lastChapterId == progress.chapterId) {
        return;
      }
      await _meta.put('lastSeriesId', seriesId);
      await _meta.put('lastChapterId', progress.chapterId);
      return;
    }
    await _progress.put(
      _progressKey(seriesId, progress.chapterId),
      progress.toMap(),
    );
    await _meta.put('lastSeriesId', seriesId);
    await _meta.put('lastChapterId', progress.chapterId);
    await _meta.put('lastUpdatedAt', progress.updatedAt.millisecondsSinceEpoch);
    // 스크롤 중 잦은 progress 저장이 로컬 파일 백업 I/O를 유발하지 않게 기본 제외합니다.
    if (allowAutoBackup) {
      unawaited(_autoBackupIfDue());
    }
    // 클라우드는 debounce 로 묶어서 읽기 위치도 동기화합니다.
    _queueCloudSync();
  }

  int downloadedChapterCount(String seriesId) {
    return getChapters(seriesId).where((c) => c.isOnCloud).length;
  }

  int newChapterCount(String seriesId) {
    return getChapters(seriesId).where((c) => !c.isOnCloud).length;
  }

  String _syncNewChaptersKey(String seriesId) => 'syncNewChapters::$seriesId';

  Set<String> getSyncNewChapterIds(String seriesId) {
    final raw = _meta.get(_syncNewChaptersKey(seriesId));
    if (raw is! List) return {};
    return raw.cast<String>().toSet();
  }

  int syncNewChapterCount(String seriesId) => getSyncNewChapterIds(seriesId).length;

  Future<void> addSyncNewChapters(
    String seriesId,
    Iterable<String> chapterIds,
  ) async {
    final merged = getSyncNewChapterIds(seriesId)..addAll(chapterIds);
    if (merged.isEmpty) return;
    await _meta.put(_syncNewChaptersKey(seriesId), merged.toList());
  }

  Future<void> clearSyncNewChapter(String seriesId, String chapterId) async {
    final merged = getSyncNewChapterIds(seriesId)..remove(chapterId);
    if (merged.isEmpty) {
      await _meta.delete(_syncNewChaptersKey(seriesId));
    } else {
      await _meta.put(_syncNewChaptersKey(seriesId), merged.toList());
    }
  }

  Future<void> clearSyncNewChapters(
    String seriesId,
    Iterable<String> chapterIds,
  ) async {
    final merged = getSyncNewChapterIds(seriesId)..removeAll(chapterIds);
    if (merged.isEmpty) {
      await _meta.delete(_syncNewChaptersKey(seriesId));
    } else {
      await _meta.put(_syncNewChaptersKey(seriesId), merged.toList());
    }
  }

  /// 읽기 기록이 있는 회차 중 가장 큰 화 번호.
  int? getFurthestReadChapterNumber(String seriesId) {
    final chapters = getChapters(seriesId);
    var furthest = 0;
    for (final chapter in chapters) {
      if (getProgress(seriesId, chapter.id) == null) continue;
      if (chapter.number > furthest) furthest = chapter.number;
    }
    return furthest > 0 ? furthest : null;
  }

  /// 가장 최근에 연 회차의 시각.
  DateTime? getLastReadAt(String seriesId) {
    final chapters = getChapters(seriesId);
    DateTime? lastAt;
    for (final chapter in chapters) {
      final progress = getProgress(seriesId, chapter.id);
      if (progress == null) continue;
      if (lastAt == null || progress.updatedAt.isAfter(lastAt)) {
        lastAt = progress.updatedAt;
      }
    }
    return lastAt;
  }

  /// 가장 최근에 연 회차.
  Chapter? getLastReadChapter(String seriesId) {
    final chapters = getChapters(seriesId);
    Chapter? lastChapter;
    DateTime? lastAt;
    for (final chapter in chapters) {
      final progress = getProgress(seriesId, chapter.id);
      if (progress == null) continue;
      if (lastAt == null || progress.updatedAt.isAfter(lastAt)) {
        lastAt = progress.updatedAt;
        lastChapter = chapter;
      }
    }
    return lastChapter;
  }

  LibrarySortMode get librarySortMode =>
      LibrarySortMode.tryParse(_meta.get('librarySortMode') as String?) ??
      LibrarySortMode.recentlyRead;

  Future<void> setLibrarySortMode(LibrarySortMode mode) async {
    await _meta.put('librarySortMode', mode.name);
  }

  LibrarySortMode get completedLibrarySortMode =>
      LibrarySortMode.tryParse(_meta.get('completedLibrarySortMode') as String?) ??
      LibrarySortMode.recentlyRead;

  Future<void> setCompletedLibrarySortMode(LibrarySortMode mode) async {
    await _meta.put('completedLibrarySortMode', mode.name);
  }

  /// light | dark | system. 기본 light.
  String get themeModeName {
    final raw = _meta.get('themeMode') as String?;
    if (raw == 'dark' || raw == 'system' || raw == 'light') return raw!;
    return 'light';
  }

  Future<void> setThemeModeName(String name) async {
    await _meta.put('themeMode', name);
  }

  /// true면 셀룰러에서 다운로드를 막습니다.
  bool get wifiOnlyDownload => _meta.get('wifiOnlyDownload') as bool? ?? false;

  Future<void> setWifiOnlyDownload(bool value) async {
    await _meta.put('wifiOnlyDownload', value);
  }

  /// 회차 목록을 오래된 순(1화→)으로 보여줄지.
  bool get chapterListOldestFirst =>
      chapterListSortMode == 'oldest';

  Future<void> setChapterListOldestFirst(bool value) async {
    await setChapterListSortMode(value ? 'oldest' : 'newest');
  }

  /// `newest` | `oldest` | `random`
  String get chapterListSortMode {
    final mode = _meta.get('chapterListSortMode') as String?;
    if (mode == 'newest' || mode == 'oldest' || mode == 'random') {
      return mode!;
    }
    return (_meta.get('chapterListOldestFirst') as bool? ?? false)
        ? 'oldest'
        : 'newest';
  }

  Future<void> setChapterListSortMode(String mode) async {
    final normalized =
        (mode == 'oldest' || mode == 'random') ? mode : 'newest';
    await _meta.put('chapterListSortMode', normalized);
    await _meta.put('chapterListOldestFirst', normalized == 'oldest');
  }

  String _randomOrderKey(String seriesId) => 'chapterRandomOrder_$seriesId';

  List<String> getChapterRandomOrder(String seriesId) {
    final raw = _meta.get(_randomOrderKey(seriesId));
    if (raw is List) {
      return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    return const [];
  }

  Future<void> setChapterRandomOrder(String seriesId, List<String> ids) async {
    await _meta.put(_randomOrderKey(seriesId), ids);
  }

  Future<void> clearChapterRandomOrder(String seriesId) async {
    await _meta.delete(_randomOrderKey(seriesId));
  }

  /// 랜덤 순서를 새로 섞거나, 기존 순서를 회차 목록에 맞게 맞춥니다.
  Future<List<Chapter>> shuffleChapterOrder(
    String seriesId, {
    bool reshuffle = true,
  }) async {
    final chapters = getChapters(seriesId);
    if (chapters.isEmpty) return chapters;

    List<String> order;
    if (reshuffle) {
      order = chapters.map((c) => c.id).toList()..shuffle();
    } else {
      order = getChapterRandomOrder(seriesId);
      if (order.isEmpty) {
        order = chapters.map((c) => c.id).toList()..shuffle();
      }
    }

    final byId = {for (final c in chapters) c.id: c};
    final ordered = <Chapter>[];
    for (final id in order) {
      final chapter = byId.remove(id);
      if (chapter != null) ordered.add(chapter);
    }
    if (byId.isNotEmpty) {
      final rest = byId.values.toList()
        ..sort((a, b) => a.number.compareTo(b.number));
      ordered.addAll(rest);
    }
    await setChapterRandomOrder(
      seriesId,
      ordered.map((c) => c.id).toList(),
    );
    await setChapterListSortMode('random');
    return ordered;
  }

  /// 회차 목록/이전다음 이동에 쓰는 표시·탐색 순서.
  List<Chapter> orderedChaptersForNavigation(String seriesId) {
    final chapters = getChapters(seriesId);
    final mode = chapterListSortMode;
    if (mode == 'oldest') {
      return chapters.toList()
        ..sort((a, b) => a.number.compareTo(b.number));
    }
    if (mode != 'random') {
      return chapters;
    }
    final order = getChapterRandomOrder(seriesId);
    if (order.isEmpty) return chapters;
    final byId = {for (final c in chapters) c.id: c};
    final ordered = <Chapter>[];
    for (final id in order) {
      final chapter = byId.remove(id);
      if (chapter != null) ordered.add(chapter);
    }
    if (byId.isNotEmpty) {
      final rest = byId.values.toList()
        ..sort((a, b) => a.number.compareTo(b.number));
      ordered.addAll(rest);
    }
    return ordered;
  }

  /// 끝 근처 읽음 비율 (페이지 기준). 이 이상이면 completed로 취급합니다.
  static const completedPageProgress = 0.92;

  /// 이어 읽기 대상. 완료된 화면 다음 화를 우선합니다.
  ({Chapter chapter, bool startAtTop, bool isNextAfterCompleted})?
      getContinueTarget(String seriesId) {
    final last = getLastReadChapter(seriesId);
    if (last == null) return null;
    final progress = getProgress(seriesId, last.id);
    if (progress != null && progress.completed) {
      final next = Chapter.findNextByNumber(
        getChapters(seriesId),
        last,
        canNavigate: (_) => true,
      );
      if (next != null) {
        return (
          chapter: next,
          startAtTop: true,
          isNextAfterCompleted: true,
        );
      }
    }
    return (
      chapter: last,
      startAtTop: false,
      isNextAfterCompleted: false,
    );
  }

  /// 시리즈 저장 폴더 용량(바이트). 디스크 I/O — UI 스레드에서 장시간 돌리지 마세요.
  Future<int> seriesStorageBytes(String seriesId) async {
    return _directorySize(seriesDir(seriesId));
  }

  /// 전체 웹툰 캐시 용량(바이트).
  Future<int> totalWebtoonStorageBytes() async {
    final root = Directory(p.join(_rootDir.path, 'webtoon'));
    return _directorySize(root);
  }

  Future<int> _directorySize(Directory dir) async {
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {}
      }
    }
    return total;
  }

  String get siteOrigin {
    final raw = _meta.get('siteOrigin') as String?;
    if (raw != null && raw.trim().isNotEmpty) {
      return SiteUrl.normalizeOrigin(raw);
    }
    return SiteUrl.normalizeOrigin(AppConstants.defaultSiteOrigin);
  }

  String get browseCatalogUrl => SiteUrl.browseCatalogUrl(siteOrigin);

  Future<void> setSiteOrigin(String origin) async {
    await _meta.put('siteOrigin', SiteUrl.normalizeOrigin(origin));
  }

  Future<SiteMigrationResult> migrateSiteOrigin(String newOriginInput) async {
    final oldOrigin = siteOrigin;
    final newOrigin = SiteUrl.normalizeOrigin(newOriginInput);
    final oldHost = SiteUrl.hostOf(oldOrigin);
    final newHost = SiteUrl.hostOf(newOrigin);

    if (oldHost == null || newHost == null || newHost.isEmpty) {
      throw ArgumentError('올바른 사이트 주소를 입력하세요');
    }
    if (oldHost == newHost) {
      throw ArgumentError('현재 주소와 같습니다');
    }

    var seriesUpdated = 0;
    var chaptersUpdated = 0;
    var urlFieldsUpdated = 0;

    String rewrite(String url) {
      final next = SiteUrl.rewriteHost(url, oldHost, newOrigin);
      if (next != url) urlFieldsUpdated++;
      return next;
    }

    for (final series in getAllSeries()) {
      var updated = series;
      var changed = false;

      final nextUrl = rewrite(series.url);
      if (nextUrl != series.url) {
        updated = updated.copyWith(url: nextUrl);
        changed = true;
      }
      if (series.coverUrl != null && series.coverUrl!.isNotEmpty) {
        final nextCover = rewrite(series.coverUrl!);
        if (nextCover != series.coverUrl) {
          updated = updated.copyWith(coverUrl: nextCover);
          changed = true;
        }
      }
      if (changed) {
        await upsertSeries(updated);
        seriesUpdated++;
      }

      final chapters = getChapters(series.id);
      var chapterListChanged = false;
      final nextChapters = chapters.map((chapter) {
        var next = chapter;
        var chapterChanged = false;

        final nextChapterUrl = rewrite(chapter.url);
        if (nextChapterUrl != chapter.url) {
          next = next.copyWith(url: nextChapterUrl);
          chapterChanged = true;
        }

        if (chapter.imageUrls.isNotEmpty) {
          final nextUrls = chapter.imageUrls.map(rewrite).toList();
          if (!_stringListsEqual(nextUrls, chapter.imageUrls)) {
            next = next.copyWith(imageUrls: nextUrls);
            chapterChanged = true;
          }
        }

        if (chapterChanged) {
          chapterListChanged = true;
          chaptersUpdated++;
        }
        return next;
      }).toList();

      if (chapterListChanged) {
        await saveChapters(series.id, nextChapters);
      }
    }

    await setSiteOrigin(newOrigin);

    return SiteMigrationResult(
      oldOrigin: oldOrigin,
      newOrigin: newOrigin,
      seriesUpdated: seriesUpdated,
      chaptersUpdated: chaptersUpdated,
      urlFieldsUpdated: urlFieldsUpdated,
    );
  }

  bool _stringListsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
