/// 처음 실행했을 때 한 번 보이는 소개 화면 (2026-10-10). 화면 아무 데나 누르면 넘어간다 (버튼 없음, 사용자 결정).
/// 문구·디자인은 Codex 몫.
library;

import 'package:flutter/material.dart';

class WelcomeScreen extends StatelessWidget {
  /// 화면을 누르면 부른다. 소개를 본 것으로 저장하고 로그인 화면으로 넘어간다.
  final VoidCallback onStart;

  const WelcomeScreen({super.key, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.textTheme;
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque, // 빈 곳을 눌러도 받는다
        onTap: onStart,
        child: SafeArea(
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
                Text('화면을 누르면 시작합니다',
                    style: t.bodySmall?.copyWith(color: theme.colorScheme.outline), textAlign: TextAlign.center),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
