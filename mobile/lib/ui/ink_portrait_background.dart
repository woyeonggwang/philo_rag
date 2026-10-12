import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'portrait_ink.dart';

// 기존 속도의 40%로 퍼진 뒤, 같은 시간 동안 번짐을 역순으로 거둔다.
const _spreadSeconds = 4.32 / 0.4;
const _holdSeconds = 2.16;
const _fadeOutSeconds = _spreadSeconds;
const _fadeInSeconds = 1.08;
const _portraitSeconds = _spreadSeconds + _holdSeconds + _fadeOutSeconds;

/// 샘플의 각 인물 영역을 한 명씩 그리며 원본 이미지는 유지한다.
class InkPortraitBackground extends StatefulWidget {
  const InkPortraitBackground({super.key});

  @override
  State<InkPortraitBackground> createState() => _InkPortraitBackgroundState();
}

class _InkPortraitBackgroundState extends State<InkPortraitBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cycle = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (_portraitSeconds * 3 * 1000).round()),
  );
  ui.Image? _image;
  ui.Image? _lightImage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Future.wait([_loadAsset(portraitDarkAsset, false), _loadAsset(portraitLightAsset, true)]);
  }

  Future<void> _loadAsset(String asset, bool light) async {
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(
      data.offsetInBytes, data.lengthInBytes,
    ));
    final frame = await codec.getNextFrame();
    codec.dispose();
    if (!mounted) {
      frame.image.dispose();
      return;
    }
    setState(() {
      if (light) {
        _lightImage = frame.image;
      } else {
        _image = frame.image;
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _cycle.stop();
      _cycle.value = 1 / 6; // 첫 인물이 완전히 드러난 유지 구간
    } else if (!_cycle.isAnimating) {
      _cycle.repeat();
    }
  }

  @override
  void dispose() {
    _cycle.dispose();
    _image?.dispose();
    _lightImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = Theme.of(context).brightness == Brightness.light ? _lightImage : _image;
    if (image == null) return const SizedBox.expand();
    return RepaintBoundary(
      child: CustomPaint(
        painter: _InkPortraitPainter(
          image: image,
          cycle: _cycle,
          dark: Theme.of(context).brightness == Brightness.dark,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _InkPortraitPainter extends CustomPainter {
  final ui.Image image;
  final Animation<double> cycle;
  final bool dark;

  _InkPortraitPainter({required this.image, required this.cycle, required this.dark})
      : super(repaint: cycle);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final position = cycle.value * 3;
    final person = position.floor().clamp(0, 2);
    final phase = position - person;
    final elapsed = phase * _portraitSeconds;
    // 등장과 퇴장에 동일한 진행값을 사용해 같은 번짐 모양을 되짚는다.
    final revealTime = math.min(elapsed, _portraitSeconds - elapsed);
    final spread = Curves.easeOutCubic.transform((revealTime / _spreadSeconds).clamp(0.0, 1.0));
    final opacity = (revealTime / _fadeInSeconds).clamp(0.0, 1.0) * (dark ? 0.85 : 0.8);
    if (opacity <= 0) return;

    final bounds = Offset.zero & size;
    final panelWidth = image.width / 3;
    final source = Rect.fromLTWH(
      person * panelWidth, 0,
      panelWidth, image.height.toDouble(),
    );
    // 원본의 여백에 더해 화면 양옆과 위아래에도 안전한 공간을 둔다.
    final available = Size(size.width * 0.84, size.height * 0.78);
    final fitted = applyBoxFit(BoxFit.contain, source.size, available);
    final destination = Alignment.center.inscribe(fitted.destination, bounds);
    final imagePaint = Paint()
      ..filterQuality = FilterQuality.high
      // 어두운 원본 배경을 투명하게 만들어 사각형 배경 경계가 남지 않게 한다.
      ..colorFilter = portraitInkFilter(dark ? Brightness.dark : Brightness.light);
    canvas.save();
    canvas.clipRect(bounds);
    canvas.saveLayer(bounds, Paint()..color = Colors.white.withValues(alpha: opacity));
    canvas.saveLayer(bounds, Paint());
    canvas.drawImageRect(image, source, destination, imagePaint);
    canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.dstIn);
    canvas.drawRect(bounds, Paint()..shader = ui.Gradient.linear(
      destination.topLeft, destination.topRight,
      [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
      [0, 0.04, 0.96, 1],
    ));
    canvas.restore();
    canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.dstIn);
    canvas.drawRect(bounds, Paint()..shader = ui.Gradient.linear(
      destination.topLeft, destination.bottomLeft,
      [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
      [0, 0.04, 0.96, 1],
    ));
    canvas.restore();
    canvas.restore();

    // 선명한 이미지의 사각 경계도 흐린 확장 영역으로 서서히 녹인다.
    canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.dstIn);
    canvas.drawRect(bounds, Paint()..shader = ui.Gradient.linear(
      Offset(destination.left - 42, 0), Offset(destination.right + 42, 0),
      [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
      [0, 0.22, 0.78, 1],
    ));
    canvas.restore();
    canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.dstIn);
    canvas.drawRect(bounds, Paint()..shader = ui.Gradient.linear(
      Offset(0, destination.top - 42), Offset(0, destination.bottom + 42),
      [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
      [0, 0.16, 0.78, 1],
    ));
    canvas.restore();

    // 중첩된 반투명 번짐과 흐린 가장자리로 잉크가 퍼지는 영역을 만든다.
    canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.dstIn);
    final center = Offset(size.width * 0.5, size.height * 0.42);
    final extent = math.sqrt(size.width * size.width + size.height * size.height);
    final random = math.Random(41 + person);
    for (var i = 0; i < 22; i++) {
      final angle = random.nextDouble() * math.pi * 2;
      final distance = random.nextDouble() * extent * 0.27;
      final delay = random.nextDouble() * 0.22;
      // 아직 나타나지 않은 영역도 난수를 소비해야 이후 영역의 모양이 유지된다.
      final fullRadius = extent * (0.12 + random.nextDouble() * 0.22);
      final growth = ((spread - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (growth == 0) continue;
      // 중심은 고정하고 반지름만 늘려 이미 드러난 부분이 다시 가려지지 않게 한다.
      final origin = center + Offset(math.cos(angle), math.sin(angle)) * distance;
      final radius = fullRadius * growth;
      canvas.drawCircle(origin, radius, Paint()
        ..color = Colors.white
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    }
    canvas.restore();
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_InkPortraitPainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.cycle != cycle || oldDelegate.dark != dark;
}
