import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/book.dart';
import '../models/medication.dart';
import '../models/session.dart';

class StorageService {
  static const _sessionsKey = 'tracking_sessions';
  static const _masturbationKey = 'masturbation_logs';
  static const _medicationsKey = 'medications';
  static const _medicationDosesKey = 'medication_doses';
  static const _medicationSetsKey = 'medication_sets';
  static const _medicationSetDosesKey = 'medication_set_doses';
  static const _booksKey = 'books';
  static const _readingLogsKey = 'reading_logs';
  static const _selectedBookKey = 'selected_book_id';
  static const _readingDailyGoalKey = 'reading_daily_goal_minutes';
  static const _themeKey = 'theme_mode'; // light | dark
  static const _lockEnabledKey = 'app_lock_enabled';
  static const _autoLockEnabledKey = 'app_auto_lock_enabled';
  static const _appPinKey = 'app_pin';
  static const _lastBackupAtKey = 'last_backup_at';
  static const _autoBackupEnabledKey = 'auto_backup_enabled';
  static const _autoBackupIntervalDaysKey = 'auto_backup_interval_days';
  static const defaultPin = '1850017';
  static const defaultAutoBackupIntervalDays = 7;

  Future<String> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_themeKey) ?? 'light'; // 기본: 라이트
  }

  Future<void> saveThemeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode);
  }


  Future<List<TrackingSession>> loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionsKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => TrackingSession.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveSessions(List<TrackingSession> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(sessions.map((s) => s.toJson()).toList());
    await prefs.setString(_sessionsKey, raw);
  }

  Future<List<MasturbationLog>> loadMasturbationLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_masturbationKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => MasturbationLog.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveMasturbationLogs(List<MasturbationLog> logs) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(logs.map((l) => l.toJson()).toList());
    await prefs.setString(_masturbationKey, raw);
  }

  Future<List<Medication>> loadMedications() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_medicationsKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => Medication.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveMedications(List<Medication> medications) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(medications.map((m) => m.toJson()).toList());
    await prefs.setString(_medicationsKey, raw);
  }

  Future<List<MedicationDose>> loadMedicationDoses() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_medicationDosesKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => MedicationDose.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveMedicationDoses(List<MedicationDose> doses) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(doses.map((d) => d.toJson()).toList());
    await prefs.setString(_medicationDosesKey, raw);
  }

  Future<List<MedicationSet>> loadMedicationSets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_medicationSetsKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => MedicationSet.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveMedicationSets(List<MedicationSet> sets) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(sets.map((s) => s.toJson()).toList());
    await prefs.setString(_medicationSetsKey, raw);
  }

  Future<List<MedicationSetDose>> loadMedicationSetDoses() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_medicationSetDosesKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => MedicationSetDose.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveMedicationSetDoses(List<MedicationSetDose> doses) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(doses.map((d) => d.toJson()).toList());
    await prefs.setString(_medicationSetDosesKey, raw);
  }

  Future<List<Book>> loadBooks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_booksKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => Book.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveBooks(List<Book> books) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(books.map((b) => b.toJson()).toList());
    await prefs.setString(_booksKey, raw);
  }

  Future<List<ReadingLog>> loadReadingLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_readingLogsKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => ReadingLog.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveReadingLogs(List<ReadingLog> logs) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(logs.map((l) => l.toJson()).toList());
    await prefs.setString(_readingLogsKey, raw);
  }

  Future<String?> loadSelectedBookId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_selectedBookKey);
  }

  Future<void> saveSelectedBookId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null || id.isEmpty) {
      await prefs.remove(_selectedBookKey);
    } else {
      await prefs.setString(_selectedBookKey, id);
    }
  }

  /// 하루 독서 목표(분). 기본 30분.
  Future<int> loadReadingDailyGoalMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_readingDailyGoalKey) ?? 30;
  }

  Future<void> saveReadingDailyGoalMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_readingDailyGoalKey, minutes.clamp(5, 600));
  }

  /// 앱 잠금 사용 여부. 기본: true
  Future<bool> loadLockEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_lockEnabledKey) ?? true;
  }

  Future<void> saveLockEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_lockEnabledKey, enabled);
  }

  /// 백그라운드 복귀 시 자동 잠금. 기본: true
  Future<bool> loadAutoLockEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoLockEnabledKey) ?? true;
  }

  Future<void> saveAutoLockEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoLockEnabledKey, enabled);
  }

  Future<String> loadAppPin() async {
    final prefs = await SharedPreferences.getInstance();
    final pin = prefs.getString(_appPinKey);
    if (pin == null || pin.isEmpty) return defaultPin;
    return pin;
  }

  Future<void> saveAppPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_appPinKey, pin);
  }

  Future<DateTime?> loadLastBackupAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastBackupAtKey);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> saveLastBackupAt(DateTime when) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastBackupAtKey, when.toIso8601String());
  }

  /// 주기 자동 백업 사용. 기본: true
  Future<bool> loadAutoBackupEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoBackupEnabledKey) ?? true;
  }

  Future<void> saveAutoBackupEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoBackupEnabledKey, enabled);
  }

  /// 자동 백업 주기(일). 기본 7일.
  Future<int> loadAutoBackupIntervalDays() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_autoBackupIntervalDaysKey) ??
        defaultAutoBackupIntervalDays;
  }

  Future<void> saveAutoBackupIntervalDays(int days) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _autoBackupIntervalDaysKey,
      days.clamp(1, 90),
    );
  }

  /// 전체 데이터 백업 (JSON 맵)
  Future<Map<String, dynamic>> exportBackup() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'app': 'discipline_tracker',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'data': {
        'sessions': _decodeList(prefs.getString(_sessionsKey)),
        'masturbationLogs': _decodeList(prefs.getString(_masturbationKey)),
        'medications': _decodeList(prefs.getString(_medicationsKey)),
        'medicationDoses': _decodeList(prefs.getString(_medicationDosesKey)),
        'medicationSets': _decodeList(prefs.getString(_medicationSetsKey)),
        'medicationSetDoses':
            _decodeList(prefs.getString(_medicationSetDosesKey)),
        'books': _decodeList(prefs.getString(_booksKey)),
        'readingLogs': _decodeList(prefs.getString(_readingLogsKey)),
        'settings': {
          'themeMode': prefs.getString(_themeKey) ?? 'light',
          'selectedBookId': prefs.getString(_selectedBookKey),
          'readingDailyGoalMinutes':
              prefs.getInt(_readingDailyGoalKey) ?? 30,
          'lockEnabled': prefs.getBool(_lockEnabledKey) ?? true,
          'autoLockEnabled': prefs.getBool(_autoLockEnabledKey) ?? true,
          'appPin': prefs.getString(_appPinKey) ?? defaultPin,
          'autoBackupEnabled': prefs.getBool(_autoBackupEnabledKey) ?? true,
          'autoBackupIntervalDays':
              prefs.getInt(_autoBackupIntervalDaysKey) ??
                  defaultAutoBackupIntervalDays,
        },
      },
    };
  }

  /// 백업 JSON으로 전체 덮어쓰기. 실패 시 예외.
  Future<void> importBackup(Map<String, dynamic> root) async {
    if (root['app'] != null && root['app'] != 'discipline_tracker') {
      throw FormatException('지원하지 않는 백업 파일입니다.');
    }
    final data = root['data'];
    if (data is! Map) {
      throw FormatException('백업 데이터 형식이 올바르지 않습니다.');
    }
    final map = Map<String, dynamic>.from(data);
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _sessionsKey,
      jsonEncode(_asList(map['sessions'])),
    );
    await prefs.setString(
      _masturbationKey,
      jsonEncode(_asList(map['masturbationLogs'])),
    );
    await prefs.setString(
      _medicationsKey,
      jsonEncode(_asList(map['medications'])),
    );
    await prefs.setString(
      _medicationDosesKey,
      jsonEncode(_asList(map['medicationDoses'])),
    );
    await prefs.setString(
      _medicationSetsKey,
      jsonEncode(_asList(map['medicationSets'])),
    );
    await prefs.setString(
      _medicationSetDosesKey,
      jsonEncode(_asList(map['medicationSetDoses'])),
    );
    await prefs.setString(
      _booksKey,
      jsonEncode(_asList(map['books'])),
    );
    await prefs.setString(
      _readingLogsKey,
      jsonEncode(_asList(map['readingLogs'])),
    );

    final settingsRaw = map['settings'];
    final settings = settingsRaw is Map
        ? Map<String, dynamic>.from(settingsRaw)
        : <String, dynamic>{};

    final theme = settings['themeMode'] as String? ?? 'light';
    await prefs.setString(_themeKey, theme == 'dark' ? 'dark' : 'light');

    final goal = settings['readingDailyGoalMinutes'];
    if (goal is int) {
      await prefs.setInt(_readingDailyGoalKey, goal.clamp(5, 600));
    } else if (goal is num) {
      await prefs.setInt(_readingDailyGoalKey, goal.toInt().clamp(5, 600));
    }

    final selected = settings['selectedBookId'] as String?;
    if (selected == null || selected.isEmpty) {
      await prefs.remove(_selectedBookKey);
    } else {
      await prefs.setString(_selectedBookKey, selected);
    }

    if (settings.containsKey('lockEnabled')) {
      await prefs.setBool(_lockEnabledKey, settings['lockEnabled'] == true);
    }
    if (settings.containsKey('autoLockEnabled')) {
      await prefs.setBool(
        _autoLockEnabledKey,
        settings['autoLockEnabled'] == true,
      );
    }
    final pin = settings['appPin'] as String?;
    if (pin != null && pin.isNotEmpty) {
      await prefs.setString(_appPinKey, pin);
    }
    if (settings.containsKey('autoBackupEnabled')) {
      await prefs.setBool(
        _autoBackupEnabledKey,
        settings['autoBackupEnabled'] == true,
      );
    }
    final interval = settings['autoBackupIntervalDays'];
    if (interval is int) {
      await prefs.setInt(
        _autoBackupIntervalDaysKey,
        interval.clamp(1, 90),
      );
    } else if (interval is num) {
      await prefs.setInt(
        _autoBackupIntervalDaysKey,
        interval.toInt().clamp(1, 90),
      );
    }
  }

  List<dynamic> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is List) return decoded;
    return [];
  }

  List<dynamic> _asList(dynamic value) {
    if (value is List) return value;
    return [];
  }
}
