/// 로그인 뒤 첫 화면 — 철학자를 2열 바둑판으로 보여 주고, 누르면 그 철학자와의 대화창을 연다 (2026-10-10, 사용자 결정).
/// 디자인은 Codex 몫.
///
/// 철학자 목록은 서버 GET /personas 에서 받는다. 서버가 막 켜지는 중이면(모델 로딩 20초 안팎) 잠시 기다렸다 다시 묻는다 —
/// 예전 임시 화면의 "연결" 버튼을 없앤 대신이다.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../state/auth.dart';
import '../state/chat.dart';
import '../state/settings.dart';
import 'chat_screen.dart';
import 'keep_words.dart';
import 'comma_mark.dart';
import 'portrait_ink.dart';
import 'app_theme.dart';

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
          setState(
            () => _error = e.isConnectionError
                ? '서버에 연결하지 못했습니다.\n서버가 켜져 있는지 확인하세요.'
                : '철학자 목록을 받지 못했습니다.\n$e',
          );
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ChatScreen(persona: p, chat: widget.chat),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CommaMark(),
            const Text('누구에게 물어볼까요?', style: TextStyle(fontSize: 12)),
          ],
        ),
        // 계정·로그아웃·서버 주소(개발용)는 설정 탭으로 옮겼다 (2026-10-12)
      ),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('다시 시도')),
            ],
          ),
        ),
      );
    }
    final ps = _personas;
    if (ps == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      key: const Key('persona-grid'),
      padding: const EdgeInsets.all(AppTheme.pageInset),
      children: [
        for (var i = 0; i < ps.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.pageInset),
            child: i + 1 == ps.length
                ? _card(context, ps[i], wide: true)
                : IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _card(context, ps[i])),
                        const SizedBox(width: AppTheme.pageInset),
                        Expanded(child: _card(context, ps[i + 1])),
                      ],
                    ),
                  ),
          ),
      ],
    );
  }

  Widget _card(BuildContext context, Persona p, {bool wide = false}) {
    final theme = Theme.of(context);
    final caption = Padding(
      padding: const EdgeInsets.all(AppTheme.pageInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.name, style: theme.textTheme.titleLarge),
          if (p.blurb.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(p.blurb, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
    return Card(
      key: ValueKey('persona-${p.key}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(p),
        child: Semantics(
          label: '${p.name}에게 물어보기',
          child: wide
              ? Row(
                  children: [
                    SizedBox(
                      width: 140,
                      height: 160,
                      child: PersonaVisual(name: p.name),
                    ),
                    Expanded(child: caption),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AspectRatio(
                      aspectRatio: 0.9,
                      child: PersonaVisual(name: p.name),
                    ),
                    caption,
                  ],
                ),
        ),
      ),
    );
  }
}

/// 기존 일러스트의 세 패널 중 해당 인물만 표시한다.
class PersonaVisual extends StatefulWidget {
  final String name;
  final Widget? illustration;
  final bool faceOnly;
  const PersonaVisual({
    super.key,
    required this.name,
    this.illustration,
    this.faceOnly = false,
  });

  @override
  State<PersonaVisual> createState() => _PersonaVisualState();
}

class _PersonaVisualState extends State<PersonaVisual> {
  // 말풍선마다 원본을 다시 디코딩하지 않는다. clone은 같은 이미지 메모리를
  // 공유하며, 각 위젯은 자기 핸들만 dispose한다.
  static Future<ui.Image>? _darkAsset;
  static Future<ui.Image>? _lightAsset;
  static ui.Image? _sharedDark;
  static ui.Image? _sharedLight;
  ui.Image? _image;
  ui.Image? _lightImage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Future.wait([
      _loadAsset(portraitDarkAsset, false),
      _loadAsset(portraitLightAsset, true),
    ]);
  }

  static Future<ui.Image> _decodeAsset(String asset) async {
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  Future<void> _loadAsset(String asset, bool light) async {
    var original = light ? _sharedLight : _sharedDark;
    if (original == null) {
      original = await (light
          ? _lightAsset ??= _decodeAsset(asset)
          : _darkAsset ??= _decodeAsset(asset));
      if (light) {
        _sharedLight = original;
      } else {
        _sharedDark = original;
      }
    }
    if (!mounted) {
      return;
    }
    final image = original.clone();
    setState(() {
      if (light) {
        _lightImage = image;
      } else {
        _image = image;
      }
    });
  }

  @override
  void dispose() {
    _image?.dispose();
    _lightImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.illustration != null) return widget.illustration!;
    final image = Theme.of(context).brightness == Brightness.light
        ? _lightImage
        : _image;
    if (image == null) return const SizedBox.expand();
    final panel = switch (widget.name) {
      '니체' => 0,
      '부처' => 2,
      _ => 1,
    };
    return CustomPaint(
      painter: _PortraitPainter(
        image,
        panel,
        Theme.of(context).brightness,
        faceOnly: widget.faceOnly,
      ),
      child: const SizedBox.expand(),
    );
  }
}

/// 어두운 배경을 투명하게 처리하고 인물을 카드에 크게 배치한다.
class _PortraitPainter extends CustomPainter {
  final ui.Image image;
  final int panel;
  final Brightness brightness;
  final bool faceOnly;
  const _PortraitPainter(
    this.image,
    this.panel,
    this.brightness, {
    this.faceOnly = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final width = image.width / 3;
    final source = faceOnly
        ? Rect.fromLTWH(
            width * (panel + 0.20),
            image.height * 0.09,
            width * 0.60,
            image.height * 0.38,
          )
        : brightness == Brightness.light
        ? Rect.fromLTWH(width * panel, 0, width, image.height.toDouble())
        : Rect.fromLTWH(
            width * (panel + 0.08),
            image.height * 0.13,
            width * 0.84,
            image.height * 0.76,
          );
    final bounds = Offset.zero & size;
    final fitted = applyBoxFit(
      faceOnly ? BoxFit.cover : BoxFit.contain,
      source.size,
      size,
    );
    final fittedSource = Alignment.center.inscribe(fitted.source, source);
    final destination = Alignment.bottomCenter.inscribe(
      fitted.destination,
      bounds,
    );
    canvas.saveLayer(bounds, Paint());
    canvas.drawImageRect(
      image,
      fittedSource,
      destination,
      Paint()
        ..filterQuality = FilterQuality.high
        ..colorFilter = portraitInkFilter(brightness),
    );
    if (!faceOnly) {
      canvas.drawRect(
        bounds,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = ui.Gradient.linear(
            Offset(0, size.height * 0.9),
            Offset(0, size.height),
            [Colors.white, Colors.transparent],
            [0.0, 1.0],
          ),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PortraitPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.panel != panel ||
      oldDelegate.brightness != brightness ||
      oldDelegate.faceOnly != faceOnly;
}
