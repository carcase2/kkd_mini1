class SyncResult {
  const SyncResult({
    this.newChapterCount = 0,
    this.downloadedCount = 0,
    this.newChaptersBySeries = const {},
    this.newChapterIds = const [],
    this.errors = const [],
  });

  final int newChapterCount;
  final int downloadedCount;
  final Map<String, int> newChaptersBySeries;
  final List<String> newChapterIds;
  final List<String> errors;

  SyncResult merge(SyncResult other) {
    final mergedMap = Map<String, int>.from(newChaptersBySeries);
    other.newChaptersBySeries.forEach((key, value) {
      mergedMap[key] = (mergedMap[key] ?? 0) + value;
    });
    return SyncResult(
      newChapterCount: newChapterCount + other.newChapterCount,
      downloadedCount: downloadedCount + other.downloadedCount,
      newChaptersBySeries: mergedMap,
      newChapterIds: [...newChapterIds, ...other.newChapterIds],
      errors: [...errors, ...other.errors],
    );
  }

  bool get hasNew => newChapterCount > 0;
}
