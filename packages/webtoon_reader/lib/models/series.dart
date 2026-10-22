class Series {
  const Series({
    required this.id,
    required this.title,
    required this.url,
    this.coverUrl,
    this.coverPath,
    this.lastRefreshedAt,
    this.addedAt,
    this.completedAt,
    this.isFavorite = false,
  });

  final String id;
  final String title;
  final String url;
  final String? coverUrl;
  final String? coverPath;
  final DateTime? lastRefreshedAt;
  final DateTime? addedAt;
  final DateTime? completedAt;
  final bool isFavorite;

  bool get isCompleted => completedAt != null;

  Series copyWith({
    String? id,
    String? title,
    String? url,
    String? coverUrl,
    String? coverPath,
    DateTime? lastRefreshedAt,
    DateTime? addedAt,
    DateTime? completedAt,
    bool? isFavorite,
    bool clearCompletedAt = false,
    bool clearCoverPath = false,
  }) {
    return Series(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
      coverUrl: coverUrl ?? this.coverUrl,
      coverPath: clearCoverPath ? null : (coverPath ?? this.coverPath),
      lastRefreshedAt: lastRefreshedAt ?? this.lastRefreshedAt,
      addedAt: addedAt ?? this.addedAt,
      completedAt:
          clearCompletedAt ? null : (completedAt ?? this.completedAt),
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'url': url,
        'coverUrl': coverUrl,
        'coverPath': coverPath,
        'lastRefreshedAt': lastRefreshedAt?.millisecondsSinceEpoch,
        'addedAt': addedAt?.millisecondsSinceEpoch,
        'completedAt': completedAt?.millisecondsSinceEpoch,
        'isFavorite': isFavorite,
      };

  factory Series.fromMap(Map<dynamic, dynamic> map) {
    return Series(
      id: map['id'] as String,
      title: map['title'] as String,
      url: map['url'] as String,
      coverUrl: map['coverUrl'] as String?,
      coverPath: map['coverPath'] as String?,
      lastRefreshedAt: map['lastRefreshedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastRefreshedAt'] as int)
          : null,
      addedAt: map['addedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['addedAt'] as int)
          : null,
      completedAt: map['completedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['completedAt'] as int)
          : null,
      isFavorite: map['isFavorite'] as bool? ?? false,
    );
  }

  static String idFromUrl(String url) {
    final uri = Uri.parse(url);
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length >= 2 && segments.first == 'webtoon') {
      return segments[1];
    }
    return segments.isNotEmpty ? segments.last : url.hashCode.toString();
  }

  static String normalizeUrl(String url) {
    var trimmed = url.trim();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'https://$trimmed';
    }
    final uri = Uri.parse(trimmed);
    var path = uri.path;
    if (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.length > 2 && segments.first == 'webtoon') {
      path = '/webtoon/${segments[1]}';
    }
    return Uri(
      scheme: uri.scheme.isEmpty ? 'https' : uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: path,
    ).toString();
  }

  /// 회차 URL에서 시리즈 페이지 URL을 복원합니다.
  static String? parentSeriesUrlFromChapterUrl(String chapterUrl) {
    final uri = Uri.tryParse(chapterUrl);
    if (uri == null || uri.host.isEmpty) return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < 3 || segments.first != 'webtoon') return null;
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: '/webtoon/${segments[1]}',
    ).toString();
  }

  /// `u-lz-checkup_x-95cc6771`처럼 `-` 뒤 해시가 빠진 잘린 slug인지 추정합니다.
  static bool isLikelyTruncatedSlug(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < 2 || segments.first != 'webtoon') return false;
    final id = segments[1];
    if (id.startsWith('u-lz-') &&
        !RegExp(r'-[a-f0-9]{8,}$', caseSensitive: false).hasMatch(id)) {
      return true;
    }
    if (id.startsWith('u-') &&
        id.contains('-') &&
        !RegExp(r'-[a-z0-9]{6,}$', caseSensitive: false).hasMatch(id)) {
      return true;
    }
    return false;
  }
}
