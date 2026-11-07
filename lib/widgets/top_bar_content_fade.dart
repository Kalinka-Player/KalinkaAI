import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Fades the content itself, exposing the unchanged background behind it.
/// Opacity is (y / extent)² within the toolbar and system inset, and 100%
/// below them. The host paints its controls outside this mask.
class TopBarContentFade extends SingleChildRenderObjectWidget {
  final double extent;

  const TopBarContentFade({
    super.key,
    required this.extent,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTopBarContentFade(extent);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderTopBarContentFade).extent = extent;
  }
}

class _RenderTopBarContentFade extends RenderProxyBox {
  _RenderTopBarContentFade(this._extent);

  double _extent;
  set extent(double value) {
    if (_extent == value) return;
    _extent = value;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => _extent > 0 && child != null;

  @override
  ShaderMaskLayer? get layer => super.layer as ShaderMaskLayer?;

  @override
  void paint(PaintingContext context, Offset offset) {
    // Keep the subtree when fading is disabled, without an offscreen layer.
    if (_extent <= 0 || child == null) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    layer ??= ShaderMaskLayer();
    layer!
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          for (var i = 0; i <= 16; i++)
            Colors.white.withValues(alpha: (i / 16) * (i / 16)),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, _extent))
      ..maskRect = offset & size
      ..blendMode = BlendMode.dstIn;
    context.pushLayer(layer!, super.paint, offset);
  }

  // Only the toolbar's controls may receive taps in the faded region.
  @override
  bool hitTestSelf(Offset position) => position.dy < _extent;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      position.dy >= _extent &&
      super.hitTestChildren(result, position: position);
}
