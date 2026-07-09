String formatDuration(Duration d, {bool short = false}) {
  if (d.isNegative) d = Duration.zero;

  final days = d.inDays;
  final hours = d.inHours.remainder(24);
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);

  if (short) {
    if (days > 0) return '$days일 $hours시간';
    if (hours > 0) return '$hours시간 $minutes분';
    if (minutes > 0) return '$minutes분';
    return '$seconds초';
  }

  final parts = <String>[];
  if (days > 0) parts.add('$days일');
  if (hours > 0 || days > 0) parts.add('$hours시간');
  if (minutes > 0 || hours > 0 || days > 0) parts.add('$minutes분');
  parts.add('$seconds초');
  return parts.join(' ');
}

String formatDurationCompact(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final days = d.inDays;
  final hours = d.inHours.remainder(24);
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);

  if (days > 0) {
    return '${days}d ${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

String formatTargetDuration(Duration? d) {
  if (d == null) return '자유 (시간 지정 없음)';
  if (d.inDays >= 1 && d.inHours % 24 == 0) {
    return '${d.inDays}일';
  }
  if (d.inHours >= 1 && d.inMinutes % 60 == 0) {
    return '${d.inHours}시간';
  }
  return formatDuration(d, short: true);
}

String formatPercent(double rate) {
  return '${(rate * 100).toStringAsFixed(0)}%';
}

/// 경과 일수를 강조한 문구 (예: "3일 5시간 경과")
String formatElapsedDays(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final days = d.inDays;
  final hours = d.inHours.remainder(24);
  final minutes = d.inMinutes.remainder(60);

  if (days > 0) {
    if (hours > 0) return '$days일 $hours시간 경과';
    return '$days일 경과';
  }
  if (hours > 0) {
    if (minutes > 0) return '$hours시간 $minutes분 경과';
    return '$hours시간 경과';
  }
  if (minutes > 0) return '$minutes분 경과';
  return '방금';
}

/// 홈 카드용: 일/시간을 항상 분리해 보여줌 (예: "3일 5시간")
String formatElapsedDayHour(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final days = d.inDays;
  final hours = d.inHours.remainder(24);
  final minutes = d.inMinutes.remainder(60);

  if (days == 0 && hours == 0) {
    if (minutes <= 0) return '0일 0시간';
    return '0일 $minutes분';
  }
  return '$days일 $hours시간';
}

/// 통계 카드용 짧은 한 줄 표기
/// 예: 19h20m, 1d12h, 45m
String formatDurationTiny(Duration d) {
  if (d.isNegative) d = Duration.zero;
  if (d == Duration.zero) return '0m';
  final days = d.inDays;
  final hours = d.inHours;
  final minutes = d.inMinutes;

  if (days >= 1) {
    final h = hours.remainder(24);
    return h > 0 ? '${days}d${h}h' : '${days}d';
  }
  if (hours >= 1) {
    final m = minutes.remainder(60);
    // 공백 없이 한 줄 유지: 19h20m
    return m > 0 ? '${hours}h${m}m' : '${hours}h';
  }
  if (minutes >= 1) return '${minutes}m';
  return '${d.inSeconds}s';
}

