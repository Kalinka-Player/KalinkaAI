import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/data_model/browse_filters.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/filter_values_provider.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/browse_filters/browse_filter_form.dart';
import 'package:kalinka/widgets/browse_filters/search_filter_button.dart';
import 'package:kalinka/widgets/browse_filters/search_filter_overlay.dart';
import 'package:kalinka/widgets/overlay_card.dart';

import 'support/focus.dart';

const _vocabulary = (
  catalogId: 'kalinka:localfiles:catalog:albums',
  field: 'genre',
);
const _genreField = FilterSpec(
  id: 'genre',
  kind: FilterKind.choice,
  label: 'Genre',
  ops: [FilterOp.any],
);

const _typeField = FilterSpec(
  id: 'type',
  kind: FilterKind.choice,
  label: 'Type',
  ops: [FilterOp.any],
);

const _liveCaps = BrowseFilterCapabilities(
  text: FacetSupport.supported,
  type: FacetSupport.supported,
  types: BrowseFilterCapabilities.allTypes,
  presentTypes: {
    SearchType.artist,
    SearchType.album,
    SearchType.track,
    SearchType.playlist,
  },
  choices: [ChoiceFacet(field: _genreField, vocabulary: _vocabulary)],
  typeField: _typeField,
);

Future<void> _pumpOverlay(
  WidgetTester tester, {
  BrowseFilterQuery applied = const BrowseFilterQuery(),
  BrowseFilterCapabilities capabilities = _liveCaps,
  required void Function(BrowseFilterQuery) onApply,
  ValueChanged<bool>? onResetApplied,
  required VoidCallback onCancel,
  List<FilterValue> genres = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        filterValuesProvider(_vocabulary).overrideWith((ref) async => genres),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SearchFilterOverlay(
            capabilities: capabilities,
            applied: applied,
            onApply: (filter, {required reset}) {
              onResetApplied?.call(reset);
              onApply(filter);
            },
            onCancel: onCancel,
            maxHeight: 560,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'vertical arrows scroll through wrapped chips before the footer',
    (tester) async {
      tester.view.physicalSize = const Size(375, 470);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pumpOverlay(
        tester,
        capabilities: const BrowseFilterCapabilities(
          choices: [ChoiceFacet(field: _genreField, vocabulary: _vocabulary)],
        ),
        genres: List.generate(
          30,
          (i) => FilterValue(id: '$i', name: 'Genre $i'),
        ),
        onApply: (_) {},
        onCancel: () {},
      );
      await tester.pumpAndSettle();
      final chips = find.byType(FilterPill);
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
      final viewport = tester.getRect(find.byType(SingleChildScrollView));
      Future<void> press(LogicalKeyboardKey key) async {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
      }

      expect(
        await tabTo(tester, find.widgetWithText(FilterPill, 'All genres')),
        isTrue,
      );
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      final rowYs = <int>[];
      while (focusIsOn(chips) && rowYs.length <= 31) {
        final center = FocusManager.instance.primaryFocus!.rect.center;
        expect(viewport.contains(center), isTrue);
        rowYs.add((center.dy + scroll.position.pixels).round());
        await press(LogicalKeyboardKey.arrowDown);
      }
      expect(rowYs.length, greaterThan(4));
      expect(rowYs.toSet().length, rowYs.length);
      expect(
        focusIsOn(find.widgetWithText(InkWell, 'Cancel')) ||
            focusIsOn(find.widgetWithText(InkWell, 'Show results')),
        isTrue,
      );
      await press(LogicalKeyboardKey.arrowUp);
      expect(focusIsOn(chips), isTrue);
      final lastCenter = FocusManager.instance.primaryFocus!.rect.center;
      expect((lastCenter.dy + scroll.position.pixels).round(), rowYs.last);
      expect(viewport.contains(lastCenter), isTrue);
    },
  );

  testWidgets('edits stage until Show results', (tester) async {
    final applied = <BrowseFilterQuery>[];
    await _pumpOverlay(
      tester,
      onApply: applied.add,
      onCancel: () => fail('cancel not expected'),
      genres: const [FilterValue(id: 'jazz', name: 'Jazz')],
    );

    await tester.tap(find.text('Albums'));
    await tester.pump();
    await tester.tap(find.text('Jazz'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'blue');
    await tester.pump();

    // One reload for a whole visit, however many pills were touched.
    expect(applied, isEmpty);

    await tester.tap(find.text('Show results'));
    await tester.pump();
    expect(applied.single.type, SearchType.album);
    expect(applied.single.genreIds, ['jazz']);
    expect(applied.single.text, 'blue');
  });

  testWidgets('Cancel leaves without applying', (tester) async {
    var cancelled = 0;
    await _pumpOverlay(
      tester,
      onApply: (_) => fail('cancel must not apply'),
      onCancel: () => cancelled++,
    );

    await tester.tap(find.text('Tracks'));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(cancelled, 1);
  });

  testWidgets('circular Close supports keyboard and the full touch target', (
    tester,
  ) async {
    var cancelled = 0;
    await _pumpOverlay(
      tester,
      onApply: (_) => fail('closing must not apply staged filters'),
      onCancel: () => cancelled++,
    );
    await tester.tap(find.text('Tracks'));
    await tester.pump();

    final close = find.byType(OverlayCloseButton);
    expect(tester.getSize(close), const Size(48, 48));
    expect(find.byTooltip('Close filters'), findsOneWidget);
    expect(find.bySemanticsLabel('Close filters'), findsOneWidget);

    // The seven pixels outside the visible 34dp circle still dismiss.
    await tester.tapAt(tester.getTopLeft(close) + const Offset(2, 24));
    await tester.pump();
    expect(cancelled, 1);

    Focus.of(tester.element(find.byIcon(Icons.close_rounded))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(cancelled, 2);
  });

  testWidgets('Reset appears with a staged selection and empties it', (
    tester,
  ) async {
    await _pumpOverlay(
      tester,
      applied: const BrowseFilterQuery(type: SearchType.album),
      onApply: (_) {},
      onCancel: () {},
    );

    expect(find.text('RESET'), findsOneWidget);
    await tester.tap(find.text('RESET'));
    await tester.pump();

    // Reset empties the staging area but stays on the card.
    expect(find.text('RESET'), findsNothing);
    expect(find.text('SEARCH & FILTERS'), findsOneWidget);
  });

  testWidgets('Reset is staged and applies to edits made after it', (
    tester,
  ) async {
    final applied = <BrowseFilterQuery>[];
    final resets = <bool>[];
    await _pumpOverlay(
      tester,
      applied: const BrowseFilterQuery(text: 'jazz'),
      onApply: applied.add,
      onResetApplied: resets.add,
      onCancel: () {},
    );

    await tester.tap(find.text('RESET'));
    await tester.pump();
    await tester.tap(find.text('Albums'));
    await tester.pump();
    expect(applied, isEmpty);
    expect(resets, isEmpty);

    await tester.tap(find.text('Show results'));
    expect(applied.single.type, SearchType.album);
    expect(resets, [true]);
  });

  testWidgets('options stay available when results change under an open card', (
    tester,
  ) async {
    final applied = <BrowseFilterQuery>[];
    const selected = BrowseFilterQuery(type: SearchType.album);
    await _pumpOverlay(
      tester,
      applied: selected,
      onApply: applied.add,
      onCancel: () {},
    );
    await _pumpOverlay(
      tester,
      capabilities: const BrowseFilterCapabilities(
        text: FacetSupport.supported,
      ),
      onApply: applied.add,
      onCancel: () {},
    );

    expect(find.text('Albums'), findsOneWidget);
    await tester.tap(find.text('All'));
    await tester.pump();
    await tester.tap(find.text('Show results'));
    expect(applied.single.type, isNull);
  });

  testWidgets('the folded filter button shows its count and opens with OK', (
    tester,
  ) async {
    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchFilterButton(
            activeCount: const BrowseFilterQuery(
              text: 'blue',
              type: SearchType.album,
              selections: {
                kGenreFieldId: ['jazz'],
              },
            ).activeCount,
            onTap: () => opens++,
          ),
        ),
      ),
    );

    expect(find.text('3'), findsOneWidget);
    final button = find.byType(SearchFilterButton);
    expect(await tabTo(tester, button), isTrue);
    expect(focusOutlineIn(button, KalinkaColors.textPrimary), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opens, 1);
  });

  testWidgets('the badged button fits the title bar', (tester) async {
    // The bar is kKalinkaTopBarHeight tall less its 3px insets; a button that
    // overflows it would paint the badge into the status area.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              height: kKalinkaTopBarHeight - 6,
              child: Row(
                children: [SearchFilterButton(activeCount: 9, onTap: () {})],
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(SearchFilterButton)).height,
      lessThanOrEqualTo(kKalinkaTopBarHeight - 6),
    );
  });

  testWidgets('the folded button lightens its edge under the pointer', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SearchFilterButton(activeCount: 0, onTap: () {})),
      ),
    );

    BoxDecoration pillDecoration() =>
        tester
                .widget<AnimatedContainer>(find.byType(AnimatedContainer))
                .decoration
            as BoxDecoration;

    final atRest = pillDecoration().color;
    final restingEdge = (pillDecoration().border as Border).top.color;

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);
    await pointer.moveTo(tester.getCenter(find.byType(SearchFilterButton)));
    await tester.pumpAndSettle();

    // The fill lift alone is ~2% on a near-black bar, so the edge is the cue:
    // borderDefault (a very dark grey) lightens to a mid grey.
    expect(pillDecoration().color, isNot(atRest));
    expect(
      (pillDecoration().border as Border).top.color,
      KalinkaColors.textMuted,
    );

    await pointer.moveTo(const Offset(600, 600));
    await tester.pumpAndSettle();
    expect(pillDecoration().color, atRest);
    expect((pillDecoration().border as Border).top.color, restingEdge);
  });

  testWidgets('a filtered button says so with its badge, not its edge', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SearchFilterButton(activeCount: 3, onTap: () {})),
      ),
    );

    final pill =
        tester
                .widget<AnimatedContainer>(find.byType(AnimatedContainer))
                .decoration
            as BoxDecoration;
    // Berry in the bar means one thing, and it is the count.
    expect((pill.border as Border).top.color, KalinkaColors.borderDefault);
    expect(pill.color, KalinkaColors.surfaceElevated);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('an unfiltered button carries no badge', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SearchFilterButton(activeCount: 0, onTap: () {})),
      ),
    );

    expect(find.textContaining(RegExp(r'^\d+$')), findsNothing);
  });
}
