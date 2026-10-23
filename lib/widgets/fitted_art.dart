import 'package:flutter/material.dart';

/// Whether an image of [aspectRatio], unstated a square, fills a box of
/// [shape]: covering it crops no more than a sliver.
bool fillsShape(double? aspectRatio, double shape) =>
    ((aspectRatio ?? 1) / shape - 1).abs() <= 0.05;

/// Whether an image of [aspectRatio], set whole in a box of [shape], meets the
/// box on its height, so is decoded by it.
bool fitsByHeight(double? aspectRatio, double shape) =>
    (aspectRatio ?? 1) < shape;

/// [url] softened to fill its box, under the same image set inside it whole.
/// Decoded a few pixels wide and stretched, it blurs without a blur pass or a
/// layer, and is darkened so the image over it stands apart.
class SoftImageFill extends StatelessWidget {
  final String url;

  const SoftImageFill({super.key, required this.url});

  /// Enough to keep the image's colours, few enough to blur when stretched.
  static const _decodeWidth = 24;

  @override
  Widget build(BuildContext context) => Image.network(
    url,
    fit: BoxFit.cover,
    cacheWidth: _decodeWidth,
    filterQuality: FilterQuality.medium,
    color: const Color(0x73000000),
    colorBlendMode: BlendMode.srcATop,
    gaplessPlayback: true,
    excludeFromSemantics: true,
    frameBuilder: (_, child, frame, _) =>
        frame == null ? const SizedBox.expand() : child,
    errorBuilder: (_, _, _) => const SizedBox.expand(),
  );
}
