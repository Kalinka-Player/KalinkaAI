import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Small, data-free layout plans survive rebuilds and return visits to a size.
/// Playback, hover, image decoding and animation never rerun the planner.
class HomeLayoutMemo<K, V> {
  final _plans = <K, V>{};
  final int capacity;

  HomeLayoutMemo({this.capacity = 32});

  V resolve(K key, V Function() calculate) {
    final previous = _plans.remove(key);
    if (previous != null) {
      _plans[key] = previous;
      return previous;
    }
    final plan = calculate();
    if (_plans.length >= capacity) _plans.remove(_plans.keys.first);
    _plans[key] = plan;
    return plan;
  }
}

const homeAlbumInset = kKalinkaFrameInset;
const homeAlbumArtGap = 8.0;
const homeAlbumMinimumCover = 120.0;
const homeAlbumOrdinaryCover = 176.0;
const homeAlbumLargeCover = 320.0;
const homeAlbumMinimumLargeCover = 240.0;
const homeAlbumMaximumSmallCover = 200.0;
const homePreviewColumnGap = 32.0;
const homeListMinimumColumnWidth = 480.0;

int homePreviewRowCount({
  required bool wide,
  bool small = false,
  bool large = false,
}) => small
    ? 3
    : large
    ? 6
    : wide
    ? 4
    : 3;

int homeListColumnCount(double width, {double textScale = 1}) => math.max(
  1,
  ((width + homePreviewColumnGap) /
          (homeListMinimumColumnWidth * textScale + homePreviewColumnGap))
      .floor(),
);

int homeListCapacity(
  double width, {
  required int rowsPerColumn,
  double textScale = 1,
}) => math.min(
  64,
  homeListColumnCount(width, textScale: textScale) * rowsPerColumn,
);

class HomeListLayout {
  final int count;
  final int columns;
  final double columnWidth;
  const HomeListLayout(this.count, this.columns, this.columnWidth);

  int get rows => (count / columns).ceil();

  // Balanced, consecutive slices: finish the left column before the right.
  int startOf(int column) =>
      column * (count ~/ columns) + math.min(column, count % columns);
}

HomeListLayout homeListLayout({
  required double width,
  required int count,
  required int rowsPerColumn,
  double textScale = 1,
}) {
  final slots = homeListColumnCount(width, textScale: textScale);
  final visible = math.min(count, math.min(64, slots * rowsPerColumn));
  return HomeListLayout(
    visible,
    math.min(slots, math.max(1, visible)),
    math.max(0, (width - (slots - 1) * homePreviewColumnGap) / slots),
  );
}

/// Fetch for either possible content shape before the listing has loaded.
int homePreviewCapacity(
  double width, {
  required bool large,
  required double captionExtent,
  required double textScale,
  required int listRowsPerColumn,
}) => math.max(
  homeAlbumLayout(
    width: width,
    captionExtent: captionExtent,
    count: 64,
    wide: true,
    large: large,
  ).count,
  homeListCapacity(
    width,
    rowsPerColumn: listRowsPerColumn,
    textScale: textScale,
  ),
);

/// Shared by the folder renderer and background planner so wrapping uses the
/// same card dimensions. Large phone cards leave a glimpse of the next cover.
double homeFolderCover(
  double width, {
  required bool wide,
  required bool large,
  double textScale = 1,
}) => math.max(
  0,
  large
      ? math.min(
          homeAlbumLargeCover,
          width / (wide ? 1 : 1.15) - 2 * homeAlbumInset,
        )
      : wide
      ? math.min(homeAlbumOrdinaryCover, width - 2 * homeAlbumInset)
      : math.min(160, (width / 2.25 - 2 * homeAlbumInset) * textScale),
);

final _captionMetrics =
    HomeLayoutMemo<(TextScaler, TextStyle, TextStyle), double>();
final _labelWidths =
    HomeLayoutMemo<(String, TextStyle, TextScaler, TextDirection), double>(
      capacity: 256,
    );

double homeLabelWidth(BuildContext context, String text, TextStyle style) {
  final merged = DefaultTextStyle.of(context).style.merge(style);
  final scaler = MediaQuery.textScalerOf(context);
  final direction = Directionality.of(context);
  return _labelWidths.resolve((text, merged, scaler, direction), () {
    final painter = TextPainter(
      text: TextSpan(text: text, style: merged),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  });
}

/// Frame padding, cover-to-title gap and both caption lines. A featured cover
/// needs this whole extent between its two cover heights to meet the second row.
double homeAlbumCaptionExtent(BuildContext context) {
  final base = DefaultTextStyle.of(context).style;
  final title = base.merge(KalinkaTextStyles.trackRowTitle);
  final subtitle = base.merge(KalinkaTextStyles.trackRowSubtitle);
  final scaler = MediaQuery.textScalerOf(context);
  return _captionMetrics.resolve((scaler, title, subtitle), () {
    double line(TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: 'Ag', style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final height = painter.height;
      painter.dispose();
      return height;
    }

    return 2 * homeAlbumInset + homeAlbumArtGap + line(title) + line(subtitle);
  });
}

enum HomeAlbumArrangement { single, row, collage, rail }

class HomeAlbumLayout {
  final HomeAlbumArrangement arrangement;
  final int count;
  final int columns;
  final double cover;
  final double leadCover;
  final double captionExtent;

  const HomeAlbumLayout({
    required this.arrangement,
    required this.count,
    required this.cover,
    required this.captionExtent,
    this.columns = 1,
    this.leadCover = 0,
  });
}

typedef _AlbumLayoutKey = ({
  double width,
  double caption,
  int count,
  bool wide,
  bool large,
  bool single,
  double largeCover,
});
final _albumLayouts = HomeLayoutMemo<_AlbumLayoutKey, HomeAlbumLayout>();

HomeAlbumLayout homeAlbumLayout({
  required double width,
  required double captionExtent,
  required int count,
  required bool wide,
  required bool large,
  bool single = false,
  double largeCover = homeAlbumLargeCover,
}) => _albumLayouts.resolve(
  (
    width: width,
    caption: captionExtent,
    count: count,
    wide: wide,
    large: large,
    single: single,
    largeCover: largeCover,
  ),
  () {
    HomeAlbumLayout layout(
      HomeAlbumArrangement arrangement,
      int visible,
      double size, {
      int columns = 1,
      double lead = 0,
    }) => HomeAlbumLayout(
      arrangement: arrangement,
      count: visible,
      cover: math.max(0, size),
      columns: columns,
      leadCover: lead,
      captionExtent: captionExtent,
    );
    if (single || count <= 1) {
      return layout(
        HomeAlbumArrangement.single,
        count,
        math.min(
          large ? largeCover : homeAlbumOrdinaryCover,
          width - 2 * homeAlbumInset,
        ),
      );
    }
    if (!wide) {
      return layout(
        HomeAlbumArrangement.rail,
        count,
        large && count == 2
            ? homeFolderCover(width, wide: false, large: true)
            : math.min(160, width / 2.25 - 2 * homeAlbumInset),
      );
    }
    if (large && count == 2) {
      final visible = math.min(
        count,
        math.max(
          1,
          (width / (homeAlbumMinimumLargeCover + 2 * homeAlbumInset)).floor(),
        ),
      );
      return layout(
        HomeAlbumArrangement.row,
        visible,
        math.min(largeCover, width / visible - 2 * homeAlbumInset),
      );
    }
    if (large && count >= 3) {
      // Prefer the reference's two-by-two side grid as soon as it can keep
      // readable covers; extra width adds further columns after that.
      final preferredColumns =
          count >= 4 &&
              width >=
                  4 * homeAlbumMinimumCover + captionExtent + 6 * homeAlbumInset
          ? 2
          : 1;
      final desiredColumns = math.max(
        preferredColumns,
        ((width -
                    captionExtent -
                    2 * homeAlbumInset -
                    2 * homeAlbumMaximumSmallCover) /
                (homeAlbumMaximumSmallCover + 2 * homeAlbumInset))
            .ceil(),
      );
      var columns = math.min(desiredColumns, ((count - 1) / 2).ceil());
      double coverFor(int columns) => math.min(
        homeAlbumMaximumSmallCover,
        (width - captionExtent - (columns + 1) * 2 * homeAlbumInset) /
            (columns + 2),
      );
      while (columns > 1 && coverFor(columns) < homeAlbumMinimumCover) {
        columns--;
      }
      final cover = coverFor(columns);
      if (cover >= homeAlbumMinimumCover) {
        return layout(
          HomeAlbumArrangement.collage,
          math.min(count, 1 + 2 * columns),
          cover,
          columns: columns,
          lead: 2 * cover + captionExtent,
        );
      }
    }
    final desired = (width / (homeAlbumOrdinaryCover + 2 * homeAlbumInset))
        .ceil();
    final viable = (width / (homeAlbumMinimumCover + 2 * homeAlbumInset))
        .floor();
    final visible = math.min(count, math.max(1, math.min(desired, viable)));
    return layout(
      HomeAlbumArrangement.row,
      visible,
      math.min(homeAlbumOrdinaryCover, width / visible - 2 * homeAlbumInset),
    );
  },
);
