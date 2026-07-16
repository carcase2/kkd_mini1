import 'package:flutter/material.dart';

import '../models/medication.dart';
import '../models/session.dart';
import '../services/storage_service.dart';

class AppState extends ChangeNotifier {
  final StorageService _storage = StorageService();

  List<TrackingSession> _sessions = [];
  List<MasturbationLog> _masturbationLogs = [];
  List<Medication> _medications = [];
  List<MedicationDose> _medicationDoses = [];
  List<MedicationSet> _medicationSets = [];
  List<MedicationSetDose> _medicationSetDoses = [];
  bool _loaded = false;
  ThemeMode _themeMode = ThemeMode.light; // 기본: 라이트

  bool get isLoaded => _loaded;
  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  List<TrackingSession> get sessions => List.unmodifiable(_sessions);
  List<MasturbationLog> get masturbationLogs =>
      List.unmodifiable(_masturbationLogs);
  List<Medication> get medications => List.unmodifiable(_medications);
  List<MedicationDose> get medicationDoses =>
      List.unmodifiable(_medicationDoses);
  List<MedicationSet> get medicationSets => List.unmodifiable(_medicationSets);
  List<MedicationSetDose> get medicationSetDoses =>
      List.unmodifiable(_medicationSetDoses);

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

  // ── Load / Save ──────────────────────────────────────────────

  Future<void> load() async {
    _sessions = await _storage.loadSessions();
    _masturbationLogs = await _storage.loadMasturbationLogs();
    _medications = await _storage.loadMedications();
    _medicationDoses = await _storage.loadMedicationDoses();
    _medicationSets = await _storage.loadMedicationSets();
    _medicationSetDoses = await _storage.loadMedicationSetDoses();
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

  Future<void> _persistMedications() async {
    await _storage.saveMedications(_medications);
  }

  Future<void> _persistMedicationDoses() async {
    await _storage.saveMedicationDoses(_medicationDoses);
  }

  Future<void> _persistMedicationSets() async {
    await _storage.saveMedicationSets(_medicationSets);
  }

  Future<void> _persistMedicationSetDoses() async {
    await _storage.saveMedicationSetDoses(_medicationSetDoses);
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

  /// UI 갱신용 틱 (활성 타이머 · 체크 경과 · 약 카운트다운)
  void tick() {
    if (activeFasting != null ||
        activeAbstinence != null ||
        lastMasturbation != null ||
        _medications.any((m) => m.active && lastDose(m.id) != null) ||
        _medicationSets.any((s) => s.active && lastSetDose(s.id) != null)) {
      notifyListeners();
    }
  }
}
