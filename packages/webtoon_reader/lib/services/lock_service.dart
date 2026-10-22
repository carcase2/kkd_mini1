import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'biometric_authenticator.dart';

class LockService extends ChangeNotifier with WidgetsBindingObserver {
  LockService._() {
    if (hostProvidesLock) {
      _isLocked = false;
    }
    WidgetsBinding.instance.addObserver(this);
  }

  static final LockService instance = LockService._();

  /// 껍데기 앱이 잠금 화면을 하나만 쓸 때 true.
  /// 생성 전에 켜 두어야 만화 쪽 잠금이 따로 시작되지 않습니다.
  static bool hostProvidesLock = false;

  /// 만화 화면의 잠금 버튼이 껍데기 잠금을 호출합니다.
  static void Function()? hostLock;

  static const correctPassword = '1850017';
  static const idleLockDuration = Duration(minutes: 3);

  @visibleForTesting
  static BiometricAuthenticator? debugAuthenticator;

  static BiometricAuthenticator? _defaultAuthenticator;
  bool _biometricInProgress = false;

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  bool _isLocked = true;
  bool _privacyShieldVisible = false;
  Timer? _idleTimer;
  DateTime? _lastActivityAt;
  DateTime? _lastTimerResetAt;
  int _keepAwakeCount = 0;

  bool get isLocked => _isLocked;
  bool get privacyShieldVisible => _privacyShieldVisible;
  bool get isKeepAwakeActive => _keepAwakeCount > 0;

  BiometricAuthenticator get _biometrics =>
      debugAuthenticator ??
      (_defaultAuthenticator ??= LocalAuthBiometricAuthenticator());

  Future<BiometricKind> biometricKind() => _biometrics.availableKind();

  /// Face ID / 지문 등으로 잠금을 풉니다. 실패하면 암호 입력을 쓰면 됩니다.
  Future<bool> tryUnlockWithBiometrics() async {
    if (!_isLocked) return true;
    if (_biometricInProgress) return false;

    _biometricInProgress = true;
    notifyListeners();
    try {
      final ok = await _biometrics.authenticate();
      if (!ok || !_isLocked) return ok && !_isLocked;
      _unlock();
      return true;
    } catch (_) {
      return false;
    } finally {
      _biometricInProgress = false;
      if (_isLocked) notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (hostProvidesLock) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      if (!_privacyShieldVisible) {
        _privacyShieldVisible = true;
        notifyListeners();
      }
      return;
    }

    if (state != AppLifecycleState.resumed) return;

    var shouldNotify = false;
    if (_privacyShieldVisible) {
      _privacyShieldVisible = false;
      shouldNotify = true;
    }

    if (_isLocked) {
      if (shouldNotify) notifyListeners();
      return;
    }

    // 다운로드/동기화 중에는 백그라운드에서 돌아와도 자동 잠금하지 않습니다.
    if (_keepAwakeCount > 0) {
      _lastActivityAt = DateTime.now();
      if (shouldNotify) notifyListeners();
      return;
    }

    final last = _lastActivityAt;
    if (last == null) {
      if (shouldNotify) notifyListeners();
      return;
    }
    if (DateTime.now().difference(last) >= idleLockDuration) {
      lock();
      return;
    }
    _resetIdleTimer();
    if (shouldNotify) notifyListeners();
  }

  /// 전체 받기 등 장시간 작업 동안 자동 잠금·화면 꺼짐을 막습니다.
  void beginKeepAwake() {
    _keepAwakeCount++;
    if (_keepAwakeCount != 1) return;
    _stopIdleTimer();
    _lastActivityAt = DateTime.now();
    unawaited(WakelockPlus.enable());
    notifyListeners();
  }

  void endKeepAwake() {
    if (_keepAwakeCount <= 0) return;
    _keepAwakeCount--;
    if (_keepAwakeCount > 0) return;
    unawaited(WakelockPlus.disable());
    if (!_isLocked) {
      _lastActivityAt = DateTime.now();
      _resetIdleTimer();
    }
    notifyListeners();
  }

  void recordActivity() {
    if (_isLocked) return;

    final now = DateTime.now();
    _lastActivityAt = now;

    if (_keepAwakeCount > 0) return;

    final lastReset = _lastTimerResetAt;
    if (lastReset != null &&
        now.difference(lastReset) < const Duration(seconds: 1)) {
      return;
    }
    _lastTimerResetAt = now;
    _resetIdleTimer();
  }

  void _resetIdleTimer() {
    if (_keepAwakeCount > 0) return;
    _idleTimer?.cancel();
    _idleTimer = Timer(idleLockDuration, lock);
  }

  void _stopIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _lastTimerResetAt = null;
  }

  bool tryUnlock(String password) {
    if (password != correctPassword) return false;
    _unlock();
    return true;
  }

  void _unlock() {
    _isLocked = false;
    _lastActivityAt = DateTime.now();
    _resetIdleTimer();
    notifyListeners();
  }

  /// [force]가 false이면 백그라운드 작업 중엔 자동 잠금을 무시합니다.
  void lock({bool force = false}) {
    if (hostProvidesLock) {
      hostLock?.call();
      return;
    }
    if (_isLocked) return;
    if (!force && _keepAwakeCount > 0) return;
    _isLocked = true;
    _stopIdleTimer();
    if (_keepAwakeCount > 0) {
      _keepAwakeCount = 0;
      unawaited(WakelockPlus.disable());
    }
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    notifyListeners();
  }
}
