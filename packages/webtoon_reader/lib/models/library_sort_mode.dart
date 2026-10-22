import '../services/storage_service.dart';
import 'chapter.dart';
import 'series.dart';

enum LibrarySortMode {
  recentlyRead,
  recentlyAdded,
  titleAsc,
  titleDesc,
  chapterCountDesc,
  chapterCountAsc,
  pendingDesc,
  completedAt;

  String get label => switch (this) {
        LibrarySortMode.recentlyRead => '최근 본 순',
        LibrarySortMode.recentlyAdded => '추가한 순',
        LibrarySortMode.titleAsc => '제목 가나다',
        LibrarySortMode.titleDesc => '제목 역순',
        LibrarySortMode.chapterCountDesc => '회차 많은 순',
        LibrarySortMode.chapterCountAsc => '회차 적은 순',
        LibrarySortMode.pendingDesc => '미보관 많은 순',
        LibrarySortMode.completedAt => '완료한 순',
      };

  static LibrarySortMode? tryParse(String? value) {
    if (value == null) return null;
    for (final mode in LibrarySortMode.values) {
      if (mode.name == value) return mode;
    }
    return null;
  }

  static const activeLibraryModes = [
    LibrarySortMode.recentlyRead,
    LibrarySortMode.recentlyAdded,
    LibrarySortMode.titleAsc,
    LibrarySortMode.titleDesc,
    LibrarySortMode.chapterCountDesc,
    LibrarySortMode.chapterCountAsc,
    LibrarySortMode.pendingDesc,
  ];

  static const completedLibraryModes = [
    LibrarySortMode.recentlyRead,
    LibrarySortMode.completedAt,
    LibrarySortMode.recentlyAdded,
    LibrarySortMode.titleAsc,
    LibrarySortMode.titleDesc,
    LibrarySortMode.chapterCountDesc,
    LibrarySortMode.chapterCountAsc,
  ];
}

/// 정렬·카드 표시용으로 시리즈당 한 번 계산하는 요약 값입니다.
class SeriesLibraryStats {
  const SeriesLibraryStats({
    required this.chapterCount,
    required this.downloadedCount,
    required this.pendingCount,
    this.cloudOnlyCount = 0,
    this.lastReadChapterNumber,
    this.lastReadAt,
  });

  final int chapterCount;
  final int downloadedCount;
  final int pendingCount;
  /// 클라우드에는 있지만 기기에는 없는 회차.
  final int cloudOnlyCount;
  final int? lastReadChapterNumber;
  final DateTime? lastReadAt;

  bool get hasEmptyChapters => chapterCount == 0;

  double get downloadProgress =>
      chapterCount == 0 ? 0.0 : downloadedCount / chapterCount;

  /// 활성 시리즈 목록에 대해 Hive/progress를 시리즈당 1회만 읽습니다.
  static Map<String, SeriesLibraryStats> buildFor(
    Iterable<Series> seriesList,
    StorageService storage,
  ) {
    final map = <String, SeriesLibraryStats>{};
    for (final series in seriesList) {
      map[series.id] = fromStorage(series.id, storage);
    }
    return map;
  }

  static SeriesLibraryStats fromStorage(String seriesId, StorageService storage) {
    final chapters = storage.getChapters(seriesId);
    var downloaded = 0;
    var pending = 0;
    var cloudOnly = 0;
    Chapter? lastChapter;
    DateTime? lastAt;

    for (final chapter in chapters) {
      if (chapter.isOnCloud) {
        downloaded++;
        if (!chapter.isDownloaded) cloudOnly++;
      } else {
        pending++;
      }
      final progress = storage.getProgress(seriesId, chapter.id);
      if (progress == null) continue;
      if (lastAt == null || progress.updatedAt.isAfter(lastAt)) {
        lastAt = progress.updatedAt;
        lastChapter = chapter;
      }
    }

    return SeriesLibraryStats(
      chapterCount: chapters.length,
      downloadedCount: downloaded,
      pendingCount: pending,
      cloudOnlyCount: cloudOnly,
      lastReadChapterNumber: lastChapter?.number,
      lastReadAt: lastAt,
    );
  }
}

class SeriesListSorter {
  static final _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  static List<Series> sort(
    List<Series> series,
    StorageService storage,
    LibrarySortMode mode, {
    Map<String, SeriesLibraryStats>? statsById,
  }) {
    final stats = statsById ??
        SeriesLibraryStats.buildFor(series, storage);
    final sorted = series.toList()
      ..sort((a, b) => _compare(a, b, mode, stats));
    return sorted;
  }

  static int _compare(
    Series a,
    Series b,
    LibrarySortMode mode,
    Map<String, SeriesLibraryStats> stats,
  ) {
    switch (mode) {
      case LibrarySortMode.recentlyRead:
        final readCmp = _dateDesc(
          stats[a.id]?.lastReadAt,
          stats[b.id]?.lastReadAt,
        );
        if (readCmp != 0) return readCmp;
        return _addedDesc(a, b);
      case LibrarySortMode.recentlyAdded:
        return _addedDesc(a, b);
      case LibrarySortMode.titleAsc:
        return _titleAsc(a, b);
      case LibrarySortMode.titleDesc:
        return _titleAsc(b, a);
      case LibrarySortMode.chapterCountDesc:
        return _chapterCountDesc(a, b, stats);
      case LibrarySortMode.chapterCountAsc:
        return _chapterCountDesc(b, a, stats);
      case LibrarySortMode.pendingDesc:
        final pendingCmp = (stats[b.id]?.pendingCount ?? 0)
            .compareTo(stats[a.id]?.pendingCount ?? 0);
        if (pendingCmp != 0) return pendingCmp;
        return _addedDesc(a, b);
      case LibrarySortMode.completedAt:
        final completedCmp = _dateDesc(a.completedAt, b.completedAt);
        if (completedCmp != 0) return completedCmp;
        return _addedDesc(a, b);
    }
  }

  static int _dateDesc(DateTime? a, DateTime? b) {
    return (b ?? _epoch).compareTo(a ?? _epoch);
  }

  static int _addedDesc(Series a, Series b) {
    return (b.addedAt ?? _epoch).compareTo(a.addedAt ?? _epoch);
  }

  static int _titleAsc(Series a, Series b) {
    final titleCmp = a.title.compareTo(b.title);
    if (titleCmp != 0) return titleCmp;
    return a.id.compareTo(b.id);
  }

  static int _chapterCountDesc(
    Series a,
    Series b,
    Map<String, SeriesLibraryStats> stats,
  ) {
    final countCmp = (stats[b.id]?.chapterCount ?? 0)
        .compareTo(stats[a.id]?.chapterCount ?? 0);
    if (countCmp != 0) return countCmp;
    return _titleAsc(a, b);
  }
}
