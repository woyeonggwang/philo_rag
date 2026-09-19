/// 대화 상태. 페르소나 하나당 메시지 목록 하나.
///
/// 서버는 stateless 다 — 매 요청에 {persona, question} 만 보내고 이전 대화를 넘기지 않는다
/// (CLAUDE.md 12절 "대화 이력 유지 방식 미정"). 따라서 여기 쌓이는 이력은 화면 표시용이지 문맥이 아니다.
/// 앱을 껐다 켜면 사라진다. 저장이 필요해지면 이 클래스에만 넣는다.
library;

import 'package:flutter/foundation.dart';

import '../api/client.dart';
import '../api/models.dart';

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
}

class ChatController extends ChangeNotifier {
  PhiloRagClient _client;
  final Map<String, List<ChatMessage>> _threads = {};
  String? _pendingPersona;

  ChatController(this._client);

  /// 서버 주소가 바뀌면 SettingsStore 쪽에서 새 클라이언트를 넣어 준다.
  set client(PhiloRagClient c) => _client = c;

  List<ChatMessage> messages(String persona) =>
      List.unmodifiable(_threads[persona] ?? const []);

  /// 이 페르소나에 답변 대기 중인 요청이 있는지. 전송 버튼 비활성화용.
  bool isPending(String persona) => _pendingPersona == persona;

  /// 질문을 보내고 답을 이력에 붙인다. 실패하면 오류 메시지를 이력에 붙이고 예외는 삼킨다
  /// (UI 는 isError 메시지로 보여주면 된다). 같은 페르소나에 요청이 진행 중이면 무시한다.
  Future<void> send(String persona, String question) async {
    final q = question.trim();
    if (q.isEmpty || _pendingPersona != null) return;

    final thread = _threads.putIfAbsent(persona, () => []);
    thread.add(ChatMessage.user(q));
    _pendingPersona = persona;
    notifyListeners();

    try {
      final res = await _client.ask(persona, q);
      thread.add(ChatMessage.persona(res));
    } on ApiException catch (e) {
      thread.add(ChatMessage.error(e.toString()));
    } finally {
      _pendingPersona = null;
      notifyListeners();
    }
  }

  void clear(String persona) {
    _threads.remove(persona);
    notifyListeners();
  }
}
