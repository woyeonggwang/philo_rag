/// 철학자 한 명의 소개 — 사상 요약과 쓴 책·관련 서적 목록 (2026-10-12). 소개 탭의 슬라이드를 누르면 열린다.
/// 탭을 덮는 전체 화면이다. 디자인은 Codex 몫.
library;

import 'package:flutter/material.dart';

import '../data/persona_profiles.dart';
import 'persona_grid_screen.dart' show PersonaVisual;

class PersonaDetailScreen extends StatelessWidget {
  final PersonaProfile profile;
  const PersonaDetailScreen({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.textTheme;
    final p = profile;
    // 일러스트는 위에 고정하고 글만 스크롤한다 — 글이 일러스트 밑으로 들어가며 흐려진다 (사용자 요청 2026-10-12)
    final visualHeight = (MediaQuery.sizeOf(context).height * 0.28).clamp(
      160.0,
      260.0,
    );
    return Scaffold(
      appBar: AppBar(title: Text(p.name)),
      body: Column(
        children: [
          SizedBox(
            height: visualHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: PersonaVisual(name: p.name),
            ),
          ),
          Expanded(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: const [Colors.transparent, Colors.black],
                stops: [0, 28 / bounds.height],
              ).createShader(bounds),
              child: _body(t),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(TextTheme t) {
    final p = profile;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Text(p.lifespan, style: t.bodySmall),
        const SizedBox(height: 6),
        Text(p.tagline, style: t.titleMedium),
        const SizedBox(height: 28),
        Text('사상', style: t.titleLarge),
        const SizedBox(height: 10),
        Text(p.summary, style: t.bodyMedium),
        const SizedBox(height: 16),
        for (final idea in p.ideas)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  idea.title,
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(idea.body, style: t.bodyMedium),
              ],
            ),
          ),
        const SizedBox(height: 16),
        Text('책', style: t.titleLarge),
        const SizedBox(height: 8),
        Text(p.booksIntro, style: t.bodySmall),
        const SizedBox(height: 8),
        for (final b in p.books)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3, right: 10),
                  child: Text(b.inApp ? '●' : '○', style: t.bodySmall),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(b.title, style: t.bodyLarge),
                      Text('${b.original} · ${b.year}', style: t.bodySmall),
                      if (b.note != null) Text(b.note!, style: t.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
