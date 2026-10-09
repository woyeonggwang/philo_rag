// 대화 저장 (state/chat_storage.dart, state/chat.dart) — 임시 폴더에 저장하고 서버는 MockClient.
// 실행: mobile 폴더에서  flutter test
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:philo_rag/api/client.dart';
import 'package:philo_rag/state/chat.dart';
import 'package:philo_rag/state/chat_storage.dart';

Map<String, dynamic> _answer(String q, {bool safety = false}) => {
      'persona': 'buddha',
      'persona_name': '부처',
      'question': q,
      'answer': safety ? '지금 많이 힘드신 것 같습니다. 자살예방 상담전화 109 …' : '그대여, 갈애를 버려라.',
      'grounded': !safety,
      'safety': safety,
      'retries': 0,
      'glossary': safety ? [] : [{'term': '갈애', 'meaning': '목마름처럼 그치지 않는 욕구'}],
      'sources': safety
          ? []
          : [
              {
                'chunk_id': 'buddha#7',
                'work': 'THE DHAMMAPADA',
                'work_ko': '법구경',
                'ref': '24:334~24:345',
                'title': 'Craving',
                'score': 0.53,
              }
            ],
      'usage': {'plan': 'pro', 'plan_name': 'Pro', 'used_today': 1, 'daily_limit': null},
    };

PhiloRagClient _server({bool fail = false}) => PhiloRagClient('http://x',
    httpClient: MockClient((req) async {
      if (fail) return http.Response.bytes(utf8.encode('{"detail":"LLM 호출 실패"}'), 502);
      final q = (jsonDecode(req.body) as Map)['question'] as String;
      return http.Response.bytes(utf8.encode(jsonEncode(_answer(q, safety: q.contains('죽고')))), 200,
          headers: {'content-type': 'application/json'});
    }));

void main() {
  late Directory tmp;
  late ChatStorage storage;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('chats_test');
    storage = ChatStorage(userKey: 'test', directory: () async => tmp);
  });
  tearDown(() async => tmp.delete(recursive: true));

  test('질문·답(근거·각주·사용량)과 위기 안내 대화를 저장했다가 그대로 불러온다', () async {
    final a = ChatController(_server(), storage: storage);
    await a.send('buddha', '화가 날 때 어떻게 해야 합니까?');
    await a.send('buddha', '죽고 싶어요');

    final b = ChatController(_server(), storage: storage); // 앱을 다시 켠 셈
    await b.load();
    final m = b.messages('buddha');
    expect(m.length, 4);
    expect(m[0].role, Role.user);
    expect(m[0].text, '화가 날 때 어떻게 해야 합니까?');
    expect(m[1].response!.sources.single.label, '법구경 24:334~24:345');
    expect(m[1].response!.glossary.single.term, '갈애');
    expect(m[1].response!.usage!.unlimited, isTrue);
    // 위기 상담 안내가 나간 대화도 저장한다 (사용자 결정)
    expect(m[3].response!.safety, isTrue);
    expect(m[3].text, contains('109'));
  });

  test('페르소나마다 최근 200개만 남긴다', () async {
    final c = ChatController(_server(), storage: storage);
    for (var i = 0; i < 101; i++) {
      await c.send('buddha', '질문 $i');
    }
    expect(c.messages('buddha').length, ChatController.maxMessagesPerPersona);
    expect(c.messages('buddha').first.text, '질문 1'); // 가장 오래된 질문 0 과 그 답이 밀려났다

    final d = ChatController(_server(), storage: storage);
    await d.load();
    expect(d.messages('buddha').length, 200);
  });

  test('오류 응답도 그 자리에 남는다', () async {
    final c = ChatController(_server(fail: true), storage: storage);
    await c.send('jesus', '원수를 어떻게 대해야 합니까');
    final d = ChatController(_server(), storage: storage);
    await d.load();
    expect(d.messages('jesus').last.isError, isTrue);
  });

  test('지우기는 화면과 파일에서 그 페르소나만 지운다', () async {
    final c = ChatController(_server(), storage: storage);
    await c.send('buddha', 'q1');
    await c.send('jesus', 'q2');
    await c.clear('buddha');
    expect(c.messages('buddha'), isEmpty);

    final d = ChatController(_server(), storage: storage);
    await d.load();
    expect(d.messages('buddha'), isEmpty);
    expect(d.messages('jesus').length, 2);
  });

  test('깨진 파일은 건너뛰고 앱은 계속 켜진다', () async {
    await File('${tmp.path}${Platform.pathSeparator}nietzsche.json').writeAsString('{망가짐');
    final c = ChatController(_server(), storage: storage);
    await c.load();
    expect(c.messages('nietzsche'), isEmpty);
  });
}
