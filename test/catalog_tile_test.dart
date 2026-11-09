import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/home/catalog_tile.dart';

void main() {
  testWidgets(
    'compact rows grow and shrink with their own asynchronous content',
    (tester) async {
      final label = ValueNotifier(
        'A long folder name that wraps over several lines '
        'with an edition, a recording date, a resolution and a file format',
      );
      final detail = ValueNotifier('My Library · 12 items');
      addTearDown(label.dispose);
      addTearDown(detail.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 600,
                child: CatalogTileGrid(
                  children: [
                    ValueListenableBuilder(
                      valueListenable: label,
                      builder: (_, title, _) => ValueListenableBuilder(
                        valueListenable: detail,
                        builder: (_, subtitle, _) => CatalogTile(
                          key: const ValueKey(0),
                          shortcut: true,
                          title: title,
                          subtitle: subtitle,
                          icon: Icons.folder_outlined,
                          onTap: () {},
                        ),
                      ),
                    ),
                    for (var i = 1; i < 4; i++)
                      CatalogTile(
                        key: ValueKey(i),
                        shortcut: true,
                        title: 'Top Releases $i',
                        subtitle: 'Qobuz · 101 albums',
                        icon: Icons.album_outlined,
                        onTap: () {},
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      Rect card(int i) => tester.getRect(find.byKey(ValueKey(i)));
      final compactHeight = card(2).height;
      expect(compactHeight, inInclusiveRange(48, 100));
      expect(card(0).height, greaterThan(compactHeight));
      expect(card(1).height, card(0).height);
      expect(card(3).height, compactHeight);
      expect(card(2).top, card(0).bottom + 8);
      label.value = 'Polly Gibbons';
      await tester.pump();
      expect(card(0).height, compactHeight);
      expect(card(1).height, compactHeight);
      expect(card(2).top, card(0).bottom + 8);
      detail.value =
          'My Library · A long saved filter with multiple genres and '
          'additional metadata that arrives after the initial preview';
      await tester.pump();
      expect(card(0).height, greaterThan(compactHeight));
      expect(card(1).height, card(0).height);
      expect(card(2).height, compactHeight);
      expect(card(2).top, card(0).bottom + 8);
      detail.value = 'My Library · 12 items';
      await tester.pump();
      expect(card(0).height, compactHeight);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (width, scale, columns, direction, count) in [
    (960.0, 1.0, 3, TextDirection.ltr, 5),
    (1600.0, 1.0, 5, TextDirection.ltr, 5),
    (600.0, 1.0, 2, TextDirection.ltr, 5),
    (375.0, 1.0, 1, TextDirection.ltr, 5),
    (960.0, 2.0, 1, TextDirection.ltr, 5),
    (375.0, 2.0, 1, TextDirection.ltr, 5),
    (960.0, 1.0, 3, TextDirection.rtl, 5),
    (1200.0, 1.0, 3, TextDirection.ltr, 3),
    (960.0, 1.0, 2, TextDirection.ltr, 2),
    (1600.0, 1.0, 1, TextDirection.ltr, 1),
  ]) {
    testWidgets('equal row heights at $width, text scale $scale, $direction', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final opened = <int>[];
      const labels = [
        (
          '1973 (2021) Pink Floyd - The Dark Side Of The Moon (2011 Remastered Version) [24B-96kHz] flac',
          'My Library · 10 items',
        ),
        (
          'Jean-Michel Jarre - 2018 - Equinoxe Infinity [Hi-Res]',
          'My Library · 11 items',
        ),
        (
          'Polly Gibbons - Ballads and Blues (NativeDSD, 2023)(DSD512)',
          'My Library · 12 items',
        ),
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
                      for (var i = 0; i < count; i++)
                        CatalogTile(
                          key: ValueKey(i),
                          shortcut: true,
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
        for (var i = 0; i < count; i++) tester.getRect(find.byKey(ValueKey(i))),
      ];
      final first = rects.first;
      for (var i = 0; i < rects.length; i++) {
        // Fractional column widths round differently per tile.
        expect(rects[i].width, moreOrLessEquals(first.width));
        expect(
          rects[i].width,
          moreOrLessEquals(
            ((width - (columns - 1) * 8) / columns).clamp(0, 480 * scale),
          ),
        );
        final row = i ~/ columns;
        expect(rects[i].height, moreOrLessEquals(rects[row * columns].height));
        expect(
          rects[i].top,
          moreOrLessEquals(
            row == 0 ? first.top : rects[(row - 1) * columns].bottom + 8,
          ),
        );
        expect(rects[i].left, greaterThanOrEqualTo(-0.001));
        expect(rects[i].right, lessThanOrEqualTo(width + 0.001));
        final tile = find.byKey(ValueKey(i));
        final title = find.descendant(
          of: tile,
          matching: find.text(labels[i].$1),
        );
        final footer = find.descendant(of: tile, matching: find.byType(Row));
        expect(tester.getRect(title).top, closeTo(rects[i].top + 16, 0.01));
        expect(
          tester.getRect(footer).bottom,
          closeTo(rects[i].bottom - 16, 0.01),
        );
        expect(
          tester.getRect(footer).top - tester.getRect(title).bottom,
          greaterThanOrEqualTo(12),
        );
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
      await tester.ensureVisible(find.byKey(ValueKey(count - 1)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(count - 1)));
      expect(opened, [0, count - 1]);
      expect(tester.takeException(), isNull);
    });
  }
}
