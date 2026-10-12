// 질문 하나와 답 지우기(말풍선 길게 누르기)와 시크릿 모드 (2026-10-12, state/chat.dart · ui/chat_screen.dart).
// 서버는 MockClient, 저장은 임시 폴더.  실행: mobile 폴더에서  flutter test
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:philo_rag/api/client.dart';
import 'package:philo_rag/api/models.dart';
import 'package:philo_rag/state/chat.dart';
import 'package:philo_rag/state/chat_storage.dart';
import 'package:philo_rag/ui/chat_screen.dart';

PhiloRagClient _server() => PhiloRagClient('http://x', httpClient: MockClient((req) async {
      final q = (jsonDecode(req.body) as Map)['question'] as String;
      return http.Response.bytes(
          utf8.encode(jsonEncode({
            'persona': 'jesus', 'persona_name': '예수', 'question': q, 'answer': '답: $q',
            'grounded': true, 'safety': false, 'retries': 0, 'glossary': [], 'sources': [],
          })),
          200,
          headers: {'content-type': 'application/json'});
    }));

List<String> _texts(ChatController c) => c.messages('jesus').map((m) => m.text).toList();

void main() {
  group('ChatController', () {
    late Directory tmp;
    late ChatStorage storage;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('chats_test');
      storage = ChatStorage(userKey: 'test', directory: () async => tmp);
    });
    tearDown(() async => tmp.delete(recursive: true));

    test('질문을 고르든 답을 고르든 그 질문과 답이 함께 지워지고, 폰에서도 지워진다', () async {
      final c = ChatController(_server(), storage: storage);
      await c.send('jesus', '첫째');
      await c.send('jesus', '둘째');
      await c.send('jesus', '셋째');

      await c.deleteExchange('jesus', c.messages('jesus')[3]); // "둘째"의 답
      expect(_texts(c), ['첫째', '답: 첫째', '셋째', '답: 셋째']);
      await c.deleteExchange('jesus', c.messages('jesus')[0]); // "첫째" 질문
      expect(_texts(c), ['셋째', '답: 셋째']);

      final d = ChatController(_server(), storage: storage); // 다시 켠 셈
      await d.load();
      expect(_texts(d), ['셋째', '답: 셋째']);
    });

    test('시크릿 모드: 빈 대화로 시작, 저장하지 않고, 끄면 사라지고 저장된 대화가 돌아온다', () async {
      final c = ChatController(_server(), storage: storage);
      await c.send('jesus', '저장되는 질문');

      c.setSecret('jesus', true);
      expect(c.isSecret('jesus'), isTrue);
      expect(c.messages('jesus'), isEmpty);
      await c.send('jesus', '남기기 싫은 질문');
      expect(_texts(c), ['남기기 싫은 질문', '답: 남기기 싫은 질문']);

      final d = ChatController(_server(), storage: storage);
      await d.load();
      expect(_texts(d), ['저장되는 질문', '답: 저장되는 질문']); // 폰에는 시크릿 대화가 없다

      c.setSecret('jesus', false);
      expect(_texts(c), ['저장되는 질문', '답: 저장되는 질문']);
      c.setSecret('jesus', true);
      expect(c.messages('jesus'), isEmpty); // 다시 켜도 지난 시크릿 대화는 없다
    });

    test('시크릿 모드에서 전체 지우기·하나 지우기는 시크릿 대화에만 작용한다', () async {
      final c = ChatController(_server(), storage: storage);
      await c.send('jesus', '저장되는 질문');
      c.setSecret('jesus', true);
      await c.send('jesus', '시크릿 1');
      await c.send('jesus', '시크릿 2');
      await c.deleteExchange('jesus', c.messages('jesus')[0]);
      expect(_texts(c), ['시크릿 2', '답: 시크릿 2']);
      await c.clear('jesus');
      expect(c.messages('jesus'), isEmpty);
      c.setSecret('jesus', false);
      expect(_texts(c), ['저장되는 질문', '답: 저장되는 질문']);
    });
  });

  group('대화창', () {
    const jesus = Persona(key: 'jesus', name: '예수', blurb: '복음서의 목소리', enabled: true);

    Future<ChatController> pump(WidgetTester t) async {
      final chat = ChatController(_server()); // 저장 없음
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => ChatScreen(persona: jesus, chat: chat))),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('열기'));
      await t.pumpAndSettle();
      return chat;
    }

    Future<void> ask(WidgetTester t, String q) async {
      await t.enterText(find.byKey(const Key('question')), q);
      await t.tap(find.byKey(const Key('send')));
      await t.pumpAndSettle();
    }

    testWidgets('말풍선을 길게 누르면 확인 후 그 질문과 답만 지운다', (t) async {
      final chat = await pump(t);
      await ask(t, '첫째');
      await ask(t, '둘째');
      await t.longPress(find.text('답: 첫째'));
      await t.pumpAndSettle();
      expect(find.text('이 질문과 답을 지울까요?'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, '지우기'));
      await t.pumpAndSettle();
      expect(find.text('첫째'), findsNothing);
      expect(find.text('답: 첫째'), findsNothing);
      expect(find.text('답: 둘째'), findsOneWidget);
      expect(_texts(chat), ['둘째', '답: 둘째']);
    });

    testWidgets('시크릿 모드: 표시가 뜨고, 끌 때 확인하고, 대화창을 나가면 끝난다', (t) async {
      final chat = await pump(t);
      await ask(t, '저장되는 질문');
      await t.tap(find.byKey(const Key('secret')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('secret-banner')), findsOneWidget);
      expect(find.text('예수 · 시크릿'), findsOneWidget);
      expect(find.text('저장되는 질문'), findsNothing);

      await ask(t, '남기기 싫은 질문');
      expect(find.text('답: 남기기 싫은 질문'), findsOneWidget);
      await t.tap(find.byKey(const Key('secret'))); // 끄기 — 시크릿 대화가 있으니 확인
      await t.pumpAndSettle();
      expect(find.text('시크릿 모드를 끌까요?'), findsOneWidget);
      await t.tap(find.text('취소'));
      await t.pumpAndSettle();
      expect(chat.isSecret('jesus'), isTrue);

      await t.pageBack(); // 대화창을 나가면 시크릿 대화는 끝난다
      await t.pumpAndSettle();
      expect(chat.isSecret('jesus'), isFalse);
      expect(_texts(chat), ['저장되는 질문', '답: 저장되는 질문']);
    });
  });
}
