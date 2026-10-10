/// 로그인 뒤 첫 화면 — 철학자를 2열 바둑판으로 보여 주고, 누르면 그 철학자와의 대화창을 연다 (2026-10-10, 사용자 결정).
/// 디자인은 Codex 몫.
///
/// 철학자 목록은 서버 GET /personas 에서 받는다. 서버가 막 켜지는 중이면(모델 로딩 20초 안팎) 잠시 기다렸다 다시 묻는다 —
/// 예전 임시 화면의 "연결" 버튼을 없앤 대신이다.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../state/auth.dart';
import '../state/chat.dart';
import '../state/settings.dart';
import 'chat_screen.dart';

class PersonaGridScreen extends StatefulWidget {
  final SettingsStore settings;
  final ChatController chat;

  /// 계정 메뉴(이름·로그아웃). null 이면 메뉴를 안 그린다.
  final AuthController? auth;

  /// 서버 클라이언트를 만든다 (서버 주소가 바뀌면 새 주소로). HomeShell 이 넘긴다.
  final PhiloRagClient Function() client;

  /// 서버에 연결이 안 될 때 다시 묻는 간격과 횟수. 테스트에서 줄인다.
  final Duration retryDelay;
  final int maxAttempts;

  const PersonaGridScreen({
    super.key,
    required this.settings,
    required this.chat,
    required this.client,
    this.auth,
    this.retryDelay = const Duration(seconds: 3),
    this.maxAttempts = 10,
  });

  @override
  State<PersonaGridScreen> createState() => _PersonaGridScreenState();
}

class _PersonaGridScreenState extends State<PersonaGridScreen> {
  List<Persona>? _personas;
  String? _error;
  int _loadId = 0; // 다시 시도 중에 화면을 떠나거나 새로 시도하면 이전 시도는 버린다

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _loadId++;
    super.dispose();
  }

  Future<void> _load() async {
    final id = ++_loadId;
    setState(() {
      _personas = null;
      _error = null;
    });
    for (var attempt = 1; attempt <= widget.maxAttempts; attempt++) {
      final client = widget.client();
      try {
        final ps = await client.personas();
        if (!mounted || id != _loadId) return;
        setState(() => _personas = ps.where((p) => p.enabled).toList());
        return;
      } on ApiException catch (e) {
        if (!mounted || id != _loadId) return;
        // 서버가 아예 안 떠 있거나 켜지는 중이면 잠시 뒤 다시. 서버가 오류를 돌려준 거면 기다려도 소용없다
        if (!e.isConnectionError || attempt == widget.maxAttempts) {
          setState(() => _error = e.isConnectionError
              ? '서버에 연결하지 못했습니다.\n서버가 켜져 있는지 확인하세요.'
              : '철학자 목록을 받지 못했습니다.\n$e');
          return;
        }
        await Future<void>.delayed(widget.retryDelay);
        if (!mounted || id != _loadId) return;
      } finally {
        client.close();
      }
    }
  }

  void _open(Persona p) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChatScreen(persona: p, chat: widget.chat),
    ));
  }

  /// 개발용 — 실기기(같은 Wi-Fi)에서 PC 서버 주소를 바꿀 때. 릴리스 빌드에는 메뉴가 없다.
  Future<void> _editServer() async {
    final ctl = TextEditingController(text: widget.settings.baseUrl);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('서버 주소 (개발용)'),
        content: TextField(
          controller: ctl,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(helperText: '에뮬레이터 http://10.0.2.2:8000\n실기기 http://192.168.0.10:8000'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('저장')),
        ],
      ),
    );
    if (ok == true) {
      await widget.settings.setBaseUrl(ctl.text);
      _load();
    }
    ctl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.auth;
    return Scaffold(
      appBar: AppBar(
        title: const Text('누구에게 물어볼까요?'),
        actions: [
          // 임시 계정 메뉴 — 정식 UI(Codex)에서 설정 화면 등으로 옮긴다
          if (auth != null)
            PopupMenuButton<String>(
              tooltip: '계정',
              icon: const Icon(Icons.account_circle_outlined),
              onSelected: (v) {
                if (v == 'server') _editServer();
                if (v == 'signout') auth.signOut();
              },
              itemBuilder: (_) => [
                PopupMenuItem(enabled: false, child: Text(auth.user?.label ?? '')),
                if (kDebugMode) const PopupMenuItem(value: 'server', child: Text('서버 주소 (개발용)')),
                const PopupMenuItem(value: 'signout', child: Text('로그아웃')),
              ],
            ),
        ],
      ),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('다시 시도')),
          ]),
        ),
      );
    }
    final ps = _personas;
    if (ps == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return GridView.count(
      crossAxisCount: 2,
      padding: const EdgeInsets.all(16),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.85,
      children: [
        for (final p in ps)
          Card(
            key: ValueKey('persona-${p.key}'),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _open(p),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Text(p.name.characters.first, style: theme.textTheme.titleLarge),
                    ),
                    const Spacer(),
                    Text(p.name, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 6),
                    Text(p.blurb, style: theme.textTheme.bodySmall, maxLines: 4, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
