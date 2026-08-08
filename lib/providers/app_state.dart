import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/book.dart';
import '../models/medication.dart';
import '../models/session.dart';
import '../services/backup_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/supabase_sync_service.dart';

class AppState extends ChangeNotifier {
  final StorageService _storage = StorageService();
  final SupabaseSyncService _cloud = SupabaseSyncService.instance;

  List<TrackingSession> _sessions = [];
  List<MasturbationLog> _masturbationLogs = [];
  List<Medication> _medications = [];
  List<MedicationDose> _medicationDoses = [];
  List<MedicationSet> _medicationSets = [];
  List<MedicationSetDose> _medicationSetDoses = [];
  List<Book> _books = [];
  List<ReadingLog> _readingLogs = [];
  String? _selectedBookId;
  int _readingDailyGoalMinutes = 30;
  bool _loaded = false;
  ThemeMode _themeMode = ThemeMode.light; // 기본: 라이트

  // 앱 잠금
  bool _lockEnabled = true;
  bool _autoLockEnabled = true;
  String _appPin = StorageService.defaultPin;
  bool _isLocked = true; // 잠금 사용 시 시작 시 잠금

  // 백업
  DateTime? _lastBackupAt;
  bool _autoBackupEnabled = true;
  int _autoBackupIntervalDays =
      StorageService.defaultAutoBackupIntervalDays;

  // 세션 알림 (중간 / 10% / 완료)
  bool _sessionNotificationsEnabled = true;

  bool get isLoaded => _loaded;
  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  bool get lockEnabled => _lockEnabled;
  bool get autoLockEnabled => _autoLockEnabled;
  bool get isLocked => _lockEnabled && _isLocked;
  int get pinLength => _appPin.length;
  DateTime? get lastBackupAt => _lastBackupAt;
  bool get autoBackupEnabled => _autoBackupEnabled;
  int get autoBackupIntervalDays => _autoBackupIntervalDays;
  bool get sessionNotificationsEnabled => _sessionNotificationsEnabled;

  Timer? _autoBackupDebounce;
  Timer? _cloudSyncDebounce;
  final bool _cloudSyncEnabled = true;
  bool get cloudSyncEnabled => _cloudSyncEnabled;
  bool get cloudSyncReady => _cloud.isReady;

  /// 데이터 변경 후 자동 백업이 아직 한 번도 없으면 true (UI 안내용)
  bool get needsFirstAutoBackup =>
      _autoBackupEnabled && _lastBackupAt == null;
  List<TrackingSession> get sessions => List.unmodifiable(_sessions);
  List<MasturbationLog> get masturbationLogs =>
      List.unmodifiable(_masturbationLogs);
  List<Medication> get medications => List.unmodifiable(_medications);
  List<MedicationDose> get medicationDoses =>
      List.unmodifiable(_medicationDoses);
  List<MedicationSet> get medicationSets => List.unmodifiable(_medicationSets);
  List<MedicationSetDose> get medicationSetDoses =>
      List.unmodifiable(_medicationSetDoses);
  List<Book> get books => List.unmodifiable(_books);
  List<ReadingLog> get readingLogs => List.unmodifiable(_readingLogs);
  String? get selectedBookId => _selectedBookId;
  int get readingDailyGoalMinutes => _readingDailyGoalMinutes;

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

  // ── Stats: Medication ────────────────────────────────────────

  List<Medication> get activeMedications {
    final list = _medications.where((m) => m.active).toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  List<Medication> get sortedMedications {
    final list = List<Medication>.from(_medications);
    list.sort((a, b) {
      if (a.active != b.active) return a.active ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return list;
  }

  int get medicationDueCount {
    final medDue = activeMedications.where(isMedicationDue).length;
    final setDue = activeMedicationSets.where(isMedicationSetDue).length;
    return medDue + setDue;
  }

  List<MedicationSet> get activeMedicationSets {
    final list = _medicationSets.where((s) => s.active).toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  List<MedicationSet> get sortedMedicationSets {
    final list = List<MedicationSet>.from(_medicationSets);
    list.sort((a, b) {
      if (a.active != b.active) return a.active ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return list;
  }

  List<Medication> membersOfSet(MedicationSet set) {
    final map = {for (final m in _medications) m.id: m};
    return set.medicationIds
        .map((id) => map[id])
        .whereType<Medication>()
        .toList();
  }

  List<MedicationDose> dosesFor(String medicationId) {
    final list =
        _medicationDoses.where((d) => d.medicationId == medicationId).toList();
    list.sort((a, b) => b.takenAt.compareTo(a.takenAt));
    return list;
  }

  MedicationDose? lastDose(String medicationId) {
    final list = dosesFor(medicationId);
    if (list.isEmpty) return null;
    return list.first;
  }

  /// 마지막 복용 + 주기. 기록이 없으면 null (언제든 복용 가능)
  DateTime? nextDoseTime(Medication med) {
    final last = lastDose(med.id);
    if (last == null) return null;
    return last.takenAt.add(med.interval);
  }

  /// 다음 복용까지 남은 시간. 음수면 이미 지남. 기록 없으면 null
  Duration? timeUntilNextDose(Medication med) {
    final next = nextDoseTime(med);
    if (next == null) return null;
    return next.difference(DateTime.now());
  }

  /// 주기 대비 경과 비율 0~1 (다음 복용 시각 기준)
  double doseCycleProgress(Medication med) {
    final last = lastDose(med.id);
    if (last == null || med.intervalMinutes <= 0) return 1;
    final elapsed = DateTime.now().difference(last.takenAt);
    return (elapsed.inSeconds / med.interval.inSeconds).clamp(0.0, 1.0);
  }

  bool isMedicationDue(Medication med) {
    final until = timeUntilNextDose(med);
    if (until == null) return true; // 기록 없음 → 복용 가능
    return until <= Duration.zero;
  }

  int doseCountThisWeek(String medicationId) {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
    return _medicationDoses
        .where((d) =>
            d.medicationId == medicationId && d.takenAt.isAfter(start))
        .length;
  }

  List<MedicationSetDose> setDosesFor(String setId) {
    final list = _medicationSetDoses.where((d) => d.setId == setId).toList();
    list.sort((a, b) => b.takenAt.compareTo(a.takenAt));
    return list;
  }

  MedicationSetDose? lastSetDose(String setId) {
    final list = setDosesFor(setId);
    if (list.isEmpty) return null;
    return list.first;
  }

  DateTime? nextSetDoseTime(MedicationSet set) {
    final last = lastSetDose(set.id);
    if (last == null) return null;
    return last.takenAt.add(set.interval);
  }

  Duration? timeUntilNextSetDose(MedicationSet set) {
    final next = nextSetDoseTime(set);
    if (next == null) return null;
    return next.difference(DateTime.now());
  }

  double setDoseCycleProgress(MedicationSet set) {
    final last = lastSetDose(set.id);
    if (last == null || set.intervalMinutes <= 0) return 1;
    final elapsed = DateTime.now().difference(last.takenAt);
    return (elapsed.inSeconds / set.interval.inSeconds).clamp(0.0, 1.0);
  }

  bool isMedicationSetDue(MedicationSet set) {
    final until = timeUntilNextSetDose(set);
    if (until == null) return true;
    return until <= Duration.zero;
  }

  int setDoseCountThisWeek(String setId) {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
    return _medicationSetDoses
        .where((d) => d.setId == setId && d.takenAt.isAfter(start))
        .length;
  }

  // ── Stats: Reading ───────────────────────────────────────────

  List<Book> get sortedBooks {
    final list = List<Book>.from(_books);
    list.sort((a, b) {
      // 읽는 중 → 일시중지 → 읽을 예정 → 완독
      final order = {
        BookStatus.reading: 0,
        BookStatus.paused: 1,
        BookStatus.wishlist: 2,
        BookStatus.completed: 3,
      };
      final oa = order[a.status] ?? 9;
      final ob = order[b.status] ?? 9;
      if (oa != ob) return oa.compareTo(ob);
      return b.createdAt.compareTo(a.createdAt);
    });
    return list;
  }

  List<Book> get activeBooks =>
      _books.where((b) => b.status != BookStatus.completed).toList();

  Book? get selectedBook {
    if (_selectedBookId == null) return null;
    try {
      return _books.firstWhere((b) => b.id == _selectedBookId);
    } catch (_) {
      return null;
    }
  }

  Book? bookById(String id) {
    try {
      return _books.firstWhere((b) => b.id == id);
    } catch (_) {
      return null;
    }
  }

  ReadingLog? get activeReading {
    try {
      return _readingLogs.firstWhere((l) => l.active);
    } catch (_) {
      return null;
    }
  }

  List<ReadingLog> get completedReadingLogs {
    final list = _readingLogs.where((l) => !l.active).toList();
    list.sort((a, b) => b.startTime.compareTo(a.startTime));
    return list;
  }

  List<ReadingLog> readingLogsForBook(String bookId) {
    final list =
        _readingLogs.where((l) => l.bookId == bookId && !l.active).toList();
    list.sort((a, b) => b.startTime.compareTo(a.startTime));
    return list;
  }

  int pagesReadForBook(String bookId) {
    return _readingLogs
        .where((l) => l.bookId == bookId && !l.active)
        .fold<int>(0, (sum, l) => sum + (l.pagesRead ?? 0));
  }

  Duration readingTimeForBook(String bookId) {
    return _readingLogs
        .where((l) => l.bookId == bookId && !l.active)
        .fold(Duration.zero, (sum, l) => sum + l.recordedDuration);
  }

  /// 책 진행률 0~1 (totalPages 있을 때). 없으면 null.
  double? bookProgress(String bookId) {
    final book = bookById(bookId);
    if (book == null || book.totalPages == null || book.totalPages! <= 0) {
      return null;
    }
    return (pagesReadForBook(bookId) / book.totalPages!).clamp(0.0, 1.0);
  }

  Duration readingDurationOnDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return _readingLogs.where((l) {
      if (l.active) return false;
      final t = l.endTime ?? l.startTime;
      return !t.isBefore(start) && t.isBefore(end);
    }).fold(Duration.zero, (sum, l) => sum + l.recordedDuration);
  }

  int readingPagesOnDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return _readingLogs.where((l) {
      if (l.active) return false;
      final t = l.endTime ?? l.startTime;
      return !t.isBefore(start) && t.isBefore(end);
    }).fold<int>(0, (sum, l) => sum + (l.pagesRead ?? 0));
  }

  Duration get readingToday => readingDurationOnDay(DateTime.now());

  int get readingPagesToday => readingPagesOnDay(DateTime.now());

  Duration get readingThisWeek {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
    return _readingLogs.where((l) {
      if (l.active) return false;
      final t = l.endTime ?? l.startTime;
      return !t.isBefore(start);
    }).fold(Duration.zero, (sum, l) => sum + l.recordedDuration);
  }

  int get readingPagesThisWeek {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
    return _readingLogs.where((l) {
      if (l.active) return false;
      final t = l.endTime ?? l.startTime;
      return !t.isBefore(start);
    }).fold<int>(0, (sum, l) => sum + (l.pagesRead ?? 0));
  }

  Duration get readingThisMonth {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    return _readingLogs.where((l) {
      if (l.active) return false;
      final t = l.endTime ?? l.startTime;
      return !t.isBefore(start);
    }).fold(Duration.zero, (sum, l) => sum + l.recordedDuration);
  }

  Duration get readingTotalTime {
    return _readingLogs
        .where((l) => !l.active)
        .fold(Duration.zero, (sum, l) => sum + l.recordedDuration);
  }

  int get readingTotalPages {
    return _readingLogs
        .where((l) => !l.active)
        .fold<int>(0, (sum, l) => sum + (l.pagesRead ?? 0));
  }

  int get readingSessionCount => _readingLogs.where((l) => !l.active).length;

  int get booksCompletedCount =>
      _books.where((b) => b.status == BookStatus.completed).length;

  int get booksReadingCount =>
      _books.where((b) => b.status == BookStatus.reading).length;

  /// 날짜별 독서 분 (달력/히트맵용)
  Map<DateTime, int> get readingMinutesByDay {
    final map = <DateTime, int>{};
    for (final log in _readingLogs) {
      if (log.active) continue;
      final t = log.endTime ?? log.startTime;
      final day = DateTime(t.year, t.month, t.day);
      map[day] = (map[day] ?? 0) + log.recordedDuration.inMinutes;
    }
    return map;
  }

  Map<DateTime, int> get readingPagesByDay {
    final map = <DateTime, int>{};
    for (final log in _readingLogs) {
      if (log.active) continue;
      final t = log.endTime ?? log.startTime;
      final day = DateTime(t.year, t.month, t.day);
      map[day] = (map[day] ?? 0) + (log.pagesRead ?? 0);
    }
    return map;
  }

  /// 연속 독서 일수 (오늘 또는 어제부터 역산)
  int get readingStreak {
    final byDay = readingMinutesByDay;
    if (byDay.isEmpty) return 0;
    final now = DateTime.now();
    var day = DateTime(now.year, now.month, now.day);
    // 오늘 기록이 없으면 어제부터
    if ((byDay[day] ?? 0) <= 0) {
      day = day.subtract(const Duration(days: 1));
    }
    var streak = 0;
    while ((byDay[day] ?? 0) > 0) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  double get readingTodayGoalProgress {
    if (_readingDailyGoalMinutes <= 0) return 0;
    return (readingToday.inMinutes / _readingDailyGoalMinutes).clamp(0.0, 1.0);
  }

  bool get readingTodayGoalMet =>
      readingToday.inMinutes >= _readingDailyGoalMinutes;

  // ── Load / Save ──────────────────────────────────────────────

  Future<void> load() async {
    await _loadFromStorage();
    // 잠금 기능 켜져 있으면 앱 시작 시 잠금
    _isLocked = _lockEnabled;
    _loaded = true;
    notifyListeners();

    // 활성 세션 알림 재예약
    if (_sessionNotificationsEnabled) {
      await NotificationService.instance.rescheduleActiveSessions(_sessions);
    }

    // 로컬 로드 후 Supabase와 맞추기 (실패해도 로컬로 계속)
    if (_cloudSyncEnabled) {
      try {
        final applied = await _cloud.syncAfterLocalLoad(_storage);
        if (applied) {
          await _loadFromStorage();
          notifyListeners();
          if (_sessionNotificationsEnabled) {
            await NotificationService.instance
                .rescheduleActiveSessions(_sessions);
          }
        }
      } catch (_) {
        // 오프라인이면 무시
      }
    }
  }

  Future<void> _loadFromStorage() async {
    _sessions = await _storage.loadSessions();
    _masturbationLogs = await _storage.loadMasturbationLogs();
    _medications = await _storage.loadMedications();
    _medicationDoses = await _storage.loadMedicationDoses();
    _medicationSets = await _storage.loadMedicationSets();
    _medicationSetDoses = await _storage.loadMedicationSetDoses();
    _books = await _storage.loadBooks();
    _readingLogs = await _storage.loadReadingLogs();
    _selectedBookId = await _storage.loadSelectedBookId();
    _readingDailyGoalMinutes = await _storage.loadReadingDailyGoalMinutes();
    if (_selectedBookId != null &&
        !_books.any((b) => b.id == _selectedBookId)) {
      _selectedBookId = null;
    }
    final theme = await _storage.loadThemeMode();
    _themeMode = theme == 'dark' ? ThemeMode.dark : ThemeMode.light;
    _lockEnabled = await _storage.loadLockEnabled();
    _autoLockEnabled = await _storage.loadAutoLockEnabled();
    _appPin = await _storage.loadAppPin();
    _lastBackupAt = await _storage.loadLastBackupAt();
    _autoBackupEnabled = await _storage.loadAutoBackupEnabled();
    _autoBackupIntervalDays = await _storage.loadAutoBackupIntervalDays();
    _sessionNotificationsEnabled =
        await _storage.loadSessionNotificationsEnabled();
    NotificationService.instance.setEnabled(_sessionNotificationsEnabled);
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

  // ── App lock ─────────────────────────────────────────────────

  /// 수동 잠금 (잠금 기능이 켜져 있을 때만)
  void lockApp() {
    if (!_lockEnabled) return;
    if (_isLocked) return;
    _isLocked = true;
    notifyListeners();
  }

  /// 백그라운드 이탈 시 자동 잠금
  void onAppPaused() {
    if (!_lockEnabled || !_autoLockEnabled) return;
    if (_isLocked) return;
    _isLocked = true;
    notifyListeners();
  }

  /// PIN 검증 후 잠금 해제. 성공 여부 반환.
  bool unlockWithPin(String pin) {
    if (!_lockEnabled) {
      _isLocked = false;
      notifyListeners();
      return true;
    }
    if (pin == _appPin) {
      _isLocked = false;
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> setLockEnabled(bool enabled) async {
    _lockEnabled = enabled;
    await _storage.saveLockEnabled(enabled);
    if (!enabled) {
      _isLocked = false;
    } else {
      // 켜는 즉시 잠금 상태로
      _isLocked = true;
    }
    notifyListeners();
  }

  Future<void> setAutoLockEnabled(bool enabled) async {
    _autoLockEnabled = enabled;
    await _storage.saveAutoLockEnabled(enabled);
    notifyListeners();
  }

  /// 현재 PIN 확인 (설정 변경용)
  bool verifyPin(String pin) => pin == _appPin;

  Future<bool> changePin({
    required String currentPin,
    required String newPin,
  }) async {
    if (currentPin != _appPin) return false;
    final cleaned = newPin.trim();
    if (cleaned.length < 4 || cleaned.length > 12) return false;
    if (!RegExp(r'^\d+$').hasMatch(cleaned)) return false;
    _appPin = cleaned;
    await _storage.saveAppPin(cleaned);
    notifyListeners();
    return true;
  }

  // ── Backup export / import ───────────────────────────────────

  /// 전체 데이터 JSON 문자열
  Future<String> exportBackupJson() async {
    final map = await _storage.exportBackup();
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// 백업 JSON으로 전체 교체 후 다시 로드
  Future<void> importBackupJson(String jsonText) async {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map) {
      throw FormatException('JSON 객체가 아닙니다.');
    }
    await _storage.importBackup(Map<String, dynamic>.from(decoded));
    // load()는 잠금 on이면 잠금 상태로 시작 — 불러오기 직후는 열어 둠
    await load();
    _isLocked = false;
    notifyListeners();
  }

  Future<void> markBackupCompleted([DateTime? when]) async {
    _lastBackupAt = when ?? DateTime.now();
    await _storage.saveLastBackupAt(_lastBackupAt!);
    notifyListeners();
  }

  Future<void> setAutoBackupEnabled(bool enabled) async {
    _autoBackupEnabled = enabled;
    await _storage.saveAutoBackupEnabled(enabled);
    if (!enabled) {
      _autoBackupDebounce?.cancel();
      _autoBackupDebounce = null;
    }
    notifyListeners();
  }

  Future<void> setAutoBackupIntervalDays(int days) async {
    // 호환용 유지 (UI에서는 더 이상 주기 선택 안 함)
    _autoBackupIntervalDays = days.clamp(1, 90);
    await _storage.saveAutoBackupIntervalDays(_autoBackupIntervalDays);
    notifyListeners();
  }

  /// 기록 추가·변경 시 호출 — 잠시 후 기기 자동 백업 (연속 저장은 묶음)
  void _queueAutoBackup() {
    if (!_autoBackupEnabled) return;
    _autoBackupDebounce?.cancel();
    _autoBackupDebounce = Timer(const Duration(seconds: 4), () {
      BackupService.backupAfterDataChange(this).catchError((_) => false);
    });
    _queueCloudSync();
  }

  void _queueCloudSync() {
    if (!_cloudSyncEnabled) return;
    _cloudSyncDebounce?.cancel();
    _cloudSyncDebounce = Timer(const Duration(seconds: 5), () async {
      try {
        if (!_cloud.isReady) await _cloud.init();
        final payload = await _storage.exportBackup();
        await _cloud.push(payload);
      } catch (_) {}
    });
  }

  Future<void> setSessionNotificationsEnabled(bool enabled) async {
    _sessionNotificationsEnabled = enabled;
    await _storage.saveSessionNotificationsEnabled(enabled);
    NotificationService.instance.setEnabled(enabled);
    if (enabled) {
      await NotificationService.instance.requestPermission();
      await NotificationService.instance.rescheduleActiveSessions(_sessions);
    } else {
      await NotificationService.instance.cancelAllSessionAlarms();
    }
    notifyListeners();
  }

  Future<void> _persistSessions() async {
    await _storage.saveSessions(_sessions);
    _queueAutoBackup();
  }

  Future<void> _persistMasturbation() async {
    await _storage.saveMasturbationLogs(_masturbationLogs);
    _queueAutoBackup();
  }

  Future<void> _persistMedications() async {
    await _storage.saveMedications(_medications);
    _queueAutoBackup();
  }

  Future<void> _persistMedicationDoses() async {
    await _storage.saveMedicationDoses(_medicationDoses);
    _queueAutoBackup();
  }

  Future<void> _persistMedicationSets() async {
    await _storage.saveMedicationSets(_medicationSets);
    _queueAutoBackup();
  }

  Future<void> _persistMedicationSetDoses() async {
    await _storage.saveMedicationSetDoses(_medicationSetDoses);
    _queueAutoBackup();
  }

  Future<void> _persistBooks() async {
    await _storage.saveBooks(_books);
    _queueAutoBackup();
  }

  Future<void> _persistReadingLogs() async {
    await _storage.saveReadingLogs(_readingLogs);
    _queueAutoBackup();
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

    final now = DateTime.now();
    var start = startTime ?? now;
    // 초 단위 노이즈 제거 (분 단위로 기록)
    start = DateTime(
      start.year,
      start.month,
      start.day,
      start.hour,
      start.minute,
    );
    // 미래 시각은 허용하지 않음
    if (start.isAfter(now)) {
      start = now;
    }

    final session = TrackingSession(
      id: now.microsecondsSinceEpoch.toString(),
      type: type,
      startTime: start,
      targetDuration: targetDuration,
      status: SessionStatus.active,
    );
    _sessions.add(session);
    await _persistSessions();
    if (_sessionNotificationsEnabled && targetDuration != null) {
      await NotificationService.instance.requestPermission();
      await NotificationService.instance.scheduleSessionMilestones(session);
    }
    notifyListeners();
  }

  Future<void> completeSession(String id) async {
    final idx = _sessions.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    final s = _sessions[idx];
    if (s.status != SessionStatus.active) return;

    _sessions[idx] = s.copyWith(
      endTime: DateTime.now(),
      status: SessionStatus.completed,
    );
    await _persistSessions();
    await NotificationService.instance.cancelForType(s.type);
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
    await NotificationService.instance.cancelForType(s.type);
    notifyListeners();
  }

  /// 목표 달성·자유 모드 → 성공, 미달 → 실패. 목표 시간 후에도 계속하다 종료 가능.
  Future<SessionStatus?> endSession(String id) async {
    final idx = _sessions.indexWhere((s) => s.id == id);
    if (idx < 0) return null;
    final s = _sessions[idx];
    if (s.status != SessionStatus.active) return null;

    final status = s.endStatus;
    _sessions[idx] = s.copyWith(
      endTime: DateTime.now(),
      status: status,
    );
    await _persistSessions();
    await NotificationService.instance.cancelForType(s.type);
    notifyListeners();
    return status;
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
    await NotificationService.instance.cancelForType(s.type);
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

  // ── Medication actions ───────────────────────────────────────

  Future<void> addMedication({
    required String name,
    required int intervalMinutes,
    String? note,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || intervalMinutes <= 0) return;

    final med = Medication(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: trimmed,
      intervalMinutes: intervalMinutes,
      note: note?.trim().isEmpty == true ? null : note?.trim(),
      createdAt: DateTime.now(),
    );
    _medications.add(med);
    await _persistMedications();
    notifyListeners();
  }

  Future<void> updateMedication(Medication updated) async {
    final idx = _medications.indexWhere((m) => m.id == updated.id);
    if (idx < 0) return;
    final trimmed = updated.name.trim();
    if (trimmed.isEmpty || updated.intervalMinutes <= 0) return;
    _medications[idx] = updated.copyWith(
      name: trimmed,
      note: updated.note?.trim().isEmpty == true ? null : updated.note?.trim(),
    );
    await _persistMedications();
    notifyListeners();
  }

  Future<void> deleteMedication(String id) async {
    _medications.removeWhere((m) => m.id == id);
    _medicationDoses.removeWhere((d) => d.medicationId == id);
    // 세트에서 해당 약 제거 (빈 세트는 유지 — 사용자가 직접 정리)
    var setsChanged = false;
    for (var i = 0; i < _medicationSets.length; i++) {
      final s = _medicationSets[i];
      if (s.medicationIds.contains(id)) {
        _medicationSets[i] = s.copyWith(
          medicationIds: s.medicationIds.where((mid) => mid != id).toList(),
        );
        setsChanged = true;
      }
    }
    await _persistMedications();
    await _persistMedicationDoses();
    if (setsChanged) await _persistMedicationSets();
    notifyListeners();
  }

  Future<void> setMedicationActive(String id, bool active) async {
    final idx = _medications.indexWhere((m) => m.id == id);
    if (idx < 0) return;
    _medications[idx] = _medications[idx].copyWith(active: active);
    await _persistMedications();
    notifyListeners();
  }

  Future<void> logMedicationDose({
    required String medicationId,
    DateTime? when,
    String? note,
    String? setId,
  }) async {
    if (!_medications.any((m) => m.id == medicationId)) return;
    final takenAt = when ?? DateTime.now();
    final safe = takenAt.isAfter(DateTime.now()) ? DateTime.now() : takenAt;

    final dose = MedicationDose(
      id: '${DateTime.now().microsecondsSinceEpoch}_$medicationId',
      medicationId: medicationId,
      takenAt: safe,
      note: note?.trim().isEmpty == true ? null : note?.trim(),
      setId: setId,
    );
    _medicationDoses.add(dose);
    await _persistMedicationDoses();
    notifyListeners();
  }

  Future<void> deleteMedicationDose(String id) async {
    _medicationDoses.removeWhere((d) => d.id == id);
    await _persistMedicationDoses();
    notifyListeners();
  }

  // ── Medication set actions ───────────────────────────────────

  Future<void> addMedicationSet({
    required String name,
    required List<String> medicationIds,
    required int intervalMinutes,
    String? note,
  }) async {
    final trimmed = name.trim();
    final ids = medicationIds.toSet().toList();
    if (trimmed.isEmpty || ids.isEmpty || intervalMinutes <= 0) return;
    // 존재하는 약만
    final validIds =
        ids.where((id) => _medications.any((m) => m.id == id)).toList();
    if (validIds.isEmpty) return;

    final set = MedicationSet(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: trimmed,
      medicationIds: validIds,
      intervalMinutes: intervalMinutes,
      note: note?.trim().isEmpty == true ? null : note?.trim(),
      createdAt: DateTime.now(),
    );
    _medicationSets.add(set);
    await _persistMedicationSets();
    notifyListeners();
  }

  Future<void> updateMedicationSet(MedicationSet updated) async {
    final idx = _medicationSets.indexWhere((s) => s.id == updated.id);
    if (idx < 0) return;
    final trimmed = updated.name.trim();
    final ids = updated.medicationIds.toSet().toList();
    final validIds =
        ids.where((id) => _medications.any((m) => m.id == id)).toList();
    if (trimmed.isEmpty || validIds.isEmpty || updated.intervalMinutes <= 0) {
      return;
    }
    _medicationSets[idx] = updated.copyWith(
      name: trimmed,
      medicationIds: validIds,
      note: updated.note?.trim().isEmpty == true ? null : updated.note?.trim(),
    );
    await _persistMedicationSets();
    notifyListeners();
  }

  Future<void> deleteMedicationSet(String id) async {
    _medicationSets.removeWhere((s) => s.id == id);
    _medicationSetDoses.removeWhere((d) => d.setId == id);
    await _persistMedicationSets();
    await _persistMedicationSetDoses();
    notifyListeners();
  }

  Future<void> setMedicationSetActive(String id, bool active) async {
    final idx = _medicationSets.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    _medicationSets[idx] = _medicationSets[idx].copyWith(active: active);
    await _persistMedicationSets();
    notifyListeners();
  }

  /// 세트 일괄 복용 — 세트 기록 + 구성 약 각각 기록
  Future<void> logMedicationSetDose({
    required String setId,
    DateTime? when,
    String? note,
  }) async {
    final setIdx = _medicationSets.indexWhere((s) => s.id == setId);
    if (setIdx < 0) return;
    final set = _medicationSets[setIdx];
    final takenAt = when ?? DateTime.now();
    final safe = takenAt.isAfter(DateTime.now()) ? DateTime.now() : takenAt;
    final noteClean = note?.trim().isEmpty == true ? null : note?.trim();
    final baseId = DateTime.now().microsecondsSinceEpoch.toString();

    _medicationSetDoses.add(
      MedicationSetDose(
        id: '${baseId}_set',
        setId: setId,
        takenAt: safe,
        note: noteClean,
      ),
    );

    for (final medId in set.medicationIds) {
      if (!_medications.any((m) => m.id == medId)) continue;
      _medicationDoses.add(
        MedicationDose(
          id: '${baseId}_$medId',
          medicationId: medId,
          takenAt: safe,
          note: noteClean,
          setId: setId,
        ),
      );
    }

    await _persistMedicationSetDoses();
    await _persistMedicationDoses();
    notifyListeners();
  }

  Future<void> deleteMedicationSetDose(String id) async {
    MedicationSetDose? dose;
    for (final d in _medicationSetDoses) {
      if (d.id == id) {
        dose = d;
        break;
      }
    }
    if (dose == null) return;

    // 같은 시각·세트로 찍힌 개별 약 기록도 함께 제거
    final setId = dose.setId;
    final takenMs = dose.takenAt.millisecondsSinceEpoch;
    _medicationSetDoses.removeWhere((d) => d.id == id);
    _medicationDoses.removeWhere(
      (d) =>
          d.setId == setId && d.takenAt.millisecondsSinceEpoch == takenMs,
    );
    await _persistMedicationSetDoses();
    await _persistMedicationDoses();
    notifyListeners();
  }

  // ── Reading / Book actions ───────────────────────────────────

  Future<void> setSelectedBookId(String? id) async {
    if (id != null && !_books.any((b) => b.id == id)) return;
    _selectedBookId = id;
    await _storage.saveSelectedBookId(id);
    notifyListeners();
  }

  Future<void> setReadingDailyGoalMinutes(int minutes) async {
    _readingDailyGoalMinutes = minutes.clamp(5, 600);
    await _storage.saveReadingDailyGoalMinutes(_readingDailyGoalMinutes);
    notifyListeners();
  }

  Future<Book?> addBook({
    required String title,
    String? author,
    int? totalPages,
    BookStatus status = BookStatus.reading,
    String? note,
    bool select = true,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return null;
    final pages = totalPages != null && totalPages > 0 ? totalPages : null;

    final book = Book(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: trimmed,
      author: author?.trim().isEmpty == true ? null : author?.trim(),
      totalPages: pages,
      status: status,
      createdAt: DateTime.now(),
      note: note?.trim().isEmpty == true ? null : note?.trim(),
    );
    _books.add(book);
    await _persistBooks();
    if (select) {
      _selectedBookId = book.id;
      await _storage.saveSelectedBookId(book.id);
    }
    notifyListeners();
    return book;
  }

  Future<void> updateBook(Book updated) async {
    final idx = _books.indexWhere((b) => b.id == updated.id);
    if (idx < 0) return;
    final trimmed = updated.title.trim();
    if (trimmed.isEmpty) return;
    final pages =
        updated.totalPages != null && updated.totalPages! > 0
            ? updated.totalPages
            : null;
    var book = updated.copyWith(
      title: trimmed,
      author:
          updated.author?.trim().isEmpty == true ? null : updated.author?.trim(),
      totalPages: pages,
      note: updated.note?.trim().isEmpty == true ? null : updated.note?.trim(),
      clearAuthor: updated.author == null || updated.author!.trim().isEmpty,
      clearTotalPages: pages == null,
      clearNote: updated.note == null || updated.note!.trim().isEmpty,
    );
    if (book.status == BookStatus.completed && book.completedAt == null) {
      book = book.copyWith(completedAt: DateTime.now());
    }
    if (book.status != BookStatus.completed) {
      book = book.copyWith(clearCompletedAt: true);
    }
    _books[idx] = book;
    await _persistBooks();
    notifyListeners();
  }

  Future<void> setBookStatus(String id, BookStatus status) async {
    final idx = _books.indexWhere((b) => b.id == id);
    if (idx < 0) return;
    var book = _books[idx].copyWith(status: status);
    if (status == BookStatus.completed) {
      book = book.copyWith(completedAt: DateTime.now());
    } else {
      book = book.copyWith(clearCompletedAt: true);
    }
    _books[idx] = book;
    await _persistBooks();
    notifyListeners();
  }

  Future<void> deleteBook(String id) async {
    _books.removeWhere((b) => b.id == id);
    _readingLogs.removeWhere((l) => l.bookId == id);
    if (_selectedBookId == id) {
      _selectedBookId = _books.isNotEmpty ? _books.first.id : null;
      await _storage.saveSelectedBookId(_selectedBookId);
    }
    await _persistBooks();
    await _persistReadingLogs();
    notifyListeners();
  }

  Future<void> startReading({String? bookId, DateTime? startTime}) async {
    if (activeReading != null) return;
    final id = bookId ?? _selectedBookId;
    if (id == null || !_books.any((b) => b.id == id)) return;

    final now = DateTime.now();
    var start = startTime ?? now;
    start = DateTime(
      start.year,
      start.month,
      start.day,
      start.hour,
      start.minute,
    );
    if (start.isAfter(now)) start = now;

    // 읽는 중으로 상태 전환
    final bookIdx = _books.indexWhere((b) => b.id == id);
    if (bookIdx >= 0 &&
        (_books[bookIdx].status == BookStatus.wishlist ||
            _books[bookIdx].status == BookStatus.paused)) {
      _books[bookIdx] = _books[bookIdx].copyWith(status: BookStatus.reading);
      await _persistBooks();
    }

    _selectedBookId = id;
    await _storage.saveSelectedBookId(id);

    _readingLogs.add(
      ReadingLog(
        id: now.microsecondsSinceEpoch.toString(),
        bookId: id,
        startTime: start,
        active: true,
      ),
    );
    await _persistReadingLogs();
    notifyListeners();
  }

  /// 활성 독서 종료. pagesRead 또는 from/to 페이지 기록.
  Future<void> endReading({
    int? pagesRead,
    int? fromPage,
    int? toPage,
    String? note,
  }) async {
    final idx = _readingLogs.indexWhere((l) => l.active);
    if (idx < 0) return;

    var pages = pagesRead;
    if (pages == null && fromPage != null && toPage != null && toPage >= fromPage) {
      pages = toPage - fromPage;
    }

    _readingLogs[idx] = _readingLogs[idx].copyWith(
      endTime: DateTime.now(),
      active: false,
      pagesRead: pages,
      fromPage: fromPage,
      toPage: toPage,
      note: note?.trim().isEmpty == true ? null : note?.trim(),
    );
    await _persistReadingLogs();
    notifyListeners();
  }

  Future<void> cancelReading() async {
    final idx = _readingLogs.indexWhere((l) => l.active);
    if (idx < 0) return;
    _readingLogs.removeAt(idx);
    await _persistReadingLogs();
    notifyListeners();
  }

  /// 수동 독서 기록 (타이머 없이)
  Future<void> logReadingManual({
    required String bookId,
    required DateTime when,
    required int durationMinutes,
    int? pagesRead,
    int? fromPage,
    int? toPage,
    String? note,
  }) async {
    if (!_books.any((b) => b.id == bookId)) return;
    if (durationMinutes <= 0 && (pagesRead == null || pagesRead <= 0)) return;

    final minutes = durationMinutes < 0 ? 0 : durationMinutes;
    final end = when;
    final start = end.subtract(Duration(minutes: minutes > 0 ? minutes : 1));

    var pages = pagesRead;
    if (pages == null && fromPage != null && toPage != null && toPage >= fromPage) {
      pages = toPage - fromPage;
    }

    _readingLogs.add(
      ReadingLog(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        bookId: bookId,
        startTime: start,
        endTime: end,
        pagesRead: pages,
        fromPage: fromPage,
        toPage: toPage,
        note: note?.trim().isEmpty == true ? null : note?.trim(),
        active: false,
      ),
    );

    final bookIdx = _books.indexWhere((b) => b.id == bookId);
    if (bookIdx >= 0 && _books[bookIdx].status == BookStatus.wishlist) {
      _books[bookIdx] = _books[bookIdx].copyWith(status: BookStatus.reading);
      await _persistBooks();
    }

    await _persistReadingLogs();
    notifyListeners();
  }

  Future<void> deleteReadingLog(String id) async {
    _readingLogs.removeWhere((l) => l.id == id && !l.active);
    await _persistReadingLogs();
    notifyListeners();
  }

  /// UI 갱신용 틱 (활성 타이머 · 체크 경과 · 약 카운트다운 · 독서)
  void tick() {
    if (activeFasting != null ||
        activeAbstinence != null ||
        activeReading != null ||
        lastMasturbation != null ||
        _medications.any((m) => m.active && lastDose(m.id) != null) ||
        _medicationSets.any((s) => s.active && lastSetDose(s.id) != null)) {
      notifyListeners();
    }
  }
}
