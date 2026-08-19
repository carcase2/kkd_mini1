import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/biometric_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_version.dart';

/// 앱 잠금 해제 화면 (Face ID 또는 PIN 입력)
///
/// 업데이트 배너는 여기에 두지 않는다. 상단 카드가 키패드를 밀어내
/// 비밀번호 입력이 막히는 문제를 피하기 위함. 업데이트는 홈에서만 안내.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  String _input = '';
  String? _error;
  late AnimationController _shake;

  bool _biometricAvailable = false;
  String _biometricLabel = 'Face ID';
  bool _authenticating = false;
  bool _wasBackgrounded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_prepareBiometric(autoPrompt: true));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(BiometricService.instance.cancel());
    _shake.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _wasBackgrounded = true;
    } else if (state == AppLifecycleState.resumed &&
        _wasBackgrounded &&
        !_authenticating) {
      _wasBackgrounded = false;
      unawaited(_prepareBiometric(autoPrompt: true));
    }
  }

  Future<void> _prepareBiometric({required bool autoPrompt}) async {
    final app = context.read<AppState>();
    if (!app.biometricUnlockEnabled) {
      if (mounted) setState(() => _biometricAvailable = false);
      return;
    }
    final available = await BiometricService.instance.isAvailable();
    if (!mounted) return;
    setState(() {
      _biometricAvailable = available;
      _biometricLabel = BiometricService.instance.label;
    });
    if (autoPrompt && available) {
      await _unlockWithBiometric();
    }
  }

  Future<void> _unlockWithBiometric() async {
    if (_authenticating) return;
    final app = context.read<AppState>();
    if (!app.biometricUnlockEnabled) return;

    setState(() {
      _authenticating = true;
      _error = null;
    });
    final ok = await BiometricService.instance.authenticate(
      reason: '$_biometricLabel로 잠금을 해제하세요',
    );
    if (!mounted) return;
    setState(() => _authenticating = false);
    if (ok) {
      HapticFeedback.mediumImpact();
      app.unlockWithBiometric();
      return;
    }
  }

  static const _maxPinLen = 12;

  void _onDigit(String d) {
    // 최대 길이만 제한 — 실제 자릿수는 UI에 노출하지 않음
    if (_input.length >= _maxPinLen) return;

    HapticFeedback.selectionClick();
    setState(() {
      _error = null;
      _input += d;
    });
  }

  void _onBackspace() {
    if (_input.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _error = null;
      _input = _input.substring(0, _input.length - 1);
    });
  }

  void _onClear() {
    if (_input.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() {
      _error = null;
      _input = '';
    });
  }

  Future<void> _tryUnlock() async {
    if (_input.isEmpty) {
      setState(() => _error = '비밀번호를 입력하세요');
      return;
    }
    final state = context.read<AppState>();
    final ok = state.unlockWithPin(_input);
    if (ok) {
      HapticFeedback.mediumImpact();
      return;
    }
    HapticFeedback.heavyImpact();
    _shake.forward(from: 0);
    setState(() {
      _error = '비밀번호가 올바르지 않습니다';
      _input = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              // 작은 화면에서도 키패드가 잘리지 않도록
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const Spacer(flex: 2),
                      Material(
                        color: c.fastingSoft,
                        borderRadius: BorderRadius.circular(22),
                        child: InkWell(
                          onTap: _biometricAvailable
                              ? _unlockWithBiometric
                              : null,
                          borderRadius: BorderRadius.circular(22),
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: c.fasting.withValues(alpha: 0.25),
                              ),
                              boxShadow: appCardShadow(c),
                            ),
                            child: Icon(
                              _biometricAvailable
                                  ? (_biometricLabel == '지문' ||
                                          _biometricLabel == 'Touch ID'
                                      ? Icons.fingerprint_rounded
                                      : Icons.face_unlock_rounded)
                                  : Icons.lock_rounded,
                              color: c.fasting,
                              size: 34,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '절제',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppVersion.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: c.textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _biometricAvailable
                            ? '$_biometricLabel 또는 비밀번호로 잠금을 해제하세요'
                            : '비밀번호를 입력한 뒤 확인을 누르세요',
                        style: TextStyle(
                          fontSize: 14,
                          color: c.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 28),
                      AnimatedBuilder(
                        animation: _shake,
                        builder: (context, child) {
                          final t = _shake.value;
                          final dx = (t < 1)
                              ? (20 *
                                  (1 - t) *
                                  ((t * 10).floor().isEven ? 1 : -1) *
                                  (t < 0.05 ? 0 : 1))
                              : 0.0;
                          return Transform.translate(
                            offset: Offset(dx, 0),
                            child: child,
                          );
                        },
                        child: _PinSlots(
                          colors: c,
                          input: _input,
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 20,
                        child: Text(
                          _error ?? '',
                          style: TextStyle(
                            color: c.danger,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (_biometricAvailable)
                        TextButton.icon(
                          onPressed:
                              _authenticating ? null : _unlockWithBiometric,
                          icon: Icon(
                            _biometricLabel == '지문' ||
                                    _biometricLabel == 'Touch ID'
                                ? Icons.fingerprint_rounded
                                : Icons.face_unlock_rounded,
                            size: 20,
                          ),
                          label: Text(
                            '$_biometricLabel로 잠금 해제',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: c.fasting,
                          ),
                        ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 36),
                        child: _PinPad(
                          colors: c,
                          onDigit: _onDigit,
                          onBackspace: _onBackspace,
                          onClear: _onClear,
                          onSubmit: _tryUnlock,
                        ),
                      ),
                      const SizedBox(height: 28),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 입력 전: 빈 칸 4개. 숫자 누르면 4칸 사라지고 입력 ●만 표시.
class _PinSlots extends StatelessWidget {
  final AppPalette colors;
  final String input;

  const _PinSlots({
    required this.colors,
    required this.input,
  });

  @override
  Widget build(BuildContext context) {
    if (input.isEmpty) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (i) {
          return Container(
            width: 18,
            height: 18,
            margin: EdgeInsets.only(left: i == 0 ? 0 : 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: colors.textMuted.withValues(alpha: 0.45),
                width: 1.6,
              ),
              color: colors.chipBg,
            ),
          );
        }),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(input.length, (i) {
        return Container(
          width: 12,
          height: 12,
          margin: EdgeInsets.only(left: i == 0 ? 0 : 10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.fasting,
          ),
        );
      }),
    );
  }
}

class _PinPad extends StatelessWidget {
  final AppPalette colors;
  final void Function(String digit) onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onSubmit;

  const _PinPad({
    required this.colors,
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['C', '0', 'OK'],
    ];

    return Column(
      children: keys.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: row.map((key) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _KeyButton(
                    label: key,
                    colors: colors,
                    emphasize: key == 'OK',
                    onTap: () {
                      if (key == 'OK') {
                        onSubmit();
                      } else if (key == 'C') {
                        onClear();
                      } else if (key == '⌫') {
                        onBackspace();
                      } else {
                        onDigit(key);
                      }
                    },
                    onLongPress: key == 'C' ? onBackspace : null,
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}

class _KeyButton extends StatelessWidget {
  final String label;
  final AppPalette colors;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool emphasize;

  const _KeyButton({
    required this.label,
    required this.colors,
    required this.onTap,
    this.onLongPress,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final isAction = label == 'C' || label == '⌫';
    final bg = emphasize
        ? colors.fasting
        : (isAction ? colors.chipBg : colors.surface);
    final fg = emphasize
        ? Colors.white
        : (isAction ? colors.textSecondary : colors.textPrimary);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: emphasize ? null : Border.all(color: colors.border),
            boxShadow: isAction || emphasize ? null : appCardShadow(colors),
          ),
          child: label == '⌫'
              ? Icon(Icons.backspace_outlined, color: fg)
              : Text(
                  label == 'OK' ? '확인' : label,
                  style: TextStyle(
                    fontSize: label == 'OK' ? 16 : (isAction ? 18 : 24),
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
        ),
      ),
    );
  }
}
