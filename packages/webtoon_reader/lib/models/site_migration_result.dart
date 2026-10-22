class SiteMigrationResult {
  const SiteMigrationResult({
    required this.oldOrigin,
    required this.newOrigin,
    required this.seriesUpdated,
    required this.chaptersUpdated,
    required this.urlFieldsUpdated,
  });

  final String oldOrigin;
  final String newOrigin;
  final int seriesUpdated;
  final int chaptersUpdated;
  final int urlFieldsUpdated;

  bool get hasChanges => urlFieldsUpdated > 0;
}
