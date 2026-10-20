import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/home/catalog_tile.dart';

void main() {
  for (final (width, scale, columns, direction) in [
    (960.0, 1.0, 3, TextDirection.ltr),
    (1600.0, 1.0, 6, TextDirection.ltr),
    (600.0, 1.0, 2, TextDirection.ltr),
    (375.0, 1.0, 1, TextDirection.ltr),
    (960.0, 2.0, 1, TextDirection.ltr),
    (375.0, 2.0, 1, TextDirection.ltr),
    (960.0, 1.0, 3, TextDirection.rtl),
  ]) {
    testWidgets('equal tiles at $width, text scale $scale, $direction', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final opened = <int>[];
      const labels = [
        ('My Library', 'My Library'),
        ('New Releases', 'Jamendo'),
        ('Featured Playlists', 'Jamendo'),
        ('Popular', 'Jamendo · New age · track'),
        ('Featured Playlists', 'Jamendo · “love”'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Directionality(
              textDirection: direction,
              child: Scaffold(
                body: SingleChildScrollView(
                  child: CatalogTileGrid(
                    children: [
                      for (var i = 0; i < labels.length; i++)
                        CatalogTile(
                          key: ValueKey(i),
                          title: labels[i].$1,
                          subtitle: labels[i].$2,
                          icon: Icons.music_note_outlined,
                          onTap: () => opened.add(i),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final rects = [
        for (var i = 0; i < labels.length; i++)
          tester.getRect(find.byKey(ValueKey(i))),
      ];
      final first = rects.first;
      for (var i = 0; i < rects.length; i++) {
        // Fractional column widths round differently per tile.
        expect(rects[i].width, moreOrLessEquals(first.width));
        // One column fills the available width; wide panes keep compact tiles.
        if (columns == 1) {
          expect(rects[i].width, width);
        } else {
          expect(rects[i].width, lessThanOrEqualTo(260 * scale));
        }
        expect(rects[i].height, moreOrLessEquals(first.height));
        expect(
          rects[i].top,
          moreOrLessEquals(first.top + (i ~/ columns) * (first.height + 8)),
        );
        expect(rects[i].left, greaterThanOrEqualTo(0));
        expect(rects[i].right, lessThanOrEqualTo(width));
      }
      if (columns > 1) {
        expect(
          rects[1].left - first.left,
          moreOrLessEquals(
            (direction == TextDirection.ltr ? 1 : -1) * (first.width + 8),
          ),
        );
      }
      // Extra space added to a shorter tile remains part of its tap target.
      await tester.tapAt(Offset(first.center.dx, first.bottom - 2));
      await tester.tapAt(rects.last.center);
      expect(opened, [0, 4]);
      expect(tester.takeException(), isNull);
    });
  }
}
