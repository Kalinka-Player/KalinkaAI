import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/widgets/home/home_section_plan.dart';
import 'package:kalinka/widgets/home/home_pins_shimmer.dart';
import 'package:kalinka/widgets/home/planned_home_sections.dart';

HomeSectionRequest request(double width, {int folders = 4}) =>
    HomeSectionRequest(
      width: width,
      textScale: 1,
      captionExtent: 60,
      blocks: [
        (kind: HomePreviewBlockKind.folders, count: folders, extraCaption: 40),
        (kind: HomePreviewBlockKind.ordinary, count: 16, extraCaption: 0),
      ],
    );

void main() {
  test('real worker preserves and caches neighbouring list lengths', () async {
    final planner = HomeSectionPlanner();
    HomeSectionRequest beside(HomePreviewBlockKind kind) => HomeSectionRequest(
      width: 1248,
      textScale: 1,
      captionExtent: 60,
      blocks: [
        (kind: kind, count: 8, extraCaption: 0),
        (kind: HomePreviewBlockKind.tracks, count: 8, extraCaption: 0),
      ],
    );
    final ordinary = beside(HomePreviewBlockKind.ordinary);
    final plan = await planner.resolve(ordinary);
    expect(plan.rows.single.automaticListRows, {1: 3});
    final collage = await planner.resolve(beside(HomePreviewBlockKind.collage));
    expect(collage.rows.single.automaticListRows, {1: 4});
    expect(await planner.resolve(ordinary), same(plan));
  });

  test(
    'real worker caches Automatic promotion separately from Small',
    () async {
      final planner = HomeSectionPlanner();
      HomeSectionRequest besideCollage(HomePreviewBlockKind kind) =>
          HomeSectionRequest(
            width: 1248,
            textScale: 1,
            captionExtent: 60,
            blocks: [
              (kind: HomePreviewBlockKind.collage, count: 8, extraCaption: 0),
              (kind: kind, count: 1, extraCaption: 0),
            ],
          );
      final automatic = besideCollage(HomePreviewBlockKind.automatic);
      final plan = await planner.resolve(automatic);
      expect(plan.rows.single.promotedBlocks, {1});
      final small = await planner.resolve(
        besideCollage(HomePreviewBlockKind.ordinary),
      );
      expect(small.rows.single.promotedBlocks, isEmpty);
      expect(await planner.resolve(automatic), same(plan));
    },
  );

  test(
    'real worker accepts geometry and returns the full-width folder plan',
    () async {
      final planner = HomeSectionPlanner();
      final plan = await planner.resolve(request(1248));
      expect(plan.rows.length, 2);
      expect(plan.rows.first.columns.single.width, 1248);
      expect(plan.rows.first.columns.single.blocks, [0]);
      expect(plan.rows.last.columns.single.blocks, [1]);
      expect(await planner.resolve(request(1248)), same(plan));
    },
  );

  test(
    'identical work is shared, completed cache is bounded, failures retry',
    () async {
      var calls = 0;
      final gate = Completer<void>();
      final planner = HomeSectionPlanner(
        calculate: (input) async {
          calls++;
          await gate.future;
          return planHomeSections(input);
        },
      );
      final a = planner.resolve(request(1248));
      final b = planner.resolve(request(1248));
      expect(a, same(b));
      gate.complete();
      final plan = await a;
      for (var i = 0; i < 100; i++) {
        expect(await planner.resolve(request(1248)), same(plan));
      }
      expect(calls, 1);
      await planner.resolve(request(1248, folders: 5));
      expect(calls, 2);
      for (var i = 0; i < 32; i++) {
        await planner.resolve(request(900 + i.toDouble()));
      }
      expect(planner.cached(request(1248)), isNull);
      var attempts = 0;
      final retry = HomeSectionPlanner(
        calculate: (input) {
          if (++attempts == 1) throw StateError('Worker failed');
          return Future.value(planHomeSections(input));
        },
      );
      await expectLater(retry.resolve(request(1248)), throwsStateError);
      expect(await retry.resolve(request(1248)), isA<HomeSectionLayout>());
      expect(attempts, 2);
    },
  );

  testWidgets('a failed layout reveals the usable stacked fallback', (
    tester,
  ) async {
    final input = request(1248);
    HomeSectionLayout? displayed;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeSectionPlannerProvider.overrideWithValue(
            HomeSectionPlanner(
              calculate: (_) => Future.error(StateError('Worker failed')),
            ),
          ),
        ],
        child: MaterialApp(
          home: PlannedHomeSections(
            request: input,
            builder: (plan) {
              displayed = plan;
              return const Text('Pins');
            },
          ),
        ),
      ),
    );
    expect(tester.takeException(), isStateError);
    await tester.pumpAndSettle();
    expect(find.byType(HomePinsShimmer), findsNothing);
    expect(find.text('Pins'), findsOneWidget);
    expect(displayed!.rows, hasLength(2));
    expect(displayed!.rows.first.columns.single.width, input.width);
  });

  testWidgets(
    'resize is coalesced and a stale worker cannot overwrite the latest pane',
    (tester) async {
      final calls = <HomeSectionRequest>[];
      final jobs = <Completer<HomeSectionLayout>>[];
      final planner = HomeSectionPlanner(
        calculate: (input) {
          calls.add(input);
          final job = Completer<HomeSectionLayout>();
          jobs.add(job);
          return job.future;
        },
      );
      final input = ValueNotifier(request(1248));
      addTearDown(input.dispose);
      HomeSectionLayout? displayed;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [homeSectionPlannerProvider.overrideWithValue(planner)],
          child: MaterialApp(
            home: ValueListenableBuilder(
              valueListenable: input,
              builder: (_, value, _) => PlannedHomeSections(
                request: value,
                builder: (plan) {
                  displayed = plan;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      expect(calls.length, 1); // The initial job starts after layout.
      expect(displayed, isNull);
      expect(find.byType(HomePinsShimmer), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 50));
      expect(calls.length, 1);
      input.value = request(1100);
      await tester.pump();
      input.value = request(900);
      await tester.pump();
      input.value = request(592);
      await tester.pump(const Duration(milliseconds: 50));
      expect(calls.length, 1); // No second worker while the first is busy.
      expect(displayed, isNull);
      expect(find.byType(HomePinsShimmer), findsOneWidget);
      jobs.first.complete(planHomeSections(calls.first));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(calls.map((r) => r.width), [1248, 592]);
      expect(displayed, isNull);
      expect(find.byType(HomePinsShimmer), findsOneWidget);
      jobs.last.complete(planHomeSections(calls.last));
      await tester.pumpAndSettle();
      expect(displayed!.wide, isFalse);
      expect(displayed!.rows.first.columns.single.width, 592);
      expect(find.byType(HomePinsShimmer), findsNothing);
      final settled = displayed;
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump();
      }
      expect(displayed, same(settled));
      expect(calls.length, 2);
      // Returning to an old width uses its completed job, even if it had become
      // stale before finishing. It cannot overwrite the newer width meanwhile.
      input.value = request(1248);
      await tester.pumpAndSettle();
      expect(calls.length, 2);
      expect(displayed!.wide, isTrue);
      final previous = displayed;
      input.value = request(1248, folders: 6);
      await tester.pump();
      expect(displayed, same(previous)); // No build with provisional geometry.
      expect(find.byType(HomePinsShimmer), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpWidget(const SizedBox());
      jobs.last.complete(planHomeSections(calls.last));
      await tester.pump();
      expect(tester.takeException(), isNull); // No setState after disposal.
    },
  );
}
