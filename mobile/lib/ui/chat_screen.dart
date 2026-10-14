/// 한 철학자와의 대화창 (2026-10-10). 철학자 바둑판에서 누르면 열린다. 디자인은 Codex 몫.
/// 대화 내용은 ChatController 가 폰에 저장하므로(페르소나당 200개) 나갔다 들어와도 남아 있다.
/// 말풍선을 길게 누르면(PC 는 오른쪽 클릭) 삭제·복사·대화내용 신고 메뉴가 뜬다. 복사·신고는 철학자의 답에만 있다.
/// 위쪽 모자·안경 아이콘은 시크릿 모드 — 저장하지 않고, 이 화면을 나가면 사라진다. 켜면 화면이 어두워진다 (2026-10-12).
library;

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../state/chat.dart';
import 'app_theme.dart';
import 'brand_widgets.dart';
import 'incognito_icon.dart';
import 'keep_words.dart';
import 'report_dialog.dart';
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
  BuildContext? _surfaceContext;

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

  /// 새 메시지가 붙거나 대화창을 열면 맨 아래로.
  /// 목록은 화면에 그린 말풍선만 길이를 재므로, 처음 잡은 "맨 아래"는 실제보다 짧다 — 긴 답이 많으면 대화창이 중간에서 열렸다
  /// (2026-10-14). 끝으로 간 뒤 끝이 더 늘어났으면 다시 가기를 끝이 멈출 때까지 되풀이한다.
  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd(10));
  }

  void _jumpToEnd(int triesLeft) {
    if (!mounted || !_scroll.hasClients) return;
    final end = _scroll.position.maxScrollExtent;
    _scroll.jumpTo(end);
    if (triesLeft == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients && _scroll.position.maxScrollExtent > end) _jumpToEnd(triesLeft - 1);
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
      context: _surfaceContext ?? context,
      builder: (ctx) => AlertDialog(
        title: Text(
          secret ? '시크릿 대화를 지울까요?' : '${widget.persona.name}와의 대화를 지울까요?',
        ),
        content: Text(
          secret ? '이 화면의 시크릿 대화만 지워집니다.' : '폰에 저장된 이 대화가 모두 지워지고 되돌릴 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('지우기'),
          ),
        ],
      ),
    );
    if (ok == true) await widget.chat.clear(_key);
  }

  /// 말풍선을 길게 눌렀을 때(또는 오른쪽 클릭) 누른 자리에 뜨는 메뉴 — 삭제 · 복사 · 대화내용 신고 (사용자 결정 2026-10-12)
  Future<void> _showMenu(
    ChatMessage m,
    Offset at, {
    required bool deletable,
  }) async {
    final isAnswer = m.role == Role.persona && !m.isError && m.response != null;
    final items = <PopupMenuEntry<String>>[
      if (deletable) _menuItem('delete', Icons.delete_outline, '삭제'),
      if (isAnswer) _menuItem('copy', Icons.copy_outlined, '복사'),
      if (isAnswer) _menuItem('report', Icons.flag_outlined, '대화내용 신고'),
    ];
    if (items.isEmpty) return;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final choice = await showMenu<String>(
      context: _surfaceContext ?? context,
      position: RelativeRect.fromRect(
        at & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: items,
    );
    if (!mounted) return;
    switch (choice) {
      case 'delete':
        await _confirmDelete(m);
      case 'copy':
        await _copy(m);
      case 'report':
        await _report(m);
    }
  }

  static PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label,
  ) => PopupMenuItem<String>(
    key: ValueKey('menu-$value'),
    value: value,
    child: Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 12),
        Flexible(child: Text(label)),
      ],
    ),
  );

  /// 철학자의 답 본문만 복사한다 (질문·용어 풀이·근거 구절은 빼고 — 사용자 결정)
  Future<void> _copy(ChatMessage m) async {
    await Clipboard.setData(ClipboardData(text: bubbleText(m)));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('답변을 복사했습니다')));
  }

  Future<void> _report(ChatMessage m) async {
    final picked = await showReportDialog(
      _surfaceContext ?? context,
      personaName: widget.persona.name,
    );
    if (picked == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.chat.report(
        _key,
        m,
        reason: picked.reason,
        detail: picked.detail,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('신고가 접수되었습니다. 검토하겠습니다.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('신고를 보내지 못했습니다: $e')));
    }
  }

  /// 삭제를 골랐을 때 — 그 질문과 답을 함께 지운다
  Future<void> _confirmDelete(ChatMessage m) async {
    final ok = await showDialog<bool>(
      context: _surfaceContext ?? context,
      builder: (ctx) => AlertDialog(
        title: const Text('이 질문과 답을 지울까요?'),
        content: const Text('지운 대화는 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('지우기'),
          ),
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
        context: _surfaceContext ?? context,
        builder: (ctx) => AlertDialog(
          title: const Text('시크릿 모드를 끌까요?'),
          content: const Text('지금까지 나눈 시크릿 대화는 사라집니다.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('끄기'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    chat.setSecret(_key, false);
  }

  @override
  Widget build(BuildContext context) {
    // 시크릿 모드는 크롬 시크릿 창처럼 어두운 화면으로 (사용자 요청 2026-10-12)
    final theme = widget.chat.isSecret(_key)
        ? AppTheme.dark
        : Theme.of(context);
    return Theme(
      data: theme,
      child: Builder(builder: _scaffold),
    );
  }

  Widget _scaffold(BuildContext context) {
    _surfaceContext = context;
    final theme = Theme.of(context);
    final secret = widget.chat.isSecret(_key);
    final pending = widget.chat.isPending(_key);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          secret ? '${widget.persona.name} · 시크릿' : widget.persona.name,
          style: secret ? theme.textTheme.titleMedium : null,
        ),
        actions: [
          // 임시 버튼 — 위치·모양은 Codex 몫. 기능은 ChatController.setSecret() / clear()
          IconButton(
            key: const Key('secret'),
            tooltip: secret ? '시크릿 모드 끄기' : '시크릿 모드',
            isSelected: secret,
            // 켜져 있으면 동그란 바탕으로 표시
            style: secret
                ? IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  )
                : null,
            icon: const IncognitoIcon(),
            onPressed: pending ? null : _toggleSecret,
          ),
          IconButton(
            tooltip: '이 대화 지우기',
            icon: const Icon(Icons.delete_outline),
            onPressed: _confirmClear,
          ),
        ],
      ),
      body: Column(
        children: [
          if (secret)
            Container(
              key: const Key('secret-banner'),
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(AppTheme.controlRadius),
              ),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const IncognitoIcon(size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '시크릿 모드 — 이 대화는 폰에 저장되지 않고, 이 화면을 나가면 사라집니다.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListenableBuilder(
              listenable: widget.chat,
              builder: (context, _) {
                final msgs = widget.chat.messages(_key);
                final pending = widget.chat.isPending(_key);
                if (msgs.isEmpty && !pending) {
                  return Center(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PersonaPortrait(
                              name: widget.persona.name,
                              size: 88,
                            ),
                            const SizedBox(height: 16),
                            if (secret) ...[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const IncognitoIcon(size: 22),
                                  const SizedBox(width: 8),
                                  Text(
                                    '시크릿 모드',
                                    style: theme.textTheme.titleLarge,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '여기서 나눈 대화는 폰에 저장되지 않고,\n이 화면을 나가면 사라집니다.',
                                style: theme.textTheme.bodySmall,
                                textAlign: TextAlign.center,
                              ),
                            ] else ...[
                              Text(
                                '${widget.persona.name}에게 물어보세요.',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                widget.persona.blurb,
                                style: theme.textTheme.bodySmall,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(12),
                  itemCount: msgs.length + (pending ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == msgs.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 4,
                        ),
                        child: Row(
                          children: [
                            PersonaPortrait(name: widget.persona.name),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '${widget.persona.name}가 생각하는 중…',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    final m = msgs[i];
                    // 답을 기다리는 마지막 질문은 지울 수 없다
                    final deletable = !(pending && i == msgs.length - 1);
                    return GestureDetector(
                      key: ValueKey('msg-$i'),
                      onLongPressStart: (d) =>
                          _showMenu(m, d.globalPosition, deletable: deletable),
                      onSecondaryTapUp: (d) =>
                          _showMenu(m, d.globalPosition, deletable: deletable),
                      child: MessageBubble(m, personaName: widget.persona.name),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('question'),
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: keepWords(
                          secret
                              ? '시크릿 모드로 질문하기'
                              : '${widget.persona.name}에게 질문하기',
                        ),
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 말풍선 하나. 철학자의 초상·이름이 보이고, 답의 근거는 한 줄로 접혀 있다가 누르면 펼쳐진다.
class MessageBubble extends StatelessWidget {
  final ChatMessage m;
  final String? personaName;
  const MessageBubble(this.m, {super.key, this.personaName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = m.role == Role.user;
    final isSent = isUser && !m.isError;
    final r = m.response;
    final name = personaName ?? r?.personaName;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        decoration: BoxDecoration(
          color: m.isError
              ? theme.colorScheme.errorContainer
              : isUser
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surface,
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(AppTheme.surfaceRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser && name != null) ...[
              Row(
                children: [
                  PersonaPortrait(name: name),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(name, style: theme.textTheme.titleSmall),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (r != null && r.safety)
              Text('안전 안내가 포함된 답변', style: theme.textTheme.labelSmall),
            Text(
              bubbleText(m),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isSent
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurface,
              ),
            ),
            if (r != null && r.glossary.isNotEmpty) ...[
              const Divider(),
              for (final g in r.glossary)
                Text(
                  '${g.term}: ${g.meaning}',
                  style: theme.textTheme.bodySmall,
                ),
            ],
            if (r != null && r.sources.isNotEmpty) ...[
              const Divider(),
              SourcesSection(sources: r.sources),
            ],
            if (r != null && !r.grounded && !r.safety) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppTheme.controlRadius),
                ),
                child: Text(
                  '원전에서 직접 다루지 않은 질문',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 말풍선에 보이는 글 (복사할 때도 이것). 문장 끝 공백 두 칸 + 줄바꿈(마크다운 줄바꿈)은 정리한다 (CLAUDE.md 12절)
String bubbleText(ChatMessage m) =>
    m.text.replaceAll(RegExp(r'[ \t]+\n'), '\n').trim();
