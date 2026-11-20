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

  /// Prefer one line when it fits without going below [minFontSize].
  /// Otherwise use the full [lines] budget.
  final bool preferSingleLine;

  /// Known text width when an ancestor already laid out the column. This
  /// also lets that ancestor measure the fitted text's intrinsic height.
  final double? availableWidth;

  const FittedTitle(
    this.text, {
    super.key,
    required this.style,
    required this.minFontSize,
    this.lines = 2,
    this.preferSingleLine = false,
    this.availableWidth,
  });

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    final full = style.fontSize!;
    final inherited = DefaultTextStyle.of(context).style.merge(style);
    final measuredStyle = MediaQuery.boldTextOf(context)
        ? inherited.copyWith(fontWeight: FontWeight.bold)
        : inherited;

    Text fit(double width) {
      if (!width.isFinite) return Text(text, style: style);

      TextPainter painterAt(double size) => TextPainter(
        text: TextSpan(
          text: text,
          style: measuredStyle.copyWith(fontSize: size),
        ),
        textDirection: direction,
        locale: locale,
        textScaler: scaler,
      );
      T measured<T>(double size, T Function(TextPainter) of) {
        final painter = painterAt(size)..layout(maxWidth: width);
        final value = of(painter);
        painter.dispose();
        return value;
      }

      double heightAt(double size) => measured(size, (p) => p.height);
      double lineHeightAt(double size) =>
          measured(size, (p) => p.preferredLineHeight);

      final (lineHeight, fullHeight) = measured(
        full,
        (p) => (p.preferredLineHeight, p.height),
      );
      final singleLine =
          preferSingleLine &&
          fullHeight > lineHeight &&
          measured(minFontSize, (p) => p.computeLineMetrics().length == 1);
      final budget = (singleLine ? 1 : lines) * lineHeight;
      var size = full;
      if (fullHeight > budget) {
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
      final fittedLineHeight = size == full ? lineHeight : lineHeightAt(size);
      final maxLines = math.max(1, ((budget + 0.5) / fittedLineHeight).floor());

      return Text(
        text,
        style: style.copyWith(fontSize: size),
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      );
    }

    final width = availableWidth;
    if (width != null) return fit(width);
    return LayoutBuilder(builder: (context, box) => fit(box.maxWidth));
  }
}
