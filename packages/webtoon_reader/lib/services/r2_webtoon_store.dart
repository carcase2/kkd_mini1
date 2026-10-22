import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/chapter.dart';
import '../models/fetch_controller.dart';
import 'r2_client.dart';
import 'r2_paths.dart';
import 'storage_service.dart';

class R2WebtoonStore {
  R2WebtoonStore({
    R2Client? client,
    StorageService? storage,
  })  : _client = client ?? R2Client(),
        _storage = storage ?? StorageService.instance;

  static final instance = R2WebtoonStore();
  static const _transferConcurrency = 6;

  final R2Client _client;
  final StorageService _storage;

  Future<bool> ping({CancelToken? cancelToken}) async {
    try {
      await _client.listObjects(prefix: '${R2Paths.root}/', cancelToken: cancelToken);
      return true;
    } catch (e, st) {
      debugPrint('R2 ping failed: $e\n$st');
      return false;
    }
  }

  Future<R2ChapterRemote?> inspectChapter(
    String seriesId,
    String chapterId, {
    CancelToken? cancelToken,
  }) async {
    final manifest = await _readManifest(seriesId, chapterId, cancelToken: cancelToken);
    if (manifest != null) {
      return R2ChapterRemote(
        chapterId: chapterId,
        pageFiles: manifest.pages,
        pageCount: manifest.pageCount,
      );
    }
    final objects = await _client.listObjects(
      prefix: R2Paths.chapterPrefix(seriesId, chapterId),
      cancelToken: cancelToken,
    );
    final pages = objects
        .map((o) => R2Paths.fileNameFromKey(seriesId, chapterId, o.key))
        .whereType<String>()
        .where((name) => name.startsWith('page_'))
        .toList()
      ..sort();
    if (pages.isEmpty) return null;
    return R2ChapterRemote(chapterId: chapterId, pageFiles: pages);
  }

  Future<Map<String, R2ChapterRemote>> listSeriesChapters(
    String seriesId, {
    CancelToken? cancelToken,
  }) async {
    final objects = await _client.listObjects(
      prefix: R2Paths.seriesPrefix(seriesId),
      cancelToken: cancelToken,
    );
    final byChapter = <String, List<String>>{};
    for (final object in objects) {
      final chapterId = R2Paths.chapterIdFromKey(seriesId, object.key);
      if (chapterId == null) continue;
      final name = R2Paths.fileNameFromKey(seriesId, chapterId, object.key);
      if (name == null || !name.startsWith('page_')) continue;
      byChapter.putIfAbsent(chapterId, () => []).add(name);
    }
    final out = <String, R2ChapterRemote>{};
    for (final entry in byChapter.entries) {
      entry.value.sort();
      out[entry.key] = R2ChapterRemote(
        chapterId: entry.key,
        pageFiles: entry.value,
        pageCount: entry.value.length,
      );
    }
    return out;
  }

  Future<Chapter?> downloadChapter({
    required String seriesId,
    required Chapter chapter,
    FetchController? controller,
    void Function(int current, int total)? onProgress,
  }) async {
    final token = controller?.dioToken;
    final remote = await inspectChapter(
      seriesId,
      chapter.id,
      cancelToken: token,
    );
    if (remote == null || remote.pageFiles.isEmpty) return null;

    final dir = _storage.chapterDir(seriesId, chapter.id);
    await dir.create(recursive: true);

    final total = remote.pageFiles.length;
    var done = 0;
    onProgress?.call(0, total);

    await _forEachConcurrent(remote.pageFiles, (name) async {
      controller?.check();
      final file = File(p.join(dir.path, name));
      if (!await _isValidLocalPage(file)) {
        final bytes = await _client.getObject(
          R2Paths.pageKey(seriesId, chapter.id, name),
          cancelToken: token,
        );
        if (bytes == null || bytes.length < Chapter.minPanelFileBytes) {
          return;
        }
        await file.writeAsBytes(bytes);
      }
      done++;
      onProgress?.call(done, total);
    });

    final localPaths = _storage.scanChapterPagePaths(seriesId, chapter.id);
    if (localPaths.isEmpty) return null;

    return chapter.copyWith(
      localPaths: localPaths,
      pageAspectRatios: Chapter.alignAspectRatios(
        chapter.pageAspectRatios,
        localPaths.length,
      ),
      sitePageTotal: remote.pageCount ?? chapter.sitePageTotal,
      cloudPageCount: remote.effectivePageCount,
      cloudUploadedAt: chapter.cloudUploadedAt ?? DateTime.now(),
      fetchedAt: DateTime.now(),
    );
  }

  Future<Chapter> uploadChapter({
    required String seriesId,
    required Chapter chapter,
    FetchController? controller,
    void Function(int current, int total)? onProgress,
    File? coverFile,
  }) async {
    final token = controller?.dioToken;
    var localPaths = chapter.localPaths;
    if (localPaths.isEmpty) {
      localPaths = _storage.scanChapterPagePaths(seriesId, chapter.id);
    }
    if (localPaths.isEmpty) return chapter;
    if (chapter.cloudPageCount != null &&
        chapter.cloudPageCount! >= localPaths.length) {
      return chapter;
    }

    final candidates = <({String path, String name})>[];
    for (final path in localPaths) {
      final name = p.basename(path);
      if (!name.startsWith('page_')) continue;
      candidates.add((path: path, name: name));
    }
    if (candidates.isEmpty) return chapter;

    final total = candidates.length;
    var done = 0;
    onProgress?.call(0, total);

    final pageFiles = <String>[];
    await _forEachConcurrent(candidates, (item) async {
      controller?.check();
      final file = File(item.path);
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      if (bytes.length < Chapter.minPanelFileBytes) return;
      await _client.putObject(
        R2Paths.pageKey(seriesId, chapter.id, item.name),
        bytes,
        cancelToken: token,
      );
      pageFiles.add(item.name);
      done++;
      onProgress?.call(done, total);
    });

    if (pageFiles.isEmpty) return chapter;
    pageFiles.sort();

    final manifest = _ChapterManifest(
      seriesId: seriesId,
      chapterId: chapter.id,
      title: chapter.title,
      number: chapter.number,
      pages: pageFiles,
      pageCount: pageFiles.length,
      sitePageTotal: chapter.sitePageTotal,
      uploadedAt: DateTime.now().toUtc(),
    );
    await _client.putObject(
      R2Paths.manifestKey(seriesId, chapter.id),
      utf8.encode(jsonEncode(manifest.toJson())),
      contentType: 'application/json',
      cancelToken: token,
    );

    if (coverFile != null && await coverFile.exists()) {
      await uploadCover(seriesId, coverFile, cancelToken: token);
    }

    return chapter.copyWith(
      localPaths: localPaths,
      cloudPageCount: pageFiles.length,
      cloudUploadedAt: DateTime.now(),
    );
  }

  Future<void> uploadCover(
    String seriesId,
    File coverFile, {
    CancelToken? cancelToken,
  }) async {
    if (!await coverFile.exists()) return;
    final ext = p.extension(coverFile.path).replaceFirst('.', '');
    final bytes = await coverFile.readAsBytes();
    if (bytes.isEmpty) return;
    await _client.putObject(
      R2Paths.coverKey(seriesId, ext: ext.isEmpty ? 'webp' : ext),
      bytes,
      cancelToken: cancelToken,
    );
  }

  Future<String?> downloadCover(
    String seriesId, {
    CancelToken? cancelToken,
  }) async {
    for (final ext in const ['webp', 'jpg', 'jpeg', 'png']) {
      final bytes = await _client.getObject(
        R2Paths.coverKey(seriesId, ext: ext),
        cancelToken: cancelToken,
      );
      if (bytes == null || bytes.isEmpty) continue;
      final file = _storage.seriesCoverFile(seriesId, ext: ext);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      return file.path;
    }
    return null;
  }

  Future<int> applyInventory(
    String seriesId,
    Map<String, R2ChapterRemote> remote,
  ) async {
    if (remote.isEmpty) return 0;
    final chapters = _storage.getChapters(seriesId);
    if (chapters.isEmpty) return 0;
    var changed = 0;
    final next = <Chapter>[];
    for (final chapter in chapters) {
      final info = remote[chapter.id];
      if (info == null) {
        next.add(chapter);
        continue;
      }
      if (chapter.cloudPageCount == info.effectivePageCount) {
        next.add(chapter);
        continue;
      }
      changed++;
      next.add(
        chapter.copyWith(
          cloudPageCount: info.effectivePageCount,
          cloudUploadedAt: chapter.cloudUploadedAt ?? DateTime.now(),
        ),
      );
    }
    if (changed > 0) {
      await _storage.saveChapters(seriesId, next);
    }
    return changed;
  }

  Future<_ChapterManifest?> _readManifest(
    String seriesId,
    String chapterId, {
    CancelToken? cancelToken,
  }) async {
    try {
      final bytes = await _client.getObject(
        R2Paths.manifestKey(seriesId, chapterId),
        cancelToken: cancelToken,
      );
      if (bytes == null || bytes.isEmpty) return null;
      final map = jsonDecode(utf8.decode(bytes));
      if (map is! Map) return null;
      return _ChapterManifest.fromJson(Map<String, dynamic>.from(map));
    } catch (e) {
      debugPrint('R2 manifest read failed: $e');
      return null;
    }
  }

  Future<bool> _isValidLocalPage(File file) async {
    if (!await file.exists()) return false;
    return await file.length() >= Chapter.minPanelFileBytes;
  }

  Future<void> _forEachConcurrent<T>(
    List<T> items,
    Future<void> Function(T item) work,
  ) async {
    if (items.isEmpty) return;
    final workers = _transferConcurrency.clamp(1, items.length);
    var next = 0;

    Future<void> worker() async {
      while (true) {
        final i = next;
        next++;
        if (i >= items.length) return;
        await work(items[i]);
      }
    }

    await Future.wait(List.generate(workers, (_) => worker()));
  }

}

class _ChapterManifest {
  const _ChapterManifest({
    required this.seriesId,
    required this.chapterId,
    required this.title,
    required this.number,
    required this.pages,
    required this.pageCount,
    this.sitePageTotal,
    required this.uploadedAt,
  });

  final String seriesId;
  final String chapterId;
  final String title;
  final int number;
  final List<String> pages;
  final int pageCount;
  final int? sitePageTotal;
  final DateTime uploadedAt;

  Map<String, dynamic> toJson() => {
        'seriesId': seriesId,
        'chapterId': chapterId,
        'title': title,
        'number': number,
        'pages': pages,
        'pageCount': pageCount,
        'sitePageTotal': sitePageTotal,
        'uploadedAt': uploadedAt.toIso8601String(),
      };

  factory _ChapterManifest.fromJson(Map<String, dynamic> json) {
    final pages = (json['pages'] as List?)?.map((e) => '$e').toList() ?? const [];
    return _ChapterManifest(
      seriesId: '${json['seriesId'] ?? ''}',
      chapterId: '${json['chapterId'] ?? ''}',
      title: '${json['title'] ?? ''}',
      number: (json['number'] as num?)?.toInt() ?? 0,
      pages: pages,
      pageCount: (json['pageCount'] as num?)?.toInt() ?? pages.length,
      sitePageTotal: (json['sitePageTotal'] as num?)?.toInt(),
      uploadedAt: DateTime.tryParse('${json['uploadedAt']}') ?? DateTime.now().toUtc(),
    );
  }
}
