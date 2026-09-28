import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/data_model/browse_filters.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/browse_genres_provider.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/browse_filters/browse_filter_form.dart';

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
const _textField = FilterSpec(
  id: 'q',
  kind: FilterKind.text,
  label: 'Search Popular Albums',
);
const _typeField = FilterSpec(
  id: 'type',
  kind: FilterKind.choice,
  label: 'Type',
  ops: [FilterOp.any],
);

/// A surface whose source honours nothing: every facet renders as a muted
/// placeholder, and the kind group only reports what the collection holds.
const _inertCaps = BrowseFilterCapabilities(
  text: FacetSupport.unsupported,
  type: FacetSupport.unsupported,
  types: BrowseFilterCapabilities.allTypes,
  presentTypes: {SearchType.album},
  genre: FacetSupport.unsupported,
);

/// A surface whose source honours every facet.
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
  textField: _textField,
  typeField: _typeField,
);

/// The form never reaches the network in tests; the genre taxonomy is served
/// from here so a `supported` genre facet stays deterministic.
Future<void> _pumpForm(
  WidgetTester tester, {
  required BrowseFilterCapabilities capabilities,
  BrowseFilterQuery query = const BrowseFilterQuery(),
  required void Function(BrowseFilterQuery) onChanged,
  List<Genre> genres = const [],
  Duration debounce = kFilterTextDebounce,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        browseGenresProvider(_vocabulary).overrideWith((ref) async => genres),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BrowseFilterForm(
              capabilities: capabilities,
              query: query,
              onChanged: onChanged,
              searchHint: 'Search Popular Albums',
              textDebounce: debounce,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('query', () {
    test('serverKey covers only the facets the backend honours', () {
      const query = BrowseFilterQuery(
        text: 'blue',
        type: SearchType.album,
        genreIds: ['jazz'],
      );

      // Placeholder facets contribute nothing, so a list keyed on this string
      // never refetches for a filter the server would ignore.
      expect(query.serverKey(_inertCaps), isEmpty);
      // The key carries the document itself, so it cannot disagree with the
      // request about what travels.
      expect(
        query.serverKey(_liveCaps),
        equals(
          '{"q":{"contains":"blue"},"type":{"any":["album"]},'
          '"genre":{"any":["jazz"]}}',
        ),
      );
      expect(query.encoded(_liveCaps), contains('"jazz"'));
    });

    test('a supported facet changes the key when its value changes', () {
      const caps = BrowseFilterCapabilities(
        genre: FacetSupport.supported,
        genreField: _genreField,
      );
      const a = BrowseFilterQuery(genreIds: ['jazz']);
      const b = BrowseFilterQuery(genreIds: ['jazz', 'blues']);

      expect(a.serverKey(caps), isNot(equals(b.serverKey(caps))));
    });

    test('activeCount counts each genre separately', () {
      const query = BrowseFilterQuery(
        text: 'blue',
        type: SearchType.album,
        genreIds: ['jazz', 'rock'],
      );
      expect(query.activeCount, 4);
      expect(const BrowseFilterQuery().activeCount, 0);
    });

    test('clearType drops the kind rather than keeping the old one', () {
      const query = BrowseFilterQuery(type: SearchType.album);
      expect(query.copyWith(clearType: true).type, isNull);
      expect(query.copyWith(text: 'x').type, SearchType.album);
    });

    test(
      'genres changed are told apart as sets, whatever order or repeats',
      () {
        const picked = BrowseFilterQuery(genreIds: ['jazz', 'blues']);

        expect(
          picked.facetsChangedFrom(
            const BrowseFilterQuery(genreIds: ['blues', 'jazz']),
          ),
          isEmpty,
        );
        expect(
          picked.facetsChangedFrom(
            const BrowseFilterQuery(genreIds: ['jazz', 'jazz']),
          ),
          {BrowseFacet.genre},
        );
        expect(
          const BrowseFilterQuery(
            genreIds: ['jazz', 'jazz'],
          ).facetsChangedFrom(picked),
          {BrowseFacet.genre},
        );
      },
    );
  });

  group('a source that honours nothing', () {
    testWidgets('search field renders but is disabled', (tester) async {
      await _pumpForm(
        tester,
        capabilities: _inertCaps,
        onChanged: (_) => fail('an inert form must not emit'),
      );

      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(find.text('Search Popular Albums'), findsOneWidget);
    });

    testWidgets('the kind group reports the single kind and offers no All', (
      tester,
    ) async {
      await _pumpForm(
        tester,
        capabilities: _inertCaps,
        onChanged: (_) => fail('an inert form must not emit'),
      );

      expect(find.text('TYPE'), findsOneWidget);
      expect(find.text('All'), findsNothing);
      for (final label in ['Artists', 'Albums', 'Tracks', 'Playlists']) {
        expect(find.text(label), findsOneWidget);
      }

      // The present kind reads as the standing answer; tapping changes nothing
      // (onChanged would fail the test).
      await tester.tap(find.text('Albums'));
      await tester.tap(find.text('Tracks'));
      await tester.pump();
    });

    testWidgets('genre renders as a lone placeholder', (tester) async {
      await _pumpForm(
        tester,
        capabilities: _inertCaps,
        onChanged: (_) => fail('an inert form must not emit'),
      );

      expect(find.text('GENRE'), findsOneWidget);
      await tester.tap(find.text('All genres'));
      await tester.pump();
    });
  });

  group('layout', () {
    testWidgets('kind chips wrap along the line, they do not stack', (
      tester,
    ) async {
      // A Container with an `alignment` expands to the constraints it is
      // handed, and a Wrap hands out the full line width — which once turned
      // this row of chips into a column of full-width slabs.
      tester.view.physicalSize = const Size(420, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpForm(tester, capabilities: _liveCaps, onChanged: (_) {});

      final all = tester.getRect(find.text('All'));
      final artists = tester.getRect(find.text('Artists'));
      expect(artists.top, all.top, reason: 'same run');
      expect(artists.left, greaterThan(all.right), reason: 'beside, not below');

      // And each chip is only as wide as its own label.
      expect(all.width, lessThan(artists.width));
    });
  });

  group('pill styling', () {
    testWidgets('a chosen pill fills crimson, white-labelled, and lightens', (
      tester,
    ) async {
      await _pumpForm(
        tester,
        capabilities: _liveCaps,
        query: const BrowseFilterQuery(type: SearchType.album),
        onChanged: (_) {},
      );

      // Fill and edge say which pill is chosen; the label stays white either
      // way, so the two read as one family.
      expect(
        tester.widget<Text>(find.text('Albums')).style?.color,
        KalinkaColors.textPrimary,
      );
      expect(
        tester.widget<Text>(find.text('Tracks')).style?.color,
        KalinkaColors.textPrimary,
      );

      BoxDecoration chosen() =>
          tester
                  .widget<AnimatedContainer>(
                    find
                        .ancestor(
                          of: find.text('Albums'),
                          matching: find.byType(AnimatedContainer),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;

      final atRest = chosen().color;
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      addTearDown(pointer.removePointer);
      await pointer.moveTo(tester.getCenter(find.text('Albums')));
      await tester.pumpAndSettle();

      // The chosen pill is a solid crimson segment, like the settings
      // segmented control; hover lightens the crimson itself.
      expect(atRest, KalinkaColors.accent);
      expect(chosen().color, KalinkaColors.accentTint);
    });
  });

  group('live facets', () {
    testWidgets('text is debounced into one query', (tester) async {
      final emitted = <BrowseFilterQuery>[];
      await _pumpForm(tester, capabilities: _liveCaps, onChanged: emitted.add);

      await tester.enterText(find.byType(TextField), 'blu');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'blue');
      expect(emitted, isEmpty, reason: 'still typing');

      await tester.pump(const Duration(milliseconds: 350));
      expect(emitted.map((q) => q.text), ['blue']);
    });

    testWidgets('a zero debounce reports every keystroke', (tester) async {
      final emitted = <BrowseFilterQuery>[];
      await _pumpForm(
        tester,
        capabilities: _liveCaps,
        onChanged: emitted.add,
        debounce: Duration.zero,
      );

      await tester.enterText(find.byType(TextField), 'bl');
      await tester.enterText(find.byType(TextField), 'blue');
      expect(emitted.map((q) => q.text), ['bl', 'blue']);
    });

    testWidgets('the kind group selects and clears', (tester) async {
      final emitted = <BrowseFilterQuery>[];
      await _pumpForm(tester, capabilities: _liveCaps, onChanged: emitted.add);

      expect(find.text('All'), findsOneWidget);

      await tester.tap(find.text('Tracks'));
      await tester.pump();
      expect(emitted.single.type, SearchType.track);

      emitted.clear();
      await tester.tap(find.text('All'));
      await tester.pump();
      expect(emitted.single.type, isNull);
    });

    testWidgets('genre stays a placeholder while the taxonomy is empty', (
      tester,
    ) async {
      // A source may declare the capability and still have no genres.
      await _pumpForm(
        tester,
        capabilities: _liveCaps,
        onChanged: (_) => fail('an empty taxonomy must not emit'),
      );

      expect(find.text('All genres'), findsOneWidget);
      await tester.tap(find.text('All genres'));
      await tester.pump();
    });

    testWidgets('genre pills toggle independently', (tester) async {
      final emitted = <BrowseFilterQuery>[];
      await _pumpForm(
        tester,
        capabilities: _liveCaps,
        query: const BrowseFilterQuery(genreIds: ['jazz']),
        onChanged: emitted.add,
        genres: [
          Genre(id: 'jazz', name: 'Jazz'),
          Genre(id: 'rock', name: 'Rock'),
        ],
      );

      await tester.tap(find.text('Rock'));
      await tester.pump();
      expect(emitted.single.genreIds, ['jazz', 'rock']);

      emitted.clear();
      await tester.tap(find.text('Jazz'));
      await tester.pump();
      expect(emitted.single.genreIds, isEmpty);

      emitted.clear();
      await tester.tap(find.text('All genres'));
      await tester.pump();
      expect(emitted.single.genreIds, isEmpty);
    });
  });
}
