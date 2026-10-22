class Chapter {
  const Chapter({
    required this.id,
    required this.title,
    required this.url,
    required this.number,
    this.imageUrls = const [],
    this.localPaths = const [],
    this.fetchedAt,
    this.sitePageTotal,
    this.publishedLabel,
    this.pageAspectRatios = const [],
    this.cloudPageCount,
    this.cloudUploadedAt,
  });

  final String id;
  final String title;
  final String url;
  final int number;
  final List<String> imageUrls;
  final List<String> localPaths;
  final DateTime? fetchedAt;
  /// 사이트 뷰어에 표시된 총 장수 (예: 1/72 → 72)
  final int? sitePageTotal;
  /// 사이트 회차 목록의 업로드일 (예: 26.06.22)
  final String? publishedLabel;
  /// 컷별 height/width 비율. 스크롤 extent 추정·복원에 사용합니다.
  final List<double> pageAspectRatios;
  /// Cloudflare R2 에 올라간 장 수. 로컬에 없어도 클라우드에서 받을 수 있습니다.
  final int? cloudPageCount;
  final DateTime? cloudUploadedAt;

  bool get isOnCloud => cloudPageCount != null && cloudPageCount! > 0;

  /// 기기 또는 클라우드에 이미지가 있어 네이티브로 열 수 있습니다.
  bool get isArchived => isOnCloud || isDownloaded;

  /// 이 기기에 이미지가 있고, Cloudflare에 아직 없거나 장 수가 모자랍니다.
  bool get needsCloudBackup {
    if (localPaths.isEmpty) return false;
    final cloud = cloudPageCount;
    return cloud == null || cloud < localPaths.length;
  }

  static const minPanelFileBytes = 8192;

  static int? pageNumberFromPath(String path) {
    final match = RegExp(r'page_(\d+)').firstMatch(path);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  /// page_001 … page_N 이 빠짐없이 있는지 확인합니다.
  static bool hasConsecutivePages(List<String> paths) {
    if (paths.isEmpty) return false;
    final numbers = paths.map(pageNumberFromPath).whereType<int>().toList()
      ..sort();
    if (numbers.length != paths.length) return false;
    for (var i = 0; i < numbers.length; i++) {
      if (numbers[i] != i + 1) return false;
    }
    return true;
  }

  /// 저장 완료 시에만 URL 목록을 정리합니다. 일부 저장 중에는 imageUrls를 줄이지 않습니다.
  static List<String> finalizeImageUrlsAfterDownload(
    List<String> imageUrls,
    List<String> localPaths,
  ) {
    if (imageUrls.isEmpty || !hasConsecutivePages(localPaths)) {
      return imageUrls;
    }
    final savedCount = localPaths.length;
    if (savedCount < imageUrls.length) {
      return imageUrls;
    }
    return imageUrls.take(savedCount).toList();
  }

  bool get isDownloaded {
    if (localPaths.isEmpty) return false;
    if (!hasConsecutivePages(localPaths)) return false;

    final expected = effectiveExpectedPageCount;
    if (expected != null && expected > 0) {
      return localPaths.length >= expected;
    }
    if (imageUrls.isEmpty) return true;
    return localPaths.length >= imageUrls.length;
  }

  bool get hasPartialDownload =>
      localPaths.isNotEmpty && !isDownloaded;

  bool get canRead => localPaths.isNotEmpty;

  /// 클라우드에 있으면 기기에 없어도 열어 읽을 수 있습니다.
  bool get canOpen => canRead || isOnCloud;

  /// 보관 여부와 상관없이 회차 주소만 있으면 다음/이전 화로 이동할 수 있습니다.
  bool get canNavigate => canOpen || url.isNotEmpty;

  /// 아직 Cloudflare에 없어서 사이트에서 처음 저장해야 합니다.
  bool get needsFirstSave => !isOnCloud;

  /// 스토리상 이전 화 (번호가 더 작은 화 중 가장 가까운 화).
  static Chapter? findPreviousByNumber(
    List<Chapter> chapters,
    Chapter current, {
    required bool Function(Chapter) canNavigate,
  }) {
    Chapter? best;
    for (final chapter in chapters) {
      if (chapter.number >= current.number || !canNavigate(chapter)) continue;
      if (best == null || chapter.number > best.number) best = chapter;
    }
    return best;
  }

  /// 스토리상 다음 화 (번호가 더 큰 화 중 가장 가까운 화).
  static Chapter? findNextByNumber(
    List<Chapter> chapters,
    Chapter current, {
    required bool Function(Chapter) canNavigate,
  }) {
    Chapter? best;
    for (final chapter in chapters) {
      if (chapter.number <= current.number || !canNavigate(chapter)) continue;
      if (best == null || chapter.number < best.number) best = chapter;
    }
    return best;
  }

  /// [ordered] 목록 기준 인접 회차. [delta] -1=이전, +1=다음.
  static Chapter? findAdjacentInOrder(
    List<Chapter> ordered,
    Chapter current, {
    required int delta,
    required bool Function(Chapter) canNavigate,
  }) {
    if (delta == 0 || ordered.isEmpty) return null;
    final index = ordered.indexWhere((c) => c.id == current.id);
    if (index < 0) return null;
    var i = index + delta;
    while (i >= 0 && i < ordered.length) {
      if (canNavigate(ordered[i])) return ordered[i];
      i += delta;
    }
    return null;
  }

  int? get effectiveExpectedPageCount {
    if (sitePageTotal != null && sitePageTotal! > 0) return sitePageTotal;
    if (imageUrls.isNotEmpty) return imageUrls.length;
    return null;
  }

  int? get expectedPageCount => effectiveExpectedPageCount;

  String get downloadStatusLabel {
    if (isOnCloud || isDownloaded) return '보관됨';
    if (hasPartialDownload) {
      final expected = effectiveExpectedPageCount;
      if (expected != null) {
        return '일부 보관 · ${localPaths.length}/$expected장';
      }
      if (imageUrls.isNotEmpty) {
        return '일부 보관 · ${localPaths.length}/${imageUrls.length}장';
      }
      return '일부 보관 · ${localPaths.length}장';
    }
    return '';
  }

  Chapter copyWith({
    String? id,
    String? title,
    String? url,
    int? number,
    List<String>? imageUrls,
    List<String>? localPaths,
    DateTime? fetchedAt,
    int? sitePageTotal,
    String? publishedLabel,
    List<double>? pageAspectRatios,
    int? cloudPageCount,
    DateTime? cloudUploadedAt,
  }) {
    return Chapter(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
      number: number ?? this.number,
      imageUrls: imageUrls ?? this.imageUrls,
      localPaths: localPaths ?? this.localPaths,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      sitePageTotal: sitePageTotal ?? this.sitePageTotal,
      publishedLabel: publishedLabel ?? this.publishedLabel,
      pageAspectRatios: pageAspectRatios ?? this.pageAspectRatios,
      cloudPageCount: cloudPageCount ?? this.cloudPageCount,
      cloudUploadedAt: cloudUploadedAt ?? this.cloudUploadedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'url': url,
        'number': number,
        'imageUrls': imageUrls,
        'localPaths': localPaths,
        'fetchedAt': fetchedAt?.millisecondsSinceEpoch,
        'sitePageTotal': sitePageTotal,
        'publishedLabel': publishedLabel,
        'pageAspectRatios': pageAspectRatios,
        'cloudPageCount': cloudPageCount,
        'cloudUploadedAt': cloudUploadedAt?.millisecondsSinceEpoch,
      };

  factory Chapter.fromMap(Map<dynamic, dynamic> map) {
    final ratiosRaw = map['pageAspectRatios'] as List?;
    return Chapter(
      id: map['id'] as String,
      title: map['title'] as String,
      url: map['url'] as String,
      number: map['number'] as int,
      imageUrls: (map['imageUrls'] as List?)?.cast<String>() ?? const [],
      localPaths: (map['localPaths'] as List?)?.cast<String>() ?? const [],
      fetchedAt: map['fetchedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['fetchedAt'] as int)
          : null,
      sitePageTotal: map['sitePageTotal'] as int?,
      publishedLabel: map['publishedLabel'] as String?,
      pageAspectRatios: ratiosRaw
              ?.map((e) => (e as num).toDouble())
              .toList(growable: false) ??
          const [],
      cloudPageCount: map['cloudPageCount'] as int?,
      cloudUploadedAt: map['cloudUploadedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['cloudUploadedAt'] as int)
          : null,
    );
  }

  /// [ratios]를 localPaths 길이에 맞게 맞춥니다. 없는 칸은 0(미측정).
  static List<double> alignAspectRatios(
    List<double> ratios,
    int pageCount,
  ) {
    if (pageCount <= 0) return const [];
    if (ratios.length == pageCount) return List<double>.from(ratios);
    final next = List<double>.filled(pageCount, 0);
    final copyLen = ratios.length < pageCount ? ratios.length : pageCount;
    for (var i = 0; i < copyLen; i++) {
      next[i] = ratios[i];
    }
    return next;
  }

  static String idFromUrl(String url) {
    final uri = Uri.parse(url);
    return uri.pathSegments.isNotEmpty
        ? uri.pathSegments.last
        : url.hashCode.toString();
  }

  static String normalizePageUrl(String url) {
    final uri = Uri.parse(url.trim());
    var path = uri.path;
    if (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return uri.replace(path: path, query: '', fragment: '').toString();
  }

  /// 웹뷰에서 열린 회차 URL을 로컬 회차 목록과 맞춥니다.
  static Chapter? findByPageUrl(List<Chapter> chapters, String? url) {
    if (url == null || url.isEmpty) return null;

    final normalized = normalizePageUrl(url);
    final pageId = idFromUrl(normalized);

    Chapter? byId;
    for (final chapter in chapters) {
      if (normalizePageUrl(chapter.url) == normalized) {
        return chapter;
      }
      if (chapter.id == pageId) {
        byId = chapter;
      }
    }
    return byId;
  }
}
