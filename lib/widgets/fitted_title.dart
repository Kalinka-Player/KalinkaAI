import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A title held to the height [lines] lines take at its full size. A longer
/// one is set smaller, over as many lines as fit in that height, down to
/// [minFontSize]; one that still does not fit there is cut short.
class FittedTitle extends StatelessWidget {
  final String text;

  /// Carries the full font size.
  final TextStyle style;

  final double minFontSize;
  final int lines;

  const FittedTitle(
    this.text, {
    super.key,
    required this.style,
    required this.minFontSize,
    this.lines = 2,
  });

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final full = style.fontSize!;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth) return Text(text, style: style);

        TextPainter painterAt(double size) => TextPainter(
          text: TextSpan(
            text: text,
            style: style.copyWith(fontSize: size),
          ),
          textDirection: direction,
          textScaler: scaler,
        );
        double measured(double size, double Function(TextPainter) of) {
          final painter = painterAt(size)
            ..layout(maxWidth: constraints.maxWidth);
          final value = of(painter);
          painter.dispose();
          return value;
        }

        double heightAt(double size) => measured(size, (p) => p.height);
        double lineHeightAt(double size) =>
            measured(size, (p) => p.preferredLineHeight);

        final budget = lines * lineHeightAt(full);
        var size = full;
        if (heightAt(full) > budget) {
          var fits = minFontSize;
          var overflows = full;
          for (var step = 0; step < 8; step++) {
            final middle = (fits + overflows) / 2;
            if (heightAt(middle) <= budget) {
              fits = middle;
            } else {
              overflows = middle;
            }
          }
          size = fits;
        }
        // The half pixel keeps rounding from costing a line that fits.
        final maxLines = math.max(
          1,
          ((budget + 0.5) / lineHeightAt(size)).floor(),
        );

        return Text(
          text,
          style: style.copyWith(fontSize: size),
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}
