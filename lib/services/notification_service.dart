import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/session.dart';
import '../utils/format.dart';

/// 목표 시각이 지났을 때 즉시 완료 알림을 보낼지.
///
/// [alreadyVisibleOrPending]이면 OS가 이미 보여줬거나 곧 울리므로 건너뛴다.
/// [grace] 안이면 예약 알림이 막 울릴 수 있어 기다린다.
@visibleForTesting
bool shouldDeliverMissedCompletion({
  required DateTime endTime,
  required DateTime now,
  required bool alreadyShown,
  required bool alreadyVisibleOrPending,
  Duration grace = const Duration(seconds: 20),
}) {
  if (alreadyShown || alreadyVisibleOrPending) return false;
  if (endTime.isAfter(now)) return false;
  return now.difference(endTime) >= grace;
}

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
  static const _shownDonePrefix = 'session_notif_done_';

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
      await _configureLocalTimezone();

      const androidInit = AndroidInitializationSettings('@drawable/ic_stat_notify');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        defaultPresentAlert: true,
        defaultPresentSound: true,
        defaultPresentBadge: true,
        defaultPresentBanner: true,
        defaultPresentList: true,
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

  Future<void> _configureLocalTimezone() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      if (_trySetLocation(info.identifier)) return;
      if (kDebugMode) {
        debugPrint('Unknown timezone identifier: ${info.identifier}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('timezone detect failed: $e');
      }
    }
    // IANA 이름을 못 찾으면 오프셋으로 근사. 실패해도 UTC 인스턴트로 예약은 가능.
    final offset = DateTime.now().timeZoneOffset;
    final hours = offset.inHours;
    const offsetToIana = <int, String>{
      9: 'Asia/Seoul',
      8: 'Asia/Shanghai',
      0: 'UTC',
      -5: 'America/New_York',
      -8: 'America/Los_Angeles',
    };
    final guessed = offsetToIana[hours];
    if (guessed != null) {
      _trySetLocation(guessed);
    }
  }

  bool _trySetLocation(String name) {
    try {
      tz.setLocalLocation(tz.getLocation(name));
      return true;
    } catch (_) {
      const aliases = <String, String>{
        'GMT+09:00': 'Asia/Seoul',
        'GMT+9': 'Asia/Seoul',
        'KST': 'Asia/Seoul',
        'Korea Standard Time': 'Asia/Seoul',
        'Seoul': 'Asia/Seoul',
        'Asia/Seoul': 'Asia/Seoul',
      };
      final alias = aliases[name];
      if (alias == null) return false;
      try {
        tz.setLocalLocation(tz.getLocation(alias));
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  /// 알림 권한 요청 (Android 13+, iOS)
  Future<bool> requestPermission({bool requestExactAlarm = false}) async {
    if (!_ready) await init();

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final notif = await android.requestNotificationsPermission();
      if (requestExactAlarm) {
        final canExact = await android.canScheduleExactNotifications();
        if (canExact != true) {
          await android.requestExactAlarmsPermission();
        }
      }
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

  /// 목표가 있는 활성 세션에 대해 알림 예약.
  /// 목표 시각이 이미 지났으면 완료 알림을 즉시 표시한다.
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
      fireIfMissed: true,
      sessionId: session.id,
    );
  }

  /// 포그라운드에서 목표 도달을 감지했을 때 완료 알림이 빠졌으면 보완.
  Future<void> notifyReachedTargets(Iterable<TrackingSession> sessions) async {
    if (!_enabled) return;
    if (!_ready) await init();
    if (!_ready) return;

    final now = DateTime.now();
    for (final session in sessions) {
      if (session.status != SessionStatus.active) continue;
      if (!session.isTargetReached) continue;
      final target = session.targetDuration;
      if (target == null) continue;

      final alreadyShown = await _alreadyShownDone(session.id);
      final ids = _idsFor(session.type);
      final visibleOrPending = await _doneAlreadyVisibleOrPending(ids[2]);
      if (visibleOrPending) {
        await _markShownDone(session.id);
        continue;
      }

      final end = session.startTime.add(target);
      if (!shouldDeliverMissedCompletion(
        endTime: end,
        now: now,
        alreadyShown: alreadyShown,
        alreadyVisibleOrPending: false,
      )) {
        continue;
      }

      final title = session.type == SessionType.fasting ? '단식' : '금욕';
      await _showNow(
        id: ids[2],
        title: '$title · 목표 달성! 🎉',
        body: '목표 시간에 도달했어요. 앱에서 종료하거나 더 이어갈 수 있어요.',
        payload: 'session_${session.type.name}_done',
      );
      await _markShownDone(session.id);
    }
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

  NotificationDetails _details(String body) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@drawable/ic_stat_notify',
        category: AndroidNotificationCategory.reminder,
        styleInformation: BigTextStyleInformation(body),
        playSound: true,
        enableVibration: true,
        visibility: NotificationVisibility.public,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        presentBanner: true,
        presentList: true,
      ),
    );
  }

  Future<void> _showNow({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: _details(body),
        payload: payload,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('show notification failed: $e');
      }
    }
  }

  Future<void> _scheduleIfFuture({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    String? payload,
    bool fireIfMissed = false,
    String? sessionId,
  }) async {
    final now = DateTime.now();
    // 이미 지난(또는 2초 안) 시각
    if (!when.isAfter(now.add(const Duration(seconds: 2)))) {
      if (fireIfMissed && sessionId != null) {
        final shown = await _alreadyShownDone(sessionId);
        final pending = await _doneAlreadyVisibleOrPending(id);
        if (!shown && !pending) {
          await _showNow(
            id: id,
            title: title,
            body: body,
            payload: payload,
          );
          await _markShownDone(sessionId);
        } else if (pending) {
          await _markShownDone(sessionId);
        }
      } else {
        try {
          await _plugin.cancel(id: id);
        } catch (_) {}
      }
      return;
    }

    final scheduled = tz.TZDateTime.from(when, tz.local);
    final details = _details(body);

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

  Future<bool> _alreadyShownDone(String sessionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('$_shownDonePrefix$sessionId') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _markShownDone(String sessionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_shownDonePrefix$sessionId', true);
    } catch (_) {}
  }

  Future<bool> _doneAlreadyVisibleOrPending(int id) async {
    try {
      final pending = await _plugin.pendingNotificationRequests();
      if (pending.any((n) => n.id == id)) return true;
    } catch (_) {}
    try {
      final active = await _plugin.getActiveNotifications();
      if (active.any((n) => n.id == id)) return true;
    } catch (_) {}
    return false;
  }
}
