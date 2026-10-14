/// 답변의 근거 — "답의 근거 5곳" 한 줄이 보이고 기본은 접혀 있다. 누르면 출처 칩이 펼쳐지고, 다시 누르면 접힌다.
/// (사용자 결정 2026-09-22 "기본은 접힘". 2026-10-14 디자인 수정 때 접기가 빠졌다가 사용자 요청으로 되살렸다.
///  "원전 출처"라는 이름도 이때 "답의 근거"로 바꿨다.)
/// 각 칩은 한글 작품명 + 위치("마태복음 3:1~3:15") 뿐이다 — 칩은 누를 수 없고 본문도 보여주지 않는다
/// (사용자 결정 2026-09-22). 서버 호출은 없다. 작품명 한글 표기는 서버가 work_ko 로 보내 준다 (backend/app/works.py).
/// http 를 직접 쓰지 않는다 (CLAUDE.md 13절).
library;

import 'package:flutter/material.dart' hide Text;

import '../api/models.dart';
import 'keep_words.dart';

class SourcesSection extends StatefulWidget {
  final List<Source> sources;

  const SourcesSection({super.key, required this.sources});

  @override
  State<SourcesSection> createState() => _SourcesSectionState();
}

class _SourcesSectionState extends State<SourcesSection> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chip = theme.chipTheme;
    final sources = widget.sources;
    return Column(
      key: ValueKey('sources-${sources.map((s) => s.chunkId).join(',')}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          key: const Key('sources-toggle'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('답의 근거 ${sources.length}곳', style: theme.textTheme.labelMedium),
                const SizedBox(width: 4),
                Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18),
              ],
            ),
          ),
        ),
        if (_open) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final source in sources)
                DecoratedBox(
                  decoration: ShapeDecoration(
                    color: chip.backgroundColor ?? theme.colorScheme.surfaceContainerHigh,
                    shape: chip.shape ?? RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Padding(
                    padding: chip.padding ?? const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text(source.label, style: chip.labelStyle),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
