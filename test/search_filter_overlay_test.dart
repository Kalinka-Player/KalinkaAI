import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/data_model/browse_filters.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/browse_genres_provider.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/browse_filters/search_filter_button.dart';
import 'package:kalinka/widgets/browse_filters/search_filter_overlay.dart';

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
  genre: FacetSupport.supported,
  genreVocabulary: _vocabulary,
  genreField: _genreField,
  typeField: _typeField,
);

Future<void> _pumpOverlay(
  WidgetTester tester, {
  BrowseFilterQuery applied = const BrowseFilterQuery(),
  BrowseFilterCapabilities capabilities = _liveCaps,
  required void Function(BrowseFilterQuery) onApply,
  ValueChanged<bool>? onResetApplied,
  required VoidCallback onCancel,
  List<Genre> genres = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        browseGenresProvider(_vocabulary).overrideWith((ref) async => genres),
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
  testWidgets('edits stage until Show results', (tester) async {
    final applied = <BrowseFilterQuery>[];
    await _pumpOverlay(
      tester,
      onApply: applied.add,
      onCancel: () => fail('cancel not expected'),
      genres: [Genre(id: 'jazz', name: 'Jazz')],
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

  testWidgets('the folded button badges the number of active answers', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchFilterButton(
            activeCount: const BrowseFilterQuery(
              text: 'blue',
              type: SearchType.album,
              genreIds: ['jazz'],
            ).activeCount,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('3'), findsOneWidget);
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
