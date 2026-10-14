/// 한글 낱말이 줄 끝에서 쪼개지지 않게 한다 (2026-10-12, 사용자 요청 — "아모르파 / 티" 처럼 끊기지 않게).
///
/// Flutter 는 한글을 글자 단위로 줄바꿈하고, CSS 의 `word-break: keep-all` 같은 설정이 없다.
/// 그래서 낱말 안의 글자 사이에 보이지 않는 '단어 잇기 문자'(U+2060 WORD JOINER)를 넣어 띄어쓰기에서만 줄이 바뀌게 한다.
///
/// 화면 파일은 Flutter 의 Text 대신 이 Text 를 쓴다:
///     import 'package:flutter/material.dart' hide Text;
///     import 'keep_words.dart';
/// 새 화면을 만들 때도 이렇게 할 것 (CLAUDE.md 5.6). 복사할 글(대화 복사)은 원래 문자열에서 만든다 — 이 문자는 화면에만 들어간다.
library;

import 'package:flutter/material.dart' as m;
import 'package:flutter/material.dart' hide Text;

const wordJoiner = '⁠';
final _word = RegExp(r'\S+');

/// 띄어쓰기가 있는 글에서 각 낱말의 글자 사이에 단어 잇기 문자를 넣는다.
/// 한 낱말짜리(버튼·탭 이름)는 그대로 둔다. 아주 긴 덩어리(주소 등)도 그대로 — 줄보다 길면 어디서든 끊겨야 한다.
String keepWords(String s) {
  if (!s.contains(' ')) return s;
  return s.replaceAllMapped(_word, (match) {
    final w = match[0]!;
    return w.length > 24 ? w : w.characters.join(wordJoiner);
  });
}

/// Flutter 의 Text 와 같게 쓰되, 글에 [keepWords] 를 적용한다. 화면 낭독기에는 원래 글을 준다.
class Text extends StatelessWidget {
  final String? data;
  final InlineSpan? textSpan;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  const Text(
    String this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : textSpan = null;

  /// 여러 모양이 섞인 글. 줄바꿈 처리는 하지 않고 그대로 넘긴다 (짧은 제목에만 쓰인다).
  const Text.rich(
    InlineSpan this.textSpan, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : data = null;

  @override
  Widget build(BuildContext context) {
    final span = textSpan;
    if (span != null) {
      return m.Text.rich(span,
          style: style,
          strutStyle: strutStyle,
          textAlign: textAlign,
          textDirection: textDirection,
          locale: locale,
          softWrap: softWrap,
          overflow: overflow,
          textScaler: textScaler,
          maxLines: maxLines,
          semanticsLabel: semanticsLabel,
          textWidthBasis: textWidthBasis,
          textHeightBehavior: textHeightBehavior,
          selectionColor: selectionColor);
    }
    final text = data!;
    final kept = keepWords(text);
    return m.Text(kept,
        style: style,
        strutStyle: strutStyle,
        textAlign: textAlign,
        textDirection: textDirection,
        locale: locale,
        softWrap: softWrap,
        overflow: overflow,
        textScaler: textScaler,
        maxLines: maxLines,
        semanticsLabel: semanticsLabel ?? (identical(kept, text) ? null : text),
        textWidthBasis: textWidthBasis,
        textHeightBehavior: textHeightBehavior,
        selectionColor: selectionColor);
  }
}
