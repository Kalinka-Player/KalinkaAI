import 'package:flutter/material.dart';

import '../../utils/web_build_target.dart';
import '../procedural_album_art.dart';

/// The cover, swinging aside cover-flow style when the track changes: the
/// old one turns away and recedes, the new one turns in from the side
/// playback moved towards.
class KioskCoverFlow extends StatelessWidget {
  final String trackId;
  final String? imageUrl;
  final double size;

  /// Reveal the next cover inside the fixed frame on the local TV.
  final bool confined;

  /// +1 when playback moved forward (the new cover comes in from the right),
  /// -1 when it went back.
  final int direction;

  const KioskCoverFlow({
    super.key,
    required this.trackId,
    required this.imageUrl,
    required this.size,
    required this.direction,
    this.confined = false,
  });

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      // Keep the same image element so the decoded cover stays on screen
      // until its replacement arrives.
      return _Cover(trackId: trackId, imageUrl: imageUrl, size: size);
    }
    if (confined) {
      return _CoverWipe(
        art: (trackId: trackId, url: imageUrl),
        size: size,
        direction: direction,
      );
    }
    final key = ValueKey(trackId);
    return SizedBox.square(
      dimension: size,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 950),
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

typedef _Artwork = ({String trackId, String? url});

class _CoverWipe extends StatefulWidget {
  final _Artwork art;
  final double size;
  final int direction;

  const _CoverWipe({
    required this.art,
    required this.size,
    required this.direction,
  });

  @override
  State<_CoverWipe> createState() => _CoverWipeState();
}

class _CoverWipeState extends State<_CoverWipe>
    with SingleTickerProviderStateMixin {
  late _Artwork _current = widget.art;
  _Artwork? _previous;
  bool _fromRight = true;
  late final _progress =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 400),
        value: 1,
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && _previous != null) {
          setState(() => _previous = null);
        }
      });

  @override
  void didUpdateWidget(_CoverWipe old) {
    super.didUpdateWidget(old);
    if (widget.art != old.art) _showWhenReady(widget.art);
  }

  Future<void> _showWhenReady(_Artwork next) async {
    final url = next.url;
    var incoming = next;
    if (url != null && url != _current.url) {
      await precacheImage(
        _coverImage(url, widget.size, context),
        context,
        onError: (_, _) => incoming = (trackId: next.trackId, url: null),
      );
    }
    if (!mounted || widget.art != next || _current == incoming) return;
    // A quick second skip starts from whichever cover is more visible.
    final outgoing = _progress.value < 0.5 ? _previous ?? _current : _current;
    setState(() {
      _previous =
          (outgoing.url ?? outgoing.trackId) ==
              (incoming.url ?? incoming.trackId)
          ? null
          : outgoing;
      _current = incoming;
      _fromRight = widget.direction >= 0;
    });
    if (_previous == null) {
      _progress.value = 1;
    } else {
      _progress.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget part(_Artwork art, {required bool outgoing}) => ClipRect(
      key: ValueKey(art.url ?? art.trackId),
      clipper: _previous == null
          ? null
          : _WipeClip(_progress, _fromRight, outgoing),
      child: _Cover(trackId: art.trackId, imageUrl: art.url, size: widget.size),
    );
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_previous case final old?) part(old, outgoing: true),
            part(_current, outgoing: false),
          ],
        ),
      ),
    );
  }
}

/// Two complementary hard clips leave each pixel to just one opaque cover.
class _WipeClip extends CustomClipper<Rect> {
  final Animation<double> progress;
  final bool fromRight;
  final bool outgoing;

  _WipeClip(this.progress, this.fromRight, this.outgoing)
    : super(reclip: progress);

  @override
  Rect getClip(Size size) {
    final t = Curves.easeInOut.transform(progress.value);
    final edge = (fromRight ? 1 - t : t) * size.width;
    return outgoing == fromRight
        ? Rect.fromLTRB(0, 0, edge, size.height)
        : Rect.fromLTRB(edge, 0, size.width, size.height);
  }

  @override
  bool shouldReclip(_WipeClip old) =>
      old.progress != progress ||
      old.fromRight != fromRight ||
      old.outgoing != outgoing;
}

/// The cover filling the whole screen, for a display too small to set it
/// beside anything. Keep the old image until the new one is ready.
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
          child: url == null
              ? fallback()
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  cacheWidth: wasmSafeCacheSize(
                    (side * MediaQuery.devicePixelRatioOf(context)).round(),
                  ),
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => fallback(),
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
        final transform = Matrix4.identity();
        if (away > 0 && travel > 0) {
          // Scale the perspective with the cover. Receding into the screen
          // keeps even a TV-sized cover behind the projection plane.
          transform
            ..setEntry(3, 2, -0.3 / travel)
            ..translateByDouble(side * away * travel, 0, -away * travel, 1)
            ..rotateY(side * away * 1.05);
        }
        return Transform(
          alignment: Alignment.center,
          transform: transform,
          child: Opacity(
            opacity: (1.0 - away * 1.4).clamp(0.0, 1.0),
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
    return RepaintBoundary(
      child: Container(
        width: size,
        height: size,
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
              : Image(
                  image: _coverImage(imageUrl!, size, context),
                  width: size,
                  height: size,
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

ImageProvider _coverImage(String url, double size, BuildContext context) =>
    ResizeImage.resizeIfNeeded(
      wasmSafeCacheSize(
        (size * MediaQuery.devicePixelRatioOf(context)).round(),
      ),
      null,
      NetworkImage(url),
    );
