import 'package:flutter/material.dart';

import '../../data_model/room_eq.dart';
import '../../theme/app_theme.dart';

/// Response silhouettes run from low frequencies on the left to high on the right.
class FilterShapeIcon extends StatelessWidget {
  const FilterShapeIcon(
    this.shape, {
    super.key,
    this.color = KalinkaColors.textPrimary,
  });

  final FilterShape shape;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(22, 18),
    painter: _ShapePainter(shape, color),
  );
}

class _ShapePainter extends CustomPainter {
  const _ShapePainter(this.shape, this.color);
  final FilterShape shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = switch (shape) {
      FilterShape.peak =>
        Path()
          ..moveTo(2, 14)
          ..lineTo(5, 14)
          ..cubicTo(8, 14, 8, 3, 11, 3)
          ..cubicTo(14, 3, 14, 14, 17, 14)
          ..lineTo(20, 14),
      FilterShape.lowShelf =>
        Path()
          ..moveTo(2, 4)
          ..lineTo(6, 4)
          ..cubicTo(11, 4, 11, 14, 16, 14)
          ..lineTo(20, 14),
      FilterShape.highShelf =>
        Path()
          ..moveTo(2, 14)
          ..lineTo(6, 14)
          ..cubicTo(11, 14, 11, 4, 16, 4)
          ..lineTo(20, 4),
      FilterShape.lowPass || FilterShape.firstOrderLowPass =>
        Path()
          ..moveTo(2, 3)
          ..lineTo(7, 3)
          ..quadraticBezierTo(10, 3, 12, 6)
          ..lineTo(shape.hasQ ? 17 : 21, 16),
      FilterShape.highPass || FilterShape.firstOrderHighPass =>
        Path()
          ..moveTo(shape.hasQ ? 5 : 1, 16)
          ..lineTo(10, 6)
          ..quadraticBezierTo(12, 3, 15, 3)
          ..lineTo(20, 3),
    };
    canvas.save();
    canvas.scale(size.width / 22, size.height / 18);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShapePainter old) =>
      old.shape != shape || old.color != color;
}
