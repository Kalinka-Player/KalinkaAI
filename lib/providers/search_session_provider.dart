import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data_model/browse_filters.dart';
import '../data_model/data_model.dart';
import '../data_model/search_results.dart';
import 'catalog_cards_provider.dart';
import 'collections_provider.dart';
import 'connection_settings_provider.dart';
import 'kalinka_player_api_provider.dart';
import 'source_modules_provider.dart';

/// Persistent history of submitted search prompts (most-recent first).
const _historyKey = 'Kalinka.chatSearchHistory';
const _maxHistoryItems = 5;
const _minHistoryQueryLength = 2;

const _resultsFilterKey = 'Kalinka.resultsFilter';

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

/// A block expanded with View all, independently of saved filters.
typedef ExpandedBlock = ({ResultKind kind, String? source});

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

  /// The chosen filter, limited to facets available in these results.
  final BrowseFilterQuery resultsFilter;

  /// Retains chosen facets even when the current results do not support them.
  final BrowseFilterQuery resultsChoice;

  /// Labels for saved genres, available before the next search answers.
  final Map<String, String> resultsGenreNames;

  /// One source picked out of the name matches, or null for all of them.
  ///
  /// Narrower than [resultsFilter]'s source facet and subordinate to it: it
  /// says which of the sources that survived the filter is being read right
  /// now, and it reaches the name matches alone. Recommendations are already
  /// a block per source, so there is nothing there to pick apart.
  final String? matchSource;

  /// Temporary navigation state; excluded from saved filters.
  final ExpandedBlock? expandedBlock;

  /// Root screen, or the one open catalog page. Its item data is fetched by the
  /// page view via `browseDetailProvider(id)` (cached across view switches).
  final CatalogPage catalogPage;

  /// Filters applied to [catalogPage]. Lives here rather than inside the page
  /// because the control that edits it sits in the title bar, a sibling of the
  /// page. Remembered per category.
  final BrowseFilterQuery catalogFilter;

  /// Shelf opened with View all; excluded from saved filters.
  final SearchType? expandedShelf;

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
    this.resultsChoice = const BrowseFilterQuery(),
    this.resultsGenreNames = const {},
    this.matchSource,
    this.expandedBlock,
    this.catalogPage = const CatalogPage.root(),
    this.catalogFilter = const BrowseFilterQuery(),
    this.expandedShelf,
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
  BrowseFilterCapabilities get resultsFilterCapabilities => _capabilitiesFor(
    results,
    holding: results?.settled == false ? resultsFilter : null,
    genreNames: resultsGenreNames,
  );

  BrowseFilterQuery get resultsShown => switch (expandedBlock) {
    null => resultsFilter,
    (:final kind, :final source) => resultsFilter.copyWith(
      kind: kind,
      sources: source == null ? null : [source],
    ),
  };

  /// Pending selections stay editable until all requests have answered.
  /// Set [gatherHeld] to false to skip type and genre validation.
  static BrowseFilterCapabilities _capabilitiesFor(
    SearchResults? results, {
    bool gatherHeld = true,
    BrowseFilterQuery? holding,
    Map<String, String> genreNames = const {},
  }) {
    if (results == null) return const BrowseFilterCapabilities();
    final present = gatherHeld
        ? {...results.typesPresent, if (holding?.type != null) holding!.type!}
        : BrowseFilterCapabilities.allTypes.toSet();
    final types = [
      for (final type in BrowseFilterCapabilities.allTypes)
        if (present.contains(type)) type,
    ];
    final genres = gatherHeld ? results.genresPresent : null;
    if (genres != null && holding != null) {
      final offered = {for (final genre in genres) genre.id};
      for (final id in holding.genreIds) {
        if (offered.add(id)) {
          genres.add(Genre(id: id, name: genreNames[id] ?? id));
        }
      }
    }
    return BrowseFilterCapabilities(
      text: FacetSupport.supported,
      kind: results.inspired.isEmpty
          ? FacetSupport.hidden
          : FacetSupport.supported,
      type: types.length > 1 || holding?.type != null
          ? FacetSupport.supported
          : FacetSupport.hidden,
      types: types,
      presentTypes: types.toSet(),
      source: results.sources.length > 1
          ? FacetSupport.supported
          : FacetSupport.hidden,
      sources: results.sources,
      genre: genres != null && genres.isEmpty
          ? FacetSupport.hidden
          : FacetSupport.supported,
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
    BrowseFilterQuery? resultsChoice,
    Map<String, String>? resultsGenreNames,
    String? matchSource,
    bool clearMatchSource = false,
    ExpandedBlock? expandedBlock,
    bool clearExpandedBlock = false,
    CatalogPage? catalogPage,
    BrowseFilterQuery? catalogFilter,
    SearchType? expandedShelf,
    bool clearExpandedShelf = false,
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
      resultsChoice: resultsChoice ?? this.resultsChoice,
      resultsGenreNames: resultsGenreNames ?? this.resultsGenreNames,
      matchSource: clearMatchSource ? null : (matchSource ?? this.matchSource),
      expandedBlock: clearExpandedBlock
          ? null
          : (expandedBlock ?? this.expandedBlock),
      catalogPage: catalogPage ?? this.catalogPage,
      catalogFilter: catalogFilter ?? this.catalogFilter,
      expandedShelf: clearExpandedShelf
          ? null
          : (expandedShelf ?? this.expandedShelf),
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

  BrowseFilterQuery _savedResultsFilter = const BrowseFilterQuery();
  Map<String, String> _savedResultsGenreNames = {};
  Map<String, BrowseFilterQuery> _savedCatalogFilters = {};

  @override
  SearchSessionState build() {
    _prefs = ref.read(sharedPrefsProvider);
    ref.onDispose(() => _disposed = true);
    _savedResultsFilter = _loadResultsFilter();
    _savedCatalogFilters = _loadCatalogFilters();
    return SearchSessionState(
      history: _loadHistory(),
      resultsFilter: _savedResultsFilter,
      resultsChoice: _savedResultsFilter,
      resultsGenreNames: _savedResultsGenreNames,
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
    _forgetUnofferedCatalogs();
  }

  /// Close Find Music and discard the ephemeral workspace (results + catalog
  /// page). History is written live on each [submit], so nothing to fold here.
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
      resultsFilter: _savedResultsFilter,
      resultsChoice: _savedResultsFilter,
      clearMatchSource: true,
      clearExpandedBlock: true,
      catalogPage: const CatalogPage.root(),
      catalogFilter: const BrowseFilterQuery(),
      clearExpandedShelf: true,
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
        clearExpandedShelf: true,
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
          _savedCatalogFilters[id]?.fittedTo(page.filterCapabilities) ??
          const BrowseFilterQuery(),
      clearExpandedShelf: true,
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
      clearExpandedShelf: true,
    );
  }

  /// Saves the catalog filter. Choosing a type replaces an expanded shelf.
  void setCatalogFilter(BrowseFilterQuery filter, {bool reset = false}) {
    final id = state.catalogPage.id;
    if (id == null) return;
    _rememberCatalogFilter(
      id,
      _withChange(
        _savedCatalogFilters[id] ?? const BrowseFilterQuery(),
        shown: state.catalogFilter,
        next: filter,
        reset: reset,
      ),
    );
    state = state.copyWith(
      catalogFilter: filter,
      clearExpandedShelf: filter.type != null,
    );
  }

  void expandShelf(SearchType? type) {
    state = state.copyWith(
      expandedShelf: type,
      clearExpandedShelf: type == null,
    );
  }

  /// Preserves hidden facets unless the user resets or removes the last chip.
  static BrowseFilterQuery _withChange(
    BrowseFilterQuery base, {
    required BrowseFilterQuery shown,
    required BrowseFilterQuery next,
    bool reset = false,
  }) {
    if (reset) return next;
    if (next.isEmpty && !shown.isEmpty) return const BrowseFilterQuery();
    return base.withFacetsFrom(next, next.facetsChangedFrom(shown));
  }

  /// Submit [rawQuery]. No-op for blank input. Enables + selects Results and
  /// replaces the current query. This is the only path that fires a search —
  /// there is no search-as-you-type, and catalog taps bypass it.
  ///
  /// Requests name matches and recommendations separately for sources
  /// included by the saved filter.
  ///
  /// [filter] and [shown] carry the card's edited and original selections.
  void submit(
    String rawQuery, {
    BrowseFilterQuery? filter,
    BrowseFilterQuery? shown,
    bool reset = false,
  }) {
    final query = rawQuery.trim();
    if (query.isEmpty) return;
    if (filter != null) {
      _rememberResultsFilter(
        _withChange(
          _savedResultsFilter,
          shown: (shown ?? state.resultsFilter).copyWith(text: ''),
          next: filter.copyWith(text: ''),
          reset: reset,
        ),
      );
    }

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
      resultsFilter: _savedResultsFilter,
      resultsChoice: _savedResultsFilter,
      resultsGenreNames: _savedResultsGenreNames,
      clearMatchSource: true,
      clearExpandedBlock: true,
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

    final pending = SearchResults.pending(
      query,
      sources,
      suggesting: suggesting,
    );
    var choice = state.resultsChoice;
    var results = pending.askingOnly(_fitResultsFilter(choice, pending));
    if (results.settled && choice.kind != null) {
      // Fall back to name matches if none of the selected sources can suggest.
      choice = choice.copyWith(clearKind: true);
      results = pending.askingOnly(_fitResultsFilter(choice, pending));
    }
    state = state.copyWith(
      searchLoading: false,
      results: results,
      resultsChoice: choice,
      resultsFilter: _fitResultsFilter(choice, results),
    );
    for (final source in sources) {
      for (final leg in ResultsLeg.values) {
        if (results.legsOf(leg)[source.name] is LegLoading) {
          _runLeg(gen, query, source.name, leg);
        }
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
      resultsFilter: _fitResultsFilter(
        state.resultsChoice,
        results,
        holding: state.resultsFilter,
      ),
    );
  }

  /// Ask one source again for one leg — the source that was unavailable,
  /// without disturbing what the others already answered.
  void retry(ResultsLeg leg, String source) {
    final results = state.results?.withLeg(leg, source, const LegLoading());
    if (results == null) return;
    state = state.copyWith(
      results: results,
      resultsFilter: _fitResultsFilter(
        state.resultsChoice,
        results,
        holding: state.resultsFilter,
      ),
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

  /// Saves filter edits and starts requests the previous filter skipped.
  /// [shown] is the card's original selection, which may differ from the
  /// current filter if requests finished while the card was open.
  void setResultsFilter(
    BrowseFilterQuery filter, {
    BrowseFilterQuery? shown,
    bool reset = false,
  }) => _narrowResults(
    filter,
    shown: (shown ?? state.resultsFilter).copyWith(text: ''),
    reset: reset,
  );

  /// Clears saved filters, the selected source and any expanded block.
  void resetResults() => _narrowResults(
    const BrowseFilterQuery(),
    shown: state.resultsFilter,
    reset: true,
    clearNavigation: true,
  );

  void _narrowResults(
    BrowseFilterQuery filter, {
    required BrowseFilterQuery shown,
    bool reset = false,
    bool clearNavigation = false,
  }) {
    final next = filter.copyWith(text: '');
    _rememberResultsFilter(
      _withChange(_savedResultsFilter, shown: shown, next: next, reset: reset),
    );
    final choice = _withChange(
      state.resultsChoice,
      shown: shown,
      next: next,
      reset: reset,
    );
    var results = state.results;
    final unasked =
        results?.unaskedUnder(
          _fitResultsFilter(choice, results, judgeHeld: false),
        ) ??
        const <({ResultsLeg leg, String source})>[];
    for (final (:leg, :source) in unasked) {
      results = results!.withLeg(leg, source, const LegLoading());
    }
    final fitted = _fitResultsFilter(choice, results, holding: next);
    final picked = state.matchSource;
    final gone =
        picked != null &&
        fitted.sources.isNotEmpty &&
        !fitted.sources.contains(picked);
    final block = state.expandedBlock;
    state = state.copyWith(
      results: results,
      resultsChoice: choice,
      resultsGenreNames: _savedResultsGenreNames,
      resultsFilter: fitted,
      clearMatchSource: clearNavigation || gone,
      clearExpandedBlock:
          clearNavigation ||
          (block != null && !fitted.shows(block.kind, block.source)),
    );
    for (final (:leg, :source) in unasked) {
      _runLeg(_queryGen, state.searchQuery, source, leg);
    }
  }

  void expandBlock(ExpandedBlock? block) {
    state = state.copyWith(
      expandedBlock: block,
      clearExpandedBlock: block == null,
    );
  }

  /// Validates types and genres after all requests finish. [holding] keeps
  /// the current selection during retries. Set [judgeHeld] to false to skip
  /// validation when deciding which deferred requests to start.
  static BrowseFilterQuery _fitResultsFilter(
    BrowseFilterQuery choice,
    SearchResults? results, {
    bool judgeHeld = true,
    BrowseFilterQuery? holding,
  }) {
    if (results == null) return choice;
    var fitted = choice.fittedTo(
      SearchSessionState._capabilitiesFor(
        results,
        gatherHeld: judgeHeld && results.settled,
      ),
    );
    if (holding != null && !results.settled) {
      fitted = fitted.withFacetsFrom(holding, const {
        BrowseFacet.type,
        BrowseFacet.genre,
      });
    }
    return fitted;
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
      resultsFilter: _savedResultsFilter,
      resultsChoice: _savedResultsFilter,
      clearMatchSource: true,
      clearExpandedBlock: true,
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
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final names = decoded['genreNames'];
      _savedResultsGenreNames = {
        if (names is Map<String, dynamic>)
          for (final entry in names.entries)
            if (entry.value is String) entry.key: entry.value as String,
      };
      return BrowseFilterQuery.fromJson(decoded).copyWith(text: '');
    } catch (_) {
      return const BrowseFilterQuery();
    }
  }

  void _rememberResultsFilter(BrowseFilterQuery filter) {
    _savedResultsFilter = filter.copyWith(text: '');
    final names = {
      ..._savedResultsGenreNames,
      for (final genre in state.results?.genresPresent ?? <Genre>[])
        genre.id: genre.name,
    };
    _savedResultsGenreNames = {
      for (final id in filter.genreIds)
        if (names[id] case final name?) id: name,
    };
    if (_savedResultsFilter.isEmpty) {
      _prefs.remove(_resultsFilterKey);
    } else {
      _prefs.setString(
        _resultsFilterKey,
        jsonEncode({
          ..._savedResultsFilter.toJson(),
          if (_savedResultsGenreNames.isNotEmpty)
            'genreNames': _savedResultsGenreNames,
        }),
      );
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
    final saved = _savedCatalogFilters[id] ?? const BrowseFilterQuery();
    if (filter.facetsChangedFrom(saved).isEmpty) return;
    if (filter.isEmpty) {
      _savedCatalogFilters.remove(id);
    } else {
      _savedCatalogFilters[id] = filter;
    }
    _saveCatalogFilters();
  }

  void _saveCatalogFilters() {
    if (_savedCatalogFilters.isEmpty) {
      _prefs.remove(_catalogFiltersKey);
    } else {
      _prefs.setString(
        _catalogFiltersKey,
        jsonEncode({
          for (final MapEntry(key: id, value: filter)
              in _savedCatalogFilters.entries)
            id: filter.toJson(),
        }),
      );
    }
  }

  /// Removes filters for deleted catalogs. Sources missing from the catalog
  /// list keep their filters because they may only be offline or logged out.
  Future<void> _forgetUnofferedCatalogs() async {
    if (_savedCatalogFilters.isEmpty) return;
    final Set<String> listing;
    final Set<String> offered;
    try {
      // The collections shelf is missing until the module list lands.
      await ref.read(sourceModulesProvider.future);
      final (groups, collections) = await (
        ref.read(catalogCardGroupsProvider.future),
        ref.read(collectionsShelfProvider.future),
      ).wait;
      listing = {
        for (final group in groups) group.sourceName,
        if (collections != null) collections.plan.sourceName,
      };
      offered = {
        for (final group in groups)
          for (final card in group.cards) card.id,
        if (collections != null) collections.plan.id,
      };
    } catch (_) {
      return;
    }
    if (_disposed) return;
    final before = _savedCatalogFilters.length;
    _savedCatalogFilters.removeWhere(
      (id, _) => listing.contains(sourceOfId(id)) && !offered.contains(id),
    );
    if (_savedCatalogFilters.length != before) _saveCatalogFilters();
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
