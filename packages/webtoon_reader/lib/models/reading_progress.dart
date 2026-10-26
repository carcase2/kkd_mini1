class ReadingProgress {
  const ReadingProgress({
    required this.chapterId,
    required this.scrollOffset,
    required this.updatedAt,
    this.pageIndex,
    this.pageFraction = 0,
    this.completed = false,
  });

  final String chapterId;

  /// 레거시/웹뷰용 절대 스크롤 오프셋(px).
  final double scrollOffset;

  /// 0-based 페이지(컷) 인덱스. 로컬 리더에서 우선 사용합니다.
  final int? pageIndex;

  /// 현재 페이지 안에서의 진행 비율 0.0~1.0.
  final double pageFraction;

  /// 회차 끝(또는 그 근처)까지 읽음.
  final bool completed;

  final DateTime updatedAt;

  /// 페이지 기반 복원이 가능한지.
  bool get hasPageAnchor => pageIndex != null && pageIndex! >= 0;

  /// 맨 위를 연 기록은 이어 읽기로 치지 않습니다.
  bool get isMeaningful => ReadingProgress.isMeaningfulMap({
        'completed': completed,
        'scrollOffset': scrollOffset,
        'pageIndex': pageIndex,
        'pageFraction': pageFraction,
      });

  static bool isMeaningfulMap(Map<dynamic, dynamic> raw) {
    if (raw['completed'] == true) return true;
    final offset = (raw['scrollOffset'] as num?)?.toDouble() ?? 0;
    if (offset > 8) return true;
    final page = (raw['pageIndex'] as num?)?.toInt() ?? 0;
    if (page > 0) return true;
    final fraction = (raw['pageFraction'] as num?)?.toDouble() ?? 0;
    return fraction > 0.02;
  }

  /// 같은 읽기 위치인지. 회차를 다시 열 때 updatedAt을 올리지 않기 위해 씁니다.
  bool isSameAnchor(ReadingProgress other, {double offsetSlop = 8}) {
    if (chapterId != other.chapterId) return false;
    if (completed != other.completed) return false;
    if ((scrollOffset - other.scrollOffset).abs() > offsetSlop) return false;
    final aPage = pageIndex;
    final bPage = other.pageIndex;
    if (aPage != bPage) {
      final aZero = aPage == null || aPage == 0;
      final bZero = bPage == null || bPage == 0;
      if (!(aZero && bZero)) return false;
    }
    if ((pageFraction - other.pageFraction).abs() > 0.02) return false;
    return true;
  }

  ReadingProgress copyWith({
    String? chapterId,
    double? scrollOffset,
    DateTime? updatedAt,
    int? pageIndex,
    double? pageFraction,
    bool? completed,
  }) {
    return ReadingProgress(
      chapterId: chapterId ?? this.chapterId,
      scrollOffset: scrollOffset ?? this.scrollOffset,
      updatedAt: updatedAt ?? this.updatedAt,
      pageIndex: pageIndex ?? this.pageIndex,
      pageFraction: pageFraction ?? this.pageFraction,
      completed: completed ?? this.completed,
    );
  }

  Map<String, dynamic> toMap() => {
        'chapterId': chapterId,
        'scrollOffset': scrollOffset,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'pageIndex': pageIndex,
        'pageFraction': pageFraction,
        'completed': completed,
      };

  factory ReadingProgress.fromMap(Map<dynamic, dynamic> map) {
    return ReadingProgress(
      chapterId: map['chapterId'] as String,
      scrollOffset: (map['scrollOffset'] as num?)?.toDouble() ?? 0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['updatedAt'] as num?)?.toInt() ?? 0,
      ),
      pageIndex: (map['pageIndex'] as num?)?.toInt(),
      pageFraction: (map['pageFraction'] as num?)?.toDouble() ?? 0,
      completed: map['completed'] as bool? ?? false,
    );
  }
}
