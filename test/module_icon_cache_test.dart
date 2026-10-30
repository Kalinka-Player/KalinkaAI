import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kalinka/data_model/module_icons.dart';
import 'package:kalinka/providers/module_icon_cache.dart';

const _svg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 26 14"><path d="M1 1h24v12H1z"/></svg>';
const _icon = ModuleIconImage(
  url: '/icon',
  mimeType: 'image/svg+xml',
  aspectRatio: 26 / 14,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'concurrent rows and navigation share one fetch and rasterization',
    () async {
      var fetched = 0;
      var rasterized = 0;
      final completed = Completer<Uint8List>();
      final cache = ModuleIconCache(
        client: MockClient((_) async {
          fetched++;
          return http.Response(_svg, 200);
        }),
        rasterize: (bytes, extent) {
          rasterized++;
          expect(extent, 96);
          return completed.future;
        },
      );
      final rows = [
        for (var i = 0; i < 100; i++)
          cache.load('http://server/icon', _icon, small: true),
      ];
      completed.complete(Uint8List.fromList([1, 2, 3]));
      final results = await Future.wait(rows);
      PaintingBinding.instance.imageCache.clear();
      final afterNavigation = await cache.load(
        'http://server/icon',
        _icon,
        small: true,
      );
      expect(fetched, 1);
      expect(rasterized, 1);
      expect(
        results.every((result) => identical(result, afterNavigation)),
        isTrue,
      );
    },
  );

  test(
    'sizes, changed artwork and servers have distinct cached bitmaps',
    () async {
      var rasterized = 0;
      final sizes = <int>[];
      final cache = ModuleIconCache(
        client: MockClient((_) async => http.Response(_svg, 200)),
        rasterize: (_, extent) async {
          rasterized++;
          sizes.add(extent);
          return Uint8List(1);
        },
      );
      await cache.load('http://one/a', _icon, small: true);
      await cache.load('http://one/a', _icon, small: false);
      await cache.load('http://two/a', _icon, small: true);
      await cache.load('http://one/b', _icon, small: true);
      expect(rasterized, 4);
      expect(sizes, [96, 256, 96, 96]);
    },
  );

  test('PNG takes the bitmap path without SVG work', () async {
    final bytes = Uint8List.fromList([137, 80, 78, 71]);
    final cache = ModuleIconCache(
      client: MockClient((_) async => http.Response.bytes(bytes, 200)),
      rasterize: (_, _) => throw StateError('PNG must not be rasterized'),
    );
    final result = await cache.load(
      'http://server/png',
      const ModuleIconImage(url: '/png', mimeType: 'image/png'),
      small: true,
    );
    expect(result, bytes);
  });

  test('failed downloads can recover on the next request', () async {
    var calls = 0;
    final cache = ModuleIconCache(
      client: MockClient(
        (_) async => http.Response(_svg, ++calls == 1 ? 503 : 200),
      ),
      rasterize: (_, _) async => Uint8List(1),
    );
    await expectLater(
      cache.load('http://server/icon', _icon, small: true),
      throwsFormatException,
    );
    await cache.load('http://server/icon', _icon, small: true);
    expect(calls, 2);
  });

  testWidgets('real SVG becomes a bounded, transparent PNG at both sizes', (
    tester,
  ) async {
    final cache = ModuleIconCache(
      client: MockClient((_) async => http.Response(_svg, 200)),
    );
    await tester.runAsync(() async {
      for (final small in [true, false]) {
        final png = await cache.load('http://server/icon', _icon, small: small);
        expect(png.sublist(1, 4), ascii.encode('PNG'));
        final codec = await ui.instantiateImageCodec(png);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, small ? 96 : 256);
        expect(frame.image.height, small ? 52 : 138);
        final pixels = (await frame.image.toByteData())!;
        expect(pixels.getUint8(3), 0);
        frame.image.dispose();
        codec.dispose();
      }
    });
  });
}
