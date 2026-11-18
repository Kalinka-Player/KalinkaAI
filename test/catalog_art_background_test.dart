import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/widgets/catalog_art.dart';

const _fixtures = 'test/fixtures/catalog_art';

Future<ui.Image> _render(
  CatalogArtSeed seed, {
  required bool card,
  double width = 360,
  bool icon = false,
}) async {
  final recorder = ui.PictureRecorder();
  final size = Size(card ? width : 120, 120);
  CatalogArtPainter(
    seed,
    captioned: card,
    icon: icon,
  ).paint(Canvas(recorder), size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.round(), 120);
  picture.dispose();
  return image;
}

Future<Uint8List> _pixels(ui.Image image) async =>
    (await image.toByteData())!.buffer.asUint8List();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final reference = jsonDecode(
    File('$_fixtures/reference.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final cases = (reference['cases'] as List).cast<Map<String, dynamic>>();

  CatalogArtSeed seed(Map<String, dynamic> entry) => CatalogArtSeed.of(
    entry['title'] as String,
    entry['description'] as String,
    entityId: entry['entityId'] as String,
  );

  test('title identity, geometry and tints match backend style 15', () {
    expect(reference['style'], 15);
    Color color(String hex) =>
        Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000);
    for (final entry in cases) {
      final actual = seed(entry);
      final label = entry['title'] as String;
      expect(actual.textKey, entry['textKey'], reason: label);
      expect(actual.geometry, entry['geometry'], reason: label);
      expect(actual.palette, entry['palette'], reason: label);
      expect(actual.tint, color(entry['tint'] as String), reason: label);
      expect(
        [actual.left, actual.right, actual.shape, actual.line],
        (entry['swatches'] as List).cast<String>().map(color).toList(),
        reason: label,
      );
    }
  });

  for (final entry in cases.where((entry) => entry.containsKey('image'))) {
    for (final card in [true, false]) {
      final name = '${entry['image']}-${card ? 'card' : 'thumb'}';
      test('$name matches the backend background', () async {
        final actual = await _render(seed(entry), card: card);
        final codec = await ui.instantiateImageCodec(
          File('$_fixtures/$name.png').readAsBytesSync(),
        );
        final expected = (await codec.getNextFrame()).image;
        codec.dispose();
        final a = await _pixels(actual);
        final b = await _pixels(expected);
        var total = 0;
        var outsideTolerance = 0;
        for (var i = 0; i < a.length; i += 4) {
          var worst = 0;
          for (var c = 0; c < 3; c++) {
            final difference = (a[i + c] - b[i + c]).abs();
            total += difference;
            if (difference > worst) worst = difference;
          }
          if (worst > 8) outsideTolerance++;
          expect(a[i + 3], 255);
        }
        // Skia and Pillow rasterize edges differently; solid areas and the
        // caption fade must agree. A different shape or palette fails both.
        expect(total / (actual.width * actual.height * 3), lessThan(1.5));
        expect(
          outsideTolerance / (actual.width * actual.height),
          lessThan(0.025),
        );

        final preview = Platform.environment['CATALOG_ART_PREVIEW_DIR'];
        if (preview != null) {
          Directory(preview).createSync(recursive: true);
          File('$preview/$name.png').writeAsBytesSync(
            (await actual.toByteData(format: ui.ImageByteFormat.png))!.buffer
                .asUint8List(),
          );
          final marked = await _render(seed(entry), card: card, icon: true);
          File('$preview/$name-marked.png').writeAsBytesSync(
            (await marked.toByteData(format: ui.ImageByteFormat.png))!.buffer
                .asUint8List(),
          );
          marked.dispose();
        }
        actual.dispose();
        expected.dispose();
      });
    }
  }

  test(
    'the icon sits where the server draws it, clear of the caption',
    () async {
      final seed = CatalogArtSeed.of('Jazz', null);
      // A 3:1 card, a square, and a card tall enough for its width to cap the
      // icon.
      for (final (card, width) in [
        (true, 360.0),
        (false, 120.0),
        (true, 180.0),
      ]) {
        final bare = await _render(seed, card: card, width: width);
        final marked = await _render(
          seed,
          card: card,
          width: width,
          icon: true,
        );
        final a = await _pixels(bare);
        final b = await _pixels(marked);
        var left = bare.width, right = 0, top = bare.height, bottom = 0;
        for (var y = 0; y < bare.height; y++) {
          for (var x = 0; x < bare.width; x++) {
            final i = (y * bare.width + x) * 4;
            if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) {
              left = math.min(left, x);
              right = math.max(right, x);
              top = math.min(top, y);
              bottom = math.max(bottom, y);
            }
          }
        }
        final side = card ? math.min(78.0, width * 0.3) : 78.0;
        final centre = width * (card ? 0.82 : 0.5);
        final reason = '${card ? 'card' : 'square'} $width wide';
        if (card) {
          expect(
            left,
            greaterThan(width * CatalogCard.captionShare),
            reason: reason,
          );
        }
        // The tilted design spans 1.6 to 97.4 of its 100 units across and 12.7
        // to 91.4 down.
        expect(left, closeTo(centre - side * 0.484, 2), reason: reason);
        expect(right, closeTo(centre + side * 0.474, 2), reason: reason);
        expect(top, closeTo(60 - side * 0.373, 2), reason: reason);
        expect(bottom, closeTo(60 + side * 0.414, 2), reason: reason);
        bare.dispose();
        marked.dispose();
      }
    },
  );
}
