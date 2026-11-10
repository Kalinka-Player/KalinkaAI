import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart' show RenderAbstractViewport;

import '../../data_model/data_model.dart';
import '../../utils/web_build_target.dart';
import '../loading_shimmer.dart';
import 'artwork_grid_card.dart';

/// Covers of about 180–220 across, more columns as the pane grows, never
/// narrower than a readable caption; [wide] art, a category's card or a
/// banner, about 220–340. A track keeps its row, which needs 68% more room
/// than a cover to read.
///
/// On wasm, CatalogCard locks a wide card's height to width/3 (see there),
/// so unlike a square cover it has no room to spare: below ~300 a 2-line
/// title plus subtitle no longer fits that fixed height and would clip.
/// Off wasm the card still grows with a tall caption, so the original,
/// looser minimum holds.
int artworkGridColumns(
  double width,
  double scale, {
  bool wide = false,
  bool tracks = false,
}) {
  // Each card is its cover with a frame inset either side.
  const frame = 2 * ArtworkGridCard.inset;
  final grow = tracks ? 1.68 : 1.0;
  final wideFitsFloor = wide && compiledToWasm ? 300 : 220;
  final wanted = (width / ((wide ? 340 : 220) * grow * scale + frame)).ceil();
  final fits = (width / ((wide ? wideFitsFloor : 140) * grow * scale + frame))
      .floor();
  return wanted.clamp(1, fits < 1 ? 1 : fits).clamp(1, 10);
}

/// Where a grid's covers will be, while they load.
class ArtworkGridShimmer extends StatelessWidget {
  final int columns;
  final int rows;

  /// Catalog cards: 3:1, their name on them.
  final bool catalogs;

  /// Other covers' shape, captioned under it.
  final double coverRatio;
  final bool round;
  final EdgeInsets padding;

  const ArtworkGridShimmer({
    super.key,
    required this.columns,
    required this.rows,
    this.catalogs = false,
    this.coverRatio = 1,
    this.round = false,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 0),
  });

  @override
  Widget build(BuildContext context) {
    return ShimmerPulse(
      child: Padding(
        padding: padding,
        child: Column(
          children: [
            for (var r = 0; r < rows; r++)
              Padding(
                padding: const EdgeInsets.only(bottom: 22),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var c = 0; c < columns; c++) ...[
                      if (c > 0) const SizedBox(width: 22),
                      Expanded(
                        child: catalogs
                            ? const AspectRatio(
                                aspectRatio: 3,
                                child: ShimmerBlock(radius: 10),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AspectRatio(
                                    aspectRatio: coverRatio,
                                    child: round
                                        ? const ClipOval(child: ShimmerBlock())
                                        : const ShimmerBlock(radius: 10),
                                  ),
                                  const SizedBox(height: 10),
                                  const FractionallySizedBox(
                                    widthFactor: 0.7,
                                    child: ShimmerBlock(height: 14, radius: 4),
                                  ),
                                  const SizedBox(height: 6),
                                  const FractionallySizedBox(
                                    widthFactor: 0.45,
                                    child: ShimmerBlock(height: 12, radius: 4),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Already-ranked search items, using the catalogue's cards and column sizes.
/// Build one row at a time so long result sets remain lazy, with captions
/// free to grow at larger text sizes.
class SliverArtworkGrid extends StatefulWidget {
  final List<BrowseItem> items;
  final bool loading;
  final bool artists;

  const SliverArtworkGrid({
    super.key,
    required this.items,
    this.loading = false,
    this.artists = false,
  });

  @override
  State<SliverArtworkGrid> createState() => _SliverArtworkGridState();
}

typedef _GridAnchor = ({String id, double offset});
typedef _GridMeasurement = ({
  String id,
  int index,
  double offset,
  double height,
  double rowHeight,
});

class _SliverArtworkGridState extends State<SliverArtworkGrid> {
  final _keys = <String, GlobalKey>{};
  late List<String> _ids;
  late Map<String, int> _indices;
  (double, TextScaler)? _layout;
  Widget? _sliver;
  int _columns = 1;
  ScrollPosition? _position;
  _GridAnchor? _anchor;
  _GridAnchor? _restoring;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    _indexItems();
  }

  void _indexItems() {
    _ids = [for (final item in widget.items) item.id];
    _indices = {for (final (i, id) in _ids.indexed) id: i};
  }

  @override
  void didUpdateWidget(SliverArtworkGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Captions and artwork can change even when the result IDs do not.
    _sliver = null;
    final ids = [for (final item in widget.items) item.id];
    if (!listEquals(_ids, ids) || oldWidget.loading != widget.loading) {
      // A new query, filter or ranking is not a resize of the old results.
      _indexItems();
      _anchor = null;
      _restoring = null;
      _layout = null;
    }
  }

  List<_GridMeasurement> _measure() {
    final position = _position;
    if (position == null || !position.hasContentDimensions) return [];
    final measured = <_GridMeasurement>[];
    for (final entry in _keys.entries) {
      final box = entry.value.currentContext?.findRenderObject();
      final index = _indices[entry.key];
      if (index == null || box is! RenderBox || !box.attached || !box.hasSize) {
        continue;
      }
      final row = box.parent;
      measured.add((
        id: entry.key,
        index: index,
        offset: RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset,
        height: box.size.height,
        rowHeight: row is RenderBox && row.hasSize
            ? row.size.height
            : box.size.height,
      ));
    }
    measured.sort((a, b) => a.index.compareTo(b.index));
    return measured;
  }

  void _capture(List<_GridMeasurement> measured) {
    final position = _position!;
    final visible = measured.where(
      (item) =>
          item.offset + item.height > position.pixels &&
          item.offset < position.pixels + position.viewportDimension,
    );
    if (position.pixels <= 0 || visible.isEmpty) {
      _anchor = null;
      return;
    }
    final first = visible.first;
    // Keep the same member of the leading row across repeated resizes,
    // even when the new row starts with a neighbouring item.
    final item =
        visible
            .where(
              (item) =>
                  item.id == _anchor?.id &&
                  (item.offset - first.offset).abs() < .5,
            )
            .firstOrNull ??
        first;
    _anchor = (id: item.id, offset: item.offset - position.pixels);
  }

  void _afterLayout() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || _position?.hasContentDimensions != true) return;
      final measured = _measure();
      final anchor = _restoring;
      final index = anchor == null ? null : _indices[anchor.id];
      if (anchor != null && index != null && measured.isNotEmpty) {
        // The old item may now be outside the lazy viewport. Approach its
        // row using a laid-out neighbour, then refine from its exact bounds
        // on the next frame. Never assume fixed caption or row heights.
        final nearest = measured.reduce(
          (a, b) => (a.index - index).abs() <= (b.index - index).abs() ? a : b,
        );
        final position = _position!;
        final target =
            (nearest.offset +
                    (index ~/ _columns - nearest.index ~/ _columns) *
                        nearest.rowHeight -
                    anchor.offset)
                .clamp(position.minScrollExtent, position.maxScrollExtent);
        if ((target - position.pixels).abs() > .5) {
          position.jumpTo(target);
          _afterLayout();
          return;
        }
      }
      _restoring = null;
      _capture(measured);
      _keys.removeWhere((_, key) => key.currentContext == null);
    });
  }

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      _position = Scrollable.of(context).position;
      final scale = MediaQuery.textScalerOf(context);
      final layout = (constraints.crossAxisExtent, scale);
      if (_layout != layout) {
        if (_layout != null) _restoring ??= _anchor;
        _sliver = null;
      }
      _layout = layout;
      final columns = artworkGridColumns(
        constraints.crossAxisExtent,
        scale.scale(16) / 16,
      );
      _columns = columns;
      _afterLayout();
      // Scroll offsets also change the sliver constraints. Keep the same
      // child in that case so scrolling only lays out rows; rebuilding every
      // visible card is needed only when its data or layout changes.
      if (widget.loading) {
        return _sliver ??= SliverToBoxAdapter(
          child: ArtworkGridShimmer(
            columns: columns,
            rows: 2,
            round: widget.artists,
            padding: const EdgeInsets.fromLTRB(
              ArtworkGridCard.inset,
              ArtworkGridCard.inset,
              ArtworkGridCard.inset,
              0,
            ),
          ),
        );
      }
      return _sliver ??= SliverList.builder(
        itemCount: (widget.items.length / columns).ceil(),
        itemBuilder: (context, row) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var col = 0; col < columns; col++)
              Expanded(
                child: row * columns + col < widget.items.length
                    ? RepaintBoundary(
                        key: _keys.putIfAbsent(
                          widget.items[row * columns + col].id,
                          GlobalKey.new,
                        ),
                        child: ArtworkGridCard(
                          item: widget.items[row * columns + col],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
          ],
        ),
      );
    },
  );
}
