import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/session.dart';

class StorageService {
  static const _sessionsKey = 'tracking_sessions';
  static const _masturbationKey = 'masturbation_logs';
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
}
