import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart';
import '../providers/url_resolver.dart';
import '../theme/app_theme.dart';
import 'fitted_art.dart';

/// What a catalog's drawn card is made of, where the server has no art for
/// it: the title picks the colour, so a genre wears the same one in every
/// source, and the title with the description places the rings.
@immutable
class CatalogArtSeed {
  final Color key;
  final int geometry;

  const CatalogArtSeed._(this.key, this.geometry);

  factory CatalogArtSeed.of(String title, String? description) {
    final name = _normalised(title);
    return CatalogArtSeed._(
      keys[fnv1a(name) % keys.length],
      fnv1a('$name\u0000${_normalised(description ?? '')}'),
    );
  }

  /// Dark jewel tones at the server's key lightness. Wine sits well under the
  /// accent, so a card never reads as a crimson fill.
  static const keys = [
    Color(0xFF7A2433), // wine
    Color(0xFF6A2556), // plum
    Color(0xFF4A2D78), // violet
    Color(0xFF2C3A7E), // indigo
    Color(0xFF1E536E), // petrol
    Color(0xFF1B5C57), // teal
    Color(0xFF2B5B3A), // pine
    Color(0xFF5E5824), // olive
    Color(0xFF74471E), // amber
    Color(0xFF7A2F20), // rust
  ];

  static final _space = RegExp(r'\s+');

  static String _normalised(String text) =>
      text.trim().toLowerCase().replaceAll(_space, ' ');

  @override
  bool operator ==(Object other) =>
      other is CatalogArtSeed && other.key == key && other.geometry == geometry;

  @override
  int get hashCode => Object.hash(key, geometry);
}

/// 32-bit FNV-1a over UTF-8: the same on every platform, as
/// [String.hashCode] is not.
@visibleForTesting
int fnv1a(String text) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(text)) {
    hash = _mul32(hash ^ byte, 0x01000193);
  }
  return hash;
}

/// [a] × [b] mod 2³², exact where ints are doubles (the web).
int _mul32(int a, int b) =>
    ((a & 0xffff) * b + ((((a >>> 16) * b) & 0xffff) << 16)) & 0xffffffff;

class _Mulberry32 {
  int _state;

  _Mulberry32(this._state);

  double next() {
    _state = (_state + 0x6d2b79f5) & 0xffffffff;
    var t = _mul32(_state ^ (_state >>> 15), _state | 1);
    t ^= (t + _mul32(t ^ (t >>> 7), t | 61)) & 0xffffffff;
    return ((t ^ (t >>> 14)) & 0xffffffff) / 4294967296;
  }
}

double _smooth(double u) {
  final t = u.clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// The server's coverless art, drawn with gradient fills alone: a wash rising
/// to the key colour, concentric bands, a few satellites and, under a
/// caption, the left side held dark. Each soft edge is a gradient ramp where
/// the server blurs, so it costs no layer and no image.
class CatalogArtPainter extends CustomPainter {
  final CatalogArtSeed seed;
  final bool captioned;

  const CatalogArtPainter(this.seed, {this.captioned = false});

  static const _base = Color(0xFF101014);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final box = Offset.zero & size;
    canvas.save();
    canvas.clipRect(box);
    _paintWash(canvas, box);
    _paintRings(canvas, box);
    if (captioned) _paintHold(canvas, box);
    canvas.restore();
  }

  /// The server's diagonal t = (x/W + y/H) / 2: dark to 0.42, easing to the
  /// key at the far corner. Opaque, so it is the ground as well.
  void _paintWash(Canvas canvas, Rect box) {
    final w = box.width;
    final h = box.height;
    final k = 2 * w * h / (w * w + h * h);
    const stops = [0.0, 0.42, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0];
    final key = seed.key;
    canvas.drawRect(
      box,
      Paint()
        ..shader = ui.Gradient.linear(box.topLeft, Offset(h * k, w * k), [
          for (final s in stops)
            Color.lerp(
              _base,
              Color.from(
                alpha: 1,
                red: key.r * s,
                green: key.g * s,
                blue: key.b * s,
              ),
              _smooth((s - 0.42) / 0.58),
            )!,
        ], stops),
    );
  }

  void _paintRings(Canvas canvas, Rect box) {
    final random = _Mulberry32(seed.geometry);
    final h = box.height;
    final centre = Offset(
      box.width * (0.48 + random.next() * 0.42),
      h * (0.1 + random.next() * 0.8),
    );
    final maxRadius = h * (1.1 + random.next() * 0.9);
    final rings = 6 + (random.next() * 5).floor();
    final band = Color.lerp(seed.key, const Color(0xFFFFFFFF), 0.45)!;
    Color tone(int ring, [double strength = 1]) => ring.isOdd
        ? band.withValues(alpha: 0.13 * strength)
        : Color.fromRGBO(0, 0, 0, 0.118 * strength);

    // All the bands in one radial gradient; each edge ramps over 4% of the
    // height either side, as wide as the server's blur.
    final edge = 0.04 * h;
    final reach = maxRadius + edge;
    final soft = math.min(edge / reach, 0.45 / rings);
    final colors = [tone(1)];
    final stops = [0.0];
    for (var ring = 1; ring < rings; ring++) {
      final boundary = maxRadius * ring / rings / reach;
      colors.addAll([tone(ring), tone(ring + 1)]);
      stops.addAll([boundary - soft, boundary + soft]);
    }
    colors.addAll([tone(rings), tone(rings, 0)]);
    stops.addAll([maxRadius / reach - soft, 1]);
    canvas.drawRect(
      box,
      Paint()..shader = ui.Gradient.radial(centre, reach, colors, stops),
    );

    final dot = band.withValues(alpha: 0.16);
    final satellites = 2 + (random.next() * 3).floor();
    for (var i = 0; i < satellites; i++) {
      final angle = random.next() * 2 * math.pi;
      final distance = (0.5 + random.next() * 0.6) * maxRadius;
      final radius = h * (0.04 + random.next() * 0.07);
      final at = centre + Offset(math.cos(angle), math.sin(angle)) * distance;
      final outer = radius + edge;
      canvas.drawCircle(
        at,
        outer,
        Paint()
          ..shader = ui.Gradient.radial(
            at,
            outer,
            [dot, dot, dot.withValues(alpha: 0)],
            [0, math.max(0, (radius - edge) / outer), 1],
          ),
      );
    }
  }

  /// 92% dark to 0.38 of the width, eased out by 0.6, as the server holds it.
  void _paintHold(Canvas canvas, Rect box) {
    const stops = [0.0, 0.38, 0.435, 0.49, 0.545, 0.6, 1.0];
    canvas.drawRect(
      box,
      Paint()
        ..shader = ui.Gradient.linear(box.topLeft, box.topRight, [
          for (final x in stops)
            Color.fromRGBO(0, 0, 0, 0.92 * _smooth((0.6 - x) / 0.22)),
        ], stops),
    );
  }

  @override
  bool shouldRepaint(CatalogArtPainter oldDelegate) =>
      oldDelegate.seed != seed || oldDelegate.captioned != captioned;
}

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
  final String? description;

  final bool square;

  const CatalogArt({
    super.key,
    required this.artPath,
    required this.aspectRatio,
    required this.title,
    required this.description,
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
    final drawn = CustomPaint(
      painter: CatalogArtPainter(
        CatalogArtSeed.of(title, description),
        captioned: !square,
      ),
      child: const SizedBox.expand(),
    );
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
        return Stack(
          fit: StackFit.expand,
          children: [
            drawn,
            Positioned(
              right: margin,
              top: (size.height - height) / 2,
              width: width,
              height: height,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(height * 0.055),
                child: _image(
                  url,
                  size: Size(width, height),
                  ratio: ratio,
                  dpr: dpr,
                  placeholder: const SizedBox.shrink(),
                ),
              ),
            ),
          ],
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
      frameBuilder: (_, child, frame, _) => frame == null ? placeholder : child,
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
/// left, vertically centred. The card grows with its caption.
class CatalogCard extends StatelessWidget {
  final String? artPath;
  final double? aspectRatio;
  final String title;

  /// The catalog's own description, which the drawn card is seeded from.
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
    this.subtitle,
    this.leading,
    this.minScale = 1,
    this.maxLines,
  });

  /// The share of the card the caption may take: the side the art keeps
  /// dark.
  static const captionShare = 0.6;

  // Lifts the caption off bright spots of a source's own art.
  static const _captionShadows = [
    Shadow(color: Color(0x99000000), blurRadius: 8),
  ];

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
            ),
          ),
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
                                  style: KalinkaTextStyles.blockTitle.apply(
                                    fontSizeFactor: 0.85 * scale,
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
                              style: KalinkaTextStyles.trackRowSubtitle.apply(
                                fontSizeFactor: 0.85 * subtitleScale,
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
