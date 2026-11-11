import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/pinned_catalogs_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/widgets/home/home_list_preview.dart';
import 'package:kalinka/widgets/home/home_pins_shimmer.dart';
import 'package:kalinka/widgets/home/home_section_plan.dart';
import 'package:kalinka/widgets/home/pinned_catalogs_section.dart';
import 'package:kalinka/widgets/home/planned_home_sections.dart';
import 'package:kalinka/widgets/search_cards/row_enqueue_button.dart';
import 'package:kalinka/widgets/search_cards/search_track_row.dart';

import 'support/adaptive_home_fixtures.dart';
import 'support/home_shell.dart';

class _EnqueueApi extends AdaptiveHomeApi {
  final added = <List<String>>[];

  @override
  Future<StatusMessage> add(List<String> items, {int? index}) async {
    added.add(List.of(items));
    return StatusMessage(count: items.length);
  }
}

const _id = 'kalinka:localfiles:catalog:resize-tracks';

String? _focusedTrack() => FocusManager.instance.primaryFocus?.context
    ?.findAncestorWidgetOfExactType<RowEnqueueButton>()
    ?.item
    .id;

Future<void> _focusTrack(WidgetTester tester, String id) async {
  for (var i = 0; i < 30 && _focusedTrack() != id; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  expect(_focusedTrack(), id);
}

Finder _enqueue(BrowseItem item) => find.byWidgetPredicate(
  (widget) => widget is RowEnqueueButton && widget.item.id == item.id,
);

Future<List<BrowseItem>> _pumpTracks(
  WidgetTester tester,
  _EnqueueApi api, {
  HomeSectionPlanner? planner,
  FocusNode? outsideFocus,
}) async {
  final items = [
    for (var i = 1; i <= 7; i++) demoTrack('resize-$i', 'Track $i', 'Artist'),
  ];
  api.listings[_id] = items;
  final pin = PinnedCatalog(
    page: CatalogPage.category(id: _id, title: 'Tracks'),
    filter: awardsPin.filter,
    preview: HomePreviewType.automatic,
  );
  await pumpHomeShell(
    tester,
    queue: SettableQueue(queueOf(0)),
    api: api,
    sources: demoSources,
    size: const Size(2400, 1000),
    planner: planner,
    screen: Scaffold(
      body: Column(
        children: [
          if (outsideFocus != null)
            TextButton(
              focusNode: outsideFocus,
              onPressed: () {},
              child: const Text('Outside pins'),
            ),
          Expanded(
            child: SingleChildScrollView(
              child: PinnedCatalogsSection(pins: [pin]),
            ),
          ),
        ],
      ),
    ),
  );
  return items;
}

void main() {
  testWidgets(
    'hidden pins block activation and retain focus after replanning',
    (tester) async {
      Completer<HomeSectionLayout>? layout;
      HomeSectionRequest? pending;
      final api = _EnqueueApi();
      final items = await _pumpTracks(
        tester,
        api,
        planner: HomeSectionPlanner(
          calculate: (request) {
            pending = request;
            return layout?.future ?? Future.value(planHomeSections(request));
          },
        ),
      );
      await _focusTrack(tester, items[2].id);
      layout = Completer();
      tester.view.physicalSize = const Size(2430, 1000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(HomePinsShimmer), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(api.added, isEmpty);
      expect(_focusedTrack(), items[2].id);

      layout.complete(planHomeSections(pending!));
      await tester.pumpAndSettle();
      expect(_focusedTrack(), items[2].id);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(api.added, [
        [items[2].id],
      ]);
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Tab leaves hidden pins and cannot traverse back into them', (
    tester,
  ) async {
    final outside = FocusNode();
    addTearDown(outside.dispose);
    Completer<HomeSectionLayout>? layout;
    HomeSectionRequest? pending;
    final api = _EnqueueApi();
    final items = await _pumpTracks(
      tester,
      api,
      outsideFocus: outside,
      planner: HomeSectionPlanner(
        calculate: (request) {
          pending = request;
          return layout?.future ?? Future.value(planHomeSections(request));
        },
      ),
    );
    await _focusTrack(tester, items[2].id);
    layout = Completer();
    tester.view.physicalSize = const Size(2430, 1000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(HomePinsShimmer), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(outside.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(outside.hasPrimaryFocus, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(outside.hasPrimaryFocus, isTrue);

    layout.complete(planHomeSections(pending!));
    await tester.pumpAndSettle();
    expect(outside.hasPrimaryFocus, isTrue); // Revealing must not steal focus.
    expect(api.added, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('replanning long pinned lists preserves the scroll offset', (
    tester,
  ) async {
    final api = _EnqueueApi();
    final pins = [
      for (var i = 0; i < 7; i++)
        PinnedCatalog(
          page: CatalogPage.category(
            id: 'kalinka:localfiles:catalog:long-$i',
            title: 'List $i',
          ),
          filter: awardsPin.filter,
          preview: HomePreviewType.list,
        ),
    ];
    for (final pin in pins) {
      api.listings[pin.page.id!] = [
        for (var i = 0; i < 5; i++)
          demoTrack('${pin.key}-$i', 'Track $i', 'Artist'),
      ];
    }
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    Completer<HomeSectionLayout>? layout;
    HomeSectionRequest? pending;
    await pumpHomeShell(
      tester,
      queue: SettableQueue(queueOf(0)),
      api: api,
      sources: demoSources,
      size: const Size(700, 800),
      planner: HomeSectionPlanner(
        calculate: (request) {
          pending = request;
          return layout?.future ?? Future.value(planHomeSections(request));
        },
      ),
      screen: Scaffold(
        body: SingleChildScrollView(
          controller: scroll,
          child: PinnedCatalogsSection(pins: pins),
        ),
      ),
    );
    scroll.jumpTo(1000);
    await tester.pumpAndSettle();
    final extent = scroll.position.maxScrollExtent;
    layout = Completer();
    tester.view.physicalSize = const Size(710, 800);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(HomePinsShimmer), findsOneWidget);
    expect(scroll.offset, 1000);
    expect(scroll.position.maxScrollExtent, extent);
    layout.complete(planHomeSections(pending!));
    await tester.pumpAndSettle();
    expect(scroll.offset, 1000);
    expect(scroll.position.maxScrollExtent, extent);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rebalancing columns cannot enqueue a different focused track', (
    tester,
  ) async {
    final api = _EnqueueApi();
    final items = await _pumpTracks(tester, api);
    Rect row(int i) => tester.getRect(
      find.byWidgetPredicate(
        (widget) => widget is SearchTrackRow && widget.item.id == items[i].id,
      ),
    );
    // Four columns split seven items 2/2/2/1; track three starts column two.
    expect(row(2).top, row(0).top);
    expect(row(2).left, greaterThan(row(0).right));
    await _focusTrack(tester, items[2].id);

    tester.view.physicalSize = const Size(2430, 1000);
    await tester.pumpAndSettle();
    expect(_focusedTrack(), items[2].id); // Same column boundaries.
    tester.view.physicalSize = const Size(2400, 1000);
    await tester.pumpAndSettle();
    expect(_focusedTrack(), items[2].id);

    tester.view.physicalSize = const Size(1820, 1000);
    await tester.pumpAndSettle();
    // Three columns split them 3/2/2; track three now ends column one.
    expect(row(2).left, row(0).left);
    expect(row(2).top, greaterThan(row(1).top));
    expect(find.byType(SearchTrackRow), findsNWidgets(7));
    expect(_focusedTrack(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(api.added, isEmpty);

    await _focusTrack(tester, items[2].id);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(api.added, [
      [items[2].id],
    ]);
    // Both widths use the same fetch bucket: only the row slices changed.
    expect(api.calls.where((call) => call.id == _id).map((c) => c.limit), [16]);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('enqueue feedback follows a row within its rebalanced column', (
    tester,
  ) async {
    final api = _EnqueueApi();
    final items = await _pumpTracks(tester, api);
    await _focusTrack(tester, items[3].id);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(1820, 1000);
    await tester.pumpAndSettle();
    // Track four moves up within column two; its state must move with it.
    expect(_focusedTrack(), isNull);
    expect(
      find.descendant(
        of: _enqueue(items[3]),
        matching: find.byTooltip('Added to queue'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _enqueue(items[4]),
        matching: find.byTooltip('Add to queue'),
      ),
      findsOneWidget,
    );
    await _focusTrack(tester, items[3].id);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(api.added, [
      [items[3].id],
    ]);
    await tester.tap(_enqueue(items[4]));
    await tester.pumpAndSettle();
    expect(api.added, [
      [items[3].id],
      [items[4].id],
    ]);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('repeated tracks keep separate enqueue actions in one column', (
    tester,
  ) async {
    final api = _EnqueueApi();
    final item = demoTrack('duplicate', 'Repeated track', 'Artist');
    await pumpHomeShell(
      tester,
      queue: SettableQueue(queueOf(0)),
      api: api,
      sources: demoSources,
      size: const Size(700, 1000),
      screen: Scaffold(
        body: HomeListPreview(items: [item, item], rowsPerColumn: 3),
      ),
    );
    expect(_enqueue(item), findsNWidgets(2));
    await tester.tap(_enqueue(item).first);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: _enqueue(item).last,
        matching: find.byTooltip('Add to queue'),
      ),
      findsOneWidget,
    );
    await tester.tap(_enqueue(item).last);
    await tester.pumpAndSettle();
    expect(api.added, [
      [item.id],
      [item.id],
    ]);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
  });
}
