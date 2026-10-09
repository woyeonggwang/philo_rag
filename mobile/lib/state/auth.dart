/// 로그인 상태 (2026-10-10). 구글·애플·이메일 — 실제 처리는 Firebase Authentication (firebase_auth_backend.dart).
///
/// 화면(ui/)은 [AuthController] 만 쓴다. Firebase 를 직접 부르지 않는다.
/// 로그인 상태는 Firebase 가 기기에 저장하므로, 한 번 로그인하면 다음 실행 때 로그인 화면 없이 바로 넘어간다.
///
/// Firebase 설정(google-services.json)이 없으면 [AuthBackend.available] 이 false 다.
/// 이때 앱은 죽지 않고 로그인 화면을 보여 주며, 디버그 빌드에서만 "로그인 없이 계속(개발용)" 으로 들어갈 수 있다.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

/// 로그인한 사용자. 화면 표시와 대화 저장 폴더 구분(uid)에 쓴다.
class AppUser {
  final String uid;
  final String? email;
  final String? displayName;

  /// "google.com" | "apple.com" | "password" | "dev"
  final String provider;

  const AppUser({required this.uid, this.email, this.displayName, required this.provider});

  /// 디버그 빌드의 "로그인 없이 계속". 서버에는 토큰 없이 기기 ID 로 요청한다.
  bool get isDev => provider == 'dev';

  /// 화면에 보일 이름
  String get label => displayName?.isNotEmpty == true ? displayName! : (email ?? (isDev ? '개발용 (로그인 안 함)' : uid));
}

/// 화면에 그대로 보여줄 로그인 오류 문장
class AuthFailure implements Exception {
  final String message;
  const AuthFailure(this.message);
  @override
  String toString() => message;
}

/// 로그인 방식의 실제 구현. Firebase 구현과 테스트용 가짜가 이걸 따른다.
abstract class AuthBackend {
  /// Firebase 설정이 돼 있어 로그인을 쓸 수 있는지
  bool get available;

  /// 로그인 상태가 바뀔 때마다 (앱 시작 직후 저장된 상태 포함). 로그아웃이면 null.
  Stream<AppUser?> userChanges();

  /// 사용자가 창을 닫아 취소하면 아무것도 던지지 않고 끝난다. 실패는 [AuthFailure].
  Future<void> signInWithGoogle();
  Future<void> signInWithApple();
  Future<void> signInWithEmail(String email, String password);
  Future<void> signUpWithEmail(String email, String password);
  Future<void> sendPasswordReset(String email);
  Future<void> signOut();

  /// 서버에 보낼 Firebase ID 토큰. 만료가 가까우면 알아서 새로 받는다. 로그인 안 했으면 null.
  Future<String?> idToken();
}

enum AuthStatus { unknown, signedOut, signedIn }

class AuthController extends ChangeNotifier {
  final AuthBackend _backend;
  StreamSubscription<AppUser?>? _sub;

  AuthStatus _status = AuthStatus.unknown;
  AppUser? _user;
  AppUser? _devUser;
  bool _busy = false;
  String? _error;
  String? _notice;

  AuthController(this._backend) {
    if (!_backend.available) {
      _status = AuthStatus.signedOut;
      return;
    }
    _sub = _backend.userChanges().listen((u) {
      _user = u;
      _status = (u != null || _devUser != null) ? AuthStatus.signedIn : AuthStatus.signedOut;
      notifyListeners();
    }, onError: (Object e) {
      _status = AuthStatus.signedOut;
      notifyListeners();
    });
  }

  bool get available => _backend.available;

  /// unknown = 저장된 로그인 상태를 아직 확인 중 (첫 화면에 잠깐 로딩 표시)
  AuthStatus get status => _status;
  AppUser? get user => _user ?? _devUser;

  /// 로그인 버튼을 누른 뒤 결과를 기다리는 중
  bool get busy => _busy;

  /// 마지막 실패 문장 (화면에 빨간 글씨로). 다음 시도 때 지워진다.
  String? get error => _error;

  /// 성공 안내 (예: 비밀번호 재설정 메일을 보냈다)
  String? get notice => _notice;

  Future<void> signInWithGoogle() => _run(_backend.signInWithGoogle);
  Future<void> signInWithApple() => _run(_backend.signInWithApple);

  Future<void> signInWithEmail(String email, String password) {
    final e = _checkEmail(email, password);
    if (e != null) return _fail(e);
    return _run(() => _backend.signInWithEmail(email.trim(), password));
  }

  Future<void> signUpWithEmail(String email, String password) {
    final e = _checkEmail(email, password);
    if (e != null) return _fail(e);
    return _run(() => _backend.signUpWithEmail(email.trim(), password));
  }

  Future<void> sendPasswordReset(String email) async {
    if (!email.contains('@')) return _fail('비밀번호를 재설정할 이메일 주소를 먼저 입력하세요.');
    await _run(() => _backend.sendPasswordReset(email.trim()));
    if (_error == null) {
      _notice = '${email.trim()} 로 비밀번호 재설정 메일을 보냈습니다.';
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    if (_devUser != null) {
      _devUser = null;
      _status = _user != null ? AuthStatus.signedIn : AuthStatus.signedOut;
      notifyListeners();
      return;
    }
    await _run(_backend.signOut);
  }

  /// 디버그 빌드 전용 — Firebase 설정 전에도 앱을 시험할 수 있게. 릴리스 빌드에서는 아무 일도 안 한다.
  void continueWithoutLogin() {
    if (!kDebugMode) return;
    _devUser = const AppUser(uid: 'local', provider: 'dev');
    _status = AuthStatus.signedIn;
    _error = null;
    notifyListeners();
  }

  /// 서버 요청에 붙일 토큰. 개발용 우회 중이면 null (서버는 기기 ID 로 센다).
  Future<String?> idToken() async {
    if (_user == null) return null;
    try {
      return await _backend.idToken();
    } catch (e) {
      debugPrint('ID 토큰을 받지 못함: $e');
      return null;
    }
  }

  String? _checkEmail(String email, String password) {
    if (!email.trim().contains('@')) return '이메일 주소를 입력하세요.';
    if (password.length < 6) return '비밀번호는 6자 이상이어야 합니다.';
    return null;
  }

  Future<void> _fail(String message) async {
    _error = message;
    _notice = null;
    notifyListeners();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    _busy = true;
    _error = null;
    _notice = null;
    notifyListeners();
    try {
      await action();
    } on AuthFailure catch (e) {
      _error = e.message;
    } catch (e) {
      _error = '로그인하지 못했습니다: $e';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
