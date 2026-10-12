// 테스트용 글 찾기 — 화면 글에는 낱말이 줄 끝에서 끊기지 않게 단어 잇기 문자(U+2060)가 들어 있다 (lib/ui/keep_words.dart).
// find.text / find.textContaining 대신 이것을 쓰면 그 문자를 빼고 비교한다. (파일 이름이 _test 로 끝나지 않아 테스트로 돌지 않는다)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:philo_rag/ui/keep_words.dart' show wordJoiner;

String? _plain(Widget w) {
  final s = switch (w) {
    Text(:final data, :final textSpan) => data ?? textSpan?.toPlainText(),
    EditableText(:final controller) => controller.text, // 입력칸과 SelectableText(안에 EditableText 가 있다)
    _ => null,
  };
  return s?.replaceAll(wordJoiner, '');
}

Finder findText(String text) =>
    find.byWidgetPredicate((w) => _plain(w) == text, description: 'text "$text"');

Finder findTextContaining(String pattern) =>
    find.byWidgetPredicate((w) => _plain(w)?.contains(pattern) ?? false, description: 'text containing "$pattern"');
