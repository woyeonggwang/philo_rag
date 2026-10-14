// 낱말이 줄 끝에서 쪼개지지 않게 (lib/ui/keep_words.dart, 2026-10-12).  실행: mobile 폴더에서  flutter test
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:philo_rag/ui/keep_words.dart' show keepWords, wordJoiner;

const _sentence = '아모르파티는 운명을 사랑하라는 뜻이다. 필연을 견디는 것으로 모자라고 그것을 사랑해야 한다.';

/// [text] 를 [width] 폭에 놓았을 때 각 줄이 끝나는 자리(원문 기준 글자 위치)
List<int> _lineEnds(String text, double width) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: const TextStyle(fontSize: 14)),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: width);
  final ends = <int>[];
  var offset = 0;
  while (offset < text.length) {
    final line = painter.getLineBoundary(TextPosition(offset: offset));
    if (line.end <= offset) break;
    ends.add(line.end);
    offset = line.end;
  }
  painter.dispose();
  return ends;
}

void main() {
  test('낱말 안의 글자 사이에만 단어 잇기 문자를 넣는다', () {
    expect(keepWords('아모르파티는 운명애다'), '${'아모르파티는'.split('').join(wordJoiner)} ${'운명애다'.split('').join(wordJoiner)}');
    expect(keepWords('설정'), '설정'); // 한 낱말짜리(버튼·탭 이름)는 그대로
    expect(keepWords('첫 줄\n둘째 줄').split('\n').length, 2); // 줄바꿈은 그대로
    const url = 'https://example.com/a-very-long-address-that-must-be-able-to-wrap';
    expect(keepWords('주소: $url'), contains(url)); // 아주 긴 덩어리는 그대로 (줄보다 길면 끊겨야 한다)
    expect(keepWords(_sentence).replaceAll(wordJoiner, ''), _sentence);
  });

  testWidgets('좁은 폭에서도 줄이 띄어쓰기에서만 바뀐다', (t) async {
    final kept = keepWords(_sentence);
    final ends = _lineEnds(kept, 120);
    expect(ends.length, greaterThan(2)); // 실제로 여러 줄이 된다
    for (final e in ends.take(ends.length - 1)) {
      // 줄 끝 바로 앞 또는 바로 뒤가 띄어쓰기여야 한다 (낱말 한가운데서 끊기지 않았다)
      final atSpace = kept[e - 1] == ' ' || (e < kept.length && kept[e] == ' ');
      expect(atSpace, isTrue, reason: '줄이 "${kept.substring(0, e).replaceAll(wordJoiner, '')}" 에서 끊겼다');
    }
    // 비교: 그대로 두면 낱말 가운데서 끊긴다 (이 문제를 고친 것이다)
    final raw = _lineEnds(_sentence, 120);
    expect(raw.take(raw.length - 1).any((e) => _sentence[e - 1] != ' ' && _sentence[e] != ' '), isTrue);
  });
}
