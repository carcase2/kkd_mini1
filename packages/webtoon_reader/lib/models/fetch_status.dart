enum FetchPhase {
  idle,
  connecting,
  cloudflare,
  parsing,
  downloading,
  backingUp,
  done,
  cancelled,
  error,
}

class FetchStatus {
  const FetchStatus({
    required this.phase,
    required this.message,
    this.seriesCurrent,
    this.seriesTotal,
    this.chapterCurrent,
    this.chapterTotal,
    this.imageCurrent,
    this.imageTotal,
    this.elapsed = Duration.zero,
  });

  final FetchPhase phase;
  final String message;
  final int? seriesCurrent;
  final int? seriesTotal;
  final int? chapterCurrent;
  final int? chapterTotal;
  final int? imageCurrent;
  final int? imageTotal;
  final Duration elapsed;

  String get phaseLabel => switch (phase) {
        FetchPhase.connecting => '연결 중',
        FetchPhase.cloudflare => 'Cloudflare 확인',
        FetchPhase.parsing => '목록 분석',
        FetchPhase.downloading => '다운로드',
        FetchPhase.backingUp => '클라우드 백업',
        FetchPhase.done => '완료',
        FetchPhase.cancelled => '취소됨',
        FetchPhase.error => '오류',
        FetchPhase.idle => '',
      };

  double? get overallProgress {
    if (chapterTotal == null ||
        chapterTotal == 0 ||
        chapterCurrent == null) {
      return null;
    }
    final chapterPart = (chapterCurrent! - 1) / chapterTotal!;
    if (imageTotal == null ||
        imageTotal == 0 ||
        imageCurrent == null) {
      return chapterPart.clamp(0.0, 1.0);
    }
    final imagePart = imageCurrent! / imageTotal!;
    return (chapterPart + imagePart / chapterTotal!).clamp(0.0, 1.0);
  }

  FetchStatus copyWith({
    FetchPhase? phase,
    String? message,
    int? seriesCurrent,
    int? seriesTotal,
    int? chapterCurrent,
    int? chapterTotal,
    int? imageCurrent,
    int? imageTotal,
    Duration? elapsed,
  }) {
    return FetchStatus(
      phase: phase ?? this.phase,
      message: message ?? this.message,
      seriesCurrent: seriesCurrent ?? this.seriesCurrent,
      seriesTotal: seriesTotal ?? this.seriesTotal,
      chapterCurrent: chapterCurrent ?? this.chapterCurrent,
      chapterTotal: chapterTotal ?? this.chapterTotal,
      imageCurrent: imageCurrent ?? this.imageCurrent,
      imageTotal: imageTotal ?? this.imageTotal,
      elapsed: elapsed ?? this.elapsed,
    );
  }
}
