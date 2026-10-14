// 대화창을 열면 맨 아래(가장 최근 답)가 보여야 한다 (2026-10-14 — 긴 답이 많으면 중간에서 열렸다).
// 실행: mobile 폴더에서  flutter test
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:philo_rag/api/client.dart';
import 'package:philo_rag/api/models.dart';
import 'package:philo_rag/state/chat.dart';
import 'package:philo_rag/ui/chat_screen.dart';

import 'text_finders.dart';

/// 앞쪽 답은 짧고 뒤쪽 답은 길게 — 목록은 앞쪽 말풍선으로 전체 길이를 어림하므로 실제보다 짧게 잡는다 (기기에서 본 상황)
String _answer(String q) {
  final n = int.parse(q.split(' ').last);
  final body = n <= 10 ? '짧은 답이다. ' : '그대는 이 길을 끝까지 걸어야 한다. ' * 30;
  return '$q 에 대한 답이다. $body마지막 문장이다.';
}

PhiloRagClient _server() => PhiloRagClient('http://x', httpClient: MockClient((req) async {
      final q = (jsonDecode(req.body) as Map)['question'] as String;
      return http.Response.bytes(
          utf8.encode(jsonEncode({
            'persona': 'nietzsche', 'persona_name': '니체', 'question': q, 'answer': _answer(q),
            'grounded': true, 'safety': false, 'retries': 0, 'glossary': [], 'sources': [],
          })),
          200,
          headers: {'content-type': 'application/json'});
    }));

void main() {
  testWidgets('긴 답이 많아도 대화창을 열면 가장 최근 답의 끝이 보인다', (t) async {
    t.view.physicalSize = const Size(400, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    final chat = ChatController(_server());
    await t.runAsync(() async {
      for (var i = 1; i <= 14; i++) {
        await chat.send('nietzsche', '질문 $i');
      }
    });
    const nietzsche = Persona(key: 'nietzsche', name: '니체', blurb: '망치를 든 철학자', enabled: true);
    await t.pumpWidget(MaterialApp(home: ChatScreen(persona: nietzsche, chat: chat)));
    await t.pumpAndSettle();

    final last = findTextContaining('질문 14 에 대한 답이다');
    expect(last, findsOneWidget);
    final screen = t.view.physicalSize.height;
    expect(t.getRect(last).bottom, lessThan(screen)); // 마지막 답의 끝이 화면 안에 있다
    final list = t.state<ScrollableState>(find.byType(Scrollable).first).position;
    expect(list.pixels, list.maxScrollExtent); // 목록이 실제 끝에 있다
  });
}
