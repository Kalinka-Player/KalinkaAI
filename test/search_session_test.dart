import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/browse_filters.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/search_results.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/catalog_cards_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/widgets/search/search_zero_state.dart';

/// Minimal fake proxy: only the methods the search session calls are
/// implemented; everything else throws if unexpectedly invoked.
class _FakeApi implements KalinkaPlayerProxy {
  int aiSearchCalls = 0;
  int matchCalls = 0;
  final List<String> queries = [];
  final List<String> aiSources = [];
  final List<String> matchSources = [];

  @override
  Future<BrowseItemsList> aiSearch(
    String query, {
    int offset = 0,
    int limit = 10,
    List<String>? sources,
  }) async {
    aiSearchCalls++;
    aiSources.add(sources!.single);
    return _inspiredFor(sources.single);
  }

  @override
  Future<BrowseItemsList> searchMatches(
    String query, {
    List<String>? sources,
  }) async {
    matchCalls++;
    queries.add(query);
    matchSources.add(sources!.single);
    return _matchesFor(sources.single);
  }

  @override
  Future<BrowseItemsList> getFavorite(
    SearchType queryType, {
    int offset = 0,
    int limit = 10,
    String filter = '',
  }) async {
    return BrowseItemsList(0, limit, 1, [
      BrowseItem(
        id: 'kalinka:localfiles:track:fav_${queryType.name}',
        canBrowse: false,
        canAdd: true,
        timestamp: 1000,
        track: Track(
          id: 'fav_${queryType.name}',
          title: 'Favourite ${queryType.name}',
          duration: 120,
          performer: Artist(id: 'a', name: 'Someone'),
        ),
      ),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// The search that never answers — neither leg's future ever completes.
class _HangingApi extends _FakeApi {
  @override
  Future<BrowseItemsList> aiSearch(
    String query, {
    int offset = 0,
    int limit = 10,
    List<String>? sources,
  }) {
    aiSearchCalls++;
    return Completer<BrowseItemsList>().future;
  }

  @override
  Future<BrowseItemsList> searchMatches(String query, {List<String>? sources}) {
    matchCalls++;
    return Completer<BrowseItemsList>().future;
  }
}

/// A source whose name-match leg fails on the first ask and answers after.
class _FlakyApi extends _FakeApi {
  @override
  Future<BrowseItemsList> searchMatches(
    String query, {
    List<String>? sources,
  }) async {
    matchCalls++;
    if (matchCalls == 1) throw Exception('upstream down');
    return _matchesFor(sources!.single);
  }
}

/// Every source finds an artist and an album.
class _TwoKindApi extends _FakeApi {
  @override
  Future<BrowseItemsList> searchMatches(
    String query, {
    List<String>? sources,
  }) async {
    final list = await super.searchMatches(query, sources: sources);
    final source = sources!.single;
    return BrowseItemsList(0, 2, 2, [
      ...list.items,
      BrowseItem(
        id: 'kalinka:$source:album:al1',
        name: 'An Album',
        canBrowse: true,
        canAdd: true,
        album: Album(id: 'al1', title: 'An Album'),
        match: const NameMatch(tier: MatchTier.partial, score: 60),
      ),
    ]);
  }
}

/// Only qobuz finds an album, and its name-match leg fails the first time.
class _AlbumsLateApi extends _TwoKindApi {
  int _qobuzAsked = 0;

  @override
  Future<BrowseItemsList> searchMatches(
    String query, {
    List<String>? sources,
  }) async {
    if (sources!.single != 'qobuz') {
      matchCalls++;
      matchSources.add(sources.single);
      return _matchesFor(sources.single);
    }
    if (++_qobuzAsked == 1) {
      matchCalls++;
      throw Exception('upstream down');
    }
    return super.searchMatches(query, sources: sources);
  }
}

class _CollectionsApi extends _FakeApi {
  static const shelfId = 'kalinka:collections:catalog:collections';
  static const _rootId = 'kalinka:collections:catalog:root';

  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async {
    final items = switch (id) {
      '' => [
        BrowseItem(
          id: _rootId,
          name: 'Collections',
          canBrowse: true,
          canAdd: false,
          catalog: Catalog(id: _rootId, title: 'Collections'),
        ),
      ],
      _rootId => [
        BrowseItem(
          id: shelfId,
          name: 'Your collections',
          canBrowse: true,
          canAdd: false,
          catalog: Catalog(
            id: shelfId,
            title: 'Your collections',
            previewConfig: Preview(
              type: PreviewType.tile,
              contentType: PreviewContentType.playlist,
            ),
          ),
        ),
      ],
      _ => const <BrowseItem>[],
    };
    return BrowseItemsList(offset, limit, items.length, items);
  }
}

/// Pinned connection state — the real notifier arms a retry [Timer] that
/// would outlive widget tests.
class _FixedConnection extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

BrowseItem _track(String source, String id, String title) => BrowseItem(
  id: 'kalinka:$source:track:$id',
  canBrowse: false,
  canAdd: true,
  track: Track(
    id: id,
    title: title,
    duration: 200,
    performer: Artist(id: 'ar', name: 'An Artist'),
  ),
);

BrowseItemsList _matchesFor(String source) => BrowseItemsList(0, 1, 1, [
  BrowseItem(
    id: 'kalinka:$source:artist:a1',
    name: 'An Artist',
    canBrowse: true,
    canAdd: false,
    artist: Artist(id: 'a1', name: 'An Artist'),
    match: const NameMatch(tier: MatchTier.exact, score: 100),
  ),
]);

BrowseItemsList _inspiredFor(String source) => BrowseItemsList(0, 1, 1, [
  BrowseItem(
    id: 'kalinka:$source:catalog:ai',
    name: 'AI SUGGESTIONS',
    canBrowse: false,
    canAdd: false,
    catalog: Catalog(id: 'ai', title: 'AI SUGGESTIONS', sources: [source]),
    sections: [_track(source, 't1', 'Song A'), _track(source, 't2', 'Song B')],
  ),
]);

final _modules = <ModuleInfo>[
  ModuleInfo(
    name: 'qobuz',
    title: 'Qobuz',
    enabled: true,
    state: ModuleState.ready,
    capabilities: const [ModuleCapability.aiSearch],
  ),
];

/// A source that is searched by name but has no audio of its own to suggest —
/// the shape collections has.
final _nameOnlyModules = <ModuleInfo>[
  ModuleInfo(
    name: 'collections',
    title: 'Collections',
    enabled: true,
    state: ModuleState.ready,
    builtin: true,
  ),
];

final _twoSources = <ModuleInfo>[
  ..._modules,
  ModuleInfo(
    name: 'localfiles',
    title: 'Local Library',
    enabled: true,
    state: ModuleState.ready,
    capabilities: const [ModuleCapability.aiSearch],
  ),
];

/// Neither source suggests, so the kind facet is hidden.
final _twoNameOnlySources = <ModuleInfo>[
  for (final (name, title) in [('qobuz', 'Qobuz'), ('localfiles', 'Local')])
    ModuleInfo(
      name: name,
      title: title,
      enabled: true,
      state: ModuleState.ready,
    ),
];

const _genreField = FilterSpec(
  id: 'genre',
  kind: FilterKind.choice,
  label: 'Genre',
  ops: [FilterOp.any],
);
const _textField = FilterSpec(
  id: 'q',
  kind: FilterKind.text,
  label: 'Search albums',
);

/// Longer than the minimum loading hold.
const _settle = Duration(milliseconds: 900);

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'Kalinka.host': 'localhost',
      'Kalinka.port': 8080,
      'Kalinka.name': 'Test',
    });
    prefs = await SharedPreferences.getInstance();
  });

  ProviderContainer makeContainer(
    _FakeApi api, {
    List<ModuleInfo>? modules,
    Duration? modulesAfter,
    List<CatalogCardGroup> Function()? cardGroups,
  }) {
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        kalinkaProxyProvider.overrideWithValue(api),
        if (modulesAfter == null)
          sourceModulesProvider.overrideWith((ref) => modules ?? _modules)
        else
          sourceModulesProvider.overrideWith(
            (ref) => Future.delayed(modulesAfter, () => modules ?? _modules),
          ),
        connectionStateProvider.overrideWith(_FixedConnection.new),
        // The real provider opens the wire-event WebSocket (retry timer).
        playerStateProvider.overrideWithValue(PlaybackState.empty),
        // Keep the zero-state's catalog section inert (its real fetch arms a
        // refresh timer that would outlive the test).
        catalogCardGroupsProvider.overrideWith(
          (ref) async => cardGroups?.call() ?? const <CatalogCardGroup>[],
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('SearchSessionNotifier', () {
    test('opening loads favourites but fires no search', () async {
      final api = _FakeApi();
      final container = makeContainer(api);
      final notifier = container.read(searchSessionProvider.notifier);

      notifier.open();
      await Future.delayed(const Duration(milliseconds: 50));

      final state = container.read(searchSessionProvider);
      expect(state.isOpen, isTrue);
      expect(state.activeView, FindMusicView.catalogs);
      expect(state.resultsAvailable, isFalse);
      expect(state.recentFavourites, isNotEmpty);
      expect(api.matchCalls + api.aiSearchCalls, 0);
    });

    test(
      'submit asks every source twice and lands each leg on its own',
      () async {
        final api = _FakeApi();
        final container = makeContainer(api);
        final notifier = container.read(searchSessionProvider.notifier);
        notifier.open();

        notifier.submit('jazz for a rainy night');
        var state = container.read(searchSessionProvider);
        expect(state.activeView, FindMusicView.results);
        expect(state.resultsAvailable, isTrue);
        expect(state.searchQuery, 'jazz for a rainy night');
        expect(state.searchLoading, isTrue);

        await Future.delayed(const Duration(milliseconds: 900));
        state = container.read(searchSessionProvider);
        final results = state.results!;
        expect(state.searchLoading, isFalse);
        expect(results.matchesSettled, isTrue);
        expect(results.rankedMatches, hasLength(1));
        expect(results.inspiredGroups.single.tracks, hasLength(2));
        expect(api.matchCalls, 1);
        expect(api.aiSearchCalls, 1);
      },
    );

    test('a source with nothing to suggest is asked once, not twice', () async {
      final api = _FakeApi();
      final container = makeContainer(api, modules: _nameOnlyModules);
      final notifier = container.read(searchSessionProvider.notifier);
      notifier.open();

      notifier.submit('night');
      await Future.delayed(const Duration(milliseconds: 900));

      final results = container.read(searchSessionProvider).results!;
      expect(api.matchCalls, 1);
      expect(api.aiSearchCalls, 0);
      // No leg was asked of it, so it holds no row waiting for one.
      expect(results.inspiredGroups, isEmpty);
    });

    test('a new submit replaces the previous query', () async {
      final api = _FakeApi();
      final container = makeContainer(api);
      final notifier = container.read(searchSessionProvider.notifier);
      notifier.open();

      notifier.submit('one');
      notifier.submit('two');
      await Future.delayed(const Duration(milliseconds: 900));

      final state = container.read(searchSessionProvider);
      expect(state.searchQuery, 'two');
      expect(state.results!.query, 'two');
      // Superseded before its sources were even resolved, the first query
      // never reaches the network.
      expect(api.queries, ['two']);
      // Newest-first history.
      expect(state.history.take(2), ['two', 'one']);
    });

    test('a source that never answers is unavailable, leg by leg', () {
      fakeAsync((async) {
        final api = _HangingApi();
        final container = makeContainer(api);
        final notifier = container.read(searchSessionProvider.notifier);
        notifier.open();
        notifier.submit('jazz');
        async.flushMicrotasks();
        var results = container.read(searchSessionProvider).results!;
        expect(results.matches['qobuz'], isA<LegLoading>());
        expect(api.matchCalls, 1);

        // Just short of the cap the legs are still patiently loading…
        async.elapse(const Duration(seconds: 9));
        results = container.read(searchSessionProvider).results!;
        expect(results.matches['qobuz'], isA<LegLoading>());

        // …and past it each leg gives up and says so.
        async.elapse(const Duration(seconds: 2));
        final state = container.read(searchSessionProvider);
        results = state.results!;
        expect(results.matches['qobuz'], isA<LegFailed>());
        expect(results.inspired['qobuz'], isA<LegFailed>());
        expect(state.searchError, isNull);
      });
    });

    test('retry asks that one source for that one leg again', () async {
      final api = _FlakyApi();
      final container = makeContainer(api);
      final notifier = container.read(searchSessionProvider.notifier);
      notifier.open();

      notifier.submit('jazz');
      await Future.delayed(const Duration(milliseconds: 900));
      expect(
        container.read(searchSessionProvider).results!.matches['qobuz'],
        isA<LegFailed>(),
      );

      notifier.retry(ResultsLeg.matches, 'qobuz');
      expect(
        container.read(searchSessionProvider).results!.matches['qobuz'],
        isA<LegLoading>(),
      );
      await Future.delayed(const Duration(milliseconds: 900));
      final results = container.read(searchSessionProvider).results!;
      expect(results.matches['qobuz'], isA<LegReady>());
      expect(api.matchCalls, 2);
      expect(api.aiSearchCalls, 1, reason: 'the other leg is left alone');
    });

    test('narrowing keeps the query out of the facets', () async {
      final api = _FakeApi();
      final container = makeContainer(api);
      final notifier = container.read(searchSessionProvider.notifier);
      notifier.open();
      notifier.submit('jazz');

      notifier.setResultsFilter(
        const BrowseFilterQuery(text: 'jazz', type: SearchType.album),
      );

      final filter = container.read(searchSessionProvider).resultsFilter;
      expect(filter.type, SearchType.album);
      expect(filter.text, isEmpty);
      await Future.delayed(const Duration(milliseconds: 900));
    });

    test('clearing the search returns to Catalogs with nothing kept', () async {
      final api = _FakeApi();
      final container = makeContainer(api);
      final notifier = container.read(searchSessionProvider.notifier);
      notifier.open();
      notifier.submit('jazz');
      await Future.delayed(const Duration(milliseconds: 900));

      notifier.clearSearch();

      final state = container.read(searchSessionProvider);
      expect(state.activeView, FindMusicView.catalogs);
      expect(state.resultsAvailable, isFalse);
      expect(state.results, isNull);
      expect(state.searchQuery, isEmpty);
    });

    test('view switches are gated and layered', () async {
      final api = _FakeApi();
      final container = makeContainer(api);
      final notifier = container.read(searchSessionProvider.notifier);
      notifier.open();

      // Results is inert until a search has run.
      notifier.selectView(FindMusicView.results);
      expect(
        container.read(searchSessionProvider).activeView,
        FindMusicView.catalogs,
      );

      notifier.openCatalog(id: 'cat1', title: 'Popular Tracks');
      expect(container.read(searchSessionProvider).catalogPage.isRoot, isFalse);

      // Reselecting Catalogs while on a page returns to its root.
      notifier.selectView(FindMusicView.catalogs);
      expect(container.read(searchSessionProvider).catalogPage.isRoot, isTrue);

      notifier.submit('jazz');
      expect(
        container.read(searchSessionProvider).activeView,
        FindMusicView.results,
      );
      notifier.selectView(FindMusicView.catalogs);
      expect(
        container.read(searchSessionProvider).activeView,
        FindMusicView.catalogs,
      );
      // Results stays reachable once available.
      notifier.selectView(FindMusicView.results);
      expect(
        container.read(searchSessionProvider).activeView,
        FindMusicView.results,
      );
      await Future.delayed(const Duration(milliseconds: 900));
    });

    test('closing discards the workspace but keeps history', () async {
      final api = _FakeApi();
      final container = makeContainer(api);
      final notifier = container.read(searchSessionProvider.notifier);
      notifier.open();
      notifier.submit('jazz');
      notifier.submit('techno');
      await Future.delayed(const Duration(milliseconds: 900));

      notifier.close();
      var state = container.read(searchSessionProvider);
      expect(state.isOpen, isFalse);
      expect(state.resultsAvailable, isFalse);
      expect(state.results, isNull);
      expect(state.catalogPage.isRoot, isTrue);

      notifier.open();
      state = container.read(searchSessionProvider);
      // Newest-first history.
      expect(state.history.take(2), ['techno', 'jazz']);
    });
  });

  group('remembered filters', () {
    void expectChosen(BrowseFilterQuery filter) {
      expect(filter.type, SearchType.album);
      expect(filter.kind, ResultKind.nameMatches);
      expect(filter.sources, ['qobuz']);
      expect(filter.text, isEmpty, reason: 'the text is the query');
    }

    test(
      'a results filter outlives the search, the session and a restart',
      () async {
        final api = _TwoKindApi();
        final container = makeContainer(api, modules: _twoSources);
        final notifier = container.read(searchSessionProvider.notifier);
        BrowseFilterQuery filter() =>
            container.read(searchSessionProvider).resultsFilter;
        notifier.open();

        notifier.setResultsFilter(
          const BrowseFilterQuery(
            text: 'jazz',
            type: SearchType.album,
            kind: ResultKind.nameMatches,
            sources: ['qobuz'],
          ),
        );
        notifier.submit('jazz');
        expectChosen(filter());
        await Future.delayed(_settle);
        expectChosen(filter());

        notifier.submit('blues');
        expectChosen(filter());
        await Future.delayed(_settle);

        notifier.close();
        notifier.open();
        expectChosen(filter());
        notifier.submit('techno');
        await Future.delayed(_settle);
        expectChosen(filter());

        final restarted = makeContainer(api, modules: _twoSources);
        expectChosen(restarted.read(searchSessionProvider).resultsFilter);
      },
    );

    test('a VIEW ALL opens a block without becoming the choice', () async {
      final api = _TwoKindApi();
      final container = makeContainer(api, modules: _twoSources);
      final notifier = container.read(searchSessionProvider.notifier);
      notifier.open();
      notifier.submit('jazz');
      await Future.delayed(_settle);

      notifier.setResultsFilter(
        const BrowseFilterQuery(kind: ResultKind.nameMatches),
        remember: false,
      );
      expect(
        container.read(searchSessionProvider).resultsFilter.kind,
        ResultKind.nameMatches,
      );

      notifier.submit('blues');
      expect(
        container.read(searchSessionProvider).resultsFilter.isEmpty,
        isTrue,
      );
      await Future.delayed(_settle);
    });

    test('a facet changed after a VIEW ALL leaves the VIEW ALL out', () async {
      final api = _TwoKindApi();
      final container = makeContainer(api, modules: _twoSources);
      final notifier = container.read(searchSessionProvider.notifier);
      BrowseFilterQuery filter() =>
          container.read(searchSessionProvider).resultsFilter;
      notifier.open();
      notifier.submit('jazz');
      await Future.delayed(_settle);

      notifier.setResultsFilter(
        filter().copyWith(kind: ResultKind.nameMatches),
        remember: false,
      );
      notifier.setResultsFilter(filter().copyWith(type: SearchType.album));
      expect(filter().kind, ResultKind.nameMatches);
      expect(filter().type, SearchType.album);

      notifier.submit('blues');
      expect(filter().kind, isNull);
      expect(filter().type, SearchType.album);
      await Future.delayed(_settle);
      expect(api.aiSearchCalls, 4, reason: 'recommendations asked both times');
    });

    test(
      'a kind cut for lacking is kept through other changes and a retry brings it back',
      () async {
        final api = _AlbumsLateApi();
        final container = makeContainer(api, modules: _twoSources);
        final notifier = container.read(searchSessionProvider.notifier);
        SearchSessionState state() => container.read(searchSessionProvider);
        notifier.open();
        notifier.setResultsFilter(
          const BrowseFilterQuery(type: SearchType.album),
        );

        notifier.submit('jazz');
        await Future.delayed(_settle);
        expect(state().results!.matches['qobuz'], isA<LegFailed>());
        expect(state().resultsFilter.type, isNull);
        expect(state().resultsChoice.type, SearchType.album);

        notifier.setResultsFilter(
          state().resultsFilter.copyWith(order: NameMatchOrder.alphabetical),
        );
        expect(state().resultsChoice.type, SearchType.album);
        expect(state().resultsChoice.order, NameMatchOrder.alphabetical);

        notifier.retry(ResultsLeg.matches, 'qobuz');
        expect(state().results!.matches['qobuz'], isA<LegLoading>());
        expect(state().resultsFilter.type, isNull);
        expect(
          state().results!.narrow(state().resultsFilter).matches,
          isNotEmpty,
        );

        await Future.delayed(_settle);
        expect(state().results!.matches['qobuz'], isA<LegReady>());
        expect(state().resultsFilter.type, SearchType.album);
        expect(
          state().results!.narrow(state().resultsFilter).matches.single.name,
          'An Album',
        );

        final restarted = makeContainer(api, modules: _twoSources);
        final saved = restarted.read(searchSessionProvider).resultsFilter;
        expect(saved.type, SearchType.album);
        expect(saved.order, NameMatchOrder.alphabetical);
      },
    );

    test('a reset drops what the results hid of the choice too', () async {
      final api = _FakeApi();
      final container = makeContainer(api, modules: _twoNameOnlySources);
      final notifier = container.read(searchSessionProvider.notifier);
      notifier.open();
      notifier.setResultsFilter(
        const BrowseFilterQuery(type: SearchType.album, sources: ['qobuz']),
      );
      notifier.submit('night');
      await Future.delayed(_settle);
      expect(container.read(searchSessionProvider).resultsFilter.type, isNull);

      notifier.setResultsFilter(const BrowseFilterQuery());

      expect(
        container.read(searchSessionProvider).resultsChoice.isEmpty,
        isTrue,
      );
      expect(prefs.getString('Kalinka.resultsFilter'), isNull);
    });

    test(
      'an empty filter that changes nothing keeps what the results hid',
      () async {
        final api = _FakeApi();
        final container = makeContainer(api, modules: _nameOnlyModules);
        final notifier = container.read(searchSessionProvider.notifier);
        SearchSessionState state() => container.read(searchSessionProvider);
        notifier.open();
        notifier.setResultsFilter(
          const BrowseFilterQuery(kind: ResultKind.recommendations),
        );
        notifier.submit('jazz');
        await Future.delayed(_settle);
        expect(state().resultsFilter.isEmpty, isTrue);

        notifier.setResultsFilter(const BrowseFilterQuery());
        expect(state().resultsChoice.kind, ResultKind.recommendations);

        notifier.submit(
          'blues',
          filter: const BrowseFilterQuery(text: 'blues'),
        );
        await Future.delayed(_settle);
        expect(state().resultsChoice.kind, ResultKind.recommendations);
        expect(prefs.getString('Kalinka.resultsFilter'), isNotNull);
      },
    );

    test(
      'recommendations are not chosen where no source can suggest, but stay the choice',
      () async {
        final api = _FakeApi();
        final container = makeContainer(api, modules: _nameOnlyModules);
        final notifier = container.read(searchSessionProvider.notifier);
        notifier.open();
        notifier.setResultsFilter(
          const BrowseFilterQuery(kind: ResultKind.recommendations),
        );

        notifier.submit('jazz');
        await Future.delayed(_settle);

        final state = container.read(searchSessionProvider);
        expect(state.resultsFilterCapabilities.kind, FacetSupport.hidden);
        expect(state.resultsFilter.kind, isNull);
        expect(api.matchCalls, 1, reason: 'the name matches are asked');
        expect(
          state.results!.narrow(state.resultsFilter).matches,
          hasLength(1),
        );
        expect(state.resultsChoice.kind, ResultKind.recommendations);

        notifier.setResultsFilter(
          state.resultsFilter.copyWith(kind: ResultKind.nameMatches),
          remember: false,
        );
        expect(
          container.read(searchSessionProvider).resultsFilter.kind,
          ResultKind.nameMatches,
        );
      },
    );

    test(
      'a remembered source that is gone, or a facet the results hide, does not narrow them',
      () async {
        final api = _FakeApi();
        final container = makeContainer(api, modules: _twoNameOnlySources);
        final notifier = container.read(searchSessionProvider.notifier);
        notifier.open();
        notifier.setResultsFilter(
          const BrowseFilterQuery(
            type: SearchType.album,
            genreIds: ['jazz'],
            sources: ['jamendo', 'qobuz'],
          ),
        );

        notifier.submit('night');
        await Future.delayed(const Duration(milliseconds: 50));
        var state = container.read(searchSessionProvider);
        expect(state.resultsFilter.sources, ['qobuz']);
        expect(state.resultsFilter.type, SearchType.album);

        await Future.delayed(_settle);
        state = container.read(searchSessionProvider);
        final capabilities = state.resultsFilterCapabilities;
        expect(capabilities.type, FacetSupport.hidden);
        expect(capabilities.genre, FacetSupport.hidden);
        expect(state.resultsFilter.type, isNull);
        expect(state.resultsFilter.genreIds, isEmpty);
        expect(state.resultsFilter.sources, ['qobuz']);
        expect(
          state.results!.narrow(state.resultsFilter).matches,
          hasLength(1),
        );

        notifier.submit('day');
        expect(
          container.read(searchSessionProvider).resultsFilter.type,
          SearchType.album,
        );
        await Future.delayed(_settle);
      },
    );

    test(
      'a remembered filter this build cannot read is let go piece by piece',
      () {
        prefs.setString(
          'Kalinka.resultsFilter',
          '{"type":"album","kind":"someday","order":"alphabetical"}',
        );
        prefs.setString('Kalinka.catalogFilters', '[not json');
        final container = makeContainer(_FakeApi());

        final state = container.read(searchSessionProvider);
        expect(state.resultsFilter.type, SearchType.album);
        expect(state.resultsFilter.kind, isNull);
        expect(state.resultsFilter.order, NameMatchOrder.alphabetical);
        container
            .read(searchSessionProvider.notifier)
            .openCatalog(id: 'a', title: 'A', filters: const [_genreField]);
        expect(
          container.read(searchSessionProvider).catalogFilter.isEmpty,
          isTrue,
        );
      },
    );

    test('each catalog comes back under its own filter', () {
      final container = makeContainer(_FakeApi());
      final notifier = container.read(searchSessionProvider.notifier);
      BrowseFilterQuery filter() =>
          container.read(searchSessionProvider).catalogFilter;
      notifier.open();

      notifier.openCatalog(id: 'a', title: 'A', filters: const [_genreField]);
      notifier.setCatalogFilter(const BrowseFilterQuery(genreIds: ['jazz']));
      notifier.openCatalog(id: 'b', title: 'B', filters: const [_genreField]);
      expect(filter().isEmpty, isTrue);

      notifier.openCatalog(id: 'a', title: 'A', filters: const [_genreField]);
      expect(filter().genreIds, ['jazz']);

      notifier.backToCatalogsRoot();
      expect(filter().isEmpty, isTrue);
      notifier.close();
      final restarted = makeContainer(_FakeApi());
      restarted
          .read(searchSessionProvider.notifier)
          .openCatalog(id: 'a', title: 'A', filters: const [_genreField]);
      expect(restarted.read(searchSessionProvider).catalogFilter.genreIds, [
        'jazz',
      ]);
    });

    test('a catalog keeps only the facets its source still declares', () {
      final container = makeContainer(_FakeApi());
      final notifier = container.read(searchSessionProvider.notifier);
      notifier.openCatalog(
        id: 'a',
        title: 'A',
        filters: const [_textField, _genreField],
      );
      notifier.setCatalogFilter(
        const BrowseFilterQuery(text: 'blue', genreIds: ['jazz']),
      );

      notifier.openCatalog(id: 'a', title: 'A', filters: const [_textField]);

      final filter = container.read(searchSessionProvider).catalogFilter;
      expect(filter.text, 'blue');
      expect(filter.genreIds, isEmpty);
    });

    group('of catalogs no longer offered', () {
      const kept = 'kalinka:jamendo:catalog:popular';
      const gone = 'kalinka:jamendo:catalog:retired';

      setUp(() {
        prefs.setString(
          'Kalinka.catalogFilters',
          '{"$kept":{"genreIds":["jazz"]},"$gone":{"genreIds":["rock"]}}',
        );
      });

      Future<void> openUnder(
        List<CatalogCardGroup> Function() cardGroups,
      ) async {
        final container = makeContainer(_FakeApi(), cardGroups: cardGroups);
        container.read(searchSessionProvider.notifier).open();
        await Future.delayed(const Duration(milliseconds: 50));
      }

      test('are forgotten once the catalog list loads', () async {
        await openUnder(
          () => const [
            CatalogCardGroup(
              sourceName: 'jamendo',
              sourceTitle: 'Jamendo',
              cards: [
                CatalogCardPlan(
                  id: kept,
                  title: 'Popular',
                  sourceName: 'jamendo',
                ),
              ],
            ),
          ],
        );

        expect(prefs.getString('Kalinka.catalogFilters'), contains(kept));
        expect(
          prefs.getString('Kalinka.catalogFilters'),
          isNot(contains(gone)),
        );
      });

      test('are kept when the list failed to load', () async {
        await openUnder(() => throw StateError('server unreachable'));

        expect(prefs.getString('Kalinka.catalogFilters'), contains(gone));
      });

      test('are kept while their source lists nothing', () async {
        await openUnder(
          () => const [
            CatalogCardGroup(
              sourceName: 'qobuz',
              sourceTitle: 'Qobuz',
              cards: [
                CatalogCardPlan(
                  id: 'kalinka:qobuz:catalog:new',
                  title: 'New',
                  sourceName: 'qobuz',
                ),
              ],
            ),
          ],
        );

        final saved = prefs.getString('Kalinka.catalogFilters');
        expect(saved, contains(kept));
        expect(saved, contains(gone));
      });

      test('are judged only once the sources have loaded', () async {
        const collections = _CollectionsApi.shelfId;
        const gone = 'kalinka:collections:catalog:retired';
        prefs.setString(
          'Kalinka.catalogFilters',
          '{"$collections":{"text":"night"},"$gone":{"genreIds":["rock"]}}',
        );
        final container = makeContainer(
          _CollectionsApi(),
          modules: _nameOnlyModules,
          modulesAfter: const Duration(milliseconds: 20),
        );
        container.read(searchSessionProvider.notifier).open();
        await Future.delayed(const Duration(milliseconds: 100));

        final saved = prefs.getString('Kalinka.catalogFilters');
        expect(saved, contains(collections));
        expect(saved, isNot(contains(gone)));
      });
    });
  });

  group('legs the filter shuts out', () {
    test('a source left out is not asked until it is let back in', () async {
      final api = _FakeApi();
      final container = makeContainer(api, modules: _twoSources);
      final notifier = container.read(searchSessionProvider.notifier);
      SearchSessionState state() => container.read(searchSessionProvider);
      notifier.open();
      notifier.setResultsFilter(const BrowseFilterQuery(sources: ['qobuz']));

      notifier.submit('jazz');
      await Future.delayed(_settle);

      expect(api.matchSources, ['qobuz']);
      expect(api.aiSources, ['qobuz']);
      var results = state().results!;
      expect(results.matches['localfiles'], isA<LegNotRequested>());
      expect(results.inspired['localfiles'], isA<LegNotRequested>());
      expect(results.matchesSettled, isTrue);
      expect(results.settled, isTrue);
      expect(results.unavailableMatchSources, isEmpty);
      expect(results.inspiredGroups.map((g) => g.source), ['qobuz']);
      expect(
        state().resultsFilterCapabilities.sources.map((s) => s.name),
        containsAll(['qobuz', 'localfiles']),
      );

      notifier.setResultsFilter(
        const BrowseFilterQuery(sources: ['qobuz', 'localfiles']),
      );
      results = state().results!;
      expect(results.matches['localfiles'], isA<LegLoading>());
      expect(results.inspired['localfiles'], isA<LegLoading>());

      await Future.delayed(_settle);
      expect(api.matchSources, ['qobuz', 'localfiles']);
      expect(api.aiSources, ['qobuz', 'localfiles']);
      results = state().results!;
      expect(results.matches['localfiles'], isA<LegReady>());
      expect(results.rankedMatches, hasLength(2));
    });

    test(
      'a source let back in keeps a kind cut for lacking until it answers',
      () async {
        final api = _FakeApi();
        final container = makeContainer(api, modules: _twoSources);
        final notifier = container.read(searchSessionProvider.notifier);
        SearchSessionState state() => container.read(searchSessionProvider);
        notifier.open();
        notifier.setResultsFilter(
          const BrowseFilterQuery(type: SearchType.album, sources: ['qobuz']),
        );

        notifier.submit('jazz');
        await Future.delayed(_settle);
        expect(state().resultsFilter.type, isNull);

        notifier.setResultsFilter(
          state().resultsFilter.copyWith(sources: ['qobuz', 'localfiles']),
        );
        expect(state().results!.matches['localfiles'], isA<LegLoading>());
        expect(state().resultsFilter.type, isNull);
        expect(state().resultsChoice.type, SearchType.album);
        expect(
          state().results!.narrow(state().resultsFilter).matches,
          isNotEmpty,
        );
        await Future.delayed(_settle);
      },
    );

    test('a block left out is not asked until it is let back in', () async {
      final api = _FakeApi();
      final container = makeContainer(api, modules: _twoSources);
      final notifier = container.read(searchSessionProvider.notifier);
      notifier.open();
      notifier.setResultsFilter(
        const BrowseFilterQuery(kind: ResultKind.nameMatches),
      );

      notifier.submit('jazz');
      await Future.delayed(_settle);
      expect(api.matchCalls, 2);
      expect(api.aiSearchCalls, 0);

      notifier.submit('blues');
      await Future.delayed(_settle);
      expect(api.aiSearchCalls, 0);

      notifier.setResultsFilter(const BrowseFilterQuery());
      await Future.delayed(_settle);
      expect(api.matchCalls, 4, reason: 'what was answered is not asked again');
      expect(api.aiSearchCalls, 2);
      expect(
        container.read(searchSessionProvider).results!.inspiredGroups,
        hasLength(2),
      );
    });

    test(
      'a saved kind that would ask no one is set aside for the search',
      () async {
        final api = _FakeApi();
        final container = makeContainer(
          api,
          modules: [..._nameOnlyModules, ..._modules],
        );
        final notifier = container.read(searchSessionProvider.notifier);
        notifier.open();
        notifier.setResultsFilter(
          const BrowseFilterQuery(
            kind: ResultKind.recommendations,
            sources: ['collections'],
          ),
        );

        notifier.submit('jazz');
        await Future.delayed(_settle);

        final state = container.read(searchSessionProvider);
        expect(api.matchSources, ['collections']);
        expect(api.aiSearchCalls, 0);
        expect(state.resultsFilter.kind, isNull);
        expect(state.resultsFilter.sources, ['collections']);
        expect(
          state.results!.narrow(state.resultsFilter).matches,
          hasLength(1),
        );

        final restarted = makeContainer(
          _FakeApi(),
          modules: [..._nameOnlyModules, ..._modules],
        );
        expect(
          restarted.read(searchSessionProvider).resultsFilter.kind,
          ResultKind.recommendations,
        );
      },
    );
  });

  group('SearchZeroState', () {
    testWidgets('shows the catalogs divider and favourites', (tester) async {
      final api = _FakeApi();
      final container = makeContainer(api);
      container.read(searchSessionProvider.notifier).open();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SearchZeroState(onOpenCatalog: (_, __, {focusItemId}) {}),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('EXPLORE CATALOGS'), findsOneWidget);
      expect(find.text('RECENTLY FAVOURITED'), findsOneWidget);
    });
  });
}
