import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/kalinka_player_api_provider.dart';
import '../../providers/toast_provider.dart';
import '../../providers/url_resolver.dart';
import '../../theme/app_theme.dart';
import '../browse_rows_shimmer.dart';
import '../procedural_album_art.dart';
import '../search/search_zero_state.dart' show kHomeSideInset;
import '../search_cards/browse_item_rows.dart';

/// A catalog's preview, drawn the way its source asked: `image` as square
/// tiles with their text underneath, in rows that scroll sideways; any other
/// type as the usual rows.
class PreviewShelf extends StatelessWidget {
  final List<BrowseItem> items;
  final Preview? preview;

  /// Opens a browsable item as a page of its own.
  final ValueChanged<BrowseItem> onOpenItem;

  const PreviewShelf({
    super.key,
    required this.items,
    required this.preview,
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
      return BrowseRowsShimmer(count: count.clamp(1, 3));
    }
    return ExcludeSemantics(
      child: _Pulse(
        child: _TileRail(
          count: count,
          rows: PreviewShelf._rowsOf(preview),
          tileSize: PreviewShelf._tileSizeOf(preview),
          scrollable: false,
          tile: (_, size) => _TilePlaceholder(size: size),
        ),
      ),
    );
  }
}

class _TileRail extends StatelessWidget {
  final int count;
  final int rows;
  final double tileSize;
  final Widget Function(int index, double size) tile;
  final bool scrollable;

  const _TileRail({
    required this.count,
    required this.rows,
    required this.tileSize,
    required this.tile,
    this.scrollable = true,
  });

  static const _gap = 12.0;
  static const _rowGap = 16.0;

  /// The art, then a line each of title and subtitle at the user's text size.
  double _tileHeight(BuildContext context) {
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

    return (tileSize +
            _Tile.artGap +
            line(_Tile.titleStyle) +
            line(_Tile.subtitleStyle))
        .ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final columns = (count / rows).ceil();
    final tileHeight = _tileHeight(context);
    // The height first: an OverflowBox fills what it is offered, and a list
    // offers unbounded height.
    return SizedBox(
      height: rows * tileHeight + (rows - 1) * _rowGap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth + 2 * kHomeSideInset;
          // Out to the window's edges, so tiles scroll off them rather than
          // stopping short at the list's inset; the first still lines up.
          return OverflowBox(
            minWidth: width,
            maxWidth: width,
            child: ScrollConfiguration(
              // A mouse can drag it too; the wheel keeps scrolling the page.
              behavior: ScrollConfiguration.of(context)
                  .copyWith(dragDevices: PointerDeviceKind.values.toSet()),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: scrollable
                    ? null
                    : const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: kHomeSideInset),
                itemCount: columns,
                separatorBuilder: (_, _) => const SizedBox(width: _gap),
                itemBuilder: (context, column) => Column(
                  spacing: _rowGap,
                  children: [
                    for (var row = 0; row < rows; row++)
                      if (column * rows + row < count)
                        tile(column * rows + row, tileSize),
                  ],
                ),
              ),
            ),
          );
        },
      ),
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
    Widget bar(double width, double fontSize) => Container(
      width: width,
      height: scaler.scale(fontSize),
      decoration: BoxDecoration(
        color: KalinkaColors.surfaceOverlay,
        borderRadius: BorderRadius.circular(4),
      ),
    );
    return SizedBox(
      width: size,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: KalinkaColors.surfaceOverlay,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: _Tile.artGap + 3),
          bar(size * 0.75, 11),
          const SizedBox(height: 6),
          bar(size * 0.5, 9),
        ],
      ),
    );
  }
}

/// The opacity pulse every shimmer here shares.
class _Pulse extends StatefulWidget {
  final Widget child;

  const _Pulse({required this.child});

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  late final Animation<double> _opacity = Tween<double>(
    begin: 0.55,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _opacity, child: widget.child);
}

/// Art above, title and a line on what it is below. A track plays; anything
/// browsable opens.
class _Tile extends ConsumerWidget {
  final BrowseItem item;
  final double size;
  final ValueChanged<BrowseItem> onOpen;

  const _Tile({required this.item, required this.size, required this.onOpen});

  static const artGap = 8.0;
  static final titleStyle = KalinkaTextStyles.trackRowTitle;
  static final subtitleStyle = KalinkaTextStyles.trackRowSubtitle;

  String get _title =>
      item.album?.title ??
      item.track?.title ??
      item.artist?.name ??
      item.name ??
      'Unknown';

  String get _subtitle {
    if (item.album != null) return item.album!.artist?.name ?? '';
    if (item.track != null) return item.track!.performer?.name ?? '';
    if (item.artist != null) return 'Artist';
    return item.subname ?? '';
  }

  Future<void> _play(WidgetRef ref) async {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final path =
        item.image?.large ?? item.image?.small ?? item.image?.thumbnail;
    final url = path == null ? null : ref.watch(urlResolverProvider).abs(path);
    final fallback = ProceduralAlbumArt(trackId: item.id, size: size);
    final art = url == null
        ? fallback
        : Image.network(
            url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
            errorBuilder: (_, _, _) => fallback,
          );
    final isArtist = item.artist != null && item.album == null;
    final subtitle = _subtitle;
    final playable = item.track != null && !item.canBrowse;

    return Semantics(
      button: true,
      label: subtitle.isEmpty ? _title : '$_title, $subtitle',
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: playable
                ? () => _play(ref)
                : item.canBrowse
                ? () => onOpen(item)
                : null,
            borderRadius: BorderRadius.circular(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                isArtist
                    ? ClipOval(child: art)
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: art,
                      ),
                const SizedBox(height: artGap),
                Text(
                  _title,
                  style: titleStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: subtitleStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
