import 'package:flutter/material.dart';

/// 두 화면에서 함께 쓰는 글꼴 없는 쉼표 그림.
class CommaMark extends StatelessWidget {
  final double size;
  const CommaMark({super.key, this.size = 28});

  @override
  Widget build(BuildContext context) => Semantics(
    label: '쉼표',
    child: SizedBox(
      width: size * 24 / 28,
      height: size,
      child: CustomPaint(painter: _CommaPainter(Theme.of(context).colorScheme.primary)),
    ),
  );
}

class _CommaPainter extends CustomPainter {
  final Color color;
  const _CommaPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 28);
    final path = Path()
      ..moveTo(15, 3)
      ..cubicTo(7, 2, 5, 12, 12, 15)
      ..cubicTo(12, 19, 9, 22, 6, 25)
      ..cubicTo(16, 23, 21, 16, 21, 10)
      ..cubicTo(21, 6, 19, 3, 15, 3)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CommaPainter oldDelegate) => oldDelegate.color != color;
}
