import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/data_model/browse_filters.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/filter_values_provider.dart';
import 'package:kalinka/providers/pinned_catalogs_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/widgets/browse_filters/active_filter_chips.dart';
import 'package:kalinka/widgets/browse_filters/browse_filter_form.dart';

const _albums = 'kalinka:localfiles:catalog:albums';

const _textField = FilterSpec(
  id: 'q',
  kind: FilterKind.text,
  label: 'Search albums and artists',
);
const _genreField = FilterSpec(
  id: 'genre',
  kind: FilterKind.choice,
  label: 'Genre',
  ops: [FilterOp.any, FilterOp.all, FilterOp.none],
);
const _decadeField = FilterSpec(
  id: 'decade',
  kind: FilterKind.choice,
  label: 'Decade',
  ops: [FilterOp.any],
);
const _typeField = FilterSpec(
  id: kTypeFieldId,
  kind: FilterKind.choice,
  label: 'Type',
  ops: [FilterOp.any],
);

/// What the local library's album shelf declares since decades.
final _shelf = BrowseFilterCapabilities.fromSpecs(const [
  _textField,
  _genreField,
  _decadeField,
], catalogId: _albums);

/// A shelf from before, or a source without decades.
final _genreOnly = BrowseFilterCapabilities.fromSpecs(const [
  _textField,
  _genreField,
], catalogId: _albums);

/// Oldest first, as the server lists them; the counts say nothing of order.
const _decades = [
  FilterValue(id: '1960', name: '1960s', count: 3),
  FilterValue(id: '1970', name: '1970s', count: 40),
  FilterValue(id: '1980', name: '1980s', count: 12),
];
const _genres = [
  FilterValue(id: 'jazz', name: 'Jazz'),
  FilterValue(id: 'rock', name: 'Rock'),
];

const _seventiesJazz = BrowseFilterQuery(
  selections: {
    kGenreFieldId: ['jazz'],
    'decade': ['1970', '1980'],
  },
);

Widget _scoped(Widget child) => ProviderScope(
  overrides: [
    filterValuesProvider((catalogId: _albums, field: 'genre'))
        .overrideWith((ref) async => _genres),
    filterValuesProvider((catalogId: _albums, field: 'decade'))
        .overrideWith((ref) async => _decades),
  ],
  child: MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  group('capabilities', () {
    test('each values field is a facet of its own, in declared order', () {
      expect(_shelf.choices.map((facet) => facet.id), ['genre', 'decade']);
      expect(_shelf.choice('decade')?.field.label, 'Decade');
      expect(_shelf.choice('decade')?.vocabulary, (
        catalogId: _albums,
        field: 'decade',
      ));
      expect(_shelf.choice('genre')?.vocabulary?.field, 'genre');
    });

    test('the kind field stays out of the values facets', () {
      final library = BrowseFilterCapabilities.fromSpecs(
        const [_textField, _typeField, _genreField, _decadeField],
        catalogId: 'kalinka:localfiles:catalog:library',
        types: const [SearchType.album, SearchType.artist],
      );
      expect(library.typeField?.id, kTypeFieldId);
      expect(library.choices.map((facet) => facet.id), ['genre', 'decade']);
    });
  });

  group('query', () {
    test('each field travels with the operation its source honours', () {
      expect(jsonDecode(_seventiesJazz.encoded(_shelf)!), {
        'genre': {
          'any': ['jazz'],
        },
        'decade': {
          'any': ['1970', '1980'],
        },
      });
    });

    test('a shelf without decades cannot honour one and drops it', () {
      const seventies = BrowseFilterQuery(
        selections: {
          'decade': ['1970'],
        },
      );
      expect(seventies.isHonouredBy(_shelf), isTrue);
      expect(seventies.isHonouredBy(_genreOnly), isFalse);
      expect(_seventiesJazz.isHonouredBy(_genreOnly), isFalse);

      final fitted = _seventiesJazz.fittedTo(_genreOnly);
      expect(fitted.genreIds, ['jazz']);
      expect(fitted.selected('decade'), isEmpty);
      expect(fitted.encoded(_genreOnly), '{"genre":{"any":["jazz"]}}');
    });

    test('each decade counts on its own', () {
      expect(_seventiesJazz.activeCount, 3);
      expect(_seventiesJazz.isEmpty, isFalse);
      expect(_seventiesJazz.withSelected('decade', const []).activeCount, 1);
    });

    test('a decade changed is told apart from one unchanged', () {
      expect(
        _seventiesJazz.facetsChangedFrom(
          const BrowseFilterQuery(
            selections: {
              'decade': ['1980', '1970'],
              kGenreFieldId: ['jazz'],
            },
          ),
        ),
        isEmpty,
      );
      expect(
        _seventiesJazz.facetsChangedFrom(
          _seventiesJazz.withSelected('decade', const ['1970']),
        ),
        {BrowseFacet.choice},
      );
    });

    test('a filter saved before decades loads its genres as before', () {
      final saved = BrowseFilterQuery.fromJson(
        jsonDecode('{"text":"blue","genreIds":["jazz","rock"]}'),
      );
      expect(saved.text, 'blue');
      expect(saved.genreIds, ['jazz', 'rock']);
      expect(saved.selections.keys, [kGenreFieldId]);
      expect(
        saved.encoded(_shelf),
        '{"q":{"contains":"blue"},"genre":{"any":["jazz","rock"]}}',
      );
    });

    test('genre is saved where an older app reads it, decades beside it', () {
      final json = _seventiesJazz.toJson();
      expect(json, {
        'genreIds': ['jazz'],
        'values': {
          'decade': ['1970', '1980'],
        },
      });
      final restored = BrowseFilterQuery.fromJson(jsonDecode(jsonEncode(json)));
      expect(restored.genreIds, ['jazz']);
      expect(restored.selected('decade'), ['1970', '1980']);
      expect(restored.encoded(_shelf), _seventiesJazz.encoded(_shelf));
    });

    test('an empty choice is not saved', () {
      expect(
        const BrowseFilterQuery(selections: {'decade': []}).toJson(),
        isEmpty,
      );
    });
  });

  group('pins', () {
    test('a pin names its decades and keeps one key whatever the order', () {
      PinnedCatalog pin(BrowseFilterQuery filter) => PinnedCatalog(
        page: const CatalogPage.category(
          id: _albums,
          title: 'Albums',
          filters: [_textField, _genreField, _decadeField],
        ),
        filter: filter,
        preview: HomePreviewType.automatic,
        valueNames: const {'jazz': 'Jazz', '1970': '1970s', '1980': '1980s'},
      );
      final reordered = pin(
        const BrowseFilterQuery(
          selections: {
            'decade': ['1980', '1970'],
            kGenreFieldId: ['jazz'],
          },
        ),
      );

      expect(pin(_seventiesJazz).key, reordered.key);
      expect(pin(_seventiesJazz).filterDescription, 'Jazz · 1970s, 1980s');
      final restored = PinnedCatalog.fromJson(
        jsonDecode(jsonEncode(pin(_seventiesJazz).toJson())),
      );
      expect(restored.key, pin(_seventiesJazz).key);
      expect(restored.valueNames['1970'], '1970s');
    });
  });

  group('form', () {
    testWidgets('a decade section follows genre under the server\'s label', (
      tester,
    ) async {
      await tester.pumpWidget(
        _scoped(
          BrowseFilterForm(
            capabilities: _shelf,
            query: const BrowseFilterQuery(),
            onChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('GENRE'), findsOneWidget);
      expect(find.text('DECADE'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('DECADE')).dy,
        greaterThan(tester.getBottomLeft(find.text('Rock')).dy),
      );
      final labels = [
        for (final pill in tester.widgetList<FilterPill>(
          find.byType(FilterPill),
        ))
          pill.label,
      ];
      expect(labels, [
        'All genres',
        'Jazz',
        'Rock',
        'All decades',
        '1960s',
        '1970s',
        '1980s',
      ]);
      final all = tester.widget<FilterPill>(
        find.widgetWithText(FilterPill, 'All decades'),
      );
      expect(all.selected, isTrue);
    });

    testWidgets('choosing decades leaves the genres chosen alone', (
      tester,
    ) async {
      var query = const BrowseFilterQuery(
        selections: {
          kGenreFieldId: ['jazz'],
        },
      );
      await tester.pumpWidget(
        _scoped(
          StatefulBuilder(
            builder: (context, setState) => BrowseFilterForm(
              capabilities: _shelf,
              query: query,
              onChanged: (next) => setState(() => query = next),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('1980s'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1960s'));
      await tester.pumpAndSettle();
      expect(query.selected('decade'), ['1980', '1960']);
      expect(query.genreIds, ['jazz']);
      expect(
        tester
            .widget<FilterPill>(find.widgetWithText(FilterPill, 'All decades'))
            .selected,
        isFalse,
      );

      await tester.tap(find.text('All decades'));
      await tester.pumpAndSettle();
      expect(query.selected('decade'), isEmpty);
      expect(query.genreIds, ['jazz']);
    });

    testWidgets('a source without decades shows no decade section', (
      tester,
    ) async {
      await tester.pumpWidget(
        _scoped(
          BrowseFilterForm(
            capabilities: _genreOnly,
            query: const BrowseFilterQuery(),
            onChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('GENRE'), findsOneWidget);
      expect(find.text('DECADE'), findsNothing);
    });
  });

  group('applied chips', () {
    testWidgets('each decade is a chip named as the server names it', (
      tester,
    ) async {
      final changes = <BrowseFilterQuery>[];
      await tester.pumpWidget(
        _scoped(
          ActiveFilterChips(
            capabilities: _shelf,
            query: _seventiesJazz,
            onChanged: changes.add,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final chips = [
        for (final chip in tester.widgetList<ActiveFilterChip>(
          find.byType(ActiveFilterChip),
        ))
          chip.label,
      ];
      expect(chips, ['Jazz', '1970s', '1980s']);

      await tester.tap(find.widgetWithText(ActiveFilterChip, '1970s'));
      await tester.pump();
      expect(changes.single.selected('decade'), ['1980']);
      expect(changes.single.genreIds, ['jazz']);
    });
  });
}
