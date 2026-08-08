import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_version.dart';

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
  AppUpdateInfo? _update;
  late AnimationController _shake;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _checkUpdate();
  }

  Future<void> _checkUpdate() async {
    final info = await UpdateService.checkForUpdate();
    if (!mounted || info == null) return;
    setState(() => _update = info);
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
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
        child: Column(
          children: [
            if (_update != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: _LockUpdateBanner(
                  info: _update!,
                  colors: c,
                  onTap: () => UpdateService.openUpdate(_update!),
                ),
              ),
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
              '비밀번호를 입력한 뒤 확인을 누르세요',
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

class _LockUpdateBanner extends StatelessWidget {
  final AppUpdateInfo info;
  final AppPalette colors;
  final VoidCallback onTap;

  const _LockUpdateBanner({
    required this.info,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.fasting.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.fasting.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(Icons.system_update_rounded, color: colors.fasting, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '새 버전 ${info.label} 출시',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      info.message.isNotEmpty
                          ? info.message
                          : '눌러서 업데이트하기',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colors.fasting),
            ],
          ),
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
            border: emphasize
                ? null
                : Border.all(color: colors.border),
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
