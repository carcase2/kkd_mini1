import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/session.dart';
import '../utils/format.dart';

/// 단식·금욕 목표 알림 (중간 50% / 10% 남음 / 완료)
///
/// 기기 로컬 예약 알림을 사용합니다.
/// (세션 시각이 기기에서만 관리되므로 FCM 서버 푸시 없이도
///  앱이 종료되어 있어도 예약 시각에 알림이 갑니다.)
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;
  bool _enabled = true;

  static const _channelId = 'session_milestones';
  static const _channelName = '세션 알림';
  static const _channelDesc = '단식·금욕 진행 중 중간·완료 알림';

  // 알림 ID (타입별 고정 슬롯 — 세션당 최대 3개)
  static const _idFastingHalf = 1101;
  static const _idFastingTen = 1102;
  static const _idFastingDone = 1103;
  static const _idAbstinenceHalf = 1201;
  static const _idAbstinenceTen = 1202;
  static const _idAbstinenceDone = 1203;

  bool get isReady => _ready;

  void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      final info = await FlutterTimezone.getLocalTimezone();
      final name = info.identifier;
      try {
        tz.setLocalLocation(tz.getLocation(name));
      } catch (_) {
        // IANA 이름을 못 찾으면 로컬 오프셋 기반 대체
        tz.setLocalLocation(tz.local);
      }

      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: androidInit,
          iOS: iosInit,
        ),
      );

      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDesc,
          importance: Importance.high,
        ),
      );

      _ready = true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('NotificationService.init failed: $e');
      }
    }
  }

  /// 알림 권한 요청 (Android 13+, iOS)
  Future<bool> requestPermission() async {
    if (!_ready) await init();

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final notif = await android.requestNotificationsPermission();
      // 정확한 알람 (Android 12+)
      await android.requestExactAlarmsPermission();
      return notif ?? true;
    }

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final result = await ios.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return result ?? false;
    }
    return true;
  }

  Future<void> cancelForType(SessionType type) async {
    if (!_ready) return;
    final ids = _idsFor(type);
    for (final id in ids) {
      await _plugin.cancel(id: id);
    }
  }

  Future<void> cancelAllSessionAlarms() async {
    if (!_ready) return;
    for (final type in SessionType.values) {
      await cancelForType(type);
    }
  }

  /// 목표가 있는 활성 세션에 대해 알림 예약
  Future<void> scheduleSessionMilestones(TrackingSession session) async {
    if (!_enabled) return;
    if (!_ready) await init();
    if (!_ready) return;

    final target = session.targetDuration;
    if (target == null || target.inSeconds <= 0) {
      await cancelForType(session.type);
      return;
    }
    if (session.status != SessionStatus.active) {
      await cancelForType(session.type);
      return;
    }

    await cancelForType(session.type);

    final title = session.type == SessionType.fasting ? '단식' : '금욕';
    final start = session.startTime;
    final end = start.add(target);
    final half = start.add(Duration(seconds: target.inSeconds ~/ 2));
    final tenLeft = start.add(
      Duration(seconds: (target.inSeconds * 0.9).floor()),
    );

    final remainingAtHalf = end.difference(half);
    final remainingAtTen = end.difference(tenLeft);

    final ids = _idsFor(session.type);

    await _scheduleIfFuture(
      id: ids[0],
      when: half,
      title: '$title · 절반 지났어요',
      body:
          '중간 지점 통과! 남은 시간 ${formatDuration(remainingAtHalf, short: true)}',
      payload: 'session_${session.type.name}_half',
    );

    await _scheduleIfFuture(
      id: ids[1],
      when: tenLeft,
      title: '$title · 10% 남았어요',
      body:
          '거의 다 왔어요. 남은 시간 ${formatDuration(remainingAtTen, short: true)}',
      payload: 'session_${session.type.name}_10',
    );

    await _scheduleIfFuture(
      id: ids[2],
      when: end,
      title: '$title · 목표 달성! 🎉',
      body: '목표 시간에 도달했어요. 앱에서 종료하거나 더 이어갈 수 있어요.',
      payload: 'session_${session.type.name}_done',
    );
  }

  Future<void> rescheduleActiveSessions(
    List<TrackingSession> sessions,
  ) async {
    if (!_enabled) {
      await cancelAllSessionAlarms();
      return;
    }
    final active = sessions.where((s) => s.status == SessionStatus.active);
    // 타입별 최신 하나만
    TrackingSession? fasting;
    TrackingSession? abstinence;
    for (final s in active) {
      if (s.type == SessionType.fasting) fasting = s;
      if (s.type == SessionType.abstinence) abstinence = s;
    }
    if (fasting != null) {
      await scheduleSessionMilestones(fasting);
    } else {
      await cancelForType(SessionType.fasting);
    }
    if (abstinence != null) {
      await scheduleSessionMilestones(abstinence);
    } else {
      await cancelForType(SessionType.abstinence);
    }
  }

  List<int> _idsFor(SessionType type) {
    if (type == SessionType.fasting) {
      return [_idFastingHalf, _idFastingTen, _idFastingDone];
    }
    return [_idAbstinenceHalf, _idAbstinenceTen, _idAbstinenceDone];
  }

  Future<void> _scheduleIfFuture({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    String? payload,
  }) async {
    final now = DateTime.now();
    // 이미 지난 시각은 스킵 (과거 시작 시각으로 세션 연 경우)
    if (!when.isAfter(now.add(const Duration(seconds: 5)))) return;

    final scheduled = tz.TZDateTime.from(when, tz.local);
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        styleInformation: BigTextStyleInformation(body),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    try {
      await _plugin.zonedSchedule(
        id: id,
        scheduledDate: scheduled,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        title: title,
        body: body,
        payload: payload,
      );
    } catch (e) {
      // exact 알람 권한 없으면 inexact로 재시도
      try {
        await _plugin.zonedSchedule(
          id: id,
          scheduledDate: scheduled,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: title,
          body: body,
          payload: payload,
        );
      } catch (e2) {
        if (kDebugMode) {
          debugPrint('schedule notification failed: $e2');
        }
      }
    }
  }
}
