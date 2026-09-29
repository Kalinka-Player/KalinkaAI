import 'package:flutter/material.dart';

import '../procedural_album_art.dart';

/// The cover standing on a glossy floor, swinging aside cover-flow style
/// when the track changes: the old one turns away and recedes, the new one
/// turns in from the side playback moved towards.
class KioskCoverFlow extends StatelessWidget {
  final String trackId;
  final String? imageUrl;
  final double size;

  /// +1 when playback moved forward (the new cover comes in from the right),
  /// -1 when it went back.
  final int direction;

  /// False where the cover has something laid over its foot, which would
  /// hide a reflection anyway.
  final bool reflected;

  const KioskCoverFlow({
    super.key,
    required this.trackId,
    required this.imageUrl,
    required this.size,
    required this.direction,
    this.reflected = true,
  });

  /// Height the floor reflection adds under a cover of [size].
  // Kept short and faint: a hint of gloss, not a second cover.
  static double reflectionExtent(double size) => size * 0.09;

  @override
  Widget build(BuildContext context) {
    final key = ValueKey(trackId);
    return SizedBox(
      width: size,
      height: reflected ? size + reflectionExtent(size) : size,
      child: AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 950),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (current, previous) => Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [...previous, ?current],
        ),
        // A fresh closure each build makes the switcher re-wrap the outgoing
        // cover too, so it leaves towards the side opposite the newcomer.
        transitionBuilder: (child, animation) => _Swing(
          animation: animation,
          side: child.key == key ? direction : -direction,
          travel: size * 0.6,
          child: child,
        ),
        child: _ReflectedCover(
          key: key,
          trackId: trackId,
          imageUrl: imageUrl,
          size: size,
          reflected: reflected,
        ),
      ),
    );
  }
}

class _Swing extends StatelessWidget {
  final Animation<double> animation;
  final int side;
  final double travel;
  final Widget child;

  const _Swing({
    required this.animation,
    required this.side,
    required this.travel,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        // 0 at rest, 1 fully aside.
        final away = 1.0 - animation.value;
        if (away == 0) return child!;
        final transform = Matrix4.identity()
          ..setEntry(3, 2, 0.0011)
          ..multiply(
            Matrix4.translationValues(side * away * travel, 0, away * travel),
          )
          // Faces the centre, as the covers flanking a cover flow do.
          ..multiply(Matrix4.rotationY(side * away * 1.05));
        return Opacity(
          opacity: (1.0 - away * 1.4).clamp(0.0, 1.0),
          child: Transform(
            alignment: Alignment.center,
            transform: transform,
            child: child,
          ),
        );
      },
    );
  }
}

class _ReflectedCover extends StatelessWidget {
  final String trackId;
  final String? imageUrl;
  final double size;
  final bool reflected;

  const _ReflectedCover({
    super.key,
    required this.trackId,
    required this.imageUrl,
    required this.size,
    required this.reflected,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.035);
    final reflection = KioskCoverFlow.reflectionExtent(size);
    final gap = size * 0.012;
    // One decode serves the cover and its reflection: same provider, same
    // size, same cache entry.
    final cacheWidth = (size * MediaQuery.devicePixelRatioOf(context)).round();
    Widget art() => ClipRRect(
      borderRadius: radius,
      child: imageUrl == null
          ? ProceduralAlbumArt(trackId: trackId, size: size)
          : Image.network(
              imageUrl!,
              width: size,
              height: size,
              cacheWidth: cacheWidth,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) =>
                  ProceduralAlbumArt(trackId: trackId, size: size),
            ),
    );

    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: size * 0.12,
                  offset: Offset(0, size * 0.05),
                ),
              ],
            ),
            child: SizedBox.square(dimension: size, child: art()),
          ),
          if (reflected) ...[
            SizedBox(height: gap),
            ExcludeSemantics(
              child: ClipRect(
                child: SizedBox(
                  width: size,
                  height: reflection - gap,
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: size,
                    maxHeight: size,
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (bounds) => LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: const [Color(0x26FFFFFF), Color(0x00FFFFFF)],
                        stops: [0.0, reflection / size],
                      ).createShader(bounds),
                      child: Transform.flip(flipY: true, child: art()),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
