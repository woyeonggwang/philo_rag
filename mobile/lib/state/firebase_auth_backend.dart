/// [AuthBackend] 의 Firebase Authentication 구현 (2026-10-10).
///
/// 필요한 설정 (CLAUDE.md 13절 "로그인"):
///   - Firebase 프로젝트 + Android 앱(com.philorag.philo_rag, SHA-1 등록) → google-services.json 을 android/app/ 에
///   - 콘솔 Authentication 에서 Google · Apple · 이메일/비밀번호 사용 설정
///   - Apple 은 Apple Developer Program(유료) 의 Services ID·키가 있어야 켜진다
/// google-services.json 이 없으면 Firebase.initializeApp() 이 실패하고 available=false 로 동작한다 (앱은 켜진다).
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'auth.dart';

class FirebaseAuthBackend implements AuthBackend {
  @override
  final bool available;

  FirebaseAuthBackend._(this.available);

  /// 앱 시작 때 한 번. Firebase 설정이 없으면 로그인 없는 모드로 돌아온다.
  static Future<FirebaseAuthBackend> create() async {
    try {
      await Firebase.initializeApp();
      return FirebaseAuthBackend._(true);
    } catch (e) {
      debugPrint('Firebase 설정이 없어 로그인을 끈다 (google-services.json 확인): $e');
      return FirebaseAuthBackend._(false);
    }
  }

  FirebaseAuth get _auth => FirebaseAuth.instance;

  void _requireAvailable() {
    if (!available) {
      throw const AuthFailure('아직 Firebase 설정 전이라 로그인할 수 없습니다. (google-services.json 이 없습니다)');
    }
  }

  @override
  Stream<AppUser?> userChanges() =>
      available ? _auth.authStateChanges().map(_toAppUser) : Stream<AppUser?>.value(null);

  static AppUser? _toAppUser(User? u) {
    if (u == null) return null;
    final provider = u.providerData.isNotEmpty ? u.providerData.first.providerId : 'password';
    return AppUser(uid: u.uid, email: u.email, displayName: u.displayName, provider: provider);
  }

  bool _googleReady = false;

  @override
  Future<void> signInWithGoogle() async {
    _requireAvailable();
    try {
      final g = GoogleSignIn.instance;
      if (!_googleReady) {
        // serverClientId 는 google-services.json 의 default_web_client_id 를 플러그인이 알아서 읽는다
        await g.initialize();
        _googleReady = true;
      }
      final account = await g.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) throw const AuthFailure('구글 로그인 정보를 받지 못했습니다.');
      await _auth.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return; // 사용자가 창을 닫음
      throw AuthFailure('구글 로그인에 실패했습니다 (${e.code.name}). ${e.description ?? ''}'.trim());
    } on FirebaseAuthException catch (e) {
      final m = _message(e);
      if (m != null) throw AuthFailure(m);
    }
  }

  @override
  Future<void> signInWithApple() async {
    _requireAvailable();
    try {
      // Android 에서도 Firebase 가 웹 창으로 애플 로그인을 띄운다 (iOS 앱이 없어도 된다)
      final apple = AppleAuthProvider()
        ..addScope('email')
        ..addScope('name');
      await _auth.signInWithProvider(apple);
    } on FirebaseAuthException catch (e) {
      final m = _message(e);
      if (m != null) throw AuthFailure(m);
    }
  }

  @override
  Future<void> signInWithEmail(String email, String password) => _guard(
      () => _auth.signInWithEmailAndPassword(email: email, password: password));

  @override
  Future<void> signUpWithEmail(String email, String password) => _guard(
      () => _auth.createUserWithEmailAndPassword(email: email, password: password));

  @override
  Future<void> sendPasswordReset(String email) => _guard(() => _auth.sendPasswordResetEmail(email: email));

  @override
  Future<void> signOut() async {
    if (!available) return;
    try {
      if (_googleReady) await GoogleSignIn.instance.signOut();
    } catch (_) {}
    await _auth.signOut();
  }

  @override
  Future<String?> idToken() async => available ? _auth.currentUser?.getIdToken() : null;

  Future<void> _guard(Future<Object?> Function() action) async {
    _requireAvailable();
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      final m = _message(e);
      if (m != null) throw AuthFailure(m);
    }
  }

  /// Firebase 오류 코드 → 화면 문장. null 이면 사용자가 취소한 것이라 아무것도 보여주지 않는다.
  static String? _message(FirebaseAuthException e) {
    switch (e.code) {
      case 'web-context-canceled':
      case 'canceled':
      case 'web-context-already-presented':
        return null;
      case 'invalid-email':
        return '이메일 주소 형식이 올바르지 않습니다.';
      case 'user-disabled':
        return '사용이 중지된 계정입니다.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'INVALID_LOGIN_CREDENTIALS':
        return '이메일 또는 비밀번호가 맞지 않습니다.';
      case 'email-already-in-use':
        return '이미 가입된 이메일입니다. 로그인하세요.';
      case 'account-exists-with-different-credential':
        return '이 이메일은 다른 방법(구글·애플·이메일 중 하나)으로 이미 가입돼 있습니다. 그 방법으로 로그인하세요.';
      case 'weak-password':
        return '비밀번호는 6자 이상이어야 합니다.';
      case 'too-many-requests':
        return '시도가 너무 많습니다. 잠시 뒤 다시 하세요.';
      case 'network-request-failed':
        return '네트워크에 연결할 수 없습니다.';
      case 'operation-not-allowed':
        return '이 로그인 방식이 아직 Firebase 콘솔에서 켜져 있지 않습니다.';
      default:
        return '로그인하지 못했습니다 (${e.code}).';
    }
  }
}
