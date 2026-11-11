import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/widgets/home/home_preview_layout.dart';
import 'package:kalinka/widgets/home/home_section_plan.dart';

void main() {
  const ordinary = HomePreviewBlockKind.ordinary;
  const collage = HomePreviewBlockKind.collage;
  const shortcut = HomePreviewBlockKind.shortcut;
  const automatic = HomePreviewBlockKind.automatic;

  test('list columns respect their minimum width and system text size', () {
    for (final scale in [1.0, 2.0]) {
      final threshold =
          2 * homeListMinimumColumnWidth * scale + homePreviewColumnGap;
      expect(homeListColumnCount(threshold - 1, textScale: scale), 1);
      expect(homeListColumnCount(threshold, textScale: scale), 2);
      final plan = homeListLayout(
        width: threshold,
        count: 20,
        rowsPerColumn: 4,
        textScale: scale,
      );
      expect(plan.count, 8);
      expect(plan.rows, 4);
      expect(plan.columnWidth, homeListMinimumColumnWidth * scale);
      expect([plan.startOf(0), plan.startOf(1), plan.startOf(2)], [0, 4, 8]);
    }
  });

  test(
    'short lists balance consecutive items without empty full-width rows',
    () {
      final plan = homeListLayout(width: 1248, count: 3, rowsPerColumn: 4);
      expect(plan.columns, 2);
      expect(plan.rows, 2);
      expect([plan.startOf(0), plan.startOf(1), plan.startOf(2)], [0, 2, 3]);
      final single = homeListLayout(width: 1248, count: 1, rowsPerColumn: 4);
      expect(single.columns, 1);
      expect(single.columnWidth, plan.columnWidth);
      final empty = homeListLayout(width: 1248, count: 0, rowsPerColumn: 4);
      expect(empty.count, 0);
      expect(empty.rows, 0);
    },
  );

  test(
    'Automatic lists match ordinary covers or a taller neighbouring collage',
    () {
      for (final scale in [1.0, 1.5]) {
        for (final (neighbour, rows) in [(ordinary, 3), (collage, 4)]) {
          for (final reverse in [false, true]) {
            final kinds = [neighbour, HomePreviewBlockKind.tracks];
            final layout = planHomeSections(
              HomeSectionRequest(
                width: 1248 * scale,
                textScale: scale,
                captionExtent: 60 * scale,
                blocks: [
                  for (final kind in reverse ? kinds.reversed : kinds)
                    (kind: kind, count: 8, extraCaption: 0),
                ],
              ),
            );
            expect(layout.rows.single.columns, hasLength(2));
            expect(layout.rows.single.automaticListRows, {
              reverse ? 0 : 1: rows,
            });
          }
        }
      }
    },
  );

  test('Automatic lists share an artwork reference in a three-column row', () {
    final layout = planHomeSections(
      HomeSectionRequest(
        width: 1900,
        textScale: 1,
        captionExtent: 60,
        blocks: const [
          (kind: ordinary, count: 8, extraCaption: 0),
          (kind: HomePreviewBlockKind.tracks, count: 8, extraCaption: 0),
          (kind: HomePreviewBlockKind.tracks, count: 8, extraCaption: 0),
        ],
      ),
    );
    expect(layout.rows.single.columns, hasLength(3));
    expect(layout.rows.single.automaticListRows, {1: 3, 2: 3});
  });

  test('list fitting leaves explicit lengths and list-only rows alone', () {
    for (final kinds in [
      [ordinary, HomePreviewBlockKind.shortTracks],
      [ordinary, HomePreviewBlockKind.longTracks],
      [HomePreviewBlockKind.tracks],
      [HomePreviewBlockKind.tracks, HomePreviewBlockKind.tracks],
    ]) {
      final layout = planHomeSections(
        HomeSectionRequest(
          width: 1248,
          textScale: 1,
          captionExtent: 60,
          blocks: [
            for (final kind in kinds) (kind: kind, count: 8, extraCaption: 0),
          ],
        ),
      );
      expect(layout.rows.every((row) => row.automaticListRows.isEmpty), isTrue);
    }
  });

  test('a short Automatic list can set the height for a longer neighbour', () {
    final layout = planHomeSections(
      HomeSectionRequest(
        width: 1248,
        textScale: 1,
        captionExtent: 60,
        blocks: const [
          (kind: HomePreviewBlockKind.tracks, count: 3, extraCaption: 0),
          (kind: HomePreviewBlockKind.tracks, count: 8, extraCaption: 0),
        ],
      ),
    );
    expect(layout.rows.single.columns, hasLength(2));
    expect(layout.rows.single.automaticListRows, {1: 3});
  });

  test(
    'Automatic fills spare row height without changing the chosen columns',
    () {
      for (final count in [1, 8]) {
        HomeSectionLayout layout(HomePreviewBlockKind kind) => planHomeSections(
          HomeSectionRequest(
            width: 1248,
            textScale: 1,
            captionExtent: 60,
            blocks: [
              (kind: collage, count: 8, extraCaption: 0),
              (kind: kind, count: count, extraCaption: 0),
            ],
          ),
        );
        final small = layout(ordinary).rows.single;
        final automaticRow = layout(automatic).rows.single;
        expect(small.promotedBlocks, isEmpty);
        expect(automaticRow.promotedBlocks, {1}, reason: 'count $count');
        expect(
          automaticRow.columns.map((c) => c.width),
          small.columns.map((c) => c.width),
        );
        final original = homeAlbumLayout(
          width: small.columns.last.width,
          captionExtent: 60,
          count: count,
          wide: true,
          large: false,
        );
        final promoted = homeAlbumLayout(
          width: automaticRow.columns.last.width,
          captionExtent: 60,
          count: count,
          wide: true,
          large: true,
          largeCover: automaticRow.largeCover,
        );
        expect(promoted.count, greaterThanOrEqualTo(original.count));
        final cover = promoted.leadCover > 0
            ? promoted.leadCover
            : promoted.cover;
        expect(cover, lessThanOrEqualTo(automaticRow.largeCover + .001));
        expect(cover, greaterThan(original.cover));
      }
    },
  );

  test(
    'Automatic stays ordinary without a large neighbour or spare height',
    () {
      for (final width in [375.0, 1248.0]) {
        for (final kinds in [
          [automatic],
          [ordinary, automatic],
          [collage, automatic, automatic],
        ]) {
          final layout = planHomeSections(
            HomeSectionRequest(
              width: width,
              textScale: 1,
              captionExtent: 60,
              blocks: [
                for (final kind in kinds)
                  (kind: kind, count: 8, extraCaption: 0),
              ],
            ),
          );
          expect(
            layout.rows.every((row) => row.promotedBlocks.isEmpty),
            isTrue,
          );
        }
      }
    },
  );

  test(
    'Large enlarges single albums and pairs within the pane and cover cap',
    () {
      for (final width in [280.0, 358.0, 592.0, 1248.0]) {
        for (final count in [1, 2]) {
          for (final single in [false, true]) {
            final small = homeAlbumLayout(
              width: width,
              captionExtent: 60,
              count: count,
              wide: width >= 800,
              large: false,
              single: single,
            );
            final large = homeAlbumLayout(
              width: width,
              captionExtent: 60,
              count: count,
              wide: width >= 800,
              large: true,
              single: single,
            );
            expect(large.cover, greaterThan(small.cover));
            expect(large.cover, lessThanOrEqualTo(homeAlbumLargeCover));
            expect(large.cover + 2 * homeAlbumInset, lessThanOrEqualTo(width));
            expect(large.count, lessThanOrEqualTo(count));
          }
        }
      }
    },
  );

  test('packing accounts for large folder cards and changing their size', () {
    HomeSectionLayout layout(HomePreviewBlockKind kind) => planHomeSections(
      HomeSectionRequest(
        width: 1248,
        textScale: 1,
        captionExtent: 60,
        blocks: [
          (kind: kind, count: 3, extraCaption: 0),
          (kind: ordinary, count: 16, extraCaption: 0),
        ],
      ),
    );
    final large = layout(HomePreviewBlockKind.largeFolders);
    expect(large.rows.first.columns.single.blocks, [0]);
    expect(large.rows.first.columns.single.width, 1248);
    expect(homeFolderCover(1248, wide: true, large: true), homeAlbumLargeCover);
    final small = layout(HomePreviewBlockKind.folders);
    expect(small.rows.single.columns.length, 2);
  });

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

  test('wide collage fits beside three readable albums', () {
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
    expect(columns.last.width, greaterThanOrEqualTo(columns.first.width));
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
      automatic,
      collage,
      ordinary,
      HomePreviewBlockKind.largeFolders,
      HomePreviewBlockKind.shortTracks,
      HomePreviewBlockKind.longTracks,
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
                2 * homeAlbumInset +
                layout.columns * (layout.cover + 2 * homeAlbumInset);
            expect(occupied, lessThanOrEqualTo(width + .001));
            expect(layout.count, lessThanOrEqualTo(count));
          }
        }
      }
    },
  );
}
