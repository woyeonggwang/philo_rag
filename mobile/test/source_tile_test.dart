// SourcesSection — "근거 구절 N개" 는 접혀 있고, 펼치면 한글 작품명 목록만 보인다. 줄은 누를 수 없다.
// 실행: mobile 폴더에서  flutter test
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:philo_rag/api/models.dart';
import 'package:philo_rag/ui/source_tile.dart';

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

Widget _app(Widget child) =>
    MaterialApp(home: Scaffold(body: ListView(children: [child])));

void main() {
  testWidgets('헤더만 보이고, 누르면 한글 작품명 목록이 펼쳐진다', (tester) async {
    await tester.pumpWidget(_app(const SourcesSection(sources: _sources)));

    expect(find.text('근거 구절 2개'), findsOneWidget);
    expect(find.text('1. 마태복음 3:1~3:15'), findsNothing);

    await tester.tap(find.text('근거 구절 2개'));
    await tester.pumpAndSettle();

    expect(find.text('1. 마태복음 3:1~3:15'), findsOneWidget);
    expect(find.text('2. 누가복음 4:34~4:44'), findsOneWidget);
    // 영어 제목은 화면에 안 나온다
    expect(find.textContaining('GOSPEL ACCORDING'), findsNothing);
    // 줄은 펼쳐지는 타일이 아니다 (헤더 하나만 ExpansionTile)
    expect(find.byType(ExpansionTile), findsOneWidget);
  });

  testWidgets('다시 누르면 접힌다', (tester) async {
    await tester.pumpWidget(
        _app(const SourcesSection(sources: _sources, initiallyExpanded: true)));
    await tester.pumpAndSettle();
    expect(find.text('1. 마태복음 3:1~3:15'), findsOneWidget);

    await tester.tap(find.text('근거 구절 2개'));
    await tester.pumpAndSettle();
    expect(find.text('1. 마태복음 3:1~3:15'), findsNothing);
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
