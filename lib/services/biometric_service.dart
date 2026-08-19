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

  Future<bool> isAvailable() async {
    try {
      final hardware = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();
      if (!hardware && !supported) return false;

      final types = await _auth.getAvailableBiometrics();
      if (types.isEmpty) return false;

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

  /// 성공 시 true. 취소·실패·미지원은 false.
  Future<bool> authenticate({String? reason}) async {
    try {
      final available = await isAvailable();
      if (!available) return false;
      return await _auth.authenticate(
        localizedReason: reason ?? '$_label로 잠금을 해제하세요',
        biometricOnly: true,
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
