// 요금제 한도 관련 앱 쪽 — 서버 없이 MockClient 로 확인한다 (CLAUDE.md 4.8, backend/app/plans.py).
// 실행: mobile 폴더에서  flutter test
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:philo_rag/api/client.dart';
import 'package:philo_rag/state/settings.dart';

Map<String, dynamic> _answer({Map<String, dynamic>? usage}) => {
      'persona': 'jesus',
      'persona_name': '예수',
      'question': 'q',
      'answer': '보라, 염려하지 말라.',
      'grounded': true,
      'safety': false,
      'retries': 0,
      'glossary': [],
      'sources': [],
      'usage': usage,
    };

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(body)), status,
    headers: {'content-type': 'application/json'});

void main() {
  test('사용자 ID 를 X-User-Id 헤더로 보내고 사용량을 읽는다', () async {
    String? sentId;
    final mock = MockClient((req) async {
      sentId = req.headers['X-User-Id'];
      return _json(_answer(usage: {
        'plan': 'personal',
        'plan_name': 'Personal',
        'used_today': 3,
        'daily_limit': 5,
      }));
    });
    final c = PhiloRagClient('http://x', userId: 'abc-123', httpClient: mock);
    final r = await c.ask('jesus', 'q');
    expect(sentId, 'abc-123');
    expect(r.usage!.plan, 'personal');
    expect(r.usage!.usedToday, 3);
    expect(r.usage!.remainingToday, 2);
    expect(r.usage!.unlimited, isFalse);
  });

  test('pro 는 무제한 (daily_limit null)', () async {
    final mock = MockClient((req) async => _json(_answer(usage: {
          'plan': 'pro',
          'plan_name': 'Pro',
          'used_today': 12,
          'daily_limit': null,
        })));
    final r = await PhiloRagClient('http://x', httpClient: mock).ask('jesus', 'q');
    expect(r.usage!.unlimited, isTrue);
    expect(r.usage!.remainingToday, isNull);
  });

  test('usage 가 없는 옛 서버 응답도 읽는다', () async {
    final body = _answer()..remove('usage');
    final mock = MockClient((req) async => _json(body));
    final r = await PhiloRagClient('http://x', httpClient: mock).ask('jesus', 'q');
    expect(r.usage, isNull);
  });

  test('한도 초과(429)는 isQuotaExceeded 이고 메시지를 그대로 보여준다', () async {
    const msg = '오늘 사용할 수 있는 질문 5건을 모두 썼습니다 (Personal 요금제). 한국 시간 자정에 다시 채워집니다.';
    final mock = MockClient((req) async => _json({'detail': msg}, 429));
    final c = PhiloRagClient('http://x', userId: 'u', httpClient: mock);
    try {
      await c.ask('jesus', 'q');
      fail('예외가 나야 한다');
    } on ApiException catch (e) {
      expect(e.isQuotaExceeded, isTrue);
      expect(e.toString(), msg);
    }
  });

  test('사용자 ID 는 UUID v4 꼴이고 매번 다르다', () {
    final re = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
    final a = SettingsStore.newUserId();
    final b = SettingsStore.newUserId();
    expect(re.hasMatch(a), isTrue, reason: a);
    expect(a, isNot(b));
    // 서버가 받는 형식(영문·숫자·'-' 1~64자)과도 맞는다 (plans.normalize_user_id)
    expect(RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(a), isTrue);
  });
}
