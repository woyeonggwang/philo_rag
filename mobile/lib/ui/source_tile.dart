/// 답변의 근거 구절 목록. "근거 구절 N개" 한 줄만 보이고(접힘), 누르면 목록이 펼쳐진다.
/// 각 줄은 한글 작품명 + 위치("마태복음 3:1~3:15") 뿐이다 — 줄은 누를 수 없고 본문도 보여주지 않는다
/// (사용자 결정 2026-09-22). 서버 호출은 없다. 작품명 한글 표기는 서버가 work_ko 로 보내 준다 (backend/app/works.py).
/// http 를 직접 쓰지 않는다 (CLAUDE.md 13절).
library;

import 'package:flutter/material.dart' hide Text;

import '../api/models.dart';
import 'keep_words.dart';

class SourcesSection extends StatelessWidget {
  final List<Source> sources;

  /// 처음부터 펼쳐 둘지. 기본은 접힘.
  final bool initiallyExpanded;

  const SourcesSection({
    super.key,
    required this.sources,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      // ExpansionTile 의 위아래 구분선을 없앤다
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: ValueKey('sources-${sources.map((s) => s.chunkId).join(',')}'),
        initiallyExpanded: initiallyExpanded,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: 4, bottom: 4),
        dense: true,
        title: Text('근거 구절 ${sources.length}개', style: theme.textTheme.labelMedium),
        children: [
          for (var i = 0; i < sources.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('${i + 1}. ${sources[i].label}',
                  style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}
