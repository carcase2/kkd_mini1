import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import 'package:webtoon_reader/config/supabase_config.dart' as webtoon_config;

enum AppMode { discipline, webtoon }

class SideAuth {
  const SideAuth({required this.ok, this.error});

  final bool ok;
  final String? error;
}

class DualSignInResult {
  const DualSignInResult({required this.discipline, required this.webtoon});

  final SideAuth discipline;
  final SideAuth webtoon;

  bool get anySuccess => discipline.ok || webtoon.ok;
}

/// 절제·만화 Supabase 를 싱글톤 없이 각각 띄웁니다.
/// 세션 키는 Supabase.initialize 와 같은 `sb-<project-ref>-auth-token` 입니다.
class DualAuth extends ChangeNotifier with WidgetsBindingObserver {
  DualAuth._();
  static final instance = DualAuth._();

  static String sessionKeyFor(String url) {
    final ref = Uri.parse(url).host.split('.').first;
    return 'sb-$ref-auth-token';
  }

  SupabaseClient? disciplineClient;
  SupabaseClient? webtoonClient;

  String? disciplineError;
  String? webtoonError;

  bool _opened = false;

  bool get disciplineLoggedIn => _loggedIn(disciplineClient);
  bool get webtoonLoggedIn => _loggedIn(webtoonClient);
  bool get anyLoggedIn => disciplineLoggedIn || webtoonLoggedIn;

  String? get email =>
      disciplineClient?.auth.currentUser?.email ??
      webtoonClient?.auth.currentUser?.email;

  bool _loggedIn(SupabaseClient? client) {
    final user = client?.auth.currentUser;
    if (user == null) return false;
    return user.isAnonymous != true;
  }

  Future<void> init() async {
    if (_opened) return;
    _opened = true;
    WidgetsBinding.instance.addObserver(this);
    disciplineClient = await _open(
      url: SupabaseConfig.url,
      key: SupabaseConfig.publishableKey,
      sessionKey: sessionKeyFor(SupabaseConfig.url),
      label: '절제',
    );
    webtoonClient = await _open(
      url: webtoon_config.SupabaseConfig.url,
      key: webtoon_config.SupabaseConfig.publishableKey,
      sessionKey: sessionKeyFor(webtoon_config.SupabaseConfig.url),
      label: '만화',
    );
    if (disciplineClient == null) {
      disciplineError ??= '절제 클라우드에 연결하지 못했습니다';
    }
    if (webtoonClient == null) {
      webtoonError ??= '만화 클라우드에 연결하지 못했습니다';
    }
    await _dropAnonymous(disciplineClient);
    await _dropAnonymous(webtoonClient);
    notifyListeners();
  }

  Future<SupabaseClient?> _open({
    required String url,
    required String key,
    required String sessionKey,
    required String label,
  }) async {
    try {
      final storage = SharedPreferencesLocalStorage(
        persistSessionKey: sessionKey,
      );
      await storage.initialize();
      final client = SupabaseClient(
        url,
        key,
        authOptions: FlutterAuthClientOptions(
          localStorage: storage,
          pkceAsyncStorage: SharedPreferencesGotrueAsyncStorage(),
        ),
      );
      client.auth.onAuthStateChange.listen(
        (data) {
          final session = data.session;
          if (session != null) {
            storage.persistSession(jsonEncode(session.toJson()));
          } else if (data.event == AuthChangeEvent.signedOut) {
            storage.removePersistedSession();
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('$label auth stream: $error\n$stackTrace');
        },
      );
      final persisted = await storage.accessToken();
      if (persisted != null && persisted.isNotEmpty) {
        try {
          await client.auth.setInitialSession(persisted);
        } catch (e, st) {
          debugPrint('$label setInitialSession: $e\n$st');
        }
        try {
          await client.auth.recoverSession(persisted);
        } catch (e, st) {
          debugPrint('$label recoverSession: $e\n$st');
        }
      }
      return client;
    } catch (e, st) {
      debugPrint('$label Supabase client failed: $e\n$st');
      return null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final clients = [disciplineClient, webtoonClient];
    if (state == AppLifecycleState.resumed) {
      for (final client in clients) {
        client?.auth.startAutoRefresh();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      for (final client in clients) {
        client?.auth.stopAutoRefresh();
      }
    }
  }

  Future<void> _dropAnonymous(SupabaseClient? client) async {
    final user = client?.auth.currentUser;
    if (user != null && user.isAnonymous == true) {
      await client!.auth.signOut();
    }
  }

  Future<DualSignInResult> signIn({
    required String email,
    required String password,
  }) async {
    final discipline = await _signInSide(
      AppMode.discipline,
      email: email,
      password: password,
    );
    final webtoon = await _signInSide(
      AppMode.webtoon,
      email: email,
      password: password,
    );
    notifyListeners();
    return DualSignInResult(discipline: discipline, webtoon: webtoon);
  }

  Future<DualSignInResult> signUp({
    required String email,
    required String password,
  }) async {
    final discipline = await _signUpSide(
      AppMode.discipline,
      email: email,
      password: password,
    );
    final webtoon = await _signUpSide(
      AppMode.webtoon,
      email: email,
      password: password,
    );
    notifyListeners();
    return DualSignInResult(discipline: discipline, webtoon: webtoon);
  }

  Future<SideAuth> signInSide(
    AppMode mode, {
    required String email,
    required String password,
  }) async {
    final result = await _signInSide(mode, email: email, password: password);
    notifyListeners();
    return result;
  }

  Future<void> signOut() async {
    await disciplineClient?.auth.signOut();
    await webtoonClient?.auth.signOut();
    disciplineError = null;
    webtoonError = null;
    notifyListeners();
  }

  Future<SideAuth> _signInSide(
    AppMode mode, {
    required String email,
    required String password,
  }) async {
    final client = mode == AppMode.discipline
        ? disciplineClient
        : webtoonClient;
    final label = mode == AppMode.discipline ? '절제' : '만화';
    if (client == null) {
      _setError(mode, '$label 클라우드에 연결하지 못했습니다');
      return SideAuth(ok: false, error: _errorOf(mode));
    }
    try {
      await client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      _setError(mode, null);
      return const SideAuth(ok: true);
    } catch (e) {
      final message = _friendly(label, e);
      _setError(mode, message);
      return SideAuth(ok: false, error: message);
    }
  }

  Future<SideAuth> _signUpSide(
    AppMode mode, {
    required String email,
    required String password,
  }) async {
    final client = mode == AppMode.discipline
        ? disciplineClient
        : webtoonClient;
    final label = mode == AppMode.discipline ? '절제' : '만화';
    if (client == null) {
      _setError(mode, '$label 클라우드에 연결하지 못했습니다');
      return SideAuth(ok: false, error: _errorOf(mode));
    }
    try {
      final res = await client.auth.signUp(
        email: email.trim(),
        password: password,
      );
      if (res.session == null) {
        await client.auth.signInWithPassword(
          email: email.trim(),
          password: password,
        );
      }
      _setError(mode, null);
      return const SideAuth(ok: true);
    } catch (e) {
      final raw = e is AuthException ? e.message.toLowerCase() : '$e'.toLowerCase();
      if (raw.contains('already') || raw.contains('registered')) {
        return _signInSide(mode, email: email, password: password);
      }
      final message = _friendly(label, e);
      _setError(mode, message);
      return SideAuth(ok: false, error: message);
    }
  }

  void _setError(AppMode mode, String? message) {
    if (mode == AppMode.discipline) {
      disciplineError = message;
    } else {
      webtoonError = message;
    }
  }

  String? _errorOf(AppMode mode) =>
      mode == AppMode.discipline ? disciplineError : webtoonError;

  String _friendly(String label, Object error) {
    final msg = error is AuthException
        ? error.message.toLowerCase()
        : '$error'.toLowerCase();
    if (msg.contains('invalid login') || msg.contains('invalid credentials')) {
      return '$label: 이메일 또는 비밀번호가 올바르지 않습니다';
    }
    if (msg.contains('already registered') || msg.contains('already been')) {
      return '$label: 이미 가입된 이메일입니다';
    }
    if (msg.contains('password')) {
      return '$label: 비밀번호는 6자 이상으로 입력해 주세요';
    }
    if (msg.contains('email')) {
      return '$label: 이메일 형식을 확인해 주세요';
    }
    if (error is AuthException && error.message.isNotEmpty) {
      return '$label: ${error.message}';
    }
    return '$label: 로그인에 실패했습니다. 네트워크를 확인해 주세요';
  }
}
