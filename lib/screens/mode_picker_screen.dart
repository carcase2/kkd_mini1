import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/app_state.dart';
import '../services/dual_auth.dart';
import '../theme/app_theme.dart';

class ModePickerScreen extends StatelessWidget {
  const ModePickerScreen({super.key, required this.onSelect});

  final ValueChanged<AppMode> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final auth = DualAuth.instance;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: auth,
          builder: (context, _) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '무엇을 열까요?',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    auth.email == null
                        ? '절제와 만화는 기록과 클라우드가 따로입니다.'
                        : '${auth.email} 로 로그인됨',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.textSecondary,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _ModeCard(
                    title: '절제',
                    subtitle: '단식 · 금욕 · 습관 · 통계',
                    icon: Icons.shield_rounded,
                    color: c.fasting,
                    soft: c.fastingSoft,
                    error: auth.disciplineError,
                    onOpen: () {
                      HapticFeedback.selectionClick();
                      onSelect(AppMode.discipline);
                    },
                    onRetry: auth.disciplineError == null
                        ? null
                        : () => _retry(context, AppMode.discipline),
                  ),
                  const SizedBox(height: 14),
                  _ModeCard(
                    title: '만화',
                    subtitle: '서재 · 카탈로그 · 리더',
                    icon: Icons.menu_book_rounded,
                    color: c.reading,
                    soft: c.readingSoft,
                    error: auth.webtoonError,
                    onOpen: () {
                      HapticFeedback.selectionClick();
                      onSelect(AppMode.webtoon);
                    },
                    onRetry: auth.webtoonError == null
                        ? null
                        : () => _retry(context, AppMode.webtoon),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _retry(BuildContext context, AppMode mode) {
    return retryModeLogin(context, mode);
  }
}

Future<void> retryModeLogin(BuildContext context, AppMode mode) async {
  final email = DualAuth.instance.email ?? await _savedLoginEmail();
  if (!context.mounted) return;
  final password = await showDialog<String>(
    context: context,
    builder: (ctx) => _RetryDialog(
      title: mode == AppMode.discipline ? '절제 다시 로그인' : '만화 다시 로그인',
      email: email ?? '',
    ),
  );
  if (password == null || password.isEmpty || email == null) return;
  await DualAuth.instance.signInSide(mode, email: email, password: password);
  if (!context.mounted) return;
  final auth = DualAuth.instance;
  final ok = mode == AppMode.discipline
      ? auth.disciplineLoggedIn
      : auth.webtoonLoggedIn;
  if (ok && mode == AppMode.discipline) {
    await context.read<AppState>().syncCloud();
  }
}

Future<String?> _savedLoginEmail() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('last_login_email');
}

class ModeFrame extends StatelessWidget {
  const ModeFrame({
    super.key,
    required this.mode,
    required this.onSelect,
    required this.child,
    this.notice,
    this.onNotice,
  });

  final AppMode mode;
  final ValueChanged<AppMode> onSelect;
  final Widget child;
  final String? notice;
  final VoidCallback? onNotice;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Column(
      children: [
        Material(
          color: c.surface,
          child: SafeArea(
            bottom: false,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.border)),
              ),
              child: SizedBox(
                height: 44,
                child: Row(
                  children: [
                    _ModeTab(
                      label: '절제',
                      icon: Icons.shield_outlined,
                      selectedIcon: Icons.shield_rounded,
                      selected: mode == AppMode.discipline,
                      color: c.fasting,
                      onTap: () => onSelect(AppMode.discipline),
                    ),
                    _ModeTab(
                      label: '만화',
                      icon: Icons.menu_book_outlined,
                      selectedIcon: Icons.menu_book_rounded,
                      selected: mode == AppMode.webtoon,
                      color: c.reading,
                      onTap: () => onSelect(AppMode.webtoon),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (notice != null && notice!.isNotEmpty)
          Material(
            color: c.warning.withValues(alpha: 0.15),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
              child: Row(
                children: [
                  Icon(Icons.cloud_off_rounded, size: 18, color: c.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      notice!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  if (onNotice != null)
                    TextButton(
                      onPressed: onNotice,
                      child: const Text('다시 로그인'),
                    ),
                ],
              ),
            ),
          ),
        // 탭 줄이 이미 상태 표시줄 아래에 있다.
        // 자식 Scaffold가 padding.top을 한 번 더 더하면 그 사이에 빈칸이 생긴다.
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        ),
      ],
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final fg = selected ? color : c.textSecondary;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: () {
              if (selected) return;
              HapticFeedback.selectionClick();
              onTap();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? color.withValues(alpha: 0.12)
                    : Colors.transparent,
                border: Border(
                  bottom: BorderSide(
                    color: selected ? color : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: ExcludeSemantics(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(selected ? selectedIcon : icon, size: 16, color: fg),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w700,
                        color: fg,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.soft,
    required this.onOpen,
    this.error,
    this.onRetry,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color soft;
  final String? error;
  final VoidCallback onOpen;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: soft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.textSecondary,
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        error!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: c.danger,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onRetry != null)
                IconButton(
                  tooltip: '다시 로그인',
                  onPressed: onRetry,
                  icon: Icon(Icons.refresh_rounded, color: color),
                )
              else
                Icon(Icons.chevron_right_rounded, color: c.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _RetryDialog extends StatefulWidget {
  const _RetryDialog({required this.title, required this.email});

  final String title;
  final String email;

  @override
  State<_RetryDialog> createState() => _RetryDialogState();
}

class _RetryDialogState extends State<_RetryDialog> {
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.email.isEmpty ? '이메일이 없습니다' : widget.email),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: _obscure,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '비밀번호',
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            onSubmitted: (_) => Navigator.pop(context, _password.text),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _password.text),
          child: const Text('로그인'),
        ),
      ],
    );
  }
}
