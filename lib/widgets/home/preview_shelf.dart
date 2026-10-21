import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/kalinka_player_api_provider.dart';
import '../../providers/toast_provider.dart';
import '../../providers/url_resolver.dart';
import '../../theme/app_theme.dart';
import '../browse_rows_shimmer.dart';
import '../loading_shimmer.dart';
import '../procedural_album_art.dart';
import '../search/search_zero_state.dart' show kHomeSideInset;
import '../search_cards/browse_item_rows.dart';
import '../search_cards/track_row_support.dart' show CornerGlyph;
import '../tap_highlight.dart' show kalinkaOverlay;

/// A catalog's preview, drawn the way its source asked: `image` as square
/// tiles with their text underneath, in rows that scroll sideways; any other
/// type as the usual rows.
class PreviewShelf extends StatelessWidget {
  final List<BrowseItem> items;
  final Preview? preview;

  /// Names the shelf's sideways scroll, so it comes back where it was left.
  final String storageId;

  /// Opens a browsable item as a page of its own.
  final ValueChanged<BrowseItem> onOpenItem;

  const PreviewShelf({
    super.key,
    required this.items,
    required this.preview,
    required this.storageId,
    required this.onOpenItem,
  });

  @override
  Widget build(BuildContext context) {
    if (preview?.type != PreviewType.imageText) {
      return BrowseItemRows(items: items);
    }
    return _TileRail(
      count: items.length,
      rows: _rowsOf(preview),
      tileSize: _tileSizeOf(preview),
      storageId: storageId,
      tile: (i, size) => _Tile(item: items[i], size: size, onOpen: onOpenItem),
    );
  }

  static int _rowsOf(Preview? preview) => (preview?.rowsCount ?? 1).clamp(1, 3);

  static double _tileSizeOf(Preview? preview) =>
      preview?.cardSize == CardSize.large ? 168 : 128;
}

/// Stands in for a [PreviewShelf] while its items load, in the shape they
/// will take. It does not scroll.
class PreviewShelfShimmer extends StatelessWidget {
  final Preview? preview;

  const PreviewShelfShimmer({super.key, required this.preview});

  @override
  Widget build(BuildContext context) {
    final count = preview?.itemsCount ?? 3;
    if (preview?.type != PreviewType.imageText) {
      return BrowseRowsShimmer(count: count.clamp(1, 5));
    }
    return ExcludeSemantics(
      child: ShimmerPulse(
        child: _TileRail(
          count: count,
          rows: PreviewShelf._rowsOf(preview),
          tileSize: PreviewShelf._tileSizeOf(preview),
          scrollable: false,
          storageId: 'placeholder',
          tile: (_, size) => _TilePlaceholder(size: size),
        ),
      ),
    );
  }
}

class _TileRail extends StatelessWidget {
  final int count;
  final int rows;

  /// The tile's size on a phone; wider screens scale it up to 1.768 times
  /// that.
  final double tileSize;
  final Widget Function(int index, double size) tile;
  final bool scrollable;
  final String storageId;

  const _TileRail({
    required this.count,
    required this.rows,
    required this.tileSize,
    required this.tile,
    required this.storageId,
    this.scrollable = true,
  });

  /// Content width at which tiles show at [tileSize]. Above it, cards grow
  /// at half the proportional rate of the available width.
  static const _phoneWidth = 400.0;
  static const _widthGrowth = 0.5;

  /// The art, then a line each of title and subtitle at the user's text size.
  double _tileHeight(BuildContext context, double tileSize) {
    final scaler = MediaQuery.textScalerOf(context);
    // Merged as Text merges it, so the measure is the line it will draw.
    final base = DefaultTextStyle.of(context).style;
    double line(TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: 'Ag', style: base.merge(style)),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final height = painter.height;
      painter.dispose();
      return height;
    }

    return (2 * _Tile.inset +
            tileSize +
            _Tile.artGap +
            line(_Tile.titleStyle) +
            line(_Tile.subtitleStyle))
        .ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final columns = (count / rows).ceil();
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale =
            1 + (constraints.maxWidth / _phoneWidth - 1) * _widthGrowth;
        final size = (tileSize * scale).clamp(tileSize, tileSize * 1.768);
        final tileHeight = _tileHeight(context, size);
        final width = constraints.maxWidth + 2 * kHomeSideInset;
        // The height first: an OverflowBox fills what it is offered, and a
        // list offers unbounded height.
        return SizedBox(
          height: rows * tileHeight,
          // Out to the window's edges, so tiles scroll off them rather than
          // stopping short at the list's inset; the first still lines up.
          child: OverflowBox(
            minWidth: width,
            maxWidth: width,
            child: ScrollConfiguration(
              // A mouse can drag it too; the wheel keeps scrolling the page.
              behavior: ScrollConfiguration.of(context)
                  .copyWith(dragDevices: PointerDeviceKind.values.toSet()),
              // Frames abut, so two highlighted side by side meet exactly;
              // the art keeps two insets apart.
              child: ListView.builder(
                // Its own key: without one it would take Home's vertical
                // offset as its own when it scrolls back into view.
                key: PageStorageKey<String>('rail:$storageId'),
                scrollDirection: Axis.horizontal,
                physics: scrollable
                    ? null
                    : const NeverScrollableScrollPhysics(),
                // The first tile's art, not its frame, lines up with the
                // list's inset.
                padding: const EdgeInsets.symmetric(
                  horizontal: kHomeSideInset - _Tile.inset,
                ),
                itemCount: columns,
                itemBuilder: (context, column) => Column(
                  children: [
                    for (var row = 0; row < rows; row++)
                      if (column * rows + row < count)
                        tile(column * rows + row, size),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A tile's art and its two lines, as grey blocks.
class _TilePlaceholder extends StatelessWidget {
  final double size;

  const _TilePlaceholder({required this.size});

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    Widget bar(double width, double fontSize) =>
        ShimmerBlock(width: width, height: scaler.scale(fontSize), radius: 4);
    return Padding(
      padding: const EdgeInsets.all(_Tile.inset),
      child: SizedBox(
        width: size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShimmerBlock(width: size, height: size, radius: 8),
            const SizedBox(height: _Tile.artGap + 3),
            bar(size * 0.75, 11),
            const SizedBox(height: 6),
            bar(size * 0.5, 9),
          ],
        ),
      ),
    );
  }
}

/// Art above, title and a line on what it is below. A track plays; anything
/// browsable opens. Under the pointer, held or focused, the whole card is
/// lifted and outlined.
class _Tile extends ConsumerStatefulWidget {
  final BrowseItem item;
  final double size;
  final ValueChanged<BrowseItem> onOpen;

  const _Tile({required this.item, required this.size, required this.onOpen});

  /// Between the card's frame and its art and text: half the room between
  /// two cards' art.
  static const inset = kKalinkaFrameInset;
  static const artGap = 8.0;
  static final titleStyle = KalinkaTextStyles.trackRowTitle;
  static final subtitleStyle = KalinkaTextStyles.trackRowSubtitle;

  @override
  ConsumerState<_Tile> createState() => _TileState();
}

class _TileState extends ConsumerState<_Tile> {
  /// Concentric with the art's corners, a frame's inset out.
  static final _frame = BorderRadius.circular(8 + _Tile.inset);

  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  BrowseItem get item => widget.item;

  String get _title =>
      item.album?.title ??
      item.track?.title ??
      item.artist?.name ??
      item.name ??
      'Unknown';

  /// The kind badge on the art, as the list rows show it. Artists need none:
  /// their round art says it.
  IconData? get _kind {
    if (item.browseType == BrowseType.folder) return Icons.folder_outlined;
    if (item.album != null) return Icons.album_outlined;
    if (item.playlist != null) return Icons.queue_music;
    return null;
  }

  String get _subtitle {
    if (item.album != null) return item.album!.artist?.name ?? '';
    if (item.track != null) return item.track!.performer?.name ?? '';
    if (item.artist != null) return 'Artist';
    return item.subname ?? '';
  }

  Future<void> _play() async {
    final api = ref.read(kalinkaProxyProvider);
    final toast = ref.read(toastProvider.notifier);
    try {
      await api.replace([item.id]);
      // Index 0, as a track row plays it, beats a stale end-of-track event.
      await api.play(0);
    } catch (e) {
      toast.show('Failed to play: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final path =
        item.image?.large ?? item.image?.small ?? item.image?.thumbnail;
    final url = path == null ? null : ref.watch(urlResolverProvider).abs(path);
    final fallback = ProceduralAlbumArt(trackId: item.id, size: size);
    final art = url == null
        ? fallback
        : _TileArt(url: url, size: size, fallback: fallback);
    final isArtist = item.artist != null && item.album == null;
    final subtitle = _subtitle;
    final playable = item.track != null && !item.canBrowse;

    return Semantics(
      button: true,
      label: subtitle.isEmpty ? _title : '$_title, $subtitle',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: playable
              ? _play
              : item.canBrowse
              ? () => widget.onOpen(item)
              : null,
          onHover: (value) => setState(() => _hovered = value),
          onFocusChange: (value) => setState(() => _focused = value),
          onHighlightChanged: (value) => setState(() => _pressed = value),
          overlayColor: kalinkaOverlay,
          borderRadius: _frame,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: _frame,
              border: Border.all(
                color: _hovered || _focused || _pressed
                    ? KalinkaColors.borderDefault
                    : Colors.transparent,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(_Tile.inset),
              child: SizedBox(
                width: size,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    isArtist
                        ? ClipOval(child: art)
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: switch (_kind) {
                              null => art,
                              final kind => Stack(
                                children: [
                                  art,
                                  // Grows with the tile, from the rows' size on a
                                  // phone.
                                  PositionedDirectional(
                                    end: 6 * size / 128,
                                    bottom: 6 * size / 128,
                                    child: SizedBox.square(
                                      dimension: 16 * size / 128,
                                      child: FittedBox(
                                        child: CornerGlyph(kind),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            },
                          ),
                    const SizedBox(height: _Tile.artGap),
                    Text(
                      _title,
                      style: _Tile.titleStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: _Tile.subtitleStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tile's artwork. Resizing the window resizes the tile, so the decode
/// width moves in steps, and art already shown stays while the next size
/// loads instead of flashing back to a placeholder.
class _TileArt extends StatefulWidget {
  final String url;
  final double size;
  final Widget fallback;

  const _TileArt({
    required this.url,
    required this.size,
    required this.fallback,
  });

  @override
  State<_TileArt> createState() => _TileArtState();
}

class _TileArtState extends State<_TileArt> {
  static const _decodeStep = 64.0;

  bool _shown = false;

  @override
  void didUpdateWidget(_TileArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _shown = false;
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final decodeSize = (size / _decodeStep).ceil() * _decodeStep;
    return Image.network(
      widget.url,
      width: size,
      height: size,
      fit: BoxFit.cover,
      cacheWidth: (decodeSize * MediaQuery.devicePixelRatioOf(context)).round(),
      gaplessPlayback: true,
      frameBuilder: (_, child, frame, _) {
        if (frame != null) _shown = true;
        return _shown
            ? child
            : ShimmerPulse(
                child: ShimmerBlock(width: size, height: size),
              );
      },
      errorBuilder: (_, _, _) => widget.fallback,
    );
  }
}
