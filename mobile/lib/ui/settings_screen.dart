/// 설정 탭 (2026-10-12, 사용자 결정): 화면 테마(라이트/다크) · 글씨 크기 · 로그인 계정 · 남은 사용량 · 결제(준비 중).
/// 디버그 빌드에는 서버 주소(개발용)도 있다 — 예전 바둑판의 계정 메뉴에서 옮겨 왔다. 디자인은 Codex 몫.
/// 개발자(서버 .env 의 ADMIN_USERS)에게만 "개발자 · 신고 내역"이 보인다 (2026-10-12).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../state/auth.dart';
import '../state/settings.dart';
import 'reports_screen.dart';

class SettingsScreen extends StatefulWidget {
  final SettingsStore settings;
  final AuthController auth;
  final PhiloRagClient Function() client;

  /// 값이 바뀌면 남은 사용량을 다시 읽는다 (설정 탭을 열 때마다 MainTabs 가 올린다)
  final int refreshToken;

  const SettingsScreen({
    super.key,
    required this.settings,
    required this.auth,
    required this.client,
    this.refreshToken = 0,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  UsageInfo? _usage;
  String? _usageError;
  bool _usageLoading = false;

  /// 신고 내역을 볼 수 있는 개발자인지. 서버가 정한다 (GET /me)
  bool _admin = false;

  @override
  void initState() {
    super.initState();
    _loadUsage();
    _loadMe();
  }

  @override
  void didUpdateWidget(SettingsScreen old) {
    super.didUpdateWidget(old);
    if (old.refreshToken != widget.refreshToken) {
      _loadUsage();
      _loadMe();
    }
  }

  /// 실패하면(옛 서버·연결 안 됨) 개발자 메뉴를 그냥 숨긴다
  Future<void> _loadMe() async {
    final c = widget.client();
    try {
      final me = await c.me();
      if (mounted) setState(() => _admin = me.admin);
    } on ApiException {
      if (mounted) setState(() => _admin = false);
    } finally {
      c.close();
    }
  }

  Future<void> _loadUsage() async {
    setState(() {
      _usageLoading = true;
      _usageError = null;
    });
    final c = widget.client();
    try {
      final u = await c.usage();
      if (mounted) setState(() => _usage = u);
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => _usageError = e.isConnectionError
              ? '서버에 연결하지 못했습니다'
              : e.toString(),
        );
      }
    } finally {
      c.close();
      if (mounted) setState(() => _usageLoading = false);
    }
  }

  static String _providerLabel(String provider) => switch (provider) {
    'google.com' => 'Google 계정',
    'apple.com' => 'Apple 계정',
    'password' => '이메일 계정',
    'dev' => '로그인 안 함 (개발용)',
    _ => provider,
  };

  String _usageText(UsageInfo u) => u.unlimited
      ? '오늘 ${u.usedToday}건 사용 · 무제한'
      : '오늘 ${u.usedToday} / ${u.dailyLimit}건 사용 · ${u.remainingToday}건 남음';

  Future<void> _confirmSignOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('로그아웃할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
    if (ok == true) await widget.auth.signOut();
  }

  /// 개발용 — 실기기(같은 Wi-Fi)에서 PC 서버 주소를 바꿀 때. 릴리스 빌드에는 없다.
  Future<void> _editServer() async {
    final ctl = TextEditingController(text: widget.settings.baseUrl);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('서버 주소 (개발용)'),
        content: TextField(
          controller: ctl,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            helperText:
                '에뮬레이터 http://10.0.2.2:8000\n실기기 http://192.168.0.10:8000',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.settings.setBaseUrl(ctl.text);
      _loadUsage();
    }
    ctl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListenableBuilder(
        listenable: Listenable.merge([s, widget.auth]),
        builder: (context, _) {
          final user = widget.auth.user;
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              const _Header('화면'),
              ListTile(
                title: const Text('테마'),
                trailing: SegmentedButton<ThemeMode>(
                  key: const Key('theme'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: ThemeMode.light, label: Text('라이트')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('다크')),
                  ],
                  selected: {s.themeMode},
                  onSelectionChanged: (v) => s.setThemeMode(v.first),
                ),
              ),
              const ListTile(title: Text('글씨 크기')),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SegmentedButton<TextSize>(
                  key: const Key('text-size'),
                  showSelectedIcon: false,
                  segments: [
                    for (final t in TextSize.values)
                      ButtonSegment(value: t, label: Text(t.label)),
                  ],
                  selected: {s.textSize},
                  onSelectionChanged: (v) => s.setTextSize(v.first),
                ),
              ),
              const _Header('계정'),
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(user?.label ?? '로그인 안 됨'),
                // 개발용 우회는 이름 자체가 "개발용 (로그인 안 함)" 이라 아래 줄을 붙이지 않는다
                subtitle: user == null || user.provider == 'dev'
                    ? null
                    : Text(
                        [
                          _providerLabel(user.provider),
                          if (user.email != null && user.email != user.label)
                            user.email!,
                        ].join(' · '),
                      ),
              ),
              ListTile(
                key: const Key('signout'),
                leading: const Icon(Icons.logout),
                title: const Text('로그아웃'),
                onTap: _confirmSignOut,
              ),
              const _Header('사용량'),
              ListTile(
                key: const Key('usage'),
                leading: const Icon(Icons.data_usage),
                title: Text(_usage == null ? '요금제' : '${_usage!.planName} 요금제'),
                subtitle: Text(
                  _usageLoading && _usage == null
                      ? '불러오는 중…'
                      : _usageError ??
                            (_usage == null ? '' : _usageText(_usage!)),
                ),
                trailing: IconButton(
                  tooltip: '다시 읽기',
                  icon: const Icon(Icons.refresh),
                  onPressed: _usageLoading ? null : _loadUsage,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                // 결제 기능은 아직 없다 (사용자 결정 2026-10-12: 버튼만 두고 비활성화)
                child: FilledButton(
                  key: const Key('pay'),
                  onPressed: null,
                  child: const Text('결제 (준비 중)'),
                ),
              ),
              if (_admin) ...[
                const _Header('개발자'),
                ListTile(
                  key: const Key('reports'),
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('신고 내역'),
                  subtitle: const Text('사용자가 신고한 대화 (개발자만 보임)'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => ReportsScreen(client: widget.client)),
                  ),
                ),
              ],
              if (kDebugMode) ...[
                const _Header('개발용'),
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: const Text('서버 주소'),
                  subtitle: Text(s.baseUrl),
                  onTap: _editServer,
                ),
              ],
              const SizedBox(height: 8),
              Center(child: Text('쉼표,', style: theme.textTheme.bodySmall)),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.labelLarge),
  );
}
