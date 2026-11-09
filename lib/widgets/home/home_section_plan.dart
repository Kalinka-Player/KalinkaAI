import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'home_preview_layout.dart';

enum HomePreviewBlockKind {
  shortcut,
  standalone,
  ordinary,
  collage,
  folders,
  largeFolders,
  tracks,
}

/// Only dimensions and counts cross the isolate boundary. No library records,
/// artwork, widgets, text painters or provider subscriptions enter the solver.
typedef HomePreviewBlock = ({
  HomePreviewBlockKind kind,
  int count,
  double extraCaption,
});

@immutable
class HomeSectionRequest {
  final double width;
  final double textScale;
  final double captionExtent;
  final List<HomePreviewBlock> blocks;

  HomeSectionRequest({
    required this.width,
    required this.textScale,
    required this.captionExtent,
    required List<HomePreviewBlock> blocks,
  }) : blocks = List.unmodifiable(blocks);

  bool get wide => width >= 800 * textScale;

  @override
  bool operator ==(Object other) =>
      other is HomeSectionRequest &&
      width == other.width &&
      textScale == other.textScale &&
      captionExtent == other.captionExtent &&
      listEquals(blocks, other.blocks);

  @override
  int get hashCode =>
      Object.hash(width, textScale, captionExtent, Object.hashAll(blocks));
}

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

/// Safe initial/resizing layout, with no search or content measurements. The
/// previous plan can stay on screen for data changes at the same pane width.
HomeSectionLayout homeStackedSections(HomeSectionRequest request) {
  final rows = <HomePreviewRow>[];
  for (var i = 0; i < request.blocks.length;) {
    final shortcuts = request.blocks[i].kind == HomePreviewBlockKind.shortcut;
    final indices = [i++];
    while (shortcuts &&
        i < request.blocks.length &&
        request.blocks[i].kind == HomePreviewBlockKind.shortcut) {
      indices.add(i++);
    }
    rows.add(
      HomePreviewRow([
        HomePreviewColumn(request.width, indices),
      ], shortcuts: shortcuts),
    );
  }
  return HomeSectionLayout(request.wide, rows);
}

typedef _Extent = ({double height, double occupied, double utility});
typedef _Candidate = ({HomePreviewRow row, int next, double cost});

/// Ordered row packing (a shortest path / dynamic program over pin prefixes).
/// It is optimal among these bounded templates, not arbitrary rectangle packs:
/// full rows, up to six columns, and short sections stacked beside a collage.
/// Width alternatives include equal columns, shared cover sizes and content's
/// natural widths. Ties prefer the earlier, simpler arrangement deterministically.
HomeSectionLayout planHomeSections(HomeSectionRequest request) {
  if (!request.wide || request.blocks.isEmpty) {
    return homeStackedSections(request);
  }
  final blocks = request.blocks;
  final width = request.width;
  final caption = request.captionExtent;
  final header =
      60 * request.textScale + 24; // Heading, subtitle and section gaps.
  final collageFixed = caption + 6 * homeAlbumInset + homeCollageGap;
  final maxColumns = math.min(
    6,
    math.max(2, ((width + 32) / (520 * request.textScale + 32)).floor()),
  );
  final extents = <(int, double), _Extent>{};

  bool adaptive(int i) =>
      i < blocks.length &&
      blocks[i].kind != HomePreviewBlockKind.shortcut &&
      blocks[i].kind != HomePreviewBlockKind.standalone;
  bool large(int i) =>
      blocks[i].kind == HomePreviewBlockKind.collage && blocks[i].count >= 3;
  bool folderCards(int i) =>
      blocks[i].kind == HomePreviewBlockKind.folders ||
      blocks[i].kind == HomePreviewBlockKind.largeFolders;
  double minimum(int i) => blocks[i].kind == HomePreviewBlockKind.largeFolders
      ? homeAlbumLargeCover + 2 * homeAlbumInset
      : blocks[i].kind == HomePreviewBlockKind.collage && blocks[i].count <= 2
      ? math.max(1, blocks[i].count) *
            (homeAlbumMinimumLargeCover + 2 * homeAlbumInset)
      : large(i)
      ? (blocks[i].count >= 4 ? 4 : 3) * homeAlbumMinimumCover +
            caption +
            (blocks[i].count >= 4 ? 6 : 4) * homeAlbumInset +
            homeCollageGap
      : math.min(2, math.max(1, blocks[i].count)) *
            (homeAlbumMinimumCover + 2 * homeAlbumInset);

  _Extent extent(int i, double w) => extents.putIfAbsent((i, w), () {
    final block = blocks[i];
    final count = block.count;
    if (block.kind == HomePreviewBlockKind.tracks || count == 0) {
      final height =
          header +
          (count == 0 ? 24 : math.min(3, count) * 64 * request.textScale);
      return (height: height, occupied: height * w, utility: 0);
    }
    if (folderCards(i)) {
      // Match HomeAlbumFolderCards' selected-size Wrap, including optional
      // Home names. Every folder must remain visible; none is sampled away.
      final size = homeFolderCover(
        w,
        wide: true,
        large: block.kind == HomePreviewBlockKind.largeFolders,
      );
      final columns = math.max(
        1,
        ((w + .001) / (size + 2 * homeAlbumInset)).floor(),
      );
      final rows = (count / columns).ceil();
      final tileHeight = size + caption + block.extraCaption;
      return (
        height: header + rows * tileHeight + (rows - 1) * 12,
        occupied: header * w + count * (size + 2 * homeAlbumInset) * tileHeight,
        utility: 0, // All alternatives show all pins, so no sampling reward.
      );
    }
    final album = homeAlbumLayout(
      width: w,
      captionExtent: caption,
      count: count,
      wide: true,
      large: block.kind == HomePreviewBlockKind.collage,
    );
    final collage = album.arrangement == HomeAlbumArrangement.collage;
    final height = collage ? album.leadCover + caption : album.cover + caption;
    final occupied = collage
        ? (album.leadCover + 2 * homeAlbumInset) * height +
              (album.count - 1) *
                  (album.cover + 2 * homeAlbumInset) *
                  (album.cover + caption)
        : album.count * (album.cover + 2 * homeAlbumInset) * height;
    return (
      height: header + height,
      occupied: header * w + occupied,
      utility: album.count * 28 * math.min(1, album.cover / 160),
    );
  });

  Iterable<List<double>> widths(List<List<int>> columns) sync* {
    final available = width - (columns.length - 1) * homePreviewColumnGap;
    final minima = [for (final c in columns) c.map(minimum).reduce(math.max)];
    if (minima.reduce((a, b) => a + b) > available) return;
    final equal = available / columns.length;
    if (minima.every((m) => m <= equal)) {
      yield List.filled(columns.length, equal);
    }
    // Match cover sizes across unequal columns where possible.
    final weights = [for (final c in columns) c.any(large) ? 4.0 : 3.0];
    final fixed = [
      for (final c in columns) c.any(large) ? collageFixed : 6 * homeAlbumInset,
    ];
    final cover =
        (available - fixed.reduce((a, b) => a + b)) /
        weights.reduce((a, b) => a + b);
    final shared = [
      for (var c = 0; c < columns.length; c++) weights[c] * cover + fixed[c],
    ];
    if (List.generate(
      columns.length,
      (c) => shared[c] >= minima[c],
    ).every((v) => v)) {
      yield shared;
    }
    // Reserve enough width for a short folder run before assigning remaining
    // space to catalogues with more albums. This avoids unnecessary wrapping.
    final natural = [
      for (final c in columns)
        c
            .map(
              (i) => folderCards(i)
                  ? blocks[i].count *
                        (2 * homeAlbumInset +
                            (blocks[i].kind == HomePreviewBlockKind.largeFolders
                                ? homeAlbumLargeCover
                                : homeAlbumOrdinaryCover))
                  : large(i)
                  ? 4 * 160 + collageFixed
                  : 3 * (160 + 2 * homeAlbumInset),
            )
            .reduce(math.max),
    ];
    final extra = available - minima.reduce((a, b) => a + b);
    final wants = [
      for (var c = 0; c < columns.length; c++)
        math.max(1.0, natural[c] - minima[c]),
    ];
    final total = wants.reduce((a, b) => a + b);
    yield [
      for (var c = 0; c < columns.length; c++)
        minima[c] + extra * wants[c] / total,
    ];
  }

  _Candidate candidate(List<List<int>> columns, List<double> sizes, int next) {
    var height = 0.0;
    var occupied = 0.0;
    var utility = 0.0;
    for (var c = 0; c < columns.length; c++) {
      var columnHeight = 0.0;
      for (final i in columns[c]) {
        final e = extent(i, sizes[c]);
        columnHeight += e.height;
        occupied += e.occupied;
        utility += e.utility;
      }
      height = math.max(height, columnHeight);
    }
    final empty = math.max(0.0, width * height - occupied) / width;
    return (
      row: HomePreviewRow([
        for (var c = 0; c < columns.length; c++)
          HomePreviewColumn(sizes[c], columns[c]),
      ]),
      next: next,
      // Minimise scrolling and blank area while rewarding additional readable
      // catalogue covers. The reward is bounded by the actual preview capacity.
      cost: height + .8 * empty - utility,
    );
  }

  Iterable<_Candidate> candidates(int start) sync* {
    if (!adaptive(start)) {
      var next = start + 1;
      final shortcuts = blocks[start].kind == HomePreviewBlockKind.shortcut;
      while (shortcuts &&
          next < blocks.length &&
          blocks[next].kind == blocks[start].kind) {
        next++;
      }
      yield (
        row: HomePreviewRow([
          HomePreviewColumn(width, [for (var i = start; i < next; i++) i]),
        ], shortcuts: shortcuts),
        next: next,
        cost: 0,
      );
      return;
    }
    yield candidate(
      [
        [start],
      ],
      [width],
      start + 1,
    );
    for (var count = 2; count <= maxColumns; count++) {
      final end = start + count;
      if (!adaptive(end - 1)) break;
      final columns = [
        for (var i = start; i < end; i++) [i],
      ];
      for (final sizes in widths(columns)) {
        yield candidate(columns, sizes, end);
      }
      if (!columns.any((c) => large(c.first))) continue;
      // Read across the first line, then across the second. This keeps the
      // established folder / Qobuz / artist arrangement without crossing pins.
      var next = end;
      for (final column in columns) {
        if (large(column.first)) continue;
        if (!adaptive(next) || large(next)) break;
        column.add(next++);
        for (final sizes in widths(columns)) {
          yield candidate(columns, sizes, next);
        }
      }
    }
  }

  final costs = List.filled(blocks.length + 1, 0.0);
  final choices = <int, _Candidate>{};
  for (var i = blocks.length - 1; i >= 0; i--) {
    var best = double.infinity;
    for (final option in candidates(i)) {
      final cost = option.cost + costs[option.next];
      if (cost < best - .001) {
        best = cost;
        choices[i] = option;
      }
    }
    costs[i] = best;
  }
  final rows = <HomePreviewRow>[];
  for (var i = 0; i < blocks.length;) {
    final choice = choices[i]!;
    rows.add(choice.row);
    i = choice.next;
  }
  return HomeSectionLayout(true, rows);
}
