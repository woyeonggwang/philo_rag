/// 한 철학자와의 대화창 (2026-10-10). 철학자 바둑판에서 누르면 열린다. 디자인은 Codex 몫.
/// 대화 내용은 ChatController 가 폰에 저장하므로(페르소나당 200개) 나갔다 들어와도 남아 있다.
/// 말풍선을 길게 누르면 그 질문과 답을 지운다. 위쪽 눈 아이콘은 시크릿 모드 — 저장하지 않고, 이 화면을 나가면 사라진다 (2026-10-12).
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
    widget.chat.addListener(_rebuild); // 시크릿 표시·버튼 상태
    _scrollToEnd();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.chat.removeListener(_scrollToEnd);
    widget.chat.removeListener(_rebuild);
    // 시크릿 대화는 대화창을 나가면 끝난다. 화면을 정리하는 중에 알림을 보내지 않도록 한 박자 늦춘다
    final chat = widget.chat, key = _key;
    Future.microtask(() => chat.setSecret(key, false, force: true));
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
    final secret = widget.chat.isSecret(_key);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(secret ? '시크릿 대화를 지울까요?' : '${widget.persona.name}와의 대화를 지울까요?'),
        content: Text(secret ? '이 화면의 시크릿 대화만 지워집니다.' : '폰에 저장된 이 대화가 모두 지워지고 되돌릴 수 없습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('지우기')),
        ],
      ),
    );
    if (ok == true) await widget.chat.clear(_key);
  }

  /// 말풍선을 길게 눌렀을 때 — 그 질문과 답을 함께 지운다
  Future<void> _confirmDelete(ChatMessage m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('이 질문과 답을 지울까요?'),
        content: const Text('지운 대화는 되돌릴 수 없습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('지우기')),
        ],
      ),
    );
    if (ok == true) await widget.chat.deleteExchange(_key, m);
  }

  Future<void> _toggleSecret() async {
    final chat = widget.chat;
    if (!chat.isSecret(_key)) {
      chat.setSecret(_key, true);
      return;
    }
    if (chat.messages(_key).isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('시크릿 모드를 끌까요?'),
          content: const Text('지금까지 나눈 시크릿 대화는 사라집니다.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('끄기')),
          ],
        ),
      );
      if (ok != true) return;
    }
    chat.setSecret(_key, false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secret = widget.chat.isSecret(_key);
    final pending = widget.chat.isPending(_key);
    return Scaffold(
      appBar: AppBar(
        title: Text(secret ? '${widget.persona.name} · 시크릿' : widget.persona.name),
        actions: [
          // 임시 버튼 — 위치·모양은 Codex 몫. 기능은 ChatController.setSecret() / clear()
          IconButton(
            key: const Key('secret'),
            tooltip: secret ? '시크릿 모드 끄기' : '시크릿 모드',
            isSelected: secret,
            icon: const Icon(Icons.visibility_off_outlined),
            selectedIcon: const Icon(Icons.visibility_off),
            onPressed: pending ? null : _toggleSecret,
          ),
          IconButton(tooltip: '이 대화 지우기', icon: const Icon(Icons.delete_outline), onPressed: _confirmClear),
        ],
      ),
      body: Column(
        children: [
          if (secret)
            Container(
              key: const Key('secret-banner'),
              width: double.infinity,
              color: theme.colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text('시크릿 모드 — 이 대화는 폰에 저장되지 않고, 이 화면을 나가면 사라집니다.',
                  style: theme.textTheme.bodySmall),
            ),
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
                        Text(secret ? '여기서 나눈 대화는 남지 않습니다.' : widget.persona.blurb,
                            style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
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
                    final m = msgs[i];
                    // 답을 기다리는 마지막 질문은 지울 수 없다
                    final deletable = !(pending && i == msgs.length - 1);
                    return GestureDetector(
                      key: ValueKey('msg-$i'),
                      onLongPress: deletable ? () => _confirmDelete(m) : null,
                      child: MessageBubble(m),
                    );
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
                      hintText: secret ? '시크릿 모드로 질문하기' : '${widget.persona.name}에게 질문하기',
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
