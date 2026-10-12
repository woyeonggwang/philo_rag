/// 로그인 화면 (2026-10-10). 구글 · 애플 · 이메일. 기능 확인용 — 디자인은 Codex 몫.
/// 로그인에 성공하면 AuthGate 가 알아서 홈으로 넘긴다 (이 화면은 화면 전환을 하지 않는다).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Text;

import '../state/auth.dart';
import 'app_theme.dart';
import 'keep_words.dart';

class LoginScreen extends StatefulWidget {
  final AuthController auth;
  const LoginScreen({super.key, required this.auth});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false; // false = 로그인, true = 회원가입

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submitEmail() {
    final a = widget.auth;
    _signUp
        ? a.signUpWithEmail(_email.text, _password.text)
        : a.signInWithEmail(_email.text, _password.text);
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.withDefaultFont(Theme.of(context)),
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final a = widget.auth;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: a,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 24),
              Text.rich(
                const TextSpan(children: [
                  TextSpan(text: '쉼표,', style: TextStyle(fontFamily: 'GowunBatang')),
                  TextSpan(text: ' · 로그인'),
                ]),
                style: theme.textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text('한 번 로그인하면 다음부터는 바로 시작합니다.',
                  style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
              if (!a.available) ...[
                const SizedBox(height: 16),
                Text(
                  'Firebase 설정 전이라 아직 로그인할 수 없습니다 (google-services.json 없음).',
                  style: TextStyle(color: theme.colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 32),
              OutlinedButton.icon(
                key: const Key('google'),
                onPressed: a.busy ? null : a.signInWithGoogle,
                icon: const Icon(Icons.g_mobiledata, size: 28),
                label: const Text('Google로 계속하기'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('apple'),
                onPressed: a.busy ? null : a.signInWithApple,
                icon: const Icon(Icons.apple),
                label: const Text('Apple로 계속하기'),
              ),
              const SizedBox(height: 28),
              Row(children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('또는 이메일', style: theme.textTheme.bodySmall),
                ),
                const Expanded(child: Divider()),
              ]),
              const SizedBox(height: 16),
              TextField(
                key: const Key('email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: '이메일'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('password'),
                controller: _password,
                obscureText: true,
                autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
                decoration: InputDecoration(
                  labelText: _signUp ? '비밀번호 (6자 이상)' : '비밀번호',
                ),
                onSubmitted: (_) => _submitEmail(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('email-submit'),
                onPressed: a.busy ? null : _submitEmail,
                child: Text(_signUp ? '이메일로 가입하기' : '이메일로 로그인'),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: a.busy ? null : () => setState(() => _signUp = !_signUp),
                    child: Text(_signUp ? '이미 계정이 있습니다' : '처음이신가요? 가입하기'),
                  ),
                  if (!_signUp)
                    TextButton(
                      onPressed: a.busy ? null : () => a.sendPasswordReset(_email.text),
                      child: const Text('비밀번호 찾기'),
                    ),
                ],
              ),
              if (a.busy) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
              if (a.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(a.error!, key: const Key('error'),
                      style: TextStyle(color: theme.colorScheme.error), textAlign: TextAlign.center),
                ),
              if (a.notice != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(a.notice!, textAlign: TextAlign.center),
                ),
              // 디버그 빌드에서만 보인다 — Firebase 설정 전에도 앱을 시험할 수 있게. 릴리스 빌드에는 없다
              if (kDebugMode) ...[
                const SizedBox(height: 32),
                TextButton(
                  key: const Key('dev-skip'),
                  onPressed: a.continueWithoutLogin,
                  child: const Text('로그인 없이 계속 (개발용)'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
