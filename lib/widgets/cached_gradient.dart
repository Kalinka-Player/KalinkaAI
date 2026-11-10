import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A centred, transparent-edged radial gradient painted from a small texture.
/// Its transform still controls the exact position and elliptical shape. The
/// texture is independent of the box size, so scrolling and resizing reuse it.
class CachedRadialGradientDecoration extends BoxDecoration {
  CachedRadialGradientDecoration({required RadialGradient gradient})
    : assert(gradient.center == Alignment.center),
      assert(gradient.radius == .5),
      assert(gradient.focal == null),
      assert(gradient.tileMode == TileMode.clamp),
      assert(gradient.colors.last.a == 0),
      super(gradient: gradient);

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _CachedGradientPainter(gradient!, onChanged);
}

/// A vertical gradient whose sampled colours can be reused at any box size.
class CachedVerticalGradientDecoration extends BoxDecoration {
  CachedVerticalGradientDecoration({required LinearGradient gradient})
    : assert(gradient.begin == Alignment.topCenter),
      assert(gradient.end == Alignment.bottomCenter),
      assert(gradient.transform == null),
      assert(gradient.tileMode == TileMode.clamp),
      super(gradient: gradient);

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _CachedGradientPainter(gradient!, onChanged);
}

class _CachedGradientPainter extends BoxPainter {
  _CachedGradientPainter(this.gradient, super.onChanged);

  static const _resolution = 256;
  final Gradient gradient;
  final _paint = Paint()..filterQuality = FilterQuality.low;
  ui.Image? _image;

  int get _width => gradient is RadialGradient ? _resolution : 1;
  Rect get _source =>
      Rect.fromLTWH(0, 0, _width.toDouble(), _resolution.toDouble());

  ui.Image _rasterize() {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      _source,
      Paint()
        ..shader =
            (gradient is RadialGradient
                    ? RadialGradient(
                        colors: gradient.colors,
                        stops: gradient.stops,
                      )
                    : gradient)
                .createShader(_source),
    );
    final picture = recorder.endRecording();
    try {
      // Creates the handle synchronously; rasterization happens on the raster
      // thread. With a GPU context the result stays resident on the GPU.
      return picture.toImageSync(_width, _resolution);
    } finally {
      picture.dispose();
    }
  }

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size!;
    if (size.isEmpty) return;
    final bounds = offset & size;
    final transform = gradient.transform?.transform(
      bounds,
      textDirection: configuration.textDirection,
    );
    canvas.save();
    canvas.clipRect(bounds);
    if (transform != null) canvas.transform(transform.storage);
    canvas.drawImageRect(
      _image ??= _rasterize(),
      _source,
      gradient is RadialGradient
          ? Rect.fromCircle(
              center: bounds.center,
              radius: size.shortestSide / 2,
            )
          : bounds,
      _paint,
    );
    canvas.restore();
  }

  @override
  void dispose() {
    _image?.dispose();
    _image = null;
    super.dispose();
  }
}
