import 'package:flutter/material.dart';

/// 손글씨가 왼쪽에서 오른쪽으로 쓰이며, 20초마다 다시 시작한다.
class HandwrittenTitle extends StatefulWidget {
  final double fontSize;
  const HandwrittenTitle({super.key, required this.fontSize});

  @override
  State<HandwrittenTitle> createState() => _HandwrittenTitleState();
}

class _HandwrittenTitleState extends State<HandwrittenTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _writing = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 20),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _writing.stop();
      _writing.value = 0.5;
    } else if (!_writing.isAnimating) {
      _writing.repeat();
    }
  }

  @override
  void dispose() {
    _writing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: 'GowunBatang',
      fontSize: widget.fontSize,
      color: const Color(0xFFD4D4D4),
      height: 1.1,
    );
    final layout = TextPainter(
      text: TextSpan(text: '쉼표,', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final size = Size(layout.width + 16, layout.height + 16);
    layout.dispose();
    return Semantics(
      label: '쉼표,',
      child: RepaintBoundary(
        child: SizedBox.fromSize(
          size: size,
          child: CustomPaint(painter: _WritingPainter(style, _writing)),
        ),
      ),
    );
  }
}

class _WritingPainter extends CustomPainter {
  final TextStyle style;
  final Animation<double> animation;
  _WritingPainter(this.style, this.animation) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final text = TextPainter(
      text: TextSpan(text: '쉼표,', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    // 3.2초 동안 음절 내부를 펜 이동 방향으로 드러낸 뒤 유지한다.
    final progress = (animation.value / 0.16).clamp(0.0, 1.0);
    if (progress >= 1) {
      text.paint(canvas, const Offset(8, 8));
      text.dispose();
      return;
    }
    final mask = Path();
    for (var i = 0; i < 3; i++) {
      final boxes = text.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
      if (boxes.isEmpty) continue;
      final rect = boxes.first.toRect().shift(const Offset(8, 8)).inflate(4);
      final local = (progress * 3 - i).clamp(0.0, 1.0);
      if (local == 0) continue;
      if (local >= 1) {
        mask.addRect(rect.inflate(2));
        continue;
      }
      // 하나의 연속된 사선으로 드러내며 음절 내부에 띠 모양 틈을 만들지 않는다.
      final edge = rect.left + (rect.width + rect.height * 0.25) * local;
      mask.addPolygon([
        rect.topLeft,
        Offset(edge, rect.top),
        Offset(edge - rect.height * 0.25, rect.bottom),
        rect.bottomLeft,
      ], true);
    }
    canvas.save();
    canvas.clipPath(mask);
    text.paint(canvas, const Offset(8, 8));
    canvas.restore();
    text.dispose();
  }

  @override
  bool shouldRepaint(_WritingPainter oldDelegate) =>
      oldDelegate.style != style || oldDelegate.animation != animation;
}
