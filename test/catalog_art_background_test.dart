import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/widgets/catalog_art.dart';

const _fixtures = 'test/fixtures/catalog_art';

Future<ui.Image> _render(
  CatalogArtSeed seed, {
  required bool card,
  bool questionMark = false,
}) async {
  final recorder = ui.PictureRecorder();
  CatalogArtPainter(
    seed,
    captioned: card,
    questionMark: questionMark,
  ).paint(Canvas(recorder), Size(card ? 360 : 120, 120));
  final picture = recorder.endRecording();
  final image = await picture.toImage(card ? 360 : 120, 120);
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

  test('title identity, colours and transforms match backend style 11', () {
    expect(reference['style'], 11);
    for (final entry in cases) {
      final actual = seed(entry);
      final label = entry['title'] as String;
      expect(actual.textKey, entry['textKey'], reason: label);
      expect(actual.geometry, entry['geometry'], reason: label);
      expect(actual.palette, entry['palette'], reason: label);
      final transform = entry['transform'] as Map<String, dynamic>;
      expect(
        actual.transform.rotation,
        closeTo(transform['rotation'] as num, 1e-12),
      );
      expect(
        actual.transform.offsetX,
        closeTo(transform['offset_x'] as num, 1e-12),
      );
      expect(
        actual.transform.offsetY,
        closeTo(transform['offset_y'] as num, 1e-12),
      );
      expect(
        actual.transform.scaleX,
        closeTo(transform['scale_x'] as num, 1e-12),
      );
      expect(
        actual.transform.scaleY,
        closeTo(transform['scale_y'] as num, 1e-12),
      );
      final matrix = actual.transform.matrix(2400, 800);
      final affine = entry['affine'] as List;
      for (final (i, j) in [(0, 0), (4, 1), (1, 2), (5, 3), (12, 4), (13, 5)]) {
        expect(matrix[i], closeTo(affine[j] as num, 1e-9), reason: label);
      }
      Color color(String hex) =>
          Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000);
      expect(actual.key, color(entry['accent'] as String), reason: label);
      expect(
        actual.highlight,
        color(entry['highlight'] as String),
        reason: label,
      );
      final tones = entry['tones'] as List;
      for (var gray = 0; gray < 256; gray++) {
        final rgb = tones[gray] as List;
        expect(
          actual.tone(gray),
          Color.fromARGB(255, rgb[0] as int, rgb[1] as int, rgb[2] as int),
          reason: '$label, gray $gray',
        );
      }
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
          final marked = await _render(
            seed(entry),
            card: card,
            questionMark: true,
          );
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

  test('the question mark leaves the caption and background alone', () async {
    final seed = CatalogArtSeed.of('Jazz', null);
    for (final card in [true, false]) {
      final bare = await _render(seed, card: card);
      final marked = await _render(seed, card: card, questionMark: true);
      final a = await _pixels(bare);
      final b = await _pixels(marked);
      var changed = 0;
      for (var y = 0; y < bare.height; y++) {
        for (var x = 0; x < bare.width; x++) {
          final i = (y * bare.width + x) * 4;
          final differs =
              a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2];
          if (differs) {
            changed++;
            expect(x, greaterThan(bare.width * (card ? 0.75 : 0.5)));
            expect(y, inInclusiveRange(30, 90));
          }
        }
      }
      expect(changed, greaterThan(100));
      bare.dispose();
      marked.dispose();
    }
  });
}
