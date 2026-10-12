/// 시크릿 모드 아이콘 — 모자와 안경 (2026-10-12, 사용자 요청: 크롬 시크릿 모드처럼).
/// Material 아이콘에 같은 모양이 없어 직접 그린다. 색과 크기는 주변 IconTheme 을 따른다 (IconButton 안에서도 맞게).
library;

import 'package:flutter/material.dart';

class IncognitoIcon extends StatelessWidget {
  final double? size;
  final Color? color;
  const IncognitoIcon({super.key, this.size, this.color});

  @override
  Widget build(BuildContext context) {
    final icon = IconTheme.of(context);
    final s = size ?? icon.size ?? 24;
    final c = color ?? icon.color ?? Theme.of(context).colorScheme.onSurface;
    return SizedBox.square(dimension: s, child: CustomPaint(painter: _IncognitoPainter(c)));
  }
}

/// 24×24 기준으로 그리고 크기에 맞춰 늘린다.
class _IncognitoPainter extends CustomPainter {
  final Color color;
  const _IncognitoPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final fill = Paint()..color = color;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round;

    // 모자 — 가운데가 살짝 눌린 윗면과 넓은 챙
    final crown = Path()
      ..moveTo(6.9, 10.2)
      ..lineTo(8.2, 4.9)
      ..quadraticBezierTo(8.5, 3.8, 9.6, 4.0)
      ..quadraticBezierTo(12, 4.9, 14.4, 4.0)
      ..quadraticBezierTo(15.5, 3.8, 15.8, 4.9)
      ..lineTo(17.1, 10.2)
      ..close();
    canvas.drawPath(crown, fill);
    canvas.drawRRect(
        RRect.fromLTRBR(2.4, 10.0, 21.6, 12.3, const Radius.circular(1.15)), fill);

    // 안경 — 두 알과 코다리
    canvas.drawCircle(const Offset(7.4, 17.3), 3.0, line);
    canvas.drawCircle(const Offset(16.6, 17.3), 3.0, line);
    canvas.drawPath(
        Path()
          ..moveTo(10.4, 17.0)
          ..quadraticBezierTo(12, 15.8, 13.6, 17.0),
        line..strokeWidth = 1.4);
  }

  @override
  bool shouldRepaint(_IncognitoPainter old) => old.color != color;
}
