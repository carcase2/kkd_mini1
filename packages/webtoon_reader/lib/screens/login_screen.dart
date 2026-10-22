import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_sync_service.dart';

/// 이메일 로그인 / 회원가입 (재설치 후 데이터 복원용)
class LoginScreen extends StatefulWidget {
  final Future<void> Function() onLoggedIn;

  const LoginScreen({super.key, required this.onLoggedIn});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _lastEmailKey = 'last_login_email';

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _signUpMode = false;
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLastEmail();
  }

  Future<void> _loadLastEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_lastEmailKey);
    if (email != null && email.isNotEmpty && mounted) {
      _emailCtrl.text = email;
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    try {
      final cloud = SupabaseSyncService.instance;
      if (_signUpMode) {
        await cloud.signUp(email: email, password: password);
      } else {
        await cloud.signIn(email: email, password: password);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastEmailKey, email);

      HapticFeedback.mediumImpact();
      await widget.onLoggedIn();
    } on AuthException catch (e) {
      setState(() => _error = _friendlyAuthError(e));
      HapticFeedback.heavyImpact();
    } catch (_) {
      setState(() => _error = '로그인에 실패했습니다. 네트워크를 확인해 주세요.');
      HapticFeedback.heavyImpact();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyAuthError(AuthException e) {
    final msg = e.message.toLowerCase();
    final code = e.code?.toLowerCase() ?? '';
    if (code.contains('over_email_send_rate_limit') ||
        msg.contains('rate limit') ||
        msg.contains('email rate limit')) {
      return '가입 요청이 너무 잦습니다. 1분 뒤 다시 시도해 주세요.';
    }
    if (msg.contains('invalid login') || msg.contains('invalid credentials')) {
      return '이메일 또는 비밀번호가 올바르지 않습니다';
    }
    if (msg.contains('already registered') ||
        msg.contains('already been') ||
        msg.contains('user already exists')) {
      return '이미 가입된 이메일입니다. 로그인으로 시도해 주세요';
    }
    if (msg.contains('email not confirmed') ||
        msg.contains('not confirmed')) {
      return '이메일 확인이 필요합니다. 잠시 후 다시 시도하거나 관리자에게 문의하세요.';
    }
    if (msg.contains('password should be') ||
        msg.contains('password is too short') ||
        (msg.contains('password') && msg.contains('6'))) {
      return '비밀번호는 6자 이상으로 입력해 주세요';
    }
    if (msg.contains('unable to validate email') ||
        msg.contains('invalid email') ||
        (msg.contains('email address') && msg.contains('invalid'))) {
      return '이메일 형식을 확인해 주세요';
    }
    // 원문 노출 — 잘못된 번역보다 원인 파악이 중요합니다.
    return e.message;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Icon(
                      Icons.auto_stories_rounded,
                      color: scheme.primary,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'COAD',
                    textAlign: TextAlign.center,
                    style: textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _signUpMode
                        ? '계정을 만들면 재설치 후에도 서재와 읽기 기록이 유지됩니다'
                        : '로그인하면 서재를 불러옵니다',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    decoration: _decoration(
                      context,
                      '이메일',
                      Icons.mail_outline_rounded,
                    ),
                    validator: (v) {
                      final t = v?.trim() ?? '';
                      if (t.isEmpty || !t.contains('@')) {
                        return '이메일을 입력하세요';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordCtrl,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: _decoration(
                      context,
                      '비밀번호',
                      Icons.lock_outline_rounded,
                      suffix: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.length < 6) {
                        return '비밀번호 6자 이상';
                      }
                      return null;
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.error,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _signUpMode ? '계정 만들기' : '로그인',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _signUpMode = !_signUpMode;
                              _error = null;
                            }),
                    child: Text(
                      _signUpMode ? '이미 계정이 있나요? 로그인' : '처음인가요? 계정 만들기',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(
    BuildContext context,
    String label,
    IconData icon, {
    Widget? suffix,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: scheme.onSurfaceVariant),
      suffixIcon: suffix,
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
    );
  }
}
