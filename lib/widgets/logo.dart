import 'package:flutter/material.dart';

import '../core/theme.dart';

/// The Lockeye icon: an eye whose pupil is a keyhole.
class LockeyeLogo extends StatelessWidget {
  const LockeyeLogo({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Lockeye logo',
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _LogoPainter()),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 128);

    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 128, 128), const Radius.circular(30)),
      Paint()..color = kAccent,
    );

    final eye = Path()
      ..moveTo(22, 64)
      ..cubicTo(38, 38, 90, 38, 106, 64)
      ..cubicTo(90, 90, 38, 90, 22, 64)
      ..close();
    canvas.drawPath(
      eye,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeJoin = StrokeJoin.round
        ..color = kInk,
    );

    canvas.drawCircle(const Offset(64, 64), 17, Paint()..color = kInk);
    canvas.drawCircle(const Offset(64, 60), 5, Paint()..color = kAccent);

    final stem = Path()
      ..moveTo(61, 62)
      ..lineTo(67, 62)
      ..lineTo(68.5, 72)
      ..lineTo(59.5, 72)
      ..close();
    canvas.drawPath(stem, Paint()..color = kAccent);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
