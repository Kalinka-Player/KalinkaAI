import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../utils/web_build_target.dart';

/// Pixels on a side of the blurred cover. Stretched over the whole screen,
/// so the blur, not this, decides how soft it looks.
const _blurSide = 128;
const _blurSigma = 2.4;

/// skwasm_heavy corrupts ImageFilter.blur (see CatalogArt's _bake), so a
/// wasm build skips it and leans on the final stretch's own bilinear
/// upscale for softness instead — the same trick as there, so it needs the
/// much smaller source _blurSide would otherwise be.
const _wasmBlurSide = 28;

/// Draw the standby glow at display resolution. The clock and pixel shift can
/// repaint the foreground while Flutter retains this background layer.
class KioskStandbyBackdrop extends StatelessWidget {
  const KioskStandbyBackdrop({super.key});

  @override
  Widget build(BuildContext context) => const RepaintBoundary(
    child: CustomPaint(size: Size.infinite, painter: _BackdropPainter()),
  );
}

/// Full-bleed cover colours. Composite the blur, dimming and vignettes at
/// thumbnail size so each playback frame samples just one opaque image.
class KioskBackdrop extends StatefulWidget {
  final String? imageUrl;

  const KioskBackdrop({super.key, required this.imageUrl});

  @override
  State<KioskBackdrop> createState() => _KioskBackdropState();
}

class _KioskBackdropState extends State<KioskBackdrop> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ui.Image? _cover;
  ui.Image? _backdrop;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(KioskBackdrop old) {
    super.didUpdateWidget(old);
    if (old.imageUrl != widget.imageUrl) _resolve();
  }

  void _resolve() {
    final url = widget.imageUrl;
    if (url == null) {
      _unsubscribe();
      _replaceCover(null);
      return;
    }
    // skwasm_heavy requires the native-size decode (see CatalogArt).
    final ImageProvider provider = compiledToWasm
        ? NetworkImage(url)
        : ResizeImage(
            NetworkImage(url),
            width: _blurSide,
            height: _blurSide,
            policy: ResizeImagePolicy.fit,
          );
    final stream = provider.resolve(createLocalImageConfiguration(context));
    if (_stream?.key == stream.key) return;
    _unsubscribe();
    _stream = stream;
    // Keep the previous backdrop while the new cover is loading. Only its
    // first frame supplies the background, including for animated artwork.
    _listener = ImageStreamListener(
      (info, _) async {
        try {
          if (_stream != stream) return;
          _stopListening();
          final image = await _blur(info.image);
          if (!mounted || _stream != stream) {
            image.dispose();
            return;
          }
          setState(() => _replaceCover(image));
        } catch (_) {
          if (mounted && _stream == stream) setState(() => _replaceCover(null));
        } finally {
          info.dispose();
        }
      },
      onError: (_, _) {
        if (mounted && _stream == stream) setState(() => _replaceCover(null));
      },
    );
    stream.addListener(_listener!);
  }

  void _stopListening() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _listener = null;
  }

  void _unsubscribe() {
    _stopListening();
    _stream = null;
  }

  void _replaceCover(ui.Image? image) {
    _cover?.dispose();
    _cover = image;
    _backdrop?.dispose();
    _backdrop = null;
  }

  @override
  void dispose() {
    _unsubscribe();
    _replaceCover(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size.isEmpty) return const SizedBox.shrink();
        final scale = _blurSide / size.longestSide;
        final width = math.max(1, (size.width * scale).round());
        final height = math.max(1, (size.height * scale).round());
        if (_backdrop?.width != width || _backdrop?.height != height) {
          _backdrop?.dispose();
          _backdrop = _bakeBackdrop(width, height);
        }
        return RawImage(
          image: _backdrop,
          width: size.width,
          height: size.height,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.low,
        );
      },
    );
  }

  ui.Image _bakeBackdrop(int width, int height) {
    final recorder = ui.PictureRecorder();
    _BackdropPainter(_cover)
        .paint(Canvas(recorder), Size(width.toDouble(), height.toDouble()));
    final picture = recorder.endRecording();
    try {
      return picture.toImageSync(width, height);
    } finally {
      picture.dispose();
    }
  }
}

class _BackdropPainter extends CustomPainter {
  final ui.Image? cover;

  const _BackdropPainter([this.cover]);

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..color = KalinkaColors.background);
    final cover = this.cover;
    if (cover == null) {
      canvas.drawRect(
        bounds,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(0.8, -0.9),
            radius: 1.2,
            colors: [
              KalinkaColors.accent.withValues(alpha: 0.22),
              KalinkaColors.accent.withValues(alpha: 0),
            ],
          ).createShader(bounds),
      );
    } else {
      // Crop to the screen's aspect, zoomed 1.25x past the blurred edges.
      final source = Size(cover.width.toDouble(), cover.height.toDouble());
      final crop = applyBoxFit(BoxFit.cover, source, size).source / 1.25;
      canvas.drawImageRect(
        cover,
        Alignment.center.inscribe(crop, Offset.zero & source),
        bounds,
        Paint()..filterQuality = FilterQuality.low,
      );
      // Cap even a white patch under the metadata at #333333. Average
      // brightness misses patches on otherwise dark covers.
      canvas.drawColor(const Color(0xCC000000), BlendMode.srcOver);
    }
    canvas.drawRect(
      bounds,
      Paint()..shader = _verticalShade.createShader(bounds),
    );
    canvas.drawRect(bounds, Paint()..shader = _edgeShade.createShader(bounds));
  }

  @override
  bool shouldRepaint(_BackdropPainter oldDelegate) =>
      oldDelegate.cover != cover;
}

const _verticalShade = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color(0x66080808),
    Color(0x00080808),
    Color(0x00080808),
    Color(0x80080808),
  ],
  stops: [0, 0.25, 0.6, 1],
);

const _edgeShade = RadialGradient(
  radius: 1.1,
  colors: [Color(0x00080808), Color(0x4D080808)],
  stops: [0.55, 1],
);

/// The blurred centre square of [source].
Future<ui.Image> _blur(ui.Image source) async {
  final side = compiledToWasm ? _wasmBlurSide : _blurSide;
  final w = source.width.toDouble();
  final h = source.height.toDouble();
  final crop = w < h ? w : h;
  final recorder = ui.PictureRecorder();
  final bounds = Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble());
  final canvas = Canvas(recorder);
  if (!compiledToWasm) {
    canvas.saveLayer(
      bounds,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: _blurSigma,
          sigmaY: _blurSigma,
          tileMode: TileMode.clamp,
        ),
    );
  }
  canvas.drawImageRect(
    source,
    Rect.fromCenter(center: Offset(w / 2, h / 2), width: crop, height: crop),
    bounds,
    Paint()..filterQuality = FilterQuality.medium,
  );
  if (!compiledToWasm) canvas.restore();
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(side, side);
  } finally {
    picture.dispose();
  }
}
