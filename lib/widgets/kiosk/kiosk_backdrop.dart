import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Full-bleed backdrop of the cover itself, blurred and zoomed in past its
/// edges.
///
/// The blur is drawn once per cover into a small image, which is then
/// stretched over the screen. A blur filter on the screen itself would be
/// re-run on every composited frame, which a streamer's GPU pays for while
/// the music plays.
class KioskBackdrop extends StatelessWidget {
  /// A small rendition of the cover.
  final String? imageUrl;

  const KioskBackdrop({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: KalinkaColors.background),
          AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 1400),
            layoutBuilder: (current, previous) =>
                Stack(fit: StackFit.expand, children: [...previous, ?current]),
            child: url == null
                ? const _Bloom(key: ValueKey('bloom'))
                : _BlurredCover(key: ValueKey(url), url: url),
          ),
          // Deeper at the top and foot, where the header and the last
          // controls sit, and at the sides, so the picture reads as lit from
          // behind the text.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x66080808),
                  Color(0x00080808),
                  Color(0x00080808),
                  Color(0x80080808),
                ],
                stops: [0.0, 0.25, 0.6, 1.0],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 1.1,
                colors: [Color(0x00080808), Color(0x4D080808)],
                stops: [0.55, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pixels on a side of the blurred cover. Stretched over the whole screen,
/// so the blur, not this, decides how soft it looks.
const _blurSide = 128;
const _blurSigma = 2.4;

class _BlurredCover extends StatefulWidget {
  final String url;

  const _BlurredCover({super.key, required this.url});

  @override
  State<_BlurredCover> createState() => _BlurredCoverState();
}

class _BlurredCoverState extends State<_BlurredCover> {
  ImageStream? _stream;
  late final _listener = ImageStreamListener(
    _onImage,
    onError: (_, _) {
      if (mounted) setState(() => _failed = true);
    },
  );
  ui.Image? _image;

  /// How light the cover is, 0 to 1: a pale cover is dimmed further, so the
  /// white text over it still reads.
  double _lightness = 0.5;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_stream != null) return;
    _stream = ResizeImage(
      NetworkImage(widget.url),
      width: _blurSide,
      height: _blurSide,
      policy: ResizeImagePolicy.fit,
    ).resolve(createLocalImageConfiguration(context))..addListener(_listener);
  }

  Future<void> _onImage(ImageInfo info, bool _) async {
    try {
      final (image, lightness) = await _blur(info.image);
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = image;
        _lightness = lightness;
      });
    } catch (_) {
      // A cover that cannot be drawn gets the bloom, not a blank backdrop.
      if (mounted && _image == null) setState(() => _failed = true);
    } finally {
      info.dispose();
    }
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const _Bloom();
    final image = _image;
    if (image == null) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: [
        Transform.scale(
          // Zoomed in: the blurred edges fall off-screen.
          scale: 1.25,
          child: RawImage(
            image: image,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
          ),
        ),
        ColoredBox(
          // Lightly over a dark cover, steeply more over a pale one.
          color: Colors.black.withValues(
            alpha: 0.14 + 0.66 * math.pow(_lightness, 1.6),
          ),
        ),
      ],
    );
  }
}

/// The centre square of [source], blurred, and how light it is.
Future<(ui.Image, double)> _blur(ui.Image source) async {
  const side = _blurSide;
  final w = source.width.toDouble();
  final h = source.height.toDouble();
  final crop = w < h ? w : h;
  final recorder = ui.PictureRecorder();
  final bounds = Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble());
  Canvas(recorder)
    ..saveLayer(
      bounds,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: _blurSigma,
          sigmaY: _blurSigma,
          tileMode: TileMode.clamp,
        ),
    )
    ..drawImageRect(
      source,
      Rect.fromCenter(center: Offset(w / 2, h / 2), width: crop, height: crop),
      bounds,
      Paint()..filterQuality = FilterQuality.medium,
    )
    ..restore();
  final picture = recorder.endRecording();
  final image = await picture.toImage(side, side);
  picture.dispose();

  var lightness = 0.5;
  final bytes = await image.toByteData();
  if (bytes != null && bytes.lengthInBytes > 0) {
    var sum = 0.0;
    final count = bytes.lengthInBytes ~/ 4;
    for (var i = 0; i < bytes.lengthInBytes; i += 4) {
      sum +=
          0.2126 * bytes.getUint8(i) +
          0.7152 * bytes.getUint8(i + 1) +
          0.0722 * bytes.getUint8(i + 2);
    }
    lightness = sum / count / 255;
  }
  return (image, lightness);
}

/// No cover: the berry bloom the Discover page wears.
class _Bloom extends StatelessWidget {
  const _Bloom({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0.8, -0.9),
          radius: 1.2,
          colors: [
            KalinkaColors.accent.withValues(alpha: 0.22),
            KalinkaColors.accent.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }
}
