import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/widgets/home/home_preview_layout.dart';
import 'package:kalinka/widgets/home/home_section_plan.dart';

void main() {
  const ordinary = HomePreviewBlockKind.ordinary;
  const collage = HomePreviewBlockKind.collage;
  const shortcut = HomePreviewBlockKind.shortcut;

  test('four folders get a full row before a plentiful catalogue', () {
    for (final width in [1000.0, 1248.0, 1300.0]) {
      final layout = planHomeSections(
        HomeSectionRequest(
          width: width,
          textScale: 1,
          captionExtent: 60,
          blocks: const [
            (kind: HomePreviewBlockKind.folders, count: 4, extraCaption: 40),
            (kind: ordinary, count: 16, extraCaption: 0),
          ],
        ),
      );
      expect(layout.rows.length, 2, reason: 'width $width');
      expect(layout.rows.first.columns.single.blocks, [0]);
      expect(layout.rows.last.columns.single.blocks, [1]);
      expect(layout.rows.last.columns.single.width, width);
    }
  });

  test('geometry plans are reused and the idle size cache is bounded', () {
    final memo = HomeLayoutMemo<int, Object>();
    var calculations = 0;
    Object calculate() {
      calculations++;
      return Object();
    }

    final first = memo.resolve(1, calculate);
    for (var frame = 0; frame < 100; frame++) {
      expect(memo.resolve(1, calculate), same(first));
    }
    expect(calculations, 1);
    for (var size = 2; size < 34; size++) {
      memo.resolve(size, calculate);
    }
    expect(memo.resolve(1, calculate), isNot(same(first)));
    expect(calculations, 34);
  });

  test('wide collage gets a larger column beside three readable albums', () {
    HomeSectionLayout plan(double width) => planHomeSections(
      HomeSectionRequest(
        width: width,
        textScale: 1,
        captionExtent: 60,
        blocks: [
          for (final kind in [ordinary, collage, ordinary])
            (kind: kind, count: 8, extraCaption: 0),
        ],
      ),
    );
    final layout = plan(1248);
    final columns = layout.rows.single.columns;
    expect(columns.first.blocks, [0, 2]);
    expect(columns.last.blocks, [1]);
    expect(columns.last.width, greaterThan(columns.first.width));
    expect(columns.first.width, greaterThanOrEqualTo(3 * 142));
    expect(columns.first.width + columns.last.width + 32, closeTo(1248, .001));
  });

  test(
    'crowded neighbour moves below and the collage gains smaller covers',
    () {
      final layout = planHomeSections(
        HomeSectionRequest(
          width: 900,
          textScale: 1,
          captionExtent: 60,
          blocks: [
            for (final kind in [collage, ordinary])
              (kind: kind, count: 24, extraCaption: 0),
          ],
        ),
      );
      expect(layout.rows.length, 2);
      expect(layout.rows.first.columns.single.width, 900);
      expect(layout.rows.last.columns.single.blocks, [1]);
      final expanded = homeAlbumLayout(
        width: 900,
        captionExtent: 60,
        count: 24,
        wide: true,
        large: true,
      );
      expect(expanded.arrangement, HomeAlbumArrangement.collage);
      expect(expanded.count, greaterThanOrEqualTo(5));
      expect(expanded.cover, greaterThanOrEqualTo(homeAlbumMinimumCover));
    },
  );

  test('phone order and shortcut boundaries survive packing', () {
    for (final width in [390.0, 900.0, 1800.0]) {
      final layout = planHomeSections(
        HomeSectionRequest(
          width: width,
          textScale: 1,
          captionExtent: 60,
          blocks: [
            for (final kind in [
              ordinary,
              shortcut,
              shortcut,
              collage,
              ordinary,
            ])
              (kind: kind, count: 8, extraCaption: 0),
          ],
        ),
      );
      expect(layout.rows[1].shortcuts, isTrue);
      expect(layout.rows[1].columns.single.blocks, [1, 2]);
      if (width < 800) {
        expect(layout.rows.expand((r) => r.columns).expand((c) => c.blocks), [
          0,
          1,
          2,
          3,
          4,
        ]);
      }
    }
  });

  test('packing preserves every block and boundary across sizes and counts', () {
    const kinds = [
      ordinary,
      collage,
      HomePreviewBlockKind.folders,
      HomePreviewBlockKind.tracks,
      shortcut,
      shortcut,
      HomePreviewBlockKind.standalone,
      ordinary,
      collage,
      ordinary,
    ];
    for (final width in [320.0, 592.0, 800.0, 1248.0, 1800.0, 3200.0]) {
      for (final scale in [1.0, 2.0]) {
        for (final count in [0, 1, 3, 4, 7, 32]) {
          final layout = planHomeSections(
            HomeSectionRequest(
              width: width,
              textScale: scale,
              captionExtent: 60 * scale,
              blocks: [
                for (final kind in kinds)
                  (kind: kind, count: count, extraCaption: 40),
              ],
            ),
          );
          final ordered = <int>[];
          for (final row in layout.rows) {
            expect(
              row.columns.fold<double>(0, (sum, c) => sum + c.width) +
                  (row.columns.length - 1) * homePreviewColumnGap,
              closeTo(width, .001),
            );
            expect(row.columns.every((c) => c.width > 0), isTrue);
            // Templates read across the first line, then any stacked sections.
            final depth = row.columns
                .map((c) => c.blocks.length)
                .reduce((a, b) => a > b ? a : b);
            final indices = [
              for (var level = 0; level < depth; level++)
                for (final column in row.columns)
                  if (column.blocks.length > level) column.blocks[level],
            ];
            ordered.addAll(indices);
            if (row.shortcuts) {
              expect(indices, [4, 5]);
            } else {
              expect(indices.any((i) => kinds[i] == shortcut), isFalse);
            }
          }
          expect(ordered, List.generate(kinds.length, (i) => i));
          if (width < 800 * scale) {
            expect(layout.rows.every((r) => r.columns.length == 1), isTrue);
          }
        }
      }
    }
  });

  test(
    'collage cover bottoms align without making small covers unreadable',
    () {
      for (final caption in [57.0, 84.0, 120.0]) {
        for (final width in [360.0, 480.0, 640.0, 800.0, 1248.0, 1800.0]) {
          for (final count in [2, 3, 4, 5, 24]) {
            final layout = homeAlbumLayout(
              width: width,
              captionExtent: caption,
              count: count,
              wide: true,
              large: true,
            );
            if (layout.arrangement != HomeAlbumArrangement.collage) continue;
            expect(layout.cover, inInclusiveRange(120, 200));
            expect(
              layout.leadCover + caption,
              closeTo(2 * (layout.cover + caption), .001),
            );
            final occupied =
                layout.leadCover +
                22 +
                16 +
                layout.columns * (layout.cover + 22);
            expect(occupied, lessThanOrEqualTo(width + .001));
            expect(layout.count, lessThanOrEqualTo(count));
          }
        }
      }
    },
  );
}
