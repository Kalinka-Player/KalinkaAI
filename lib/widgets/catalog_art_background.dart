import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../utils/catalog_casefold.dart';

/// The title identity and tint mapping from catalog_art_render.py, style 12.
@immutable
class CatalogArtSeed {
  final String textKey;

  /// Arcs, folds or rings: the banner geometry the title selects.
  final int geometry;
  final int palette;
  final Color tint;

  /// The tint over the base for the left surface, the right surface, the
  /// geometry and its fine line.
  final Color left;
  final Color right;
  final Color shape;
  final Color line;

  const CatalogArtSeed._(
    this.textKey,
    this.geometry,
    this.palette,
    this.tint,
    this.left,
    this.right,
    this.shape,
    this.line,
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
    final palette = part(8, _tints.length);
    final tint = _tints[palette];
    Color over(double weight) {
      int channel(int shift) {
        final base = (_base >> shift) & 255;
        final value = (tint >> shift) & 255;
        return _roundEven(base * (1 - weight) + value * weight);
      }

      return Color.fromARGB(255, channel(16), channel(8), channel(0));
    }

    return CatalogArtSeed._(
      digest.toString(),
      part(0, 3),
      palette,
      Color(0xFF000000 | tint),
      over(0.12),
      over(0.34),
      over(0.48),
      over(0.68),
    );
  }

  static const _base = 0x1B1B1E;

  static const _tints = [
    0x814354,
    0x7E4D3E,
    0x7D653B,
    0x696C3D,
    0x4F6543,
    0x3A644C,
    0x386762,
    0x44617E,
    0x566174,
    0x4F5482,
    0x60507C,
    0x6C4A73,
    0x774668,
    0x6E5F53,
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

/// Draws the backend's bare background, with the catalogue icon for
/// unavailable artwork. The icon is omitted underneath a successfully loaded
/// inset cover.
class CatalogArtPainter extends CustomPainter {
  final CatalogArtSeed seed;
  final bool captioned;
  final bool icon;

  const CatalogArtPainter(
    this.seed, {
    this.captioned = false,
    this.icon = true,
  });

  // The banner designs' viewBox.
  static const _width = 600.0;
  static const _height = 200.0;

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
      Paint()..color = seed.left,
    );
    // Firefox/skwasm_heavy has dropped gradient fills; the flat left surface
    // then stands in for the wash.
    canvas.drawRect(
      const Rect.fromLTRB(0.4 * _width, 0, _width, _height),
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0.4 * _width, 0),
          const Offset(_width, 0),
          [seed.left, seed.right],
        ),
    );
    _shapes(canvas);
    canvas.restore();
    if (icon) _icon(canvas, size);
    canvas.restore();
  }

  void _shapes(Canvas canvas) {
    final fill = Paint()..color = seed.shape;
    Paint stroke(Color color, double width) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (seed.geometry) {
      case 0: // arcs
        canvas.drawPath(
          Path()
            ..moveTo(291, 220)
            ..cubicTo(360, 73, 458, -12, 602, -37)
            ..lineTo(638, -23)
            ..cubicTo(510, -8, 391, 83, 326, 220)
            ..close(),
          fill,
        );
        canvas.drawPath(
          Path()
            ..moveTo(347, 220)
            ..cubicTo(406, 103, 496, 31, 608, -9),
          stroke(seed.line, 1.05),
        );
        canvas.drawPath(
          Path()
            ..moveTo(365, 220)
            ..cubicTo(426, 111, 506, 49, 612, 7),
          stroke(seed.shape, 1.25),
        );
      case 1: // folds
        canvas.drawPath(
          Path()..addPolygon(const [
            Offset(289, 213),
            Offset(452, -12),
            Offset(500, -12),
            Offset(337, 213),
          ], true),
          fill,
        );
        canvas.drawLine(
          const Offset(359, 213),
          const Offset(522, -12),
          stroke(seed.line, 1.05),
        );
        canvas.drawLine(
          const Offset(379, 214),
          const Offset(542, -12),
          stroke(seed.shape, 1.2),
        );
        canvas.drawPath(
          Path()..addPolygon(const [
            Offset(480, 213),
            Offset(640, -9),
            Offset(640, 50),
            Offset(523, 213),
          ], true),
          fill,
        );
      case 2: // rings
        // Their lower halves fall below the card, as the design's arcs end.
        const centre = Offset(480, 201);
        for (final (radius, width) in const [
          (114.0, 1.2),
          (128.0, 1.2),
          (143.0, 1.2),
          (167.0, 21.0),
        ]) {
          canvas.drawCircle(centre, radius, stroke(seed.shape, width));
        }
        canvas.drawCircle(centre, 190, stroke(seed.line, 1.0));
    }
  }

  // The solid catalogue icon in a 100-unit square: its cover, then each page
  // and its entries.
  static const _iconShapes = [
    (
      Color(0xFF414044),
      [
        Offset(4, 25),
        Offset(50, 40),
        Offset(96, 25),
        Offset(96, 80),
        Offset(50, 95),
        Offset(4, 80),
      ],
    ),
    (
      Color(0xFF9D9792),
      [Offset(8, 15), Offset(47, 28), Offset(47, 86), Offset(8, 73)],
    ),
    (
      Color(0xFF716D69),
      [Offset(17, 31), Offset(38, 38), Offset(38, 50), Offset(17, 43)],
    ),
    (
      Color(0xFF716D69),
      [Offset(17, 51), Offset(38, 58), Offset(38, 70), Offset(17, 63)],
    ),
    (
      Color(0xFF716D69),
      [Offset(53, 28), Offset(92, 15), Offset(92, 73), Offset(53, 86)],
    ),
    (
      Color(0xFF9D9792),
      [Offset(62, 38), Offset(83, 31), Offset(83, 43), Offset(62, 50)],
    ),
    (
      Color(0xFF9D9792),
      [Offset(62, 58), Offset(83, 51), Offset(83, 63), Offset(62, 70)],
    ),
  ];

  void _icon(Canvas canvas, Size size) {
    final side = math.min(size.height, size.width) * 0.5;
    canvas.save();
    // The drawing sits 5 units low in its square.
    canvas.translate(
      size.width * (captioned ? 0.82 : 0.66) - side / 2,
      size.height / 2 - side * 0.55,
    );
    canvas.scale(side / 100);
    for (final (colour, points) in _iconShapes) {
      canvas.drawPath(
        Path()..addPolygon(points, true),
        Paint()..color = colour,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(CatalogArtPainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.captioned != captioned ||
      oldDelegate.icon != icon;
}
