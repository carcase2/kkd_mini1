import 'dart:io';

import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Face ID / Touch ID / 지문 등 기기 생체 인증
class BiometricService {
  BiometricService._();
  static final instance = BiometricService._();

  final LocalAuthentication _auth = LocalAuthentication();

  String _label = 'Face ID';

  /// 설정·잠금 화면에 쓸 이름 (Face ID / Touch ID / 지문)
  String get label => _label;

  /// iPad는 분할 화면에서 Face ID 목록이 비어 나온다.
  /// 하드웨어가 있으면 목록이 비어도 인증을 시도한다.
  Future<bool> isAvailable() async {
    try {
      final hardware = await _auth.canCheckBiometrics;
      if (!hardware) return false;

      final types = await _auth.getAvailableBiometrics();
      _label = _labelFor(types);
      return true;
    } catch (_) {
      return false;
    }
  }

  String _labelFor(List<BiometricType> types) {
    if (types.contains(BiometricType.face)) return 'Face ID';
    if (types.contains(BiometricType.fingerprint)) {
      return Platform.isIOS ? 'Touch ID' : '지문';
    }
    if (Platform.isIOS) return 'Face ID';
    return '생체 인증';
  }

  /// 얼굴 인식 창이 떠 있는 동안 true.
  /// 아이패드는 이 창 때문에 앱이 잠깐 백그라운드로 간다.
  bool get isAuthenticating => _inFlight != null;

  Future<bool>? _inFlight;

  /// 성공 시 true. 취소·실패·미지원은 false.
  ///
  /// apartment_webtoon_reader 의 잠금과 같다. 인증 직전에 가능 여부를
  /// 다시 물어 프롬프트를 건너뛰지 않고, 화면이 다시 만들어져도
  /// 진행 중인 인증을 공유한다.
  Future<bool> authenticate({String? reason}) {
    final current = _inFlight;
    if (current != null) return current;
    final run = _authenticate(reason: reason);
    _inFlight = run;
    return run.whenComplete(() {
      if (identical(_inFlight, run)) _inFlight = null;
    });
  }

  Future<bool> _authenticate({String? reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason ?? '앱 잠금을 해제하려면 인증하세요',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException {
      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> cancel() async {
    try {
      await _auth.stopAuthentication();
    } catch (_) {}
  }
}
