import '../models/chapter.dart';
import '../models/reading_progress.dart';
import '../models/series.dart';

const _deviceMetaKeys = {
  'themeMode',
  'wifiOnlyDownload',
  'librarySortMode',
  'completedLibrarySortMode',
  'chapterListOldestFirst',
  'chapterListSortMode',
  'lastAutoBackupAtMs',
  'siteOrigin',
};

bool isBackupEffectivelyEmpty(Map<String, dynamic> root) {
  final series = root['series'];
  if (series is List && series.isNotEmpty) return false;
  final chapters = root['chapters'];
  if (chapters is Map && chapters.isNotEmpty) return false;
  final progress = root['progress'];
  if (progress is Map && progress.isNotEmpty) return false;
  final meta = root['meta'];
  if (meta is Map) {
    final seriesId = meta['lastSeriesId']?.toString() ?? '';
    final chapterId = meta['lastChapterId']?.toString() ?? '';
    if (seriesId.isNotEmpty && chapterId.isNotEmpty) return false;
  }
  return true;
}

/// 원격 조회가 실패하면 빈 서재로 보고 로컬을 올리지 않습니다.
bool shouldUploadLocalShelf({
  required bool pullFailed,
  required bool remoteMissing,
  required bool localEmpty,
}) {
  if (pullFailed || localEmpty || !remoteMissing) return false;
  return true;
}

/// Two-device snapshot merge. Reading progress is per-chapter, newer
/// [updatedAt] wins. Last-read pointer follows the newest meaningful
/// progress so opening the app cannot overwrite another phone's chapter.
Map<String, dynamic> mergeWebtoonBackups(
  Map<String, dynamic> local,
  Map<String, dynamic> remote,
) {
  final progress = mergeProgressMaps(
    _asStringKeyedMap(local['progress']),
    _asStringKeyedMap(remote['progress']),
  );
  final meta = mergeMetaMaps(
    _asStringKeyedMap(local['meta']),
    _asStringKeyedMap(remote['meta']),
    progress,
  );
  final exportedAt = _laterIso(
        local['exportedAt']?.toString(),
        remote['exportedAt']?.toString(),
      ) ??
      DateTime.now().toUtc().toIso8601String();

  return <String, dynamic>{
    'app': local['app'] ?? remote['app'],
    'version': local['version'] ?? remote['version'] ?? 1,
    'exportedAt': exportedAt,
    'createdAt': exportedAt,
    'series': mergeSeriesLists(local['series'], remote['series']),
    'chapters': mergeChapterGroups(local['chapters'], remote['chapters']),
    'progress': progress,
    'meta': meta,
  };
}

bool backupShouldReloadUi(
  Map<String, dynamic> local,
  Map<String, dynamic> merged,
) {
  final localMeta = _asStringKeyedMap(local['meta']);
  final mergedMeta = _asStringKeyedMap(merged['meta']);
  if (localMeta['lastSeriesId'] != mergedMeta['lastSeriesId']) return true;
  if (localMeta['lastChapterId'] != mergedMeta['lastChapterId']) return true;

  final localSeries = _seriesIds(local['series']);
  final mergedSeries = _seriesIds(merged['series']);
  if (localSeries.length != mergedSeries.length ||
      !localSeries.containsAll(mergedSeries)) {
    return true;
  }

  final localChapters = _asStringKeyedMap(local['chapters']);
  final mergedChapters = _asStringKeyedMap(merged['chapters']);
  if (localChapters.length != mergedChapters.length) return true;
  for (final entry in mergedChapters.entries) {
    final before = localChapters[entry.key];
    final after = entry.value;
    if (before is! List || after is! List) return true;
    if (before.length != after.length) return true;
  }

  final localProgress = _asStringKeyedMap(local['progress']);
  final mergedProgress = _asStringKeyedMap(merged['progress']);
  if (localProgress.length != mergedProgress.length) return true;
  for (final entry in mergedProgress.entries) {
    final before = localProgress[entry.key];
    if (before is! Map) return true;
    final after = entry.value;
    if (after is! Map) continue;
    if (_updatedAtMs(before) != _updatedAtMs(after)) return true;
    if (before['chapterId'] != after['chapterId']) return true;
  }
  return false;
}

Map<String, dynamic> mergeProgressMaps(
  Map<String, dynamic> local,
  Map<String, dynamic> remote,
) {
  final keys = {...local.keys, ...remote.keys};
  final out = <String, dynamic>{};
  for (final key in keys) {
    final left = local[key];
    final right = remote[key];
    if (left == null) {
      out[key] = _cloneValue(right);
      continue;
    }
    if (right == null) {
      out[key] = _cloneValue(left);
      continue;
    }
    out[key] = _newerProgress(left, right);
  }
  return out;
}

Map<String, dynamic> mergeMetaMaps(
  Map<String, dynamic> local,
  Map<String, dynamic> remote,
  Map<String, dynamic> progress,
) {
  final out = <String, dynamic>{...remote, ...local};
  for (final key in _deviceMetaKeys) {
    if (local.containsKey(key)) {
      out[key] = local[key];
    } else if (remote.containsKey(key)) {
      out[key] = remote[key];
    }
  }
  _applyLastReadFromProgress(out, progress);
  return out;
}

List<dynamic> mergeSeriesLists(dynamic local, dynamic remote) {
  final byId = <String, Map<String, dynamic>>{};
  void ingest(dynamic list, {required bool isLocal}) {
    if (list is! List) return;
    for (final item in list) {
      if (item is! Map) continue;
      final map = _asStringKeyedMap(item);
      final id = map['id']?.toString();
      if (id == null || id.isEmpty) continue;
      final existing = byId[id];
      if (existing == null) {
        byId[id] = map;
        continue;
      }
      byId[id] = isLocal
          ? _mergeSeriesMaps(map, existing)
          : _mergeSeriesMaps(existing, map);
    }
  }

  ingest(remote, isLocal: false);
  ingest(local, isLocal: true);
  return byId.values.toList();
}

Map<String, dynamic> mergeChapterGroups(dynamic local, dynamic remote) {
  final localMap = _asStringKeyedMap(local);
  final remoteMap = _asStringKeyedMap(remote);
  final out = <String, dynamic>{};
  for (final seriesId in {...localMap.keys, ...remoteMap.keys}) {
    out[seriesId] = _mergeChapterLists(localMap[seriesId], remoteMap[seriesId]);
  }
  return out;
}

List<dynamic> _mergeChapterLists(dynamic local, dynamic remote) {
  final byId = <String, Map<String, dynamic>>{};
  void ingest(dynamic list, {required bool isLocal}) {
    if (list is! List) return;
    for (final item in list) {
      if (item is! Map) continue;
      final map = _asStringKeyedMap(item);
      final id = map['id']?.toString();
      if (id == null || id.isEmpty) continue;
      final existing = byId[id];
      if (existing == null) {
        byId[id] = map;
        continue;
      }
      byId[id] = _mergeChapterMaps(
        existing,
        map,
        preferIncomingLocalPaths: isLocal,
      );
    }
  }

  ingest(remote, isLocal: false);
  ingest(local, isLocal: true);
  return byId.values.toList();
}

Map<String, dynamic> _mergeSeriesMaps(
  Map<String, dynamic> a,
  Map<String, dynamic> b,
) {
  Series parsed(Map<String, dynamic> raw) => Series.fromMap(raw);
  try {
    final left = parsed(a);
    final right = parsed(b);
    final laterRefresh = _laterDate(left.lastRefreshedAt, right.lastRefreshedAt);
    final title = laterRefresh == right.lastRefreshedAt && right.title.isNotEmpty
        ? right.title
        : (left.title.isNotEmpty ? left.title : right.title);
    return Series(
      id: left.id,
      title: title,
      url: left.url.isNotEmpty ? left.url : right.url,
      coverUrl: left.coverUrl ?? right.coverUrl,
      coverPath: left.coverPath ?? right.coverPath,
      lastRefreshedAt: laterRefresh,
      addedAt: _earlierDate(left.addedAt, right.addedAt) ?? left.addedAt ?? right.addedAt,
      completedAt: _laterDate(left.completedAt, right.completedAt),
      isFavorite: left.isFavorite || right.isFavorite,
    ).toMap();
  } catch (_) {
    return {...a, ...b};
  }
}

Map<String, dynamic> _mergeChapterMaps(
  Map<String, dynamic> existing,
  Map<String, dynamic> incoming, {
  required bool preferIncomingLocalPaths,
}) {
  try {
    final current = Chapter.fromMap(existing);
    final next = Chapter.fromMap(incoming);
    final localPaths =
        preferIncomingLocalPaths ? next.localPaths : current.localPaths;
    final richerImages = next.imageUrls.length > current.imageUrls.length
        ? next.imageUrls
        : current.imageUrls;
    return Chapter(
      id: current.id,
      title: current.title.isNotEmpty ? current.title : next.title,
      url: current.url.isNotEmpty ? current.url : next.url,
      number: current.number != 0 ? current.number : next.number,
      imageUrls: richerImages,
      localPaths: localPaths,
      fetchedAt: _laterDate(current.fetchedAt, next.fetchedAt),
      sitePageTotal: _maxInt(current.sitePageTotal, next.sitePageTotal),
      publishedLabel: (current.publishedLabel != null &&
              current.publishedLabel!.isNotEmpty)
          ? current.publishedLabel
          : next.publishedLabel,
      pageAspectRatios: Chapter.alignAspectRatios(
        localPaths.isNotEmpty &&
                current.pageAspectRatios.length >= localPaths.length
            ? current.pageAspectRatios
            : next.pageAspectRatios,
        localPaths.length,
      ),
      cloudPageCount: _maxInt(current.cloudPageCount, next.cloudPageCount),
      cloudUploadedAt: _laterDate(current.cloudUploadedAt, next.cloudUploadedAt),
    ).toMap();
  } catch (_) {
    return preferIncomingLocalPaths ? {...existing, ...incoming} : {...incoming, ...existing};
  }
}

dynamic _newerProgress(dynamic left, dynamic right) {
  final a = left is Map ? _asStringKeyedMap(left) : null;
  final b = right is Map ? _asStringKeyedMap(right) : null;
  if (a == null) return _cloneValue(right);
  if (b == null) return _cloneValue(left);
  final aAt = _updatedAtMs(a);
  final bAt = _updatedAtMs(b);
  if (bAt > aAt) return b;
  if (aAt > bAt) return a;
  final aProgress = ReadingProgress.fromMap(a);
  final bProgress = ReadingProgress.fromMap(b);
  if (bProgress.completed && !aProgress.completed) return b;
  if (aProgress.completed && !bProgress.completed) return a;
  if ((bProgress.pageIndex ?? 0) > (aProgress.pageIndex ?? 0)) return b;
  if (bProgress.scrollOffset > aProgress.scrollOffset) return b;
  return a;
}

void _applyLastReadFromProgress(
  Map<String, dynamic> meta,
  Map<String, dynamic> progress,
) {
  String? bestKey;
  var bestAt = -1;
  var usedMeaningful = false;

  void consider(String key, Map<String, dynamic> raw, {required bool meaningfulOnly}) {
    if (meaningfulOnly && !_isMeaningfulProgress(raw)) return;
    final at = _updatedAtMs(raw);
    if (at > bestAt) {
      bestAt = at;
      bestKey = key;
    }
  }

  for (final entry in progress.entries) {
    final raw = entry.value;
    if (raw is! Map) continue;
    consider(entry.key, _asStringKeyedMap(raw), meaningfulOnly: true);
  }
  usedMeaningful = bestKey != null;
  if (!usedMeaningful) {
    for (final entry in progress.entries) {
      final raw = entry.value;
      if (raw is! Map) continue;
      consider(entry.key, _asStringKeyedMap(raw), meaningfulOnly: false);
    }
  }

  if (bestKey == null) return;
  final split = bestKey!.indexOf('::');
  if (split <= 0) {
    meta['lastChapterId'] = bestKey;
    if (bestAt >= 0) meta['lastUpdatedAt'] = bestAt;
    return;
  }
  meta['lastSeriesId'] = bestKey!.substring(0, split);
  meta['lastChapterId'] = bestKey!.substring(split + 2);
  if (bestAt >= 0) meta['lastUpdatedAt'] = bestAt;
}

bool _isMeaningfulProgress(Map<String, dynamic> raw) {
  return ReadingProgress.isMeaningfulMap(raw);
}

Map<String, dynamic> _asStringKeyedMap(dynamic raw) {
  if (raw is! Map) return <String, dynamic>{};
  return <String, dynamic>{
    for (final entry in raw.entries) entry.key.toString(): entry.value,
  };
}

Set<String> _seriesIds(dynamic series) {
  if (series is! List) return <String>{};
  return {
    for (final item in series)
      if (item is Map && item['id'] != null) item['id'].toString(),
  };
}

int _updatedAtMs(Map<dynamic, dynamic> raw) {
  final value = raw['updatedAt'];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

int? _maxInt(int? a, int? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a >= b ? a : b;
}

DateTime? _laterDate(DateTime? a, DateTime? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.isAfter(b) ? a : b;
}

DateTime? _earlierDate(DateTime? a, DateTime? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.isBefore(b) ? a : b;
}

String? _laterIso(String? a, String? b) {
  final aAt = a == null ? null : DateTime.tryParse(a)?.toUtc();
  final bAt = b == null ? null : DateTime.tryParse(b)?.toUtc();
  if (aAt == null) return b;
  if (bAt == null) return a;
  return aAt.isAfter(bAt) ? a : b;
}

dynamic _cloneValue(dynamic value) {
  if (value is Map) return _asStringKeyedMap(value);
  if (value is List) return value.map(_cloneValue).toList();
  return value;
}
