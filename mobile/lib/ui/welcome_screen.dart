/// 처음 실행했을 때 한 번 보이는 소개 화면 (2026-10-10). 기능 확인용 — 문구·디자인은 Codex 몫.
library;

import 'package:flutter/material.dart';

class WelcomeScreen extends StatelessWidget {
  /// "시작하기". 누르면 소개를 본 것으로 저장하고 로그인 화면으로 넘어간다.
  final VoidCallback onStart;

  const WelcomeScreen({super.key, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Text('철학 RAG', style: t.headlineLarge, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Text(
                '니체 · 예수 · 부처에게 묻고,\n그들이 남긴 글로 답을 듣습니다.',
                style: t.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                '답은 원전(니체의 저작, 공관복음, 초기 경전)에서 찾은 구절을 근거로 하며,\n어느 구절에서 왔는지 함께 보여 줍니다.',
                style: t.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              FilledButton(onPressed: onStart, child: const Text('시작하기')),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
