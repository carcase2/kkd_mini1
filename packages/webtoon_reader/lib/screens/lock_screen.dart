import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/biometric_authenticator.dart';
import '../services/lock_service.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _obscure = true;
  String? _error;
  BiometricKind _biometricKind = BiometricKind.none;
  bool _authenticating = false;
  AppLifecycleState? _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_prepareBiometrics(autoPrompt: true));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasBackground =
        _lifecycle == AppLifecycleState.paused ||
        _lifecycle == AppLifecycleState.hidden;
    _lifecycle = state;
    if (state == AppLifecycleState.resumed && wasBackground) {
      unawaited(_tryBiometric());
    }
  }

  Future<void> _prepareBiometrics({required bool autoPrompt}) async {
    final kind = await LockService.instance.biometricKind();
    if (!mounted) return;
    setState(() => _biometricKind = kind);
    if (autoPrompt && kind != BiometricKind.none) {
      await _tryBiometric();
      return;
    }
    _focusPassword();
  }

  Future<void> _tryBiometric() async {
    if (_biometricKind == BiometricKind.none || _authenticating) return;
    if (!LockService.instance.isLocked) return;

    setState(() {
      _authenticating = true;
      _error = null;
    });
    final unlocked = await LockService.instance.tryUnlockWithBiometrics();
    if (!mounted) return;
    setState(() => _authenticating = false);
    if (!unlocked) {
      _focusPassword();
    }
  }

  void _focusPassword() {
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
  }

  void _submit() {
    final password = _controller.text.trim();
    if (LockService.instance.tryUnlock(password)) {
      return;
    }
    setState(() {
      _error = '암호가 올바르지 않습니다';
      _controller.clear();
    });
    _focusPassword();
  }

  String get _biometricLabel {
    switch (_biometricKind) {
      case BiometricKind.face:
        return defaultTargetPlatform == TargetPlatform.iOS
            ? 'Face ID로 잠금 해제'
            : '얼굴 인식으로 잠금 해제';
      case BiometricKind.fingerprint:
        return defaultTargetPlatform == TargetPlatform.iOS
            ? 'Touch ID로 잠금 해제'
            : '지문으로 잠금 해제';
      case BiometricKind.generic:
        return '생체 인증으로 잠금 해제';
      case BiometricKind.none:
        return '';
    }
  }

  IconData get _biometricIcon {
    switch (_biometricKind) {
      case BiometricKind.face:
        return Icons.face_outlined;
      case BiometricKind.fingerprint:
        return Icons.fingerprint;
      case BiometricKind.generic:
        return Icons.verified_user_outlined;
      case BiometricKind.none:
        return Icons.verified_user_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showBiometric = _biometricKind != BiometricKind.none;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 64,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '암호를 입력하세요',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    obscureText: _obscure,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: '암호',
                      errorText: _error,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: _obscure ? '암호 보기' : '암호 숨기기',
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _submit,
                      child: const Text('확인'),
                    ),
                  ),
                  if (showBiometric) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _authenticating ? null : _tryBiometric,
                        icon: _authenticating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(_biometricIcon),
                        label: Text(_biometricLabel),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
