import 'package:flutter/material.dart';

import '../procedural_album_art.dart';

/// The cover, swinging aside cover-flow style when the track changes: the
/// old one turns away and recedes, the new one turns in from the side
/// playback moved towards.
class KioskCoverFlow extends StatelessWidget {
  final String trackId;
  final String? imageUrl;
  final double size;

  /// +1 when playback moved forward (the new cover comes in from the right),
  /// -1 when it went back.
  final int direction;

  const KioskCoverFlow({
    super.key,
    required this.trackId,
    required this.imageUrl,
    required this.size,
    required this.direction,
  });

  @override
  Widget build(BuildContext context) {
    final key = ValueKey(trackId);
    return SizedBox.square(
      dimension: size,
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
        child: _Cover(
          key: key,
          trackId: trackId,
          imageUrl: imageUrl,
          size: size,
        ),
      ),
    );
  }
}

/// The cover filling the whole screen, for a display too small to set it
/// beside anything. A new track's cover fades in over the old one.
class KioskCoverFill extends StatelessWidget {
  final String trackId;
  final String? imageUrl;

  const KioskCoverFill({
    super.key,
    required this.trackId,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.longestSide;
        final url = imageUrl;
        Widget fallback() => FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: ProceduralAlbumArt(trackId: trackId, size: side),
        );
        return RepaintBoundary(
          child: AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 900),
            layoutBuilder: (current, previous) =>
                Stack(fit: StackFit.expand, children: [...previous, ?current]),
            child: KeyedSubtree(
              key: ValueKey(trackId),
              child: url == null
                  ? fallback()
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      cacheWidth:
                          (side * MediaQuery.devicePixelRatioOf(context))
                              .round(),
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => fallback(),
                    ),
            ),
          ),
        );
      },
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

class _Cover extends StatelessWidget {
  final String trackId;
  final String? imageUrl;
  final double size;

  const _Cover({
    super.key,
    required this.trackId,
    required this.imageUrl,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.03);
    final cacheWidth = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return RepaintBoundary(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: size * 0.08,
            ),
          ],
        ),
        // A hairline of light round the edge lifts the cover off a backdrop
        // made of its own colours.
        foregroundDecoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: ClipRRect(
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
        ),
      ),
    );
  }
}
