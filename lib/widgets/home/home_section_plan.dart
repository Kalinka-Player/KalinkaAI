import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'home_preview_layout.dart';

enum HomePreviewBlockKind {
  shortcut,
  standalone,
  ordinary,
  // Ordinary artwork that may grow into spare space beside a Large preview.
  automatic,
  collage,
  folders,
  largeFolders,
  tracks,
  shortTracks,
  longTracks;

  int? get listRowsPerColumn => switch (this) {
    tracks => homePreviewRowCount(wide: true),
    shortTracks => homePreviewRowCount(wide: true, small: true),
    longTracks => homePreviewRowCount(wide: true, large: true),
    _ => null,
  };
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
  // Single/pair Large previews share a neighbouring collage's lead size.
  final double largeCover;
  final Set<int> promotedBlocks;
  // Automatic lists fit three or four rows against neighbouring content.
  final Map<int, int> automaticListRows;
  HomePreviewRow(
    List<HomePreviewColumn> columns, {
    this.shortcuts = false,
    this.largeCover = homeAlbumLargeCover,
    this.promotedBlocks = const {},
    Map<int, int> automaticListRows = const {},
  }) : columns = List.unmodifiable(columns),
       automaticListRows = Map.unmodifiable(automaticListRows);
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
  final collageFixed = caption + 6 * homeAlbumInset;
  final maxColumns = math.min(
    6,
    math.max(2, ((width + 32) / (520 * request.textScale + 32)).floor()),
  );
  final extents = <(int, double, double, bool, int?), _Extent>{};

  bool adaptive(int i) =>
      i < blocks.length &&
      blocks[i].kind != HomePreviewBlockKind.shortcut &&
      blocks[i].kind != HomePreviewBlockKind.standalone;
  bool large(int i) =>
      blocks[i].kind == HomePreviewBlockKind.collage && blocks[i].count >= 3;
  bool folderCards(int i) =>
      blocks[i].kind == HomePreviewBlockKind.folders ||
      blocks[i].kind == HomePreviewBlockKind.largeFolders;
  double minimum(int i) => blocks[i].kind.listRowsPerColumn != null
      ? homeListMinimumColumnWidth * request.textScale
      : blocks[i].kind == HomePreviewBlockKind.largeFolders
      ? homeAlbumLargeCover + 2 * homeAlbumInset
      : blocks[i].kind == HomePreviewBlockKind.collage && blocks[i].count <= 2
      ? math.max(1, blocks[i].count) *
            (homeAlbumMinimumLargeCover + 2 * homeAlbumInset)
      : large(i)
      ? (blocks[i].count >= 4 ? 4 : 3) * homeAlbumMinimumCover +
            caption +
            (blocks[i].count >= 4 ? 6 : 4) * homeAlbumInset
      : math.min(2, math.max(1, blocks[i].count)) *
            (homeAlbumMinimumCover + 2 * homeAlbumInset);

  _Extent extent(
    int i,
    double w,
    double largeCover, {
    bool promote = false,
    int? listRows,
  }) => extents.putIfAbsent((i, w, largeCover, promote, listRows), () {
    final block = blocks[i];
    final count = block.count;
    if (count == 0) {
      final height = header + 24;
      return (height: height, occupied: height * w, utility: 0);
    }
    if (block.kind.listRowsPerColumn case final int rowsPerColumn) {
      final list = homeListLayout(
        width: w,
        count: count,
        rowsPerColumn: listRows ?? rowsPerColumn,
        textScale: request.textScale,
      );
      // Track artwork (44), vertical padding (16), and inter-row divider (14).
      // Include the separators when comparing a list with album-card height.
      final rowHeight = 74 * request.textScale;
      final trailingGap = 14 * request.textScale;
      return (
        height: header + list.rows * rowHeight - trailingGap,
        occupied:
            header * w +
            (list.count * rowHeight - list.columns * trailingGap) *
                list.columnWidth,
        utility: 0,
      );
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
      large: promote || block.kind == HomePreviewBlockKind.collage,
      largeCover: largeCover,
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
    double? leadCover;
    for (var c = 0; c < columns.length; c++) {
      for (final i in columns[c].where(large)) {
        final album = homeAlbumLayout(
          width: sizes[c],
          captionExtent: caption,
          count: blocks[i].count,
          wide: true,
          large: true,
        );
        if (album.arrangement == HomeAlbumArrangement.collage) {
          leadCover = math.max(leadCover ?? 0, album.leadCover);
        }
      }
    }
    final largeCover = leadCover ?? homeAlbumLargeCover;
    double columnHeight(int c, Map<int, int> listRows) => columns[c].fold(
      0.0,
      (height, i) =>
          height +
          extent(i, sizes[c], largeCover, listRows: listRows[i]).height,
    );
    final automaticLists = [
      for (var c = 0; c < columns.length; c++)
        columns[c]
            .where(
              (i) =>
                  blocks[i].kind == HomePreviewBlockKind.tracks &&
                  blocks[i].count >
                      homeListCapacity(
                        sizes[c],
                        rowsPerColumn: homePreviewRowCount(
                          wide: true,
                          small: true,
                        ),
                        textScale: request.textScale,
                      ),
            )
            .toList(),
    ];
    // Use columns with a fixed content height as the reference, including
    // lists too short for a fourth row. Without a reference, Automatic lists
    // keep the four-row default rather than causing each other to shrink.
    final neighbours = [
      for (var c = 0; c < columns.length; c++)
        if (automaticLists[c].isEmpty) columnHeight(c, const {}),
    ];
    final listRows = <int, int>{};
    if (neighbours.isNotEmpty) {
      final target = neighbours.reduce(math.max);
      for (var c = 0; c < columns.length; c++) {
        final indices = automaticLists[c];
        if (indices.isEmpty) continue;
        var distance = double.infinity;
        var best = <int, int>{};
        // Templates stack at most two sections per column: at most four
        // combinations, evaluated together so stacked lists share the space.
        for (var mask = 0; mask < (1 << indices.length); mask++) {
          final option = {
            for (var j = 0; j < indices.length; j++)
              indices[j]: homePreviewRowCount(
                wide: true,
                small: mask & (1 << j) != 0,
              ),
          };
          final gap = (columnHeight(c, option) - target).abs();
          // Try four first to retain more items when either length fits equally.
          if (gap < distance - .001) {
            distance = gap;
            best = option;
          }
        }
        listRows.addAll(best);
      }
    }
    var height = 0.0;
    var occupied = 0.0;
    var utility = 0.0;
    for (var c = 0; c < columns.length; c++) {
      var columnHeight = 0.0;
      for (final i in columns[c]) {
        final e = extent(i, sizes[c], largeCover, listRows: listRows[i]);
        columnHeight += e.height;
        occupied += e.occupied;
        utility += e.utility;
      }
      height = math.max(height, columnHeight);
    }
    final empty = math.max(0.0, width * height - occupied) / width;
    return (
      row: HomePreviewRow(
        [
          for (var c = 0; c < columns.length; c++)
            HomePreviewColumn(sizes[c], columns[c]),
        ],
        largeCover: largeCover,
        automaticListRows: listRows,
      ),
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
  // Fill spare height only after choosing rows. This adds a linear pass over
  // the selected blocks, not another set of alternatives to the row search.
  HomePreviewRow fillSpareSpace(HomePreviewRow row) {
    if (row.columns.length < 2 ||
        !row.columns
            .expand((c) => c.blocks)
            .any((i) => blocks[i].kind == HomePreviewBlockKind.collage)) {
      return row;
    }
    final heights = [
      for (final column in row.columns)
        column.blocks.fold<double>(
          0,
          (height, i) =>
              height +
              extent(
                i,
                column.width,
                row.largeCover,
                listRows: row.automaticListRows[i],
              ).height,
        ),
    ];
    final height = heights.reduce(math.max);
    final promoted = <int>{};
    for (var c = 0; c < row.columns.length; c++) {
      final column = row.columns[c];
      for (final i in column.blocks) {
        if (blocks[i].kind != HomePreviewBlockKind.automatic ||
            blocks[i].count == 0) {
          continue;
        }
        HomeAlbumLayout artwork(bool large) => homeAlbumLayout(
          width: column.width,
          captionExtent: caption,
          count: blocks[i].count,
          wide: true,
          large: large,
          largeCover: row.largeCover,
        );
        // Never trade visible items for a larger cover in Automatic mode.
        if (artwork(true).count < artwork(false).count) continue;
        final ordinary = extent(i, column.width, row.largeCover);
        final enlarged = extent(i, column.width, row.largeCover, promote: true);
        final growth = enlarged.height - ordinary.height;
        if (enlarged.occupied > ordinary.occupied &&
            heights[c] + growth <= height + .001) {
          promoted.add(i);
          heights[c] += growth;
        }
      }
    }
    if (promoted.isEmpty) return row;
    return HomePreviewRow(
      row.columns,
      largeCover: row.largeCover,
      promotedBlocks: Set.unmodifiable(promoted),
      automaticListRows: row.automaticListRows,
    );
  }

  final rows = <HomePreviewRow>[];
  for (var i = 0; i < blocks.length;) {
    final choice = choices[i]!;
    rows.add(fillSpareSpace(choice.row));
    i = choice.next;
  }
  return HomeSectionLayout(true, rows);
}
