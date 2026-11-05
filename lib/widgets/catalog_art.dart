import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart';
import '../providers/url_resolver.dart';
import '../theme/app_theme.dart';
import 'catalog_art_background.dart';
import 'fitted_art.dart';

export 'catalog_art_background.dart';

/// A catalog's art, filling its box: a card, with its left side held dark for
/// a caption, or a [square] for a row or a tile. On a card, art shaped like
/// the server's 3:1 card covers it, and any other shape sits on the right of
/// a drawn card, as album covers sit on the server's. A square covers itself
/// with the catalog's thumbnail. The drawn art stands in until an image
/// arrives, and for good where there is none.
class CatalogArt extends ConsumerWidget {
  final String? artPath;

  /// Width over height of the catalog's card art, its large image. Unstated,
  /// it is taken for a square.
  final double? aspectRatio;

  /// What the drawn art is seeded from.
  final String title;
  final String entityId;
  final String? description;

  final bool square;

  const CatalogArt({
    super.key,
    required this.artPath,
    required this.aspectRatio,
    required this.title,
    required this.description,
    this.entityId = '',
    this.square = false,
  });

  /// [item]'s art: its thumbnail for a [square], else its large image.
  factory CatalogArt.of(BrowseItem item, {Key? key, bool square = false}) {
    final image = item.image;
    return CatalogArt(
      key: key,
      artPath: square
          ? image?.thumbnail ?? image?.small ?? image?.large
          : image?.large ?? image?.small ?? image?.thumbnail,
      aspectRatio: image?.aspectRatio,
      title: item.catalog?.title ?? item.name ?? 'Catalog',
      description: item.description,
      entityId: item.id,
      square: square,
    );
  }

  /// A catalog card's shape.
  static const cardRatio = 3.0;

  /// Art at least this wide for its height is card-shaped.
  static const cardShape = 2.0;

  /// An inset image's share of the card, leaving the caption its side.
  static const _insetRoom = 0.4;

  /// Where a square crops a card-shaped image, stated 2:1 or wider, across
  /// it: past the caption's side, over the art.
  static const _cropStart = 0.55;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seed = CatalogArtSeed.of(title, description, entityId: entityId);
    Widget background({bool questionMark = true}) => CustomPaint(
      painter: CatalogArtPainter(
        seed,
        questionMark: questionMark,
        captioned: !square,
      ),
      child: const SizedBox.expand(),
    );
    final drawn = background();
    final path = artPath;
    if (path == null || path.isEmpty) return drawn;
    final url = ref.watch(urlResolverProvider).abs(path);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final ratio = aspectRatio ?? 1;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size.isEmpty) return drawn;
        if (square || fillsShape(aspectRatio, cardRatio)) {
          return _image(
            url,
            size: size,
            ratio: ratio,
            dpr: dpr,
            placeholder: drawn,
            // Moves nothing unless the image is wider than its box.
            alignment: square && ratio >= cardShape
                ? _cropAlignment(size.aspectRatio / ratio)
                : Alignment.center,
          );
        }
        final margin = size.height * 0.12;
        var height = size.height - 2 * margin;
        var width = height * ratio;
        if (width > size.width * _insetRoom) {
          width = size.width * _insetRoom;
          height = width / ratio;
        }
        return _image(
          url,
          size: Size(width, height),
          ratio: ratio,
          dpr: dpr,
          placeholder: drawn,
          loadedBuilder: (image) => Stack(
            fit: StackFit.expand,
            children: [
              background(questionMark: false),
              Positioned(
                right: margin,
                top: (size.height - height) / 2,
                width: width,
                height: height,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(height * 0.055),
                  child: image,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Crops a card from [_cropStart] across, [visible] of its width wide.
  static Alignment _cropAlignment(double visible) => visible >= 1
      ? Alignment.center
      : Alignment((2 * _cropStart / (1 - visible) - 1).clamp(-1.0, 1.0), 0);

  static Widget _image(
    String url, {
    required Size size,
    required double ratio,
    required double dpr,
    required Widget placeholder,
    Alignment alignment = Alignment.center,
    Widget Function(Widget image)? loadedBuilder,
  }) {
    // Covering, the image meets the box on its tighter side; decoding in
    // steps lets a resize redraw without decoding again.
    int step(double logical) => ((logical * dpr) / 128).ceil() * 128;
    final byHeight = size.aspectRatio < ratio;
    return Image.network(
      url,
      width: size.width,
      height: size.height,
      fit: BoxFit.cover,
      alignment: alignment,
      cacheWidth: byHeight ? null : step(size.width),
      cacheHeight: byHeight ? step(size.height) : null,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      frameBuilder: (_, child, frame, _) =>
          frame == null ? placeholder : loadedBuilder?.call(child) ?? child,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}

/// A catalog's art as a square, as rows and rail tiles show it.
class CatalogThumb extends StatelessWidget {
  final BrowseItem item;
  final double size;
  final double radius;

  const CatalogThumb({
    super.key,
    required this.item,
    required this.size,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: SizedBox.square(
      dimension: size,
      child: CatalogArt.of(item, square: true),
    ),
  );
}

/// A catalog as a card: its art, never shorter than 3:1, with its name on the
/// left, vertically centred over a dark gradient. The card grows with its
/// caption.
class CatalogCard extends StatelessWidget {
  final String? artPath;
  final double? aspectRatio;
  final String title;
  final String entityId;

  /// Used as the background seed only when the title is empty.
  final String? description;

  /// What the caption says under the title.
  final String? subtitle;

  /// Before the title, sized to the caption's [scale].
  final Widget Function(double scale)? leading;

  /// How far the title may shrink on a card narrower than 400dp, as a share
  /// of its size there. The subtitle keeps its size.
  final double minScale;

  final int? maxLines;

  const CatalogCard({
    super.key,
    required this.artPath,
    required this.aspectRatio,
    required this.title,
    required this.description,
    this.entityId = '',
    this.subtitle,
    this.leading,
    this.minScale = 1,
    this.maxLines,
  });

  /// The share of the card the caption may take: the side the art keeps
  /// dark.
  static const captionShare = 0.6;

  // The caption's sizes on a 400dp card, in the styles album cards use. The
  // title stays well under a page title's, so a card never outweighs the
  // heading over it.
  static const _titleSize = KalinkaTypography.baseSize + 6;
  static const _subtitleSize = KalinkaTypography.baseSize + 2;

  // Lifts the caption off bright spots of a source's own art: a tight edge
  // round each glyph, and a softer one under it.
  static const _captionShadows = [
    Shadow(color: Color(0xCC000000), blurRadius: 3, offset: Offset(0, 1)),
    Shadow(color: Color(0x99000000), blurRadius: 10),
  ];

  /// Holds the caption's side dark where covers in the art run beneath it.
  static const _scrim = BoxDecoration(
    gradient: LinearGradient(
      colors: [
        Color(0xCC000000),
        Color(0xB3000000),
        Color(0x59000000),
        Color(0x00000000),
      ],
      stops: [0, 0.35, 0.55, 0.75],
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final scale = math.max(minScale, width / 400);
      final subtitleScale = math.max(1.0, width / 400);
      final subtitle = this.subtitle;
      return Stack(
        children: [
          Positioned.fill(
            child: CatalogArt(
              artPath: artPath,
              aspectRatio: aspectRatio,
              title: title,
              description: description,
              entityId: entityId,
            ),
          ),
          const Positioned.fill(child: DecoratedBox(decoration: _scrim)),
          SizedBox(
            width: width,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: width / CatalogArt.cardRatio,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: width * captionShare),
                    child: Padding(
                      padding: EdgeInsets.all(16 * scale),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (leading case final leading?) ...[
                                leading(scale),
                                SizedBox(width: 8 * scale),
                              ],
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: maxLines,
                                  overflow: maxLines == null
                                      ? null
                                      : TextOverflow.ellipsis,
                                  style: KalinkaTextStyles.trackRowTitle
                                      .copyWith(
                                        fontSize: _titleSize * scale,
                                        shadows: _captionShadows,
                                      ),
                                ),
                              ),
                            ],
                          ),
                          if (subtitle != null && subtitle.isNotEmpty) ...[
                            SizedBox(height: 4 * scale),
                            Text(
                              subtitle,
                              maxLines: maxLines,
                              overflow: maxLines == null
                                  ? null
                                  : TextOverflow.ellipsis,
                              style: KalinkaTextStyles.trackRowSubtitle
                                  .copyWith(
                                    fontSize: _subtitleSize * subtitleScale,
                                    shadows: _captionShadows,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}
