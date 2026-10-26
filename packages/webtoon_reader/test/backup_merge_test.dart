import 'package:flutter_test/flutter_test.dart';
import 'package:webtoon_reader/models/reading_progress.dart';
import 'package:webtoon_reader/utils/backup_merge.dart';

void main() {
  test('progress or a saved continue pointer keeps a backup', () {
    expect(isBackupEffectivelyEmpty({'series': [], 'chapters': {}}), isTrue);
    expect(
      isBackupEffectivelyEmpty({
        'series': const [],
        'chapters': const {},
        'progress': {
          's1::c50': {'chapterId': 'c50', 'scrollOffset': 120, 'updatedAt': 10},
        },
      }),
      isFalse,
    );
    expect(
      isBackupEffectivelyEmpty({
        'meta': {'lastSeriesId': 's1', 'lastChapterId': 'c50'},
      }),
      isFalse,
    );
  });

  test('a failed cloud read does not upload the local shelf', () {
    expect(
      shouldUploadLocalShelf(
        pullFailed: true,
        remoteMissing: true,
        localEmpty: false,
      ),
      isFalse,
    );
    expect(
      shouldUploadLocalShelf(
        pullFailed: false,
        remoteMissing: true,
        localEmpty: false,
      ),
      isTrue,
    );
    expect(
      shouldUploadLocalShelf(
        pullFailed: false,
        remoteMissing: false,
        localEmpty: false,
      ),
      isFalse,
    );
  });

  test('opening the top of a chapter is not a continue position', () {
    expect(
      ReadingProgress(
        chapterId: 'c1',
        scrollOffset: 0,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      ).isMeaningful,
      isFalse,
    );
    expect(
      ReadingProgress(
        chapterId: 'c50',
        scrollOffset: 120,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(10),
      ).isMeaningful,
      isTrue,
    );
  });
}
