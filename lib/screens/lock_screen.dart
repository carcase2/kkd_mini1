import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../theme/app_theme.dart';

/// 앱 잠금 해제 화면 (PIN 입력)
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen>
    with SingleTickerProviderStateMixin {
  String _input = '';
  String? _error;
  late AnimationController _shake;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  void _onDigit(String d) {
    final state = context.read<AppState>();
    final maxLen = state.pinLength;
    if (_input.length >= maxLen) return;

    HapticFeedback.selectionClick();
    setState(() {
      _error = null;
      _input += d;
    });

    if (_input.length == maxLen) {
      _tryUnlock();
    }
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
    final pinLen = context.watch<AppState>().pinLength;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: c.fastingSoft,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: c.fasting.withValues(alpha: 0.25)),
                boxShadow: appCardShadow(c),
              ),
              child: Icon(Icons.lock_rounded, color: c.fasting, size: 34),
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
            const SizedBox(height: 8),
            Text(
              '비밀번호를 입력하세요',
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
                // 좌우 흔들림
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(pinLen, (i) {
                  final filled = i < _input.length;
                  return Container(
                    width: 14,
                    height: 14,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled ? c.fasting : Colors.transparent,
                      border: Border.all(
                        color: filled ? c.fasting : c.border,
                        width: 1.6,
                      ),
                    ),
                  );
                }),
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
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: _PinPad(
                colors: c,
                onDigit: _onDigit,
                onBackspace: _onBackspace,
                onClear: _onClear,
              ),
            ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}

class _PinPad extends StatelessWidget {
  final AppPalette colors;
  final void Function(String digit) onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  const _PinPad({
    required this.colors,
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['C', '0', '⌫'],
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
                    onTap: () {
                      if (key == '⌫') {
                        onBackspace();
                      } else if (key == 'C') {
                        onClear();
                      } else {
                        onDigit(key);
                      }
                    },
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

  const _KeyButton({
    required this.label,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isAction = label == 'C' || label == '⌫';
    return Material(
      color: isAction ? colors.chipBg : colors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.border),
            boxShadow: isAction ? null : appCardShadow(colors),
          ),
          child: label == '⌫'
              ? Icon(Icons.backspace_outlined, color: colors.textSecondary)
              : Text(
                  label,
                  style: TextStyle(
                    fontSize: isAction ? 18 : 24,
                    fontWeight: FontWeight.w800,
                    color: isAction ? colors.textSecondary : colors.textPrimary,
                  ),
                ),
        ),
      ),
    );
  }
}
