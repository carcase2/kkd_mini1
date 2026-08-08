/// 책 상태
enum BookStatus {
  /// 읽는 중
  reading,
  /// 일시 중지
  paused,
  /// 완독
  completed,
  /// 읽을 예정
  wishlist,
}

/// 등록된 책
class Book {
  final String id;
  final String title;
  final String? author;
  /// 전체 페이지 (null = 미입력)
  final int? totalPages;
  final BookStatus status;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? note;

  const Book({
    required this.id,
    required this.title,
    this.author,
    this.totalPages,
    this.status = BookStatus.reading,
    required this.createdAt,
    this.completedAt,
    this.note,
  });

  Book copyWith({
    String? id,
    String? title,
    String? author,
    bool clearAuthor = false,
    int? totalPages,
    bool clearTotalPages = false,
    BookStatus? status,
    DateTime? createdAt,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    String? note,
    bool clearNote = false,
  }) {
    return Book(
      id: id ?? this.id,
      title: title ?? this.title,
      author: clearAuthor ? null : (author ?? this.author),
      totalPages: clearTotalPages ? null : (totalPages ?? this.totalPages),
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      completedAt:
          clearCompletedAt ? null : (completedAt ?? this.completedAt),
      note: clearNote ? null : (note ?? this.note),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'totalPages': totalPages,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'note': note,
      };

  factory Book.fromJson(Map<String, dynamic> json) {
    return Book(
      id: json['id'] as String,
      title: json['title'] as String,
      author: json['author'] as String?,
      totalPages: json['totalPages'] as int?,
      status: BookStatus.values.byName(
        json['status'] as String? ?? BookStatus.reading.name,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
      note: json['note'] as String?,
    );
  }
}

/// 독서 기록 (타이머 세션 또는 수동 기록)
class ReadingLog {
  final String id;
  final String bookId;
  final DateTime startTime;
  final DateTime? endTime;
  /// 이번 세션에서 읽은 페이지 수
  final int? pagesRead;
  /// 시작 페이지
  final int? fromPage;
  /// 종료 페이지
  final int? toPage;
  final String? note;
  /// 활성 타이머 여부
  final bool active;

  const ReadingLog({
    required this.id,
    required this.bookId,
    required this.startTime,
    this.endTime,
    this.pagesRead,
    this.fromPage,
    this.toPage,
    this.note,
    this.active = false,
  });

  Duration get elapsed {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }

  /// 완료된 세션의 독서 시간 (활성 세션은 0)
  Duration get recordedDuration {
    if (active || endTime == null) return Duration.zero;
    return endTime!.difference(startTime);
  }

  ReadingLog copyWith({
    String? id,
    String? bookId,
    DateTime? startTime,
    DateTime? endTime,
    bool clearEndTime = false,
    int? pagesRead,
    bool clearPagesRead = false,
    int? fromPage,
    bool clearFromPage = false,
    int? toPage,
    bool clearToPage = false,
    String? note,
    bool clearNote = false,
    bool? active,
  }) {
    return ReadingLog(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      startTime: startTime ?? this.startTime,
      endTime: clearEndTime ? null : (endTime ?? this.endTime),
      pagesRead: clearPagesRead ? null : (pagesRead ?? this.pagesRead),
      fromPage: clearFromPage ? null : (fromPage ?? this.fromPage),
      toPage: clearToPage ? null : (toPage ?? this.toPage),
      note: clearNote ? null : (note ?? this.note),
      active: active ?? this.active,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'bookId': bookId,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime?.toIso8601String(),
        'pagesRead': pagesRead,
        'fromPage': fromPage,
        'toPage': toPage,
        'note': note,
        'active': active,
      };

  factory ReadingLog.fromJson(Map<String, dynamic> json) {
    return ReadingLog(
      id: json['id'] as String,
      bookId: json['bookId'] as String,
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: json['endTime'] != null
          ? DateTime.parse(json['endTime'] as String)
          : null,
      pagesRead: json['pagesRead'] as int?,
      fromPage: json['fromPage'] as int?,
      toPage: json['toPage'] as int?,
      note: json['note'] as String?,
      active: json['active'] as bool? ?? false,
    );
  }
}

String bookStatusLabel(BookStatus status) {
  switch (status) {
    case BookStatus.reading:
      return '읽는 중';
    case BookStatus.paused:
      return '일시 중지';
    case BookStatus.completed:
      return '완독';
    case BookStatus.wishlist:
      return '읽을 예정';
  }
}
