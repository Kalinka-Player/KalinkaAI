import 'dart:math' as math;

import 'package:flutter/material.dart';

/// [icon] struck through, as a slashed pin is: the action that undoes what
/// [icon] does. Sized and coloured by the [IconTheme] it sits in.
class StruckIcon extends StatelessWidget {
  final IconData icon;

  const StruckIcon(this.icon, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    return SizedBox.square(
      dimension: theme.size ?? 24,
      child: CustomPaint(
        foregroundPainter: _Slash(theme.color ?? Colors.white),
        child: ClipPath(clipper: const _SlashGap(), child: Icon(icon)),
      ),
    );
  }
}

/// The icon cut away either side of the slash, so it reads on any ground.
class _SlashGap extends CustomClipper<Path> {
  const _SlashGap();

  @override
  Path getClip(Size size) {
    final across = Offset(size.width, -size.height) * (0.12 / math.sqrt2);
    final end = Offset(size.width, size.height);
    return Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addPolygon([
        Offset.zero + across,
        end + across,
        end - across,
        Offset.zero - across,
      ], true),
    );
  }

  @override
  bool shouldReclip(_SlashGap oldClipper) => false;
}

class _Slash extends CustomPainter {
  final Color color;

  const _Slash(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(size.width * 0.12, size.height * 0.12),
      Offset(size.width * 0.88, size.height * 0.88),
      Paint()
        ..color = color
        ..strokeWidth = size.width * 0.09
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_Slash oldDelegate) => oldDelegate.color != color;
}
