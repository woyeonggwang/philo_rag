/// 대화 상태. 페르소나 하나당 메시지 목록 하나.
///
/// 서버는 stateless 다 — 매 요청에 {persona, question} 만 보내고 이전 대화를 넘기지 않는다
/// (CLAUDE.md 12절 "대화 이력 유지 방식 미정"). 따라서 여기 쌓이는 이력은 화면 표시용이지 문맥이 아니다.
///
/// 폰에 저장한다 (2026-10-10, chat_storage.dart). 앱을 켤 때 load(), 메시지가 붙을 때마다 그 페르소나 파일을 다시 쓴다.
/// 페르소나마다 최근 [maxMessagesPerPersona]개(질문·답 각각 1개)만 남기고 오래된 것부터 지운다.
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

  List<ChatMessage> messages(String persona) =>
      List.unmodifiable(_threads[persona] ?? const []);

  /// 이 페르소나에 답변 대기 중인 요청이 있는지. 전송 버튼 비활성화용.
  bool isPending(String persona) => _pendingPersona == persona;

  /// 질문을 보내고 답을 이력에 붙인다. 실패하면 오류 메시지를 이력에 붙이고 예외는 삼킨다
  /// (UI 는 isError 메시지로 보여주면 된다). 같은 페르소나에 요청이 진행 중이면 무시한다.
  /// 질문을 붙인 직후와 답을 붙인 뒤 두 번 저장한다 — 답을 기다리는 사이 앱이 꺼져도 질문은 남는다.
  Future<void> send(String persona, String question) async {
    final q = question.trim();
    if (q.isEmpty || _pendingPersona != null) return;

    final thread = _threads.putIfAbsent(persona, () => []);
    thread.add(ChatMessage.user(q));
    _pendingPersona = persona;
    notifyListeners();
    await _persist(persona);

    try {
      final res = await _client.ask(persona, q);
      thread.add(ChatMessage.persona(res));
    } on ApiException catch (e) {
      thread.add(ChatMessage.error(e.toString()));
    } finally {
      _pendingPersona = null;
      notifyListeners();
    }
    await _persist(persona);
  }

  /// 이 페르소나의 대화를 화면과 폰에서 모두 지운다.
  Future<void> clear(String persona) async {
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
