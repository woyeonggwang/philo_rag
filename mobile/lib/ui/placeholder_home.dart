/// 기능 확인용 임시 화면. Codex 가 만드는 정식 UI 로 교체된다.
/// 보여주는 것: 서버 주소 입력·연결 확인 / 페르소나 선택 / 질문·답변·근거·각주.
/// api/·state/ 의 사용 예시로 남겨 두는 것이 목적이다. http 를 직접 쓰지 않는다.
library;

import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../state/chat.dart';
import '../state/settings.dart';
import 'source_tile.dart';

class PlaceholderHome extends StatefulWidget {
  final SettingsStore settings;
  final ChatController chat;

  const PlaceholderHome({super.key, required this.settings, required this.chat});

  @override
  State<PlaceholderHome> createState() => _PlaceholderHomeState();
}

class _PlaceholderHomeState extends State<PlaceholderHome> {
  late final TextEditingController _urlCtl;
  final _questionCtl = TextEditingController();
  List<Persona> _personas = const [];
  String? _persona;
  String _status = '연결 확인 전';

  @override
  void initState() {
    super.initState();
    _urlCtl = TextEditingController(text: widget.settings.baseUrl);
    _connect();
  }

  @override
  void dispose() {
    _urlCtl.dispose();
    _questionCtl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    await widget.settings.setBaseUrl(_urlCtl.text);
    _urlCtl.text = widget.settings.baseUrl;
    final client = PhiloRagClient(widget.settings.baseUrl);
    setState(() => _status = '연결 중… ${widget.settings.baseUrl}');
    try {
      final h = await client.health();
      final ps = await client.personas();
      setState(() {
        _status = '연결됨 — ${h.llmProvider} / ${h.llmModel}';
        _personas = ps.where((p) => p.enabled).toList();
        _persona ??= _personas.isNotEmpty ? _personas.first.key : null;
      });
    } on ApiException catch (e) {
      setState(() => _status = e.toString());
    } finally {
      client.close();
    }
  }

  Future<void> _confirmClear() async {
    final p = _persona;
    if (p == null) return;
    final name = _personas.where((x) => x.key == p).map((x) => x.name).firstOrNull ?? p;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$name 와의 대화를 지울까요?'),
        content: const Text('폰에 저장된 이 대화가 모두 지워지고 되돌릴 수 없습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('지우기')),
        ],
      ),
    );
    if (ok == true) await widget.chat.clear(p);
  }

  Future<void> _send() async {
    final p = _persona;
    if (p == null) return;
    final q = _questionCtl.text;
    _questionCtl.clear();
    await widget.chat.send(p, q);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('철학 RAG (임시 화면)'),
        actions: [
          // 임시 버튼 — 정식 UI(Codex)에서 위치·모양을 다시 정한다. 기능은 ChatController.clear()
          IconButton(
            tooltip: '이 대화 지우기',
            icon: const Icon(Icons.delete_outline),
            onPressed: _persona == null ? null : _confirmClear,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _urlCtl,
                  decoration: const InputDecoration(labelText: '서버 주소', isDense: true),
                  keyboardType: TextInputType.url,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _connect, child: const Text('연결')),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(_status, style: Theme.of(context).textTheme.bodySmall),
          ),
          if (_personas.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: SegmentedButton<String>(
                segments: [
                  for (final p in _personas)
                    ButtonSegment(value: p.key, label: Text(p.name)),
                ],
                selected: {?_persona},
                onSelectionChanged: (s) => setState(() => _persona = s.first),
              ),
            ),
          Expanded(
            child: AnimatedBuilder(
              animation: widget.chat,
              builder: (context, _) {
                final p = _persona;
                final msgs = p == null ? const <ChatMessage>[] : widget.chat.messages(p);
                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: msgs.length + (p != null && widget.chat.isPending(p) ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == msgs.length) {
                      return const ListTile(
                        leading: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        title: Text('답을 찾는 중… (10~30초)'),
                      );
                    }
                    return _MessageTile(msgs[i]);
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _questionCtl,
                    decoration: const InputDecoration(hintText: '질문', isDense: true),
                    onSubmitted: (_) => _send(),
                    textInputAction: TextInputAction.send,
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedBuilder(
                  animation: widget.chat,
                  builder: (context, _) => IconButton.filled(
                    onPressed: _persona != null && !widget.chat.isPending(_persona!) ? _send : null,
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

class _MessageTile extends StatelessWidget {
  final ChatMessage m;
  const _MessageTile(this.m);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = m.role == Role.user;
    final r = m.response;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          color: m.isError
              ? theme.colorScheme.errorContainer
              : isUser
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (r != null && r.safety)
              Text('안전 안내가 포함된 답변', style: theme.textTheme.labelSmall),
            Text(m.text),
            if (r != null && r.glossary.isNotEmpty) ...[
              const Divider(),
              for (final g in r.glossary)
                Text('${g.term}: ${g.meaning}', style: theme.textTheme.bodySmall),
            ],
            if (r != null && r.sources.isNotEmpty) ...[
              const Divider(),
              SourcesSection(sources: r.sources),
            ],
            if (r != null && !r.grounded && !r.safety)
              Text('근거 구절 없음', style: theme.textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}
