import 'package:flutter/material.dart';

import '../models/session.dart';
import '../services/storage_service.dart';

class AppState extends ChangeNotifier {
  final StorageService _storage = StorageService();

  List<TrackingSession> _sessions = [];
  List<MasturbationLog> _masturbationLogs = [];
  bool _loaded = false;
  ThemeMode _themeMode = ThemeMode.light; // 기본: 라이트

  bool get isLoaded => _loaded;
  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  List<TrackingSession> get sessions => List.unmodifiable(_sessions);
  List<MasturbationLog> get masturbationLogs =>
      List.unmodifiable(_masturbationLogs);

  // ── Active sessions ──────────────────────────────────────────

  TrackingSession? get activeFasting {
    try {
      return _sessions.firstWhere(
        (s) => s.type == SessionType.fasting && s.status == SessionStatus.active,
      );
    } catch (_) {
      return null;
    }
  }

  TrackingSession? get activeAbstinence {
    try {
      return _sessions.firstWhere(
        (s) =>
            s.type == SessionType.abstinence &&
            s.status == SessionStatus.active,
      );
    } catch (_) {
      return null;
    }
  }

  // ── Stats: Fasting ───────────────────────────────────────────

  List<TrackingSession> get fastingHistory {
    final list = _sessions
        .where((s) =>
            s.type == SessionType.fasting &&
            s.status != SessionStatus.active &&
            s.status != SessionStatus.cancelled)
        .toList();
    list.sort((a, b) => b.startTime.compareTo(a.startTime));
    return list;
  }

  int get fastingTotal => fastingHistory.length;
  int get fastingSuccess =>
      fastingHistory.where((s) => s.status == SessionStatus.completed).length;
  int get fastingFailed =>
      fastingHistory.where((s) => s.status == SessionStatus.failed).length;

  double get fastingSuccessRate =>
      fastingTotal == 0 ? 0 : fastingSuccess / fastingTotal;

  Duration get fastingTotalTime {
    return fastingHistory.fold(
      Duration.zero,
      (sum, s) => sum + s.elapsed,
    );
  }

  Duration get fastingLongest {
    if (fastingHistory.isEmpty) return Duration.zero;
    return fastingHistory
        .map((s) => s.elapsed)
        .reduce((a, b) => a > b ? a : b);
  }

  // ── Stats: Abstinence ────────────────────────────────────────

  List<TrackingSession> get abstinenceHistory {
    final list = _sessions
        .where((s) =>
            s.type == SessionType.abstinence &&
            s.status != SessionStatus.active &&
            s.status != SessionStatus.cancelled)
        .toList();
    list.sort((a, b) => b.startTime.compareTo(a.startTime));
    return list;
  }

  int get abstinenceTotal => abstinenceHistory.length;
  int get abstinenceSuccess => abstinenceHistory
      .where((s) => s.status == SessionStatus.completed)
      .length;
  int get abstinenceFailed =>
      abstinenceHistory.where((s) => s.status == SessionStatus.failed).length;

  double get abstinenceSuccessRate =>
      abstinenceTotal == 0 ? 0 : abstinenceSuccess / abstinenceTotal;

  Duration get abstinenceTotalTime {
    return abstinenceHistory.fold(
      Duration.zero,
      (sum, s) => sum + s.elapsed,
    );
  }

  Duration get abstinenceLongest {
    if (abstinenceHistory.isEmpty) return Duration.zero;
    return abstinenceHistory
        .map((s) => s.elapsed)
        .reduce((a, b) => a > b ? a : b);
  }

  /// 현재 활성 금욕 세션이 있으면 그 elapsed, 없으면 마지막 완료 세션 이후
  Duration get currentAbstinenceStreak {
    final active = activeAbstinence;
    if (active != null) return active.elapsed;
    return Duration.zero;
  }

  // ── Stats: Masturbation ──────────────────────────────────────

  List<MasturbationLog> get sortedMasturbationLogs {
    final list = List<MasturbationLog>.from(_masturbationLogs);
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  MasturbationLog? get lastMasturbation {
    if (_masturbationLogs.isEmpty) return null;
    return sortedMasturbationLogs.first;
  }

  /// 마지막 기록 이후 경과 시간
  Duration get timeSinceLastMasturbation {
    final last = lastMasturbation;
    if (last == null) return Duration.zero;
    return DateTime.now().difference(last.timestamp);
  }

  int get masturbationThisWeek {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
    return _masturbationLogs.where((l) => l.timestamp.isAfter(start)).length;
  }

  int get masturbationThisMonth {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    return _masturbationLogs.where((l) => l.timestamp.isAfter(start)).length;
  }

  int get masturbationTotal => _masturbationLogs.length;

  Map<DateTime, int> get masturbationByDay {
    final map = <DateTime, int>{};
    for (final log in _masturbationLogs) {
      final day =
          DateTime(log.timestamp.year, log.timestamp.month, log.timestamp.day);
      map[day] = (map[day] ?? 0) + 1;
    }
    return map;
  }

  // ── Load / Save ──────────────────────────────────────────────

  Future<void> load() async {
    _sessions = await _storage.loadSessions();
    _masturbationLogs = await _storage.loadMasturbationLogs();
    final theme = await _storage.loadThemeMode();
    _themeMode = theme == 'dark' ? ThemeMode.dark : ThemeMode.light;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode != ThemeMode.light && mode != ThemeMode.dark) {
      mode = ThemeMode.light;
    }
    _themeMode = mode;
    await _storage.saveThemeMode(mode == ThemeMode.dark ? 'dark' : 'light');
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    await setThemeMode(
      _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
    );
  }

  Future<void> _persistSessions() async {
    await _storage.saveSessions(_sessions);
  }

  Future<void> _persistMasturbation() async {
    await _storage.saveMasturbationLogs(_masturbationLogs);
  }

  // ── Session actions ──────────────────────────────────────────

  Future<void> startSession({
    required SessionType type,
    Duration? targetDuration,
    DateTime? startTime,
  }) async {
    // 같은 타입 활성 세션이 있으면 시작 불가
    final existing = type == SessionType.fasting
        ? activeFasting
        : activeAbstinence;
    if (existing != null) return;

    final start = startTime ?? DateTime.now();
    // 미래 시각은 허용하지 않음
    final safeStart =
        start.isAfter(DateTime.now()) ? DateTime.now() : start;

    final session = TrackingSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      type: type,
      startTime: safeStart,
      targetDuration: targetDuration,
      status: SessionStatus.active,
    );
    _sessions.add(session);
    await _persistSessions();
    notifyListeners();
  }

  Future<void> completeSession(String id) async {
    final idx = _sessions.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    final s = _sessions[idx];
    if (s.status != SessionStatus.active) return;

    // 목표가 있으면 달성 여부에 따라 success/fail 결정하지 않고
    // complete는 성공(목표 달성 또는 자유 모드 종료)
    _sessions[idx] = s.copyWith(
      endTime: DateTime.now(),
      status: SessionStatus.completed,
    );
    await _persistSessions();
    notifyListeners();
  }

  Future<void> failSession(String id) async {
    final idx = _sessions.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    final s = _sessions[idx];
    if (s.status != SessionStatus.active) return;

    _sessions[idx] = s.copyWith(
      endTime: DateTime.now(),
      status: SessionStatus.failed,
    );
    await _persistSessions();
    notifyListeners();
  }

  Future<void> cancelSession(String id) async {
    final idx = _sessions.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    final s = _sessions[idx];
    if (s.status != SessionStatus.active) return;

    _sessions[idx] = s.copyWith(
      endTime: DateTime.now(),
      status: SessionStatus.cancelled,
    );
    await _persistSessions();
    notifyListeners();
  }

  Future<void> deleteSession(String id) async {
    _sessions.removeWhere((s) => s.id == id);
    await _persistSessions();
    notifyListeners();
  }

  // ── Masturbation actions ─────────────────────────────────────

  Future<void> logMasturbation({DateTime? when, String? note}) async {
    final log = MasturbationLog(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      timestamp: when ?? DateTime.now(),
      note: note,
    );
    _masturbationLogs.add(log);
    await _persistMasturbation();
    notifyListeners();
  }

  Future<void> deleteMasturbationLog(String id) async {
    _masturbationLogs.removeWhere((l) => l.id == id);
    await _persistMasturbation();
    notifyListeners();
  }

  /// UI 갱신용 틱 (활성 타이머 · 체크 경과)
  void tick() {
    if (activeFasting != null ||
        activeAbstinence != null ||
        lastMasturbation != null) {
      notifyListeners();
    }
  }
}
