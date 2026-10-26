import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

enum BiometricKind { none, face, fingerprint, generic }

abstract class BiometricAuthenticator {
  Future<bool> isAvailable();
  Future<BiometricKind> availableKind();
  Future<bool> authenticate();
}

class LocalAuthBiometricAuthenticator implements BiometricAuthenticator {
  LocalAuthBiometricAuthenticator({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() async {
    final kind = await availableKind();
    return kind != BiometricKind.none;
  }

  @override
  Future<BiometricKind> availableKind() async {
    if (kIsWeb) return BiometricKind.none;
    try {
      final canCheck = await _auth.canCheckBiometrics;
      if (!canCheck) return BiometricKind.none;
      final types = await _auth.getAvailableBiometrics();
      if (types.contains(BiometricType.face)) return BiometricKind.face;
      if (types.contains(BiometricType.fingerprint)) {
        return BiometricKind.fingerprint;
      }
      if (types.isNotEmpty) return BiometricKind.generic;
      // iPad Face ID는 전체 화면이 되기 전에 등록 목록이 비어 있다.
      if (defaultTargetPlatform == TargetPlatform.iOS) return BiometricKind.face;
      return BiometricKind.none;
    } catch (_) {
      return BiometricKind.none;
    }
  }

  @override
  Future<bool> authenticate() async {
    if (kIsWeb) return false;
    try {
      return await _auth.authenticate(
        localizedReason: '앱 잠금을 해제하려면 인증하세요',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
