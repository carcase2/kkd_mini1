import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/dual_auth.dart';
import '../theme/app_theme.dart';

/// 만화 모드에 들어가기 전에 클라우드 계정을 확인합니다.
/// 이어 읽기와 저장한 서재는 이 계정의 webtoon_app_data 에 있습니다.
class WebtoonCloudGate extends StatefulWidget {
  const WebtoonCloudGate({super.key});

  @override
  State<WebtoonCloudGate> createState() => _WebtoonCloudGateState();
}

class _WebtoonCloudGateState extends State<WebtoonCloudGate> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscure = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final known = DualAuth.instance.email;
    if (known != null && known.isNotEmpty) {
      _email.text = known;
    } else {
      _loadEmail();
    }
  }

  Future<void> _loadEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('last_login_email');
    if (!mounted || saved == null || saved.isEmpty || _email.text.isNotEmpty) {
      return;
    }
    setState(() => _email.text = saved);
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    final result = await DualAuth.instance.signInSide(
      AppMode.webtoon,
      email: _email.text.trim(),
      password: _password.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.ok) {
      HapticFeedback.heavyImpact();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_login_email', _email.text.trim());
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final error = DualAuth.instance.webtoonError;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.cloud_done_rounded, size: 48, color: c.reading),
                  const SizedBox(height: 16),
                  Text(
                    '클라우드에 저장된 이어 읽기',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '저장한 만화와 읽던 위치는 만화 클라우드에 있습니다. 예전에 쓰던 만화 계정으로 로그인하면 그 위치부터 엽니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '이메일',
                      prefixIcon: Icon(Icons.mail_outline_rounded),
                    ),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty || !text.contains('@')) {
                        return '이메일을 입력하세요';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: '비밀번호',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '비밀번호를 입력하세요';
                      }
                      return null;
                    },
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: c.danger,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('클라우드에서 불러오기'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
