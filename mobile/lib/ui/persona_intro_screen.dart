/// 소개 탭 — 철학자를 한 명씩 슬라이드로 넘겨 본다 (2026-10-12, 사용자 결정).
/// 한 화면에 한 명(옆 철학자가 살짝 보이게), 일러스트 · 이름 · 한 줄 소개. 누르면 사상·서적 페이지가 열린다.
/// 글은 앱에 넣어 둔 고정 글(data/persona_profiles.dart)이라 서버가 꺼져 있어도 보인다. 디자인은 Codex 몫.
library;

import 'package:flutter/material.dart';

import '../data/persona_profiles.dart';
import 'persona_detail_screen.dart';
import 'persona_grid_screen.dart' show PersonaVisual;

class PersonaIntroScreen extends StatefulWidget {
  const PersonaIntroScreen({super.key});

  @override
  State<PersonaIntroScreen> createState() => _PersonaIntroScreenState();
}

class _PersonaIntroScreenState extends State<PersonaIntroScreen> {
  final _pages = PageController(viewportFraction: 0.84);
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _open(PersonaProfile p) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PersonaDetailScreen(profile: p)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('철학자 소개')),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: personaProfiles.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) {
                final p = personaProfiles[i];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                  child: Card(
                    key: ValueKey('intro-${p.key}'),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _open(p),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
                              child: PersonaVisual(name: p.name),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.name,
                                  style: theme.textTheme.headlineSmall,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  p.tagline,
                                  style: theme.textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Text(
                                      '사상과 책 보기',
                                      style: theme.textTheme.labelLarge,
                                    ),
                                    const Icon(Icons.chevron_right, size: 18),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // 몇 번째 철학자인지 점으로
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < personaProfiles.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 18 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
