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
const homeAlbumMaximumSmallCover = 200.0;
const homeCollageGap = 16.0;
const homePreviewColumnGap = 32.0;

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
});
final _albumLayouts = HomeLayoutMemo<_AlbumLayoutKey, HomeAlbumLayout>();

HomeAlbumLayout homeAlbumLayout({
  required double width,
  required double captionExtent,
  required int count,
  required bool wide,
  required bool large,
  bool single = false,
}) => _albumLayouts.resolve(
  (
    width: width,
    caption: captionExtent,
    count: count,
    wide: wide,
    large: large,
    single: single,
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
        math.min(homeAlbumOrdinaryCover, width - 2 * homeAlbumInset),
      );
    }
    if (!wide) {
      return layout(
        HomeAlbumArrangement.rail,
        count,
        math.min(160, width / 2.25 - 2 * homeAlbumInset),
      );
    }
    if (large && count >= 3) {
      // Prefer the reference's two-by-two side grid as soon as it can keep
      // readable covers; extra width adds further columns after that.
      final preferredColumns =
          count >= 4 &&
              width >=
                  4 * homeAlbumMinimumCover +
                      captionExtent +
                      6 * homeAlbumInset +
                      homeCollageGap
          ? 2
          : 1;
      final desiredColumns = math.max(
        preferredColumns,
        ((width -
                    homeCollageGap -
                    captionExtent -
                    2 * homeAlbumInset -
                    2 * homeAlbumMaximumSmallCover) /
                (homeAlbumMaximumSmallCover + 2 * homeAlbumInset))
            .ceil(),
      );
      var columns = math.min(desiredColumns, ((count - 1) / 2).ceil());
      double coverFor(int columns) => math.min(
        homeAlbumMaximumSmallCover,
        (width -
                homeCollageGap -
                captionExtent -
                (columns + 1) * 2 * homeAlbumInset) /
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

enum HomePreviewBlockKind { shortcut, standalone, ordinary, collage }

class HomePreviewColumn {
  final double width;
  final List<int> blocks;
  HomePreviewColumn(this.width, List<int> blocks)
    : blocks = List.unmodifiable(blocks);
}

class HomePreviewRow {
  final bool shortcuts;
  final List<HomePreviewColumn> columns;
  HomePreviewRow(List<HomePreviewColumn> columns, {this.shortcuts = false})
    : columns = List.unmodifiable(columns);
}

class HomeSectionLayout {
  final bool wide;
  final List<HomePreviewRow> rows;
  HomeSectionLayout(this.wide, List<HomePreviewRow> rows)
    : rows = List.unmodifiable(rows);
}

final _sectionLayouts =
    HomeLayoutMemo<(double, double, double, String), HomeSectionLayout>();

/// Precomputed from pane constraints and pin shapes, never from render-object
/// measurements. Different-width columns share a common preferred cover size.
HomeSectionLayout homeSectionLayout({
  required double width,
  required double textScale,
  required double captionExtent,
  required List<HomePreviewBlockKind> kinds,
}) => _sectionLayouts.resolve(
  (width, textScale, captionExtent, kinds.map((kind) => kind.index).join(',')),
  () {
    final wide = width >= 800 * textScale;
    final maxColumns = math.max(
      2,
      ((width + homePreviewColumnGap) /
              (520 * textScale + homePreviewColumnGap))
          .floor(),
    );
    final rows = <HomePreviewRow>[];
    bool adaptive(int index) =>
        index < kinds.length &&
        (kinds[index] == HomePreviewBlockKind.ordinary ||
            kinds[index] == HomePreviewBlockKind.collage);
    final collageFixed = captionExtent + 6 * homeAlbumInset + homeCollageGap;
    final collageMinimum = 4 * homeAlbumMinimumCover + collageFixed;
    final ordinaryMinimum = 2 * (homeAlbumMinimumCover + 2 * homeAlbumInset);
    for (var index = 0; index < kinds.length;) {
      if (kinds[index] == HomePreviewBlockKind.shortcut) {
        final run = <int>[];
        do {
          run.add(index++);
        } while (index < kinds.length &&
            kinds[index] == HomePreviewBlockKind.shortcut);
        rows.add(
          HomePreviewRow([HomePreviewColumn(width, run)], shortcuts: true),
        );
        continue;
      }
      if (!wide || !adaptive(index)) {
        rows.add(
          HomePreviewRow([
            HomePreviewColumn(width, [index++]),
          ]),
        );
        continue;
      }
      final selected = <int>[index];
      var used = kinds[index] == HomePreviewBlockKind.collage
          ? collageMinimum
          : ordinaryMinimum;
      while (selected.length < maxColumns &&
          adaptive(index + selected.length)) {
        final next = index + selected.length;
        final minimum = kinds[next] == HomePreviewBlockKind.collage
            ? collageMinimum
            : ordinaryMinimum;
        if (used + homePreviewColumnGap + minimum > width) break;
        selected.add(next);
        used += homePreviewColumnGap + minimum;
      }
      index += selected.length;
      final large = selected
          .where((i) => kinds[i] == HomePreviewBlockKind.collage)
          .length;
      final ordinary = selected.length - large;
      final available = width - (selected.length - 1) * homePreviewColumnGap;
      final ordinaryCards =
          available >=
              large * collageMinimum +
                  ordinary * 3 * (homeAlbumMinimumCover + 2 * homeAlbumInset)
          ? 3
          : 2;
      final commonCover =
          (available -
              large * collageFixed -
              ordinary * ordinaryCards * 2 * homeAlbumInset) /
          (large * 4 + ordinary * ordinaryCards);
      final columns = <HomePreviewColumn>[];
      for (final first in selected) {
        final isLarge = kinds[first] == HomePreviewBlockKind.collage;
        final columnWidth = selected.length == 1
            ? width
            : large == 0
            ? available / selected.length
            : isLarge
            ? 4 * commonCover + collageFixed
            : ordinaryCards * (commonCover + 2 * homeAlbumInset);
        final blocks = [first];
        if (large > 0 &&
            !isLarge &&
            adaptive(index) &&
            kinds[index] == HomePreviewBlockKind.ordinary) {
          blocks.add(index++);
        }
        columns.add(HomePreviewColumn(columnWidth, blocks));
      }
      rows.add(HomePreviewRow(columns));
    }
    return HomeSectionLayout(wide, rows);
  },
);
