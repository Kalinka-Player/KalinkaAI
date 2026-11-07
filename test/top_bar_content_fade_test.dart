import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/top_bar_content_fade.dart';

void main() {
  testWidgets('top fade makes content transparent and reveals the background', (
    tester,
  ) async {
    final key = GlobalKey();
    for (final background in [null, const Color(0xFF286496)]) {
      var taps = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 100,
                height: 120,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (background != null) ColoredBox(color: background),
                    TopBarContentFade(
                      extent: 24 + kKalinkaTopBarHeight,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: 80,
                          height: 120,
                          child: GestureDetector(
                            onTap: () => taps++,
                            child: const ColoredBox(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final pixels = (await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final pixels = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        image.dispose();
        return pixels;
      }))!;
      List<int> pixel(int x, int y) => [
        for (var channel = 0; channel < 4; channel++)
          pixels.getUint8((y * 100 + x) * 4 + channel),
      ];
      if (background == null) {
        // Actual alpha falls quadratically: approximately 10% at the
        // notification area's foot, 25% midway and 100% below the toolbar.
        expect(pixel(50, 0)[3], 0);
        expect(pixel(50, 24)[3], inInclusiveRange(24, 29));
        expect(pixel(50, 38)[3], inInclusiveRange(62, 68));
        expect(pixel(90, 38)[3], 0);
      } else {
        // An opaque black scrim would darken these blue pixels. A content
        // mask reveals the original background and leaves empty space alone.
        expect(pixel(50, 0), [40, 100, 150, 255]);
        expect(pixel(90, 38), [40, 100, 150, 255]);
        final middle = pixel(50, 38);
        expect(middle[0], closeTo(95, 2));
        expect(middle[1], closeTo(140, 2));
        expect(middle[2], closeTo(177, 2));
      }
      expect(pixel(50, 76), [255, 255, 255, 255]);
      expect(pixel(50, 100), [255, 255, 255, 255]);
      await tester.tapAt(const Offset(50, 38));
      expect(taps, 0);
      await tester.tapAt(const Offset(50, 100));
      expect(taps, 1);
    }
  });
}
