import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/medication.dart';
import '../models/session.dart';

class StorageService {
  static const _sessionsKey = 'tracking_sessions';
  static const _masturbationKey = 'masturbation_logs';
  static const _medicationsKey = 'medications';
  static const _medicationDosesKey = 'medication_doses';
  static const _medicationSetsKey = 'medication_sets';
  static const _medicationSetDosesKey = 'medication_set_doses';
  static const _themeKey = 'theme_mode'; // light | dark

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
}
