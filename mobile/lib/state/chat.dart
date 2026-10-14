/// 대화 상태. 페르소나 하나당 메시지 목록 하나.
///
/// 서버는 stateless 다 — 매 요청에 {persona, question} 만 보내고 이전 대화를 넘기지 않는다
/// (CLAUDE.md 5.3 — 대화 기억은 범위 밖). 따라서 여기 쌓이는 이력은 화면 표시용이지 문맥이 아니다.
///
/// 폰에 저장한다 (2026-10-10, chat_storage.dart). 앱을 켤 때 load(), 메시지가 붙을 때마다 그 페르소나 파일을 다시 쓴다.
/// 페르소나마다 최근 [maxMessagesPerPersona]개(질문·답 각각 1개)만 남기고 오래된 것부터 지운다.
///
/// 2026-10-12 (사용자 결정):
///  - 질문 하나와 그 답을 골라 지울 수 있다 ([deleteExchange]). 전체 지우기([clear])는 그대로.
///  - 시크릿 모드 ([setSecret]) — 켜면 저장된 대화 대신 빈 대화가 보이고, 여기서 나눈 대화는 폰에 저장하지 않는다.
///    끄면(대화창을 나가도) 사라진다. 서버는 원래 질문을 남기지 않는다 (사용 횟수만 센다).
library;

import 'package:flutter/foundation.dart';

import '../api/client.dart';
import '../api/models.dart';
import 'chat_storage.dart';

enum Role { user, persona }

class ChatMessage {
  final Role role;
  final String text;
  final DateTime at;

  /// persona 메시지에만 있다. 근거·각주·안전 여부를 UI 가 여기서 꺼낸다.
  final AskResponse? response;

  /// 요청이 실패한 자리. text 에 오류 메시지가 들어 있다.
  final bool isError;

  ChatMessage.user(this.text)
      : role = Role.user,
        at = DateTime.now(),
        response = null,
        isError = false;

  ChatMessage.persona(this.response)
      : role = Role.persona,
        text = response!.answer,
        at = DateTime.now(),
        isError = false;

  ChatMessage.error(this.text)
      : role = Role.persona,
        at = DateTime.now(),
        response = null,
        isError = true;

  ChatMessage._(this.role, this.text, this.at, this.response, this.isError);

  Map<String, dynamic> toJson() => {
        'role': role.name,
        'text': text,
        'at': at.toIso8601String(),
        'error': isError,
        'response': response?.toJson(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage._(
        Role.values.byName(j['role'] as String),
        j['text'] as String,
        DateTime.parse(j['at'] as String),
        j['response'] == null
            ? null
            : AskResponse.fromJson(j['response'] as Map<String, dynamic>),
        j['error'] as bool? ?? false,
      );
}

class ChatController extends ChangeNotifier {
  /// 페르소나별 보관 한도 (사용자 결정 2026-10-10). 질문 1개 + 답 1개 = 2개로 센다.
  static const maxMessagesPerPersona = 200;

  PhiloRagClient _client;

  /// null 이면 저장하지 않는다 (테스트·미리보기용).
  final ChatStorage? _storage;
  final Map<String, List<ChatMessage>> _threads = {};

  /// 시크릿 모드인 페르소나의 대화. 메모리에만 있고 저장하지 않는다.
  final Map<String, List<ChatMessage>> _secretThreads = {};
  String? _pendingPersona;

  /// 같은 페르소나 파일을 동시에 두 번 쓰지 않게 순서대로 줄 세운다.
  final Map<String, Future<void>> _saving = {};

  ChatController(this._client, {ChatStorage? storage}) : _storage = storage; // ignore: prefer_initializing_formals

  /// 서버 주소가 바뀌면 SettingsStore 쪽에서 새 클라이언트를 넣어 준다.
  set client(PhiloRagClient c) => _client = c;

  /// 앱 시작 때 한 번. 저장된 대화를 불러온다.
  Future<void> load() async {
    final s = _storage;
    if (s == null) return;
    final saved = await s.loadAll();
    saved.forEach((persona, msgs) => _threads[persona] = _trimmed(msgs));
    notifyListeners();
  }

  /// 지금 화면에 보일 대화 — 시크릿 모드면 시크릿 대화.
  List<ChatMessage> messages(String persona) =>
      List.unmodifiable(_current(persona) ?? const []);

  List<ChatMessage>? _current(String persona) =>
      isSecret(persona) ? _secretThreads[persona] : _threads[persona];

  bool isSecret(String persona) => _secretThreads.containsKey(persona);

  /// 시크릿 모드를 켜고 끈다. 끄면 시크릿 대화는 사라진다. 답을 기다리는 중에는 바꾸지 않는다
  /// (대화창을 나갈 때는 [force] 로 끈다 — 늦게 온 답은 버려진 목록에 붙고 저장되지 않는다).
  void setSecret(String persona, bool on, {bool force = false}) {
    if (on == isSecret(persona)) return;
    if (isPending(persona) && !force) return;
    if (on) {
      _secretThreads[persona] = [];
    } else {
      _secretThreads.remove(persona);
    }
    notifyListeners();
  }

  /// 이 페르소나에 답변 대기 중인 요청이 있는지. 전송 버튼 비활성화용.
  bool isPending(String persona) => _pendingPersona == persona;

  /// 질문을 보내고 답을 이력에 붙인다. 실패하면 오류 메시지를 이력에 붙이고 예외는 삼킨다
  /// (UI 는 isError 메시지로 보여주면 된다). 같은 페르소나에 요청이 진행 중이면 무시한다.
  /// 질문을 붙인 직후와 답을 붙인 뒤 두 번 저장한다 — 답을 기다리는 사이 앱이 꺼져도 질문은 남는다.
  Future<void> send(String persona, String question) async {
    final q = question.trim();
    if (q.isEmpty || _pendingPersona != null) return;

    final secret = isSecret(persona);
    final thread = secret ? _secretThreads[persona]! : _threads.putIfAbsent(persona, () => []);
    thread.add(ChatMessage.user(q));
    _pendingPersona = persona;
    notifyListeners();
    if (!secret) await _persist(persona);

    try {
      final res = await _client.ask(persona, q);
      thread.add(ChatMessage.persona(res));
    } on ApiException catch (e) {
      thread.add(ChatMessage.error(e.toString()));
    } finally {
      _pendingPersona = null;
      notifyListeners();
    }
    if (!secret) await _persist(persona);
  }

  /// 질문 하나와 그 답을 함께 지운다 (말풍선을 길게 눌러 지우기). [m] 은 질문이든 답이든 된다.
  /// 답을 기다리는 마지막 질문은 지우지 않는다. 시크릿 대화면 저장하지 않는다.
  Future<void> deleteExchange(String persona, ChatMessage m) async {
    final thread = _current(persona);
    if (thread == null) return;
    final i = thread.indexOf(m);
    if (i < 0) return;
    var start = i, end = i + 1;
    if (m.role == Role.user) {
      if (i == thread.length - 1 && isPending(persona)) return;
      if (end < thread.length && thread[end].role == Role.persona) end++;
    } else if (i > 0 && thread[i - 1].role == Role.user) {
      start = i - 1;
    }
    thread.removeRange(start, end);
    notifyListeners();
    if (!isSecret(persona)) await _persist(persona);
  }

  /// 철학자의 답 [answer] 바로 앞의 질문. 없으면 빈 문자열 (오래된 질문이 200개 한도로 밀려난 경우).
  String questionFor(String persona, ChatMessage answer) {
    final thread = _current(persona) ?? const <ChatMessage>[];
    final i = thread.indexOf(answer);
    return i > 0 && thread[i - 1].role == Role.user ? thread[i - 1].text : '';
  }

  /// 대화 신고 (2026-10-12). 답과 그 질문, 근거 여부·근거 구절 위치를 함께 보낸다 (사용자 결정 — 대화 내용 첨부).
  /// 실패하면 ApiException 을 그대로 올린다 (UI 가 알려 준다).
  Future<void> report(String persona, ChatMessage answer, {required String reason, String? detail}) {
    final r = answer.response;
    return _client.report(
      persona: persona,
      reason: reason,
      detail: detail,
      question: questionFor(persona, answer),
      answer: answer.text,
      extra: {
        'grounded': r?.grounded,
        'safety': r?.safety,
        'sources': [for (final s in r?.sources ?? const <Source>[]) s.label],
        'secret': isSecret(persona),
      },
    );
  }

  /// 이 페르소나의 대화를 화면과 폰에서 모두 지운다. 시크릿 모드면 시크릿 대화만 지운다.
  Future<void> clear(String persona) async {
    if (isSecret(persona)) {
      _secretThreads[persona]!.clear();
      notifyListeners();
      return;
    }
    _threads.remove(persona);
    notifyListeners();
    final s = _storage;
    if (s == null) return;
    final prev = _saving[persona] ?? Future.value();
    final job = prev.then((_) => s.delete(persona));
    _saving[persona] = job.catchError((_) {});
    await job;
  }

  /// 한도를 넘는 오래된 메시지를 잘라 내고 파일에 쓴다. 저장 실패는 대화를 막지 않는다 (로그만).
  Future<void> _persist(String persona) {
    final s = _storage;
    if (s == null) return Future.value();
    final thread = _threads[persona];
    if (thread != null && thread.length > maxMessagesPerPersona) {
      thread.removeRange(0, thread.length - maxMessagesPerPersona);
    }
    final snapshot = List<ChatMessage>.of(thread ?? const []);
    final prev = _saving[persona] ?? Future.value();
    final job = prev.then((_) => s.save(persona, snapshot)).catchError((Object e) {
      debugPrint('대화 저장 실패 ($persona): $e');
    });
    _saving[persona] = job;
    return job;
  }

  static List<ChatMessage> _trimmed(List<ChatMessage> msgs) => msgs.length <= maxMessagesPerPersona
      ? msgs
      : msgs.sublist(msgs.length - maxMessagesPerPersona);
}
