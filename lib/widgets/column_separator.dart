import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The hairline between a wide row's columns. Rows of one listing share
/// their column widths, so these line up from row to row.
class ColumnSeparator extends StatelessWidget {
  final double height;
  final double gap;

  const ColumnSeparator({super.key, this.height = 28, this.gap = 12});

  /// Room one separator takes across a row.
  static double widthOf({double gap = 12}) => gap * 2 + 1;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gap),
      child: SizedBox(
        width: 1,
        height: height,
        child: const ColoredBox(color: KalinkaColors.borderSubtle),
      ),
    );
  }
}
