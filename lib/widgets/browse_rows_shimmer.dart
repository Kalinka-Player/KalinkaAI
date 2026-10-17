import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'loading_shimmer.dart';

/// Where the rows below start their artwork. Shared by both shapes because
/// the search rows and the collection shelf agree on it, having agreed on
/// nothing else about their leading column.
const double _kRowLeftPadding = 3;

/// The row a shimmer stands in for: every part of a row's geometry a
/// placeholder has to match, so nothing shifts sideways or jumps taller when
/// the real rows land in its place.
class ShimmerRowShape {
  final double artwork;

  /// Artwork to text.
  final double gap;

  final double verticalPadding;

  /// The space the hairline between two rows takes, as that list draws it.
  final double dividerHeight;

  const ShimmerRowShape({
    required this.artwork,
    required this.gap,
    required this.verticalPadding,
    required this.dividerHeight,
  });

  /// Where the words start — and so where the hairline under the row starts.
  /// Held to what `BrowseItemRows.textInsetOf` returns for the row being
  /// stood in for, by a test; a shimmer that drifts from it is a list that
  /// twitches when its rows land.
  double get textInset => _kRowLeftPadding + artwork + gap;

  double get height => artwork + verticalPadding * 2;

  /// What [BrowseItemRows] builds: every search result and shelf preview.
  static const row = ShimmerRowShape(
    artwork: 44,
    gap: 10,
    verticalPadding: 8,
    dividerHeight: 14,
  );

  /// The taller row a collection takes on its own shelf.
  static const collection = ShimmerRowShape(
    artwork: 64,
    gap: 14,
    verticalPadding: 10,
    dividerHeight: 1,
  );
}

/// A block of [count] shimmering placeholder rows — artwork and two text
/// lines — pulsing under one shared controller (cheap: a single Opacity
/// rebuild, not one per row). Takes the [shape] of the rows it stands in for
/// so the block it occupies is the block they will fill, down to where the
/// hairlines between them start. Used as the load-more footer in
/// paged/infinite lists.
class BrowseRowsShimmer extends StatelessWidget {
  final int count;

  /// Hairline divider above the first shimmer row, so it reads as a
  /// continuation of the list it trails rather than a detached block.
  final bool leadingDivider;

  final ShimmerRowShape shape;

  const BrowseRowsShimmer({
    super.key,
    this.count = 3,
    this.leadingDivider = false,
    this.shape = ShimmerRowShape.row,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (int i = 0; i < count; i++) {
      if (leadingDivider || i > 0) {
        rows.add(
          Padding(
            padding: EdgeInsets.only(left: shape.textInset),
            child: Divider(
              color: KalinkaColors.borderSubtle,
              thickness: 1,
              height: shape.dividerHeight,
            ),
          ),
        );
      }
      rows.add(_row(shape));
    }
    return ShimmerPulse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }

  Widget _row(ShimmerRowShape shape) => Padding(
    padding: EdgeInsets.fromLTRB(
      _kRowLeftPadding,
      shape.verticalPadding,
      8,
      shape.verticalPadding,
    ),
    child: Row(
      children: [
        _box(shape.artwork),
        SizedBox(width: shape.gap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _line(0.55, 12),
              const SizedBox(height: 7),
              _line(0.35, 9),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _box(double size) => ShimmerBlock(width: size, height: size);

  Widget _line(double factor, double height) => Align(
    alignment: Alignment.centerLeft,
    child: FractionallySizedBox(
      widthFactor: factor,
      child: ShimmerBlock(height: height, radius: 4),
    ),
  );
}
