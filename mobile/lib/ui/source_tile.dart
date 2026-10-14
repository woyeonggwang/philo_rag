/// 답변의 원전 출처를 접지 않고 바로 표시한다.
/// 각 줄은 한글 작품명 + 위치("마태복음 3:1~3:15") 뿐이다 — 줄은 누를 수 없고 본문도 보여주지 않는다
/// (사용자 결정 2026-09-22). 서버 호출은 없다. 작품명 한글 표기는 서버가 work_ko 로 보내 준다 (backend/app/works.py).
/// http 를 직접 쓰지 않는다 (CLAUDE.md 13절).
library;

import 'package:flutter/material.dart' hide Text;

import '../api/models.dart';
import 'keep_words.dart';

class SourcesSection extends StatelessWidget {
  final List<Source> sources;

  const SourcesSection({super.key, required this.sources});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chip = theme.chipTheme;
    return Column(
      key: ValueKey('sources-${sources.map((s) => s.chunkId).join(',')}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('원전 출처 · ${sources.length}개', style: theme.textTheme.labelMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final source in sources)
              DecoratedBox(
                decoration: ShapeDecoration(
                  color:
                      chip.backgroundColor ??
                      theme.colorScheme.surfaceContainerHigh,
                  shape:
                      chip.shape ??
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                ),
                child: Padding(
                  padding:
                      chip.padding ??
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(source.label, style: chip.labelStyle),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
