/// 한 철학자와의 대화창 (2026-10-10). 철학자 바둑판에서 누르면 열린다. 디자인은 Codex 몫.
/// 대화 내용은 ChatController 가 폰에 저장하므로(페르소나당 200개) 나갔다 들어와도 남아 있다.
library;

import 'package:flutter/material.dart';

import '../api/models.dart';
import '../state/chat.dart';
import 'source_tile.dart';

class ChatScreen extends StatefulWidget {
  final Persona persona;
  final ChatController chat;

  const ChatScreen({super.key, required this.persona, required this.chat});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  String get _key => widget.persona.key;

  @override
  void initState() {
    super.initState();
    widget.chat.addListener(_scrollToEnd);
    _scrollToEnd();
  }

  @override
  void dispose() {
    widget.chat.removeListener(_scrollToEnd);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 새 메시지가 붙으면 맨 아래로
  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final q = _input.text;
    if (q.trim().isEmpty || widget.chat.isPending(_key)) return;
    _input.clear();
    await widget.chat.send(_key, q);
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${widget.persona.name}와의 대화를 지울까요?'),
        content: const Text('폰에 저장된 이 대화가 모두 지워지고 되돌릴 수 없습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('지우기')),
        ],
      ),
    );
    if (ok == true) await widget.chat.clear(_key);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.persona.name),
        actions: [
          // 임시 버튼 — 위치·모양은 Codex 몫. 기능은 ChatController.clear()
          IconButton(tooltip: '이 대화 지우기', icon: const Icon(Icons.delete_outline), onPressed: _confirmClear),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: widget.chat,
              builder: (context, _) {
                final msgs = widget.chat.messages(_key);
                final pending = widget.chat.isPending(_key);
                if (msgs.isEmpty && !pending) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('${widget.persona.name}에게 물어보세요.', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(widget.persona.blurb, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                      ]),
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(12),
                  itemCount: msgs.length + (pending ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == msgs.length) {
                      return const ListTile(
                        leading: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        title: Text('답을 찾는 중…'),
                      );
                    }
                    return MessageBubble(msgs[i]);
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    key: const Key('question'),
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: '${widget.persona.name}에게 질문하기',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ListenableBuilder(
                  listenable: widget.chat,
                  builder: (context, _) => IconButton.filled(
                    key: const Key('send'),
                    onPressed: widget.chat.isPending(_key) ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

/// 말풍선 하나. 철학자 답에는 안전 안내 표시·용어 풀이·근거 구절(접힘)이 붙는다.
class MessageBubble extends StatelessWidget {
  final ChatMessage m;
  const MessageBubble(this.m, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = m.role == Role.user;
    final isSent = isUser && !m.isError;
    final isDark = theme.brightness == Brightness.dark;
    final r = m.response;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
        decoration: BoxDecoration(
          color: m.isError
              ? theme.colorScheme.errorContainer
              : isUser
                  ? const Color(0xFF7638FA)
                  : Color(isDark ? 0xFF262626 : 0xFFEFEFEF),
          border: isSent ? null : Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (r != null && r.safety) Text('안전 안내가 포함된 답변', style: theme.textTheme.labelSmall),
            // 문장 끝 공백 두 칸 + 줄바꿈(마크다운 줄바꿈)은 정리해서 보여준다 (CLAUDE.md 12절)
            Text(
              m.text.replaceAll(RegExp(r'[ \t]+\n'), '\n').trim(),
              style: TextStyle(color: isSent ? Colors.white : theme.colorScheme.onSurface),
            ),
            if (r != null && r.glossary.isNotEmpty) ...[
              const Divider(),
              for (final g in r.glossary) Text('${g.term}: ${g.meaning}', style: theme.textTheme.bodySmall),
            ],
            if (r != null && r.sources.isNotEmpty) ...[
              const Divider(),
              SourcesSection(sources: r.sources),
            ],
            if (r != null && !r.grounded && !r.safety) Text('근거 구절 없음', style: theme.textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}
