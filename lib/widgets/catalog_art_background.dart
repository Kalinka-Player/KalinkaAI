import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../utils/catalog_casefold.dart';
import '../utils/web_build_target.dart';

/// Geometry around the artwork side, independent of the caption and overlays.
@immutable
class CatalogGeometryTransform {
  final double rotation;
  final double offsetX;
  final double offsetY;
  final double scaleX;
  final double scaleY;

  CatalogGeometryTransform.fromHash(List<int> bytes)
    : rotation = (bytes[24] % 61 - 30).toDouble(),
      offsetX = (bytes[25] / 255 - 0.5) * 0.14,
      offsetY = (bytes[26] / 255 - 0.5) * 0.50,
      scaleX = 0.82 + bytes[27] / 255 * 0.36,
      scaleY = 0.80 + bytes[28] / 255 * 0.40;

  Float64List matrix(double width, double height) {
    final radians = rotation * math.pi / 180;
    final cosine = math.cos(radians), sine = math.sin(radians);
    final a = cosine * scaleX, b = -sine * scaleY;
    final c = sine * scaleX, d = cosine * scaleY;
    final px = 0.82 * width, py = 0.5 * height;
    return Float64List.fromList([
      a,
      c,
      0,
      0,
      b,
      d,
      0,
      0,
      0,
      0,
      1,
      0,
      px + offsetX * width - a * px - b * py,
      py + offsetY * height - c * px - d * py,
      0,
      1,
    ]);
  }
}

/// The title identity and colour mapping from catalog_art_render.py, style 11.
@immutable
class CatalogArtSeed {
  final String textKey;
  final int geometry;
  final int palette;
  final Color key;
  final Color highlight;
  final Color shadow;
  final CatalogGeometryTransform transform;

  const CatalogArtSeed._(
    this.textKey,
    this.geometry,
    this.palette,
    this.key,
    this.highlight,
    this.shadow,
    this.transform,
  );

  factory CatalogArtSeed.of(
    String title,
    String? description, {
    String entityId = '',
  }) {
    final names = [title, description ?? ''].map(_normalised);
    final name = names.where((name) => name.isNotEmpty).firstOrNull;
    final digest = sha256.convert(
      utf8.encode(name == null ? 'id:$entityId' : jsonEncode([name])),
    );
    // Reduce byte by byte: Dart's web ints cannot represent a 64-bit hash.
    int part(int start, int modulus) => digest.bytes
        .skip(start)
        .take(8)
        .fold(0, (value, byte) => (value * 256 + byte) % modulus);
    final palette = part(8, _palettes.length);
    final (accent, light) = _palettes[palette];
    final strength = [0.90, 1.0, 1.10][part(16, 3)];
    Color scaled(int rgb, double scale, int ceiling) => Color.fromARGB(
      255,
      math.min(ceiling, _roundEven(((rgb >> 16) & 255) * scale)),
      math.min(ceiling, _roundEven(((rgb >> 8) & 255) * scale)),
      math.min(ceiling, _roundEven((rgb & 255) * scale)),
    );
    return CatalogArtSeed._(
      digest.toString(),
      part(0, 6),
      palette,
      Color(0xFF000000 | accent),
      scaled(light, strength, 240),
      scaled(accent, 0.35, 255),
      CatalogGeometryTransform.fromHash(digest.bytes),
    );
  }

  static const _palettes = [
    (0xA13B50, 0xCE8291),
    (0xAF563D, 0xDFA080),
    (0x94702F, 0xCFB66B),
    (0x687B38, 0xA8BB77),
    (0x2F7958, 0x82B499),
    (0x28836D, 0x82C4AE),
    (0x277B84, 0x81B7C4),
    (0x367F9E, 0x8BC4D9),
    (0x32669B, 0x82A9D4),
    (0x4E5CA6, 0xA1A8DC),
    (0x6A4E9B, 0xB59FD5),
    (0x834D91, 0xC59CCB),
    (0xA34479, 0xD894BA),
    (0xA54F67, 0xDF9BA8),
    (0x896456, 0xC3AA90),
    (0x526F7D, 0xADC3C9),
  ];

  // Python str.split() whitespace, including U+0085 and excluding U+FEFF.
  static final _space = RegExp(
    r'[\u0009-\u000d\u001c-\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]+',
  );

  static String _normalised(String text) =>
      catalogCaseFold(unorm.nfkc(text))
          .split(_space)
          .where((part) => part.isNotEmpty)
          .join(' ');

  /// Pillow's three-point grayscale lookup, with its integer interpolation.
  Color tone(int gray) {
    final low = (gray < 160 ? shadow : key).toARGB32();
    final high = (gray < 160 ? key : highlight).toARGB32();
    final position = gray < 160 ? gray : gray - 160;
    final span = gray < 160 ? 160 : 95;
    int channel(int shift) {
      final a = (low >> shift) & 255;
      final b = (high >> shift) & 255;
      return a + ((b - a) * position / span).floor();
    }

    return Color.fromARGB(255, channel(16), channel(8), channel(0));
  }

  static int _roundEven(double value) {
    final floor = value.floor();
    return value - floor == 0.5 ? floor + (floor % 2) : value.round();
  }

  @override
  bool operator ==(Object other) =>
      other is CatalogArtSeed && other.textKey == textKey;

  @override
  int get hashCode => textKey.hashCode;
}

/// Draws the backend's bare background, with a mark for unavailable artwork.
/// The question mark is omitted underneath a successfully loaded inset cover.
class CatalogArtPainter extends CustomPainter {
  final CatalogArtSeed seed;
  final bool captioned;
  final bool questionMark;

  const CatalogArtPainter(
    this.seed, {
    this.captioned = false,
    this.questionMark = true,
  });

  static const _width = 2400.0;
  static const _height = 800.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.save();
    if (captioned) {
      canvas.scale(size.width / _width, size.height / _height);
    } else {
      // ImageOps.fit(..., centering=(0.8, 0.5)), as in server thumbnails.
      final scale = math.max(size.width / _width, size.height / _height);
      canvas.translate(
        (size.width - _width * scale) * 0.8,
        (size.height - _height * scale) * 0.5,
      );
      canvas.scale(scale);
    }
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, _width, _height),
      Paint()..color = seed.tone(48),
    );
    _shapes(canvas);
    canvas.restore();
    if (questionMark) _question(canvas, size);
    canvas.restore();
  }

  Paint _fill(int gray) {
    if (!captioned) return Paint()..color = seed.tone(gray);
    // DIAGNOSTIC: the shapes below are invisible on Firefox/skwasm_heavy;
    // testing whether the Gradient.linear shader is why, by skipping it.
    if (compiledToWasm) return Paint()..color = seed.tone(gray);
    // Fade in grayscale before applying the LUT, just like the backend.
    final colors = <Color>[seed.tone(48)];
    final stops = <double>[0];
    for (var i = 0; i <= 128; i++) {
      final t = i / 128;
      final alpha = (t * t * (3 - 2 * t) * 255).floor();
      colors.add(seed.tone((48 + (gray - 48) * alpha / 255).round()));
      stops.add(0.58 + 0.14 * t);
    }
    colors.add(seed.tone(gray));
    stops.add(1);
    return Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        const Offset(_width, 0),
        colors,
        stops,
      );
  }

  void _shapes(Canvas canvas) {
    const w = _width, h = _height;
    final matrix = seed.transform.matrix(w, h);
    void draw(Path path, int gray) =>
        canvas.drawPath(path.transform(matrix), _fill(gray));

    switch (seed.geometry) {
      case 0: // sweep
        draw(
          Path()
            ..addOval(Rect.fromLTRB(0.54 * w, -0.85 * h, 1.32 * w, 1.3 * h)),
          176,
        );
        draw(
          Path()
            ..addOval(Rect.fromLTRB(0.64 * w, -0.94 * h, 1.34 * w, 0.97 * h)),
          92,
        );
      case 1: // arch
        draw(
          Path()..addRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTRB(0.59 * w, 0.08 * h, 1.04 * w, 1.8 * h),
              const Radius.circular(0.225 * w),
            ),
          ),
          192,
        );
        draw(
          Path()..addRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTRB(0.68 * w, 0.36 * h, 0.95 * w, 1.8 * h),
              const Radius.circular(0.135 * w),
            ),
          ),
          92,
        );
      case 2: // diagonal
        draw(
          Path()
            ..moveTo(0.53 * w, h)
            ..lineTo(0.80 * w, 0)
            ..lineTo(w, 0)
            ..lineTo(0.73 * w, h)
            ..close(),
          184,
        );
      case 3: // circles
        draw(
          Path()..addOval(
            Rect.fromCircle(
              center: Offset(0.82 * w, 0.36 * h),
              radius: 0.62 * h,
            ),
          ),
          184,
        );
        draw(
          Path()..addOval(
            Rect.fromCircle(
              center: Offset(0.96 * w, 0.92 * h),
              radius: 0.24 * h,
            ),
          ),
          112,
        );
      case 4: // wave
        final wave = Path();
        for (var i = 0; i < 240; i++) {
          final x = 0.45 + 0.55 * i / 239;
          final y = h * (0.52 + 0.22 * math.sin((x - 0.45) * 3 * math.pi));
          if (i == 0) {
            wave.moveTo(x * w, y);
          } else {
            wave.lineTo(x * w, y);
          }
        }
        wave
          ..lineTo(w, h)
          ..lineTo(0.45 * w, h)
          ..close();
        draw(wave, 184);
      case 5: // block
        final tile = Path()
          ..addRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTRB(-480, -580, 479, 579),
              const Radius.circular(0.13 * h),
            ),
          );
        final c = math.cos(24 * math.pi / 180);
        final s = math.sin(24 * math.pi / 180);
        // Preserve the original block's tilt and expanded-tile centre;
        // draw() adds the title transform without rotating the caption fade.
        draw(
          tile.transform(
            Float64List.fromList([
              c,
              -s,
              0,
              0,
              s,
              c,
              0,
              0,
              0,
              0,
              1,
              0,
              2091,
              406,
              0,
              1,
            ]),
          ),
          176,
        );
    }
  }

  void _question(Canvas canvas, Size size) {
    final height = math.min(size.height, size.width) * 0.40;
    canvas.save();
    canvas.translate(
      size.width * (captioned ? 0.82 : 0.66),
      size.height * 0.5 - height * 0.5,
    );
    canvas.scale(height);
    final paint = Paint()
      ..color = const Color(0xCCFAF5F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.09
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(-0.23, 0.20)
        ..cubicTo(-0.20, -0.06, 0.23, -0.07, 0.23, 0.20)
        ..cubicTo(0.23, 0.39, 0, 0.42, 0, 0.61)
        ..lineTo(0, 0.66),
      paint,
    );
    canvas.drawCircle(
      const Offset(0, 0.94),
      0.055,
      paint..style = PaintingStyle.fill,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(CatalogArtPainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.captioned != captioned ||
      oldDelegate.questionMark != questionMark;
}
