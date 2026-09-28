import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data_model/browse_filters.dart';
import '../data_model/data_model.dart';
import '../data_model/search_results.dart';
import 'catalog_cards_provider.dart';
import 'connection_settings_provider.dart';
import 'kalinka_player_api_provider.dart';
import 'source_modules_provider.dart';

/// Persistent history of submitted search prompts (most-recent first).
const _historyKey = 'Kalinka.chatSearchHistory';
const _maxHistoryItems = 5;
const _minHistoryQueryLength = 2;

/// The results filter last chosen, which each new search starts under. Never
/// its text: on the results that is the query itself.
const _resultsFilterKey = 'Kalinka.resultsFilter';

/// Each catalog's filter last chosen, by catalog id. Kept apart because each
/// catalog declares its own fields, and fills its genres from its own
/// vocabulary.
const _catalogFiltersKey = 'Kalinka.catalogFilters';

/// Minimum time the "working…" state stays up, even if results resolve
/// instantly — the request may be slow, so the UI must always read as busy
/// rather than flickering a frame of loading.
const _minLoadingDuration = Duration(milliseconds: 650);

/// How long one source may take to answer one leg before the app gives up on
/// it. ai_search fronts an AI pipeline that can wedge without the HTTP layer
/// noticing, so the cap is deliberately tighter than the Dio receive timeout.
const _searchTimeout = Duration(seconds: 10);

/// How many suggestions the zero state asks the server for.
const _suggestionCount = 4;

/// Static fallback prompts for the zero state, shown until the server's
/// context-aware suggestions arrive (or when the fetch fails). Phrased the
/// way the retrieval stack handles well — concrete genre/instrument words,
/// no negation ("no vocals" retrieves vocals).
const _fallbackSuggestions = <SearchSuggestion>[
  SearchSuggestion(query: 'something melancholic for a late night'),
  SearchSuggestion(query: 'upbeat indie for a morning run'),
  SearchSuggestion(query: 'calm piano for deep focus'),
  SearchSuggestion(query: 'smooth jazz for a cozy evening'),
];

/// The two views of the Find Music workspace; Results sits one back-layer
/// above Catalogs (there are no tabs).
enum FindMusicView { catalogs, results }

/// The Catalogs view is either at its root (search invitation + catalog cards)
/// or on one selected catalog page. Navigation is exactly one level deep — a
/// page never opens another page; albums/artists/playlists unroll inline.
class CatalogPage {
  /// Stable browse id of the open catalog category; null on the root screen.
  final String? id;

  /// Category title, e.g. "Popular Albums" (shown in Playfair on the page).
  final String? title;

  /// Owning provider, e.g. "Jamendo" — shown with its source badge as the
  /// page's attribution line.
  final String? provider;

  /// Category description, e.g. "Most played this month" — the page subtitle.
  final String? description;

  /// Server-rendered card art path — reused as the page's header backdrop.
  final String? artPath;

  /// The fields this category's source declared for it, carried from the
  /// catalog the page was opened from.
  final List<FilterSpec> filters;

  /// The shelves this category is made of, one per entity kind it holds, as
  /// its source declared them. Each is a catalog to browse in its own right;
  /// empty for a category that is a single flat listing.
  final List<BrowseItem> sections;

  /// The server accepts writes that change what this listing holds — the
  /// collections screen. Its own actions manage the listing; each row carries
  /// the ones that change what is inside it.
  final bool canEdit;

  /// The row the page was opened on, if any: it starts unrolled and the page
  /// scrolls to it. Null when the page was opened at its top.
  final String? focusItemId;

  const CatalogPage.root()
    : id = null,
      title = null,
      provider = null,
      description = null,
      artPath = null,
      filters = const [],
      sections = const [],
      canEdit = false,
      focusItemId = null;

  const CatalogPage.category({
    required this.id,
    required this.title,
    this.provider,
    this.description,
    this.artPath,
    this.filters = const [],
    this.sections = const [],
    this.canEdit = false,
    this.focusItemId,
  });

  bool get isRoot => id == null;

  /// The same page with its landing instruction spent — see
  /// [SearchSessionNotifier.catalogFocusReached].
  CatalogPage withoutFocus() => CatalogPage.category(
    id: id,
    title: title,
    provider: provider,
    description: description,
    artPath: artPath,
    filters: filters,
    sections: sections,
    canEdit: canEdit,
  );

  /// The entity kinds this category holds, in the order its source listed
  /// them — one per section. Empty for a single-kind category, which is what
  /// keeps the kind facet off a page with nothing to choose between.
  List<SearchType> get sectionTypes => [
    for (final section in sections)
      if (typeOf(section) case final type?) type,
  ];

  /// The entity kind a shelf stands for, as its source declared it — null
  /// for a shelf that names no single kind.
  static SearchType? typeOf(BrowseItem section) {
    final contentType = section.catalog?.previewConfig?.contentType;
    return switch (contentType) {
      PreviewContentType.track => SearchType.track,
      PreviewContentType.album => SearchType.album,
      PreviewContentType.artist => SearchType.artist,
      PreviewContentType.playlist => SearchType.playlist,
      _ => null,
    };
  }

  /// What this category can be filtered by — whatever its source declared, and
  /// nothing more.
  ///
  /// The kind group shows only where the source declared a kind field AND
  /// said which kinds it holds — a category of one kind has nothing to choose
  /// between.
  ///
  /// A facet the source did not declare is hidden rather than muted: the
  /// server refuses a field it never offered, so there is no affordance to
  /// stand in for. Which facets a source offers differs per shelf — Jamendo
  /// filters its track shelf by genre and its album shelf only by text.
  BrowseFilterCapabilities get filterCapabilities {
    if (isRoot) return const BrowseFilterCapabilities();
    return BrowseFilterCapabilities.fromSpecs(
      filters,
      catalogId: id!,
      types: sectionTypes,
    );
  }
}

/// State for the Find Music workspace: two views (Catalogs / Results) with
/// independently preserved content, plus the persisted zero-state data.
/// Results holds a single current query — a new search replaces it.
class SearchSessionState {
  /// Whether the full-screen Find Music surface is open.
  final bool isOpen;

  /// The visible view. Switching is pure state — no back-stack.
  final FindMusicView activeView;

  /// Results is disabled until the first search is submitted; true thereafter
  /// for the life of the workspace.
  final bool resultsAvailable;

  final String searchQuery;

  /// What every source has answered so far, leg by leg. Null until the
  /// sources to ask are known.
  final SearchResults? results;

  /// True while the sources to ask are being resolved — before there is a
  /// leg to show as loading.
  final bool searchLoading;

  /// A failure before any source could be asked; per-source failures live
  /// in [results].
  final String? searchError;

  /// Narrows what [results] shows. Applied in hand — the results are already
  /// here — so nothing is refetched.
  ///
  /// The choice is remembered, so each search starts under the last one, cut
  /// to what its own results can be narrowed by.
  final BrowseFilterQuery resultsFilter;

  /// One source picked out of the name matches, or null for all of them.
  ///
  /// Narrower than [resultsFilter]'s source facet and subordinate to it: it
  /// says which of the sources that survived the filter is being read right
  /// now, and it reaches the name matches alone. Recommendations are already
  /// a block per source, so there is nothing there to pick apart.
  final String? matchSource;

  /// Root screen, or the one open catalog page. Its item data is fetched by the
  /// page view via `browseDetailProvider(id)` (cached across view switches).
  final CatalogPage catalogPage;

  /// Filters applied to [catalogPage]. Lives here rather than inside the page
  /// because the control that edits it sits in the title bar, a sibling of the
  /// page. Each category's own is remembered and comes back with it when it
  /// is opened again.
  final BrowseFilterQuery catalogFilter;

  final List<String> history;
  final List<BrowseItem> recentFavourites;
  final bool zeroStateLoading;

  /// Context-aware suggestions fetched from `/ai_search/suggestions` —
  /// matched to the listener's time of day and validated against the
  /// library. Empty until the first successful fetch.
  final List<SearchSuggestion> aiSuggestions;

  const SearchSessionState({
    this.isOpen = false,
    this.activeView = FindMusicView.catalogs,
    this.resultsAvailable = false,
    this.searchQuery = '',
    this.results,
    this.searchLoading = false,
    this.searchError,
    this.resultsFilter = const BrowseFilterQuery(),
    this.matchSource,
    this.catalogPage = const CatalogPage.root(),
    this.catalogFilter = const BrowseFilterQuery(),
    this.history = const [],
    this.recentFavourites = const [],
    this.zeroStateLoading = false,
    this.aiSuggestions = const [],
  });

  /// Prompts shown in the search overlay: the server's context-aware
  /// suggestions once fetched, static examples until then.
  List<SearchSuggestion> get suggestions =>
      aiSuggestions.isEmpty ? _fallbackSuggestions : aiSuggestions;

  /// What the results can be narrowed by: whatever they hold. A facet with
  /// nothing to choose between is hidden — one source, one kind.
  BrowseFilterCapabilities get resultsFilterCapabilities =>
      _capabilitiesFor(results);

  static BrowseFilterCapabilities _capabilitiesFor(SearchResults? results) {
    if (results == null) return const BrowseFilterCapabilities();
    final types = results.typesPresent;
    final genres = results.genresPresent;
    return BrowseFilterCapabilities(
      text: FacetSupport.supported,
      kind: FacetSupport.supported,
      type: types.length > 1 ? FacetSupport.supported : FacetSupport.hidden,
      types: types,
      presentTypes: types.toSet(),
      source: results.sources.length > 1
          ? FacetSupport.supported
          : FacetSupport.hidden,
      sources: results.sources,
      genre: genres.isEmpty ? FacetSupport.hidden : FacetSupport.supported,
      genreOptions: genres,
      order: FacetSupport.supported,
    );
  }

  SearchSessionState copyWith({
    bool? isOpen,
    FindMusicView? activeView,
    bool? resultsAvailable,
    String? searchQuery,
    SearchResults? results,
    bool clearResults = false,
    bool? searchLoading,
    String? searchError,
    bool clearError = false,
    BrowseFilterQuery? resultsFilter,
    String? matchSource,
    bool clearMatchSource = false,
    CatalogPage? catalogPage,
    BrowseFilterQuery? catalogFilter,
    List<String>? history,
    List<BrowseItem>? recentFavourites,
    bool? zeroStateLoading,
    List<SearchSuggestion>? aiSuggestions,
  }) {
    return SearchSessionState(
      isOpen: isOpen ?? this.isOpen,
      activeView: activeView ?? this.activeView,
      resultsAvailable: resultsAvailable ?? this.resultsAvailable,
      searchQuery: searchQuery ?? this.searchQuery,
      results: clearResults ? null : (results ?? this.results),
      searchLoading: searchLoading ?? this.searchLoading,
      searchError: clearError ? null : (searchError ?? this.searchError),
      resultsFilter: resultsFilter ?? this.resultsFilter,
      matchSource: clearMatchSource ? null : (matchSource ?? this.matchSource),
      catalogPage: catalogPage ?? this.catalogPage,
      catalogFilter: catalogFilter ?? this.catalogFilter,
      history: history ?? this.history,
      recentFavourites: recentFavourites ?? this.recentFavourites,
      zeroStateLoading: zeroStateLoading ?? this.zeroStateLoading,
      aiSuggestions: aiSuggestions ?? this.aiSuggestions,
    );
  }
}

class SearchSessionNotifier extends Notifier<SearchSessionState> {
  late SharedPreferences _prefs;

  /// Bumped on each [submit]; a resolving query whose generation no longer
  /// matches has been superseded and drops its result.
  int _queryGen = 0;

  bool _disposed = false;

  /// The results filter as last chosen — see [_resultsFilterKey].
  BrowseFilterQuery _resultsChoice = const BrowseFilterQuery();

  /// Each catalog's filter as last chosen — see [_catalogFiltersKey].
  Map<String, BrowseFilterQuery> _catalogChoices = {};

  @override
  SearchSessionState build() {
    _prefs = ref.read(sharedPrefsProvider);
    ref.onDispose(() => _disposed = true);
    _resultsChoice = _loadResultsFilter();
    _catalogChoices = _loadCatalogFilters();
    return SearchSessionState(
      history: _loadHistory(),
      resultsFilter: _resultsChoice,
    );
  }

  /// Open Find Music on the Catalogs root and refresh its data. Catalog
  /// cards reload on every open (shimmer meanwhile) — a stale set from the
  /// last session may miss sources added or re-indexed since.
  void open() {
    if (state.isOpen) return;
    state = state.copyWith(isOpen: true, history: _loadHistory());
    ref.read(catalogCardsReloadProvider.notifier).bump();
    _loadRecentFavourites();
    _loadSuggestions();
  }

  /// Close Find Music and discard the ephemeral workspace (results + catalog
  /// page). History is written live on each [submit], and filters on each
  /// choice, so nothing to fold here.
  void close() {
    if (!state.isOpen) return;
    state = state.copyWith(
      isOpen: false,
      activeView: FindMusicView.catalogs,
      resultsAvailable: false,
      searchQuery: '',
      clearResults: true,
      searchLoading: false,
      clearError: true,
      resultsFilter: _resultsChoice,
      clearMatchSource: true,
      catalogPage: const CatalogPage.root(),
      catalogFilter: const BrowseFilterQuery(),
      history: _loadHistory(),
    );
  }

  /// Switch view (pure state, no back-stack). Results is inert until a search
  /// has run. Reselecting Catalogs while on a page returns to its root.
  void selectView(FindMusicView view) {
    if (view == FindMusicView.results && !state.resultsAvailable) return;
    if (view == FindMusicView.catalogs &&
        state.activeView == FindMusicView.catalogs &&
        !state.catalogPage.isRoot) {
      state = state.copyWith(
        catalogPage: const CatalogPage.root(),
        catalogFilter: const BrowseFilterQuery(),
      );
      return;
    }
    if (view == state.activeView) return;
    state = state.copyWith(activeView: view);
  }

  /// Open a catalog category page directly by its stable browse id. Not
  /// recorded in search history — this is navigation, not a search.
  void openCatalog({
    required String id,
    required String title,
    String? provider,
    String? description,
    String? artPath,
    List<FilterSpec> filters = const [],
    List<BrowseItem> sections = const [],
    bool canEdit = false,
    String? focusItemId,
  }) {
    final page = CatalogPage.category(
      id: id,
      title: title,
      provider: provider,
      description: description,
      artPath: artPath,
      filters: filters,
      sections: sections,
      canEdit: canEdit,
      focusItemId: focusItemId,
    );
    state = state.copyWith(
      activeView: FindMusicView.catalogs,
      catalogPage: page,
      // The source may have dropped a field since the filter was chosen.
      catalogFilter:
          _catalogChoices[id]?.fittedTo(page.filterCapabilities) ??
          const BrowseFilterQuery(),
    );
  }

  /// The page has landed on the row it was opened by. Spending the focus
  /// keeps a row that is scrolled away and built again from jumping the list
  /// a second time.
  void catalogFocusReached() {
    if (state.catalogPage.focusItemId == null) return;
    state = state.copyWith(catalogPage: state.catalogPage.withoutFocus());
  }

  /// Return from a catalog page to the Catalogs root (the search screen).
  void backToCatalogsRoot() {
    if (state.catalogPage.isRoot) return;
    state = state.copyWith(
      catalogPage: const CatalogPage.root(),
      catalogFilter: const BrowseFilterQuery(),
    );
  }

  /// Apply a filter selection to the open catalog page. The page reloads only
  /// when the part of it the backend honours actually changed.
  ///
  /// The page opens under it again next time, unless [remember] is false — a
  /// shelf's View all, which narrows the page without being a choice of
  /// filter.
  void setCatalogFilter(BrowseFilterQuery filter, {bool remember = true}) {
    final id = state.catalogPage.id;
    if (id == null) return;
    if (remember) _rememberCatalogFilter(id, filter);
    state = state.copyWith(catalogFilter: filter);
  }

  /// Submit [rawQuery]. No-op for blank input. Enables + selects Results and
  /// replaces the current query. This is the only path that fires a search —
  /// there is no search-as-you-type, and catalog taps bypass it.
  ///
  /// Every source is asked twice, separately — for its name matches and for
  /// its recommendations — so each answer can land on its own.
  ///
  /// The search runs under the results filter last chosen, or under [filter]
  /// where the query was edited in the filter card alongside its facets.
  void submit(String rawQuery, {BrowseFilterQuery? filter}) {
    final query = rawQuery.trim();
    if (query.isEmpty) return;
    if (filter != null) _rememberResultsFilter(filter);

    // Dedup + move-to-front, so a repeated query jumps to the top of Recent
    // searches. Catalog navigation never reaches here, so it stays out of it.
    _appendHistory(query);
    final gen = ++_queryGen;
    state = state.copyWith(
      activeView: FindMusicView.results,
      resultsAvailable: true,
      searchQuery: query,
      clearResults: true,
      searchLoading: true,
      clearError: true,
      resultsFilter: _resultsChoice,
      clearMatchSource: true,
      history: _loadHistory(),
    );
    _runQuery(query, gen);
  }

  Future<void> _runQuery(String query, int gen) async {
    final settings = ref.read(connectionSettingsProvider);
    if (!settings.isSet) {
      _fail(gen, 'No server connected');
      return;
    }

    List<SourceOption> sources;
    Set<String> suggesting;
    try {
      final modules = await ref.read(sourceModulesProvider.future);
      sources = _inDisplayOrder(modules);
      suggesting = {
        for (final module in modules)
          if (module.can(ModuleCapability.aiSearch)) module.name,
      };
    } catch (e) {
      _fail(gen, 'Could not reach the server: $e');
      return;
    }
    if (_disposed || gen != _queryGen) return;

    final results = SearchResults.pending(
      query,
      sources,
      suggesting: suggesting,
    );
    state = state.copyWith(
      searchLoading: false,
      results: results,
      resultsFilter: _fitResultsFilter(state.resultsFilter, results),
    );
    for (final source in sources) {
      _runLeg(gen, query, source.name, ResultsLeg.matches);
      // A source with no audio of its own — collections — would answer this
      // empty, having held a row open while it did.
      if (suggesting.contains(source.name)) {
        _runLeg(gen, query, source.name, ResultsLeg.inspired);
      }
    }
  }

  void _fail(int gen, String message) {
    if (_disposed || gen != _queryGen) return;
    state = state.copyWith(searchLoading: false, searchError: message);
  }

  /// The listener's own library first, then the rest by name.
  static List<SourceOption> _inDisplayOrder(List<ModuleInfo> modules) {
    final sources = [
      for (final module in modules) (name: module.name, title: module.title),
    ];
    sources.sort((a, b) {
      final aLocal = isLocalSource(a.name);
      final bLocal = isLocalSource(b.name);
      if (aLocal != bLocal) return aLocal ? -1 : 1;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return sources;
  }

  Future<void> _runLeg(
    int gen,
    String query,
    String source,
    ResultsLeg leg,
  ) async {
    final start = DateTime.now();
    final api = ref.read(kalinkaProxyProvider);
    LegState outcome;
    try {
      final list = await switch (leg) {
        ResultsLeg.matches => api.searchMatches(query, sources: [source]),
        ResultsLeg.inspired => api.aiSearch(query, sources: [source]),
      }.timeout(_searchTimeout);
      outcome = LegReady(list);
    } on TimeoutException {
      outcome = const LegFailed('timed out');
    } catch (e) {
      outcome = LegFailed('$e');
    }
    await _holdMinimumLoading(start);
    if (_disposed || gen != _queryGen) return;
    final results = state.results?.withLeg(leg, source, outcome);
    if (results == null) return;
    state = state.copyWith(
      results: results,
      resultsFilter: _fitResultsFilter(state.resultsFilter, results),
    );
  }

  /// Ask one source again for one leg — the source that was unavailable,
  /// without disturbing what the others already answered.
  void retry(ResultsLeg leg, String source) {
    final results = state.results;
    if (results == null) return;
    state = state.copyWith(
      results: results.withLeg(leg, source, const LegLoading()),
    );
    _runLeg(_queryGen, state.searchQuery, source, leg);
  }

  Future<void> _holdMinimumLoading(DateTime start) async {
    final elapsed = DateTime.now().difference(start);
    final remaining = _minLoadingDuration - elapsed;
    if (remaining > Duration.zero) {
      await Future.delayed(remaining);
    }
  }

  /// Narrow the results. The query itself is not a facet here — a changed
  /// query is a new search, which is [submit]'s job.
  ///
  /// The searches after this one start under it too, unless [remember] is
  /// false — a block's VIEW ALL, which opens that block in full without being
  /// a choice of filter.
  void setResultsFilter(BrowseFilterQuery filter, {bool remember = true}) {
    if (remember) _rememberResultsFilter(filter);
    final fitted = _fitResultsFilter(filter.copyWith(text: ''), state.results);
    final picked = state.matchSource;
    final gone =
        picked != null &&
        fitted.sources.isNotEmpty &&
        !fitted.sources.contains(picked);
    state = state.copyWith(resultsFilter: fitted, clearMatchSource: gone);
  }

  /// [filter] cut to what [results] can be narrowed by, so a remembered facet
  /// the filter card does not offer cannot narrow them unseen. What the
  /// results hold grows until the last leg answers, so their kinds and genres
  /// are judged only then.
  static BrowseFilterQuery _fitResultsFilter(
    BrowseFilterQuery filter,
    SearchResults? results,
  ) {
    if (results == null) return filter;
    final fitted = filter.fittedTo(
      SearchSessionState._capabilitiesFor(results),
    );
    if (results.settled) return fitted;
    return fitted.copyWith(type: filter.type, genreIds: filter.genreIds);
  }

  /// Read one source's name matches, or all of them again with null.
  void setMatchSource(String? source) {
    state = state.copyWith(
      matchSource: source,
      clearMatchSource: source == null,
    );
  }

  /// Drop the search: no query, so no results, and back to Catalogs.
  void clearSearch() {
    _queryGen++;
    state = state.copyWith(
      activeView: FindMusicView.catalogs,
      resultsAvailable: false,
      searchQuery: '',
      clearResults: true,
      searchLoading: false,
      clearError: true,
      resultsFilter: _resultsChoice,
      clearMatchSource: true,
    );
  }

  /// Fetch context-aware suggestions for the zero state. The proxy sends the
  /// device's real UTC offset so "morning" is the listener's morning. Any
  /// failure keeps what is already shown (the static fallback or the last
  /// successful fetch).
  Future<void> _loadSuggestions() async {
    final settings = ref.read(connectionSettingsProvider);
    if (!settings.isSet) return;
    try {
      final api = ref.read(kalinkaProxyProvider);
      final result = await api.searchSuggestions(count: _suggestionCount);
      if (_disposed || result.suggestions.isEmpty) return;
      state = state.copyWith(aiSuggestions: result.suggestions);
    } catch (_) {
      // Zero state must render regardless — the fallback stays.
    }
  }

  Future<void> _loadRecentFavourites() async {
    final settings = ref.read(connectionSettingsProvider);
    if (!settings.isSet) return;
    final api = ref.read(kalinkaProxyProvider);
    state = state.copyWith(zeroStateLoading: true);
    try {
      final (tracks, albums, artists, playlists) = await (
        api.getFavorite(SearchType.track, limit: 5),
        api.getFavorite(SearchType.album, limit: 5),
        api.getFavorite(SearchType.artist, limit: 5),
        api.getFavorite(SearchType.playlist, limit: 5),
      ).wait;
      if (_disposed) return;

      final all = [
        ...tracks.items,
        ...albums.items,
        ...artists.items,
        ...playlists.items,
      ];
      // Newest first; entries without a timestamp sink to the bottom.
      all.sort((a, b) {
        if (a.timestamp == 0 && b.timestamp == 0) return 0;
        if (a.timestamp == 0) return 1;
        if (b.timestamp == 0) return -1;
        return b.timestamp.compareTo(a.timestamp);
      });

      state = state.copyWith(
        recentFavourites: all.take(6).toList(),
        zeroStateLoading: false,
      );
    } catch (_) {
      state = state.copyWith(zeroStateLoading: false);
    }
  }

  List<String> _loadHistory() {
    final json = _prefs.getString(_historyKey);
    if (json == null) return <String>[];
    try {
      // A fresh modifiable list — callers append/remove in place. Clamp on
      // load too, so a store written under an older (larger) cap shrinks
      // immediately rather than on the next append.
      final items = List<String>.from(
        (jsonDecode(json) as List).cast<String>(),
      );
      if (items.length > _maxHistoryItems) {
        items.removeRange(_maxHistoryItems, items.length);
      }
      return items;
    } catch (_) {
      return <String>[];
    }
  }

  void _appendHistory(String rawQuery) {
    final query = rawQuery.trim();
    if (query.length < _minHistoryQueryLength) return;
    final lower = query.toLowerCase();
    final history = _loadHistory()
      ..removeWhere((h) => h.toLowerCase() == lower);
    history.insert(0, query);
    if (history.length > _maxHistoryItems) {
      history.removeRange(_maxHistoryItems, history.length);
    }
    _prefs.setString(_historyKey, jsonEncode(history));
  }

  void removeHistoryItem(String query) {
    final history = _loadHistory()..remove(query);
    _prefs.setString(_historyKey, jsonEncode(history));
    state = state.copyWith(history: history);
  }

  void clearHistory() {
    _prefs.remove(_historyKey);
    state = state.copyWith(history: const []);
  }

  BrowseFilterQuery _loadResultsFilter() {
    final json = _prefs.getString(_resultsFilterKey);
    if (json == null) return const BrowseFilterQuery();
    try {
      return BrowseFilterQuery.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      ).copyWith(text: '');
    } catch (_) {
      return const BrowseFilterQuery();
    }
  }

  void _rememberResultsFilter(BrowseFilterQuery filter) {
    _resultsChoice = filter.copyWith(text: '');
    if (_resultsChoice.isEmpty) {
      _prefs.remove(_resultsFilterKey);
    } else {
      _prefs.setString(_resultsFilterKey, jsonEncode(_resultsChoice.toJson()));
    }
  }

  Map<String, BrowseFilterQuery> _loadCatalogFilters() {
    final json = _prefs.getString(_catalogFiltersKey);
    if (json == null) return {};
    try {
      return {
        for (final MapEntry(key: id, value: filter)
            in (jsonDecode(json) as Map<String, dynamic>).entries)
          if (filter is Map<String, dynamic>)
            id: BrowseFilterQuery.fromJson(filter),
      };
    } catch (_) {
      return {};
    }
  }

  void _rememberCatalogFilter(String id, BrowseFilterQuery filter) {
    if (filter.isEmpty) {
      _catalogChoices.remove(id);
    } else {
      _catalogChoices[id] = filter;
    }
    if (_catalogChoices.isEmpty) {
      _prefs.remove(_catalogFiltersKey);
    } else {
      _prefs.setString(
        _catalogFiltersKey,
        jsonEncode({
          for (final MapEntry(key: id, value: filter)
              in _catalogChoices.entries)
            id: filter.toJson(),
        }),
      );
    }
  }
}

final searchSessionProvider =
    NotifierProvider<SearchSessionNotifier, SearchSessionState>(
      SearchSessionNotifier.new,
    );

/// True while the animated search overlay (the focused entry + keyboard) is up.
/// The main screen watches it to drop the mini-player out of the way so the
/// keyboard and suggestions own the bottom of the screen.
class SearchEntryModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) {
    if (state != value) state = value;
  }
}

final searchEntryModeProvider = NotifierProvider<SearchEntryModeNotifier, bool>(
  SearchEntryModeNotifier.new,
);
