// SourcesSection — "답의 근거 N곳" 한 줄만 보이고(기본은 접힘), 누르면 한글 작품명과 위치가 펼쳐진다. 칩은 본문을 열지 않는다.
// 실행: mobile 폴더에서  flutter test
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:philo_rag/api/models.dart';
import 'package:philo_rag/ui/source_tile.dart';

import 'text_finders.dart';

const _sources = [
  Source(
    chunkId: 'jesus#3',
    work: 'THE GOSPEL ACCORDING TO MATTHEW',
    workKo: '마태복음',
    ref: '3:1~3:15',
    title: '',
    score: 0.49,
  ),
  Source(
    chunkId: 'jesus#40',
    work: 'THE GOSPEL ACCORDING TO LUKE',
    workKo: '누가복음',
    ref: '4:34~4:44',
    title: null,
    score: 0.47,
  ),
];

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(body: ListView(children: [child])),
);

void main() {
  testWidgets('기본은 접혀 "답의 근거 2곳"만 보이고, 누르면 출처가 펼쳐지고, 다시 누르면 접힌다', (tester) async {
    await tester.pumpWidget(_app(const SourcesSection(sources: _sources)));

    expect(findText('답의 근거 2곳'), findsOneWidget);
    expect(findText('마태복음 3:1~3:15'), findsNothing); // 접혀 있다

    await tester.tap(find.byKey(const Key('sources-toggle')));
    await tester.pumpAndSettle();
    expect(findText('마태복음 3:1~3:15'), findsOneWidget);
    expect(findText('누가복음 4:34~4:44'), findsOneWidget);
    // 영어 제목은 화면에 안 나온다
    expect(findTextContaining('GOSPEL ACCORDING'), findsNothing);

    // 칩을 눌러도 아무 일이 없다 (본문·번역을 열지 않는다)
    await tester.tap(findText('마태복음 3:1~3:15'));
    await tester.pumpAndSettle();
    expect(findText('마태복음 3:1~3:15'), findsOneWidget);
    expect(find.byType(InkWell), findsOneWidget); // 누를 수 있는 것은 머리줄 하나뿐

    await tester.tap(find.byKey(const Key('sources-toggle')));
    await tester.pumpAndSettle();
    expect(findText('마태복음 3:1~3:15'), findsNothing); // 다시 접혔다
    expect(find.byKey(const ValueKey('sources-jesus#3,jesus#40')), findsOneWidget);
  });

  test('Source.fromJson — work_ko 가 없으면 영어 제목으로 대신한다', () {
    final s = Source.fromJson({
      'chunk_id': 'x#1',
      'work': 'THE DHAMMAPADA',
      'ref': '1:1',
      'title': null,
      'score': 0.5,
    });
    expect(s.label, 'THE DHAMMAPADA 1:1');
    final k = Source.fromJson({
      'chunk_id': 'x#1',
      'work': 'THE DHAMMAPADA',
      'work_ko': '법구경',
      'ref': '1:1',
      'score': 0.5,
    });
    expect(k.label, '법구경 1:1');
  });
}
