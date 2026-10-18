import 'package:flutter/material.dart';

import '../../providers/pinned_catalogs_provider.dart';
import '../../theme/app_theme.dart';

/// Decorative, locally drawn examples shared by the pin sheet and picker.
/// No catalog fetch or image download is needed to explain a layout.
class HomePreviewIllustration extends StatelessWidget {
  final HomePreviewType type;
  final Color sourceColor;

  const HomePreviewIllustration({
    super.key,
    required this.type,
    this.sourceColor = KalinkaColors.accent,
  });

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: AspectRatio(
      aspectRatio: 2.1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CustomPaint(painter: _LayoutPainter(type, sourceColor)),
      ),
    ),
  );
}

class _LayoutPainter extends CustomPainter {
  final HomePreviewType type;
  final Color sourceColor;
  const _LayoutPainter(this.type, this.sourceColor);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 210, size.height / 100);
    canvas.clipRect(const Rect.fromLTWH(0, 0, 210, 100));
    canvas.drawColor(KalinkaColors.surfaceBase, BlendMode.srcOver);

    void box(
      double x,
      double y,
      double w,
      double h,
      Color color, [
      double radius = 3,
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w, h),
          Radius.circular(radius),
        ),
        Paint()..color = color,
      );
    }

    void cover(double x, double y, double side, int variant) {
      final tone = [
        KalinkaColors.accentTint,
        KalinkaColors.gold,
        KalinkaColors.textSecondary,
      ][variant % 3];
      final rect = Rect.fromLTWH(x, y, side, side);
      canvas.save();
      canvas.clipRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(side / 10)),
      );
      canvas.drawRect(
        rect,
        Paint()..color = Color.lerp(KalinkaColors.surfaceInput, tone, .35)!,
      );
      canvas.drawCircle(
        Offset(x + side * .65, y + side * .34),
        side * .3,
        Paint()..color = tone,
      );
      canvas.drawPath(
        Path()
          ..moveTo(x - side * .1, y + side)
          ..lineTo(x + side * .45, y + side * .28)
          ..lineTo(x + side * 1.2, y + side)
          ..close(),
        Paint()..color = KalinkaColors.background.withValues(alpha: .55),
      );
      canvas.drawCircle(
        Offset(x + side * .32, y + side * .7),
        side * .16,
        Paint()..color = tone.withValues(alpha: .5),
      );
      canvas.restore();
    }

    switch (type) {
      case HomePreviewType.cards:
        for (var i = 0; i < 4; i++) {
          cover(10 + i * 62, 16, 54, i);
          box(10 + i * 62, 77, 40, 4, KalinkaColors.textMuted);
          box(10 + i * 62, 85, 28, 3, KalinkaColors.borderDefault);
        }
      case HomePreviewType.artwork:
        cover(10, 10, 80, 0);
        box(104, 26, 92, 7, KalinkaColors.textSecondary);
        box(104, 43, 76, 4, KalinkaColors.textMuted);
        box(104, 54, 84, 4, KalinkaColors.textMuted);
        box(104, 65, 55, 4, KalinkaColors.borderDefault);
      case HomePreviewType.list:
        for (var i = 0; i < 5; i++) {
          final y = 6.0 + i * 18;
          cover(14, y, 15, i);
          box(38, y + 2, 106 - i % 3 * 14, 4, KalinkaColors.textSecondary);
          box(38, y + 9, 67 - i % 2 * 17, 3, KalinkaColors.borderDefault);
          canvas.drawPath(
            Path()
              ..moveTo(190, y + 4)
              ..lineTo(193, y + 7)
              ..lineTo(190, y + 10),
            Paint()
              ..color = KalinkaColors.textMuted
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
        }
      case HomePreviewType.compact:
        final rect = RRect.fromRectAndRadius(
          const Rect.fromLTWH(10, 23, 190, 54),
          const Radius.circular(8),
        );
        canvas.drawRRect(
          rect,
          Paint()
            ..color = Color.alphaBlend(
              sourceColor.withValues(alpha: .14),
              KalinkaColors.surfaceRaised,
            ),
        );
        canvas.drawRRect(
          rect,
          Paint()
            ..color = sourceColor.withValues(alpha: .5)
            ..style = PaintingStyle.stroke,
        );
        box(22, 33, 32, 34, sourceColor.withValues(alpha: .15), 6);
        final note = Paint()
          ..color = sourceColor
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke;
        canvas.drawPath(
          Path()
            ..moveTo(35, 55)
            ..lineTo(35, 42)
            ..lineTo(45, 39)
            ..lineTo(45, 53),
          note,
        );
        canvas.drawOval(
          const Rect.fromLTWH(29, 53, 7, 5),
          Paint()..color = sourceColor,
        );
        canvas.drawOval(
          const Rect.fromLTWH(39, 51, 7, 5),
          Paint()..color = sourceColor,
        );
        box(67, 38, 98, 7, KalinkaColors.textSecondary);
        box(67, 53, 65, 5, KalinkaColors.textMuted);
        canvas.drawPath(
          Path()
            ..moveTo(181, 45)
            ..lineTo(186, 50)
            ..lineTo(181, 55),
          Paint()
            ..color = KalinkaColors.textMuted
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LayoutPainter oldDelegate) =>
      type != oldDelegate.type || sourceColor != oldDelegate.sourceColor;
}
