import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data_model/browse_filters.dart';
import '../data_model/data_model.dart';
import '../data_model/search_results.dart';
import 'box_control_provider.dart';
import 'catalog_cards_provider.dart';
import 'catalog_sources_provider.dart';
import 'catalog_section_provider.dart';
import 'collections_provider.dart';
import 'connection_settings_provider.dart';
import 'kalinka_player_api_provider.dart';
import 'source_modules_provider.dart';

/// Persistent history of submitted search prompts (most-recent first).
const _historyKey = 'Kalinka.chatSearchHistory';
const _maxHistoryItems = 5;
const _minHistoryQueryLength = 2;

const _resultsFilterKey = 'Kalinka.resultsFilter';

/// The source last picked out of the name matches, picked again for the next
/// search.
const _matchSourceKey = 'Kalinka.resultsSource';

/// Minimum time the "working…" state stays up, even if results resolve
/// instantly — the request may be slow, so the UI must always read as busy
/// rather than flickering a frame of loading.
const _minLoadingDuration = Duration(milliseconds: 650);

/// How long one source may take to answer one leg before the app gives up on
/// it. ai_search fronts an AI pipeline that can wedge without the HTTP layer
/// noticing, so the cap is deliberately tighter than the Dio receive timeout.
const _searchTimeout = Duration(seconds: 10);

/// How many visits Back can return through; older ones are forgotten.
const _maxVisits = 40;

/// How many suggestions the zero state asks the server for.
const _suggestionCount = 4;

/// How old Home's data may get before coming back to the app refreshes it.
const _staleAfter = Duration(minutes: 5);
const _pinnedPreviewsExpireAfter = Duration(hours: 1);

/// Suggestions are refetched past this age, or in a new hour, when the search
/// opens: they are picked for the time of day.
const _suggestionsStaleAfter = Duration(minutes: 20);

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

/// What an artist page lists: their releases, or their tracks.
enum ArtistRelation { albums, tracks }

/// The places the navigation rail lists, each keeping a history of its own:
/// Home, the latest search's results, each source, and collections.
abstract final class BrowseDestination {
  static const home = 'home';
  static const results = 'results';
  static const collections = 'collections';
  static String source(String name) => 'source:$name';

  /// The source [destination] is, or null for any other.
  static String? sourceOf(String destination) =>
      destination.startsWith('source:') ? destination.substring(7) : null;
}

/// A block expanded with View all, independently of saved filters.
typedef ExpandedBlock = ({ResultKind kind, String? source});

/// The Catalogs view is either at its root (Home) or on a browsed page: a
/// source, catalog, folder or entity, each a visit in the browsing history.
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

  /// The source's album total, retained even while only a page of tracks is
  /// loaded. Null means the page must wait for a complete list to add it up.
  final int? totalDurationSeconds;

  /// Server-rendered card art path — reused as the page's header backdrop.
  final String? artPath;

  /// [artPath]'s width over its height, where its source said.
  final double? artAspectRatio;

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

  /// The listing is a folder's: its subfolders, then its tracks, under a
  /// breadcrumb of the folders enclosing it.
  final bool folderLayout;

  /// Adding the id to the queue adds tracks — for a folder, whether any sit
  /// directly in it.
  final bool canAdd;
  final Preview? preview;

  /// The item the page was opened from, when it was one: an album, artist,
  /// playlist or collection keeps the metadata its listing already supplied.
  final BrowseItem? item;

  const CatalogPage.root()
    : id = null,
      title = null,
      provider = null,
      description = null,
      totalDurationSeconds = null,
      artPath = null,
      artAspectRatio = null,
      filters = const [],
      sections = const [],
      canEdit = false,
      folderLayout = false,
      canAdd = false,
      preview = null,
      item = null;

  const CatalogPage.category({
    required this.id,
    required this.title,
    this.provider,
    this.description,
    this.totalDurationSeconds,
    this.artPath,
    this.artAspectRatio,
    this.filters = const [],
    this.sections = const [],
    this.canEdit = false,
    this.folderLayout = false,
    this.canAdd = false,
    this.preview,
    this.item,
  });

  bool get isCatalog {
    try {
      return id != null && EntityId.fromString(id!).type == EntityType.catalog;
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'provider': provider,
    'description': description,
    'artPath': artPath,
    'artAspectRatio': artAspectRatio,
    'filters': filters.map((f) => f.toJson()).toList(),
    'sections': sections.map((s) => s.toJson()).toList(),
    'folderLayout': folderLayout,
    'canAdd': canAdd,
    'preview': preview?.toJson(),
  };

  factory CatalogPage.fromJson(Map<String, dynamic> json) =>
      CatalogPage.category(
        id: json['id'] as String,
        title: json['title'] as String,
        provider: json['provider'] as String?,
        description: json['description'] as String?,
        artPath: json['artPath'] as String?,
        artAspectRatio: validAspectRatio(json['artAspectRatio']),
        filters: FilterSpec.parseList(json['filters']),
        sections: [
          for (final item in json['sections'] as List? ?? [])
            BrowseItem.fromJson(Map<String, dynamic>.from(item as Map)),
        ],
        folderLayout: json['folderLayout'] == true,
        canAdd: json['canAdd'] == true,
        preview: json['preview'] == null
            ? null
            : Preview.fromJson(
                Map<String, dynamic>.from(json['preview'] as Map),
              ),
      );

  EntityType? get _entityType {
    final id = this.id;
    if (id == null) return null;
    try {
      return EntityId.fromString(id).type;
    } catch (_) {
      return null;
    }
  }

  /// An album's own page: its tracks under its cover, not a catalog.
  bool get isAlbum => _entityType == EntityType.album;

  /// An artist's own page: their releases and tracks.
  bool get isArtist => _entityType == EntityType.artist;

  /// A playlist's or a collection's own page: its ordered tracks.
  bool get isPlaylist => _entityType == EntityType.playlist;

  /// The listing a browsable [item] stands for, owned by [provider].
  factory CatalogPage.fromItem(BrowseItem item, {String? provider}) =>
      CatalogPage.category(
        id: item.id,
        title: item.catalog?.title ?? item.name,
        provider: provider,
        description:
            item.catalog?.description ??
            item.album?.artist?.name ??
            item.subname,
        totalDurationSeconds: item.album?.duration,
        artPath: item.image?.large ?? item.image?.small ?? artPathOf(item),
        artAspectRatio: (item.image?.large ?? item.image?.small) != null
            ? item.image?.aspectRatio
            : item.catalog?.image?.aspectRatio,
        filters: item.catalog?.filters ?? const [],
        sections: item.sections ?? const [],
        canEdit: item.canEdit,
        folderLayout: item.opensAsFolder,
        canAdd: item.canAdd,
        preview: item.catalog?.previewConfig,
        item: item,
      );

  /// A folder as [toFolderJson] kept it, owned by [provider].
  factory CatalogPage.savedFolder(
    Map<String, dynamic> json, {
    String? provider,
  }) => CatalogPage.category(
    id: json['id'] as String,
    title: json['title'] as String?,
    provider: provider,
    description: json['description'] as String?,
    artPath: json['artPath'] as String?,
    folderLayout: true,
    canAdd: json['canAdd'] == true,
  );

  /// What of a folder outlives the app: enough to show it again before its
  /// listing loads.
  Map<String, dynamic> toFolderJson() => {
    'id': id,
    if (title != null) 'title': title,
    if (description != null) 'description': description,
    if (artPath != null) 'artPath': artPath,
    'canAdd': canAdd,
  };

  bool get isRoot => id == null;

  /// The same page under another name, its item renamed with it so its menu
  /// and actions say the new one.
  CatalogPage retitled(String title) {
    final item = this.item;
    final playlist = item?.playlist;
    return CatalogPage.category(
      id: id,
      title: title,
      provider: provider,
      description: description,
      totalDurationSeconds: totalDurationSeconds,
      artPath: artPath,
      artAspectRatio: artAspectRatio,
      filters: filters,
      sections: sections,
      canEdit: canEdit,
      folderLayout: folderLayout,
      canAdd: canAdd,
      preview: preview,
      item: item?.copyWith(
        name: title,
        playlist: playlist == null
            ? null
            : Playlist(
                id: playlist.id,
                name: title,
                owner: playlist.owner,
                image: playlist.image,
                description: playlist.description,
                trackCount: playlist.trackCount,
                duration: playlist.duration,
              ),
      ),
    );
  }

  /// The entity kinds this category holds, in the order its source listed
  /// them — one per section. Empty for a single-kind category, which is what
  /// keeps the kind facet off a page with nothing to choose between.
  List<SearchType> get sectionTypes => [
    for (final section in sections) ?typeOf(section),
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

/// The browsing pane's current visit — Home, a page or a search's results —
/// together with the visits Back returns through and Home's own data.
///
/// A visit keeps everything it showed: its page, filters and folder, its
/// query, results and source shortcut. Opening a page, a complete listing or
/// a new search adds a visit; filtering and switching sources do not.
class SearchSessionState {
  /// The visible view of this visit.
  final FindMusicView activeView;

  /// Tells one visit from another, including two of the same page. Home is
  /// always 0.
  final int visitId;

  /// The visits Back returns through, oldest first. Each is a whole state of
  /// its own whose [previousVisits] is empty.
  final List<SearchSessionState> previousVisits;

  /// The [BrowseDestination] this visit, and those under it, belong to.
  final String destination;

  /// Every other destination as it was left, by destination: its visit,
  /// holding the visits under it, and nothing parked of its own.
  final Map<String, SearchSessionState> parked;

  /// Which search [results] answer; see [SearchSessionNotifier.submit].
  final int queryGen;

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

  /// The folders opened one inside another on a [CatalogPage.folderLayout]
  /// page, outermost first; empty at the page's own top.
  final List<CatalogPage> folderPath;

  /// Filters applied to [catalogPage]. Lives here rather than inside the page
  /// because the control that edits it sits in the title bar, a sibling of the
  /// page. Remembered per category.
  final BrowseFilterQuery catalogFilter;

  /// Shelf opened with View all; excluded from saved filters.
  final SearchType? expandedShelf;

  /// The relation an artist page shows. Switching it adds no visit.
  final ArtistRelation artistTab;

  final List<String> history;

  /// Context-aware suggestions fetched from `/ai_search/suggestions` —
  /// matched to the listener's time of day and validated against the
  /// library. Empty until the first successful fetch.
  final List<SearchSuggestion> aiSuggestions;

  const SearchSessionState({
    this.activeView = FindMusicView.catalogs,
    this.visitId = 0,
    this.previousVisits = const [],
    this.destination = BrowseDestination.home,
    this.parked = const {},
    this.queryGen = 0,
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
    this.folderPath = const [],
    this.catalogFilter = const BrowseFilterQuery(),
    this.expandedShelf,
    this.artistTab = ArtistRelation.albums,
    this.history = const [],
    this.aiSuggestions = const [],
  });

  /// What the catalog page lists now: the folder it was moved to, or the
  /// page itself.
  CatalogPage get shownListing =>
      folderPath.isEmpty ? catalogPage : folderPath.last;

  /// Home: nothing to go back to.
  bool get atHome => activeView == FindMusicView.catalogs && catalogPage.isRoot;

  /// Every visit kept: this one, those under it, and every other
  /// destination's.
  Iterable<SearchSessionState> get allVisits sync* {
    yield this;
    yield* previousVisits;
    for (final top in parked.values) {
      yield top;
      yield* top.previousVisits;
    }
  }

  /// This visit as a history keeps it, without what only the shown one holds.
  SearchSessionState get _snapshot =>
      copyWith(previousVisits: const [], parked: const {});

  /// Prompts shown in the search overlay: the server's context-aware
  /// suggestions once fetched, static examples until then.
  List<SearchSuggestion> get suggestions =>
      aiSuggestions.isEmpty ? _fallbackSuggestions : aiSuggestions;

  /// What the Filters card narrows the results by: what kind of music
  /// (artist, album, playlist, track) and genre, each while the results hold
  /// more than one. A source is picked on the name matches' own line, and a
  /// block opened in full is a page of its own.
  BrowseFilterCapabilities get resultsFilterCapabilities {
    final held = _capabilitiesFor(
      results,
      holding: results?.settled == false ? resultsFilter : null,
      genreNames: resultsGenreNames,
    );
    return BrowseFilterCapabilities(
      type: held.type,
      types: held.types,
      presentTypes: held.presentTypes,
      genre: held.genre,
      genreOptions: held.genreOptions,
    );
  }

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
    FindMusicView? activeView,
    int? visitId,
    List<SearchSessionState>? previousVisits,
    String? destination,
    Map<String, SearchSessionState>? parked,
    int? queryGen,
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
    List<CatalogPage>? folderPath,
    BrowseFilterQuery? catalogFilter,
    SearchType? expandedShelf,
    bool clearExpandedShelf = false,
    ArtistRelation? artistTab,
    List<String>? history,
    List<SearchSuggestion>? aiSuggestions,
  }) {
    return SearchSessionState(
      activeView: activeView ?? this.activeView,
      visitId: visitId ?? this.visitId,
      previousVisits: previousVisits ?? this.previousVisits,
      destination: destination ?? this.destination,
      parked: parked ?? this.parked,
      queryGen: queryGen ?? this.queryGen,
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
      folderPath: folderPath ?? this.folderPath,
      catalogFilter: catalogFilter ?? this.catalogFilter,
      expandedShelf: clearExpandedShelf
          ? null
          : (expandedShelf ?? this.expandedShelf),
      artistTab: artistTab ?? this.artistTab,
      history: history ?? this.history,
      aiSuggestions: aiSuggestions ?? this.aiSuggestions,
    );
  }
}

class SearchSessionNotifier extends Notifier<SearchSessionState> {
  late SharedPreferences _prefs;

  /// Bumped on each [submit]; a resolving query whose generation no longer
  /// matches has been superseded and drops its result.
  int _queryGen = 0;

  int _lastVisitId = 0;

  /// The destination shown before the current one, where dropping a search
  /// returns.
  String _cameFrom = BrowseDestination.home;

  bool _disposed = false;

  DateTime? _refreshedAt;
  DateTime? _pinnedPreviewsAt;

  /// When the shown suggestions were asked for; null until one succeeds.
  DateTime? _suggestionsAt;

  /// The shown search's filter as chosen, facets it hides included. Each
  /// search starts without one: a filter belongs to the search it narrowed.
  BrowseFilterQuery _savedResultsFilter = const BrowseFilterQuery();
  Map<String, String> _savedResultsGenreNames = {};
  Map<String, BrowseFilterQuery> _loadedCatalogFilters = {};
  ServerStorageKey? _catalogFiltersOf;

  /// Every server's saved folder paths, decoded from [_folderPathsJson].
  Map<String, List<Map<String, dynamic>>> _folderPaths = {};
  String? _folderPathsJson;

  /// The [ServerStorageKey.scope] of the server this session's pages came
  /// from; null until one is known.
  String? _sessionServer;

  /// The connected server's key while this session is that server's, so
  /// nothing left open on one server is kept for another. A call that saves
  /// what is kept per server calls [_followServer] before reading the state.
  ServerStorageKey? get _serverKey {
    final key = ref.read(serverStorageKeyProvider);
    if (key == null) return null;
    _sessionServer ??= key.scope;
    return key.scope == _sessionServer ? key : null;
  }

  /// The connected server's catalog filters, loaded again once another server
  /// answers. Nothing is kept until the server has said who it is.
  Map<String, BrowseFilterQuery> get _savedCatalogFilters {
    final server = _serverKey;
    if (server != _catalogFiltersOf) {
      _catalogFiltersOf = server;
      _loadedCatalogFilters = _loadCatalogFilters(server);
    }
    return _loadedCatalogFilters;
  }

  @override
  SearchSessionState build() {
    _prefs = ref.read(sharedPrefsProvider);
    ref.onDispose(() => _disposed = true);
    // Kept by earlier versions for every next search.
    _prefs.remove(_resultsFilterKey);
    _sessionServer = ref.read(serverStorageKeyProvider)?.scope;
    // Another server's results and pages mean nothing on this one.
    ref.listen(connectionSettingsProvider.select((s) => s.baseUrl), (
      previous,
      next,
    ) {
      if (previous == next) return;
      _sessionServer = null;
      _leaveServer();
    });
    // Nor do those of one that has taken over the address. Not at once: a
    // call that has read the state may be what read the new key.
    ref.listen(serverStorageKeyProvider, (_, next) {
      if (next != null) scheduleMicrotask(_followServer);
    });
    return SearchSessionState(
      history: _loadHistory(),
      resultsFilter: _savedResultsFilter,
      resultsChoice: _savedResultsFilter,
      resultsGenreNames: _savedResultsGenreNames,
    );
  }

  /// Refresh what Home fetches for itself: suggestions and the saved
  /// searches. The catalog and collection sections refetch on their own when
  /// the connection comes back.
  void refresh() {
    _refreshedAt = DateTime.now();
    _expirePinnedPreviews();
    state = state.copyWith(history: _loadHistory());
    _loadSuggestions();
  }

  /// Everything on Home, catalogs too, unless refreshed within [_staleAfter].
  /// The catalog sections keep showing while they refetch.
  /// Pinned previews keep their own, longer expiry; see
  /// [_expirePinnedPreviews].
  void refreshIfStale() {
    final at = _refreshedAt;
    if (at != null && DateTime.now().difference(at) < _staleAfter) return;
    _refreshCatalogs();
  }

  /// Everything on Home, pinned previews too. Completes once the sources and
  /// collections have reloaded, failed or not.
  Future<void> refreshAll() {
    _pinnedPreviewsAt = DateTime.now();
    ref.invalidate(pinnedPreviewProvider);
    return _refreshCatalogs();
  }

  /// Refetches pinned previews an hour after they were last refreshed. The
  /// first call only starts the clock: Home is fetching them already.
  void _expirePinnedPreviews() {
    final now = DateTime.now();
    final at = _pinnedPreviewsAt;
    if (at != null && now.difference(at) < _pinnedPreviewsExpireAfter) return;
    _pinnedPreviewsAt = now;
    if (at != null) ref.invalidate(pinnedPreviewProvider);
  }

  Future<void> _refreshCatalogs() async {
    ref.invalidate(catalogSourcesProvider);
    ref.invalidate(collectionsShelfProvider);
    refresh();
    try {
      await Future.wait([
        ref.read(catalogSourcesProvider.future),
        ref.read(collectionsShelfProvider.future),
      ]);
    } catch (_) {
      // Each section shows its own error.
    }
  }

  /// Refetch the suggestions if [_suggestionsStaleAfter] old or from an
  /// earlier hour, so a Home left open keeps up with the time of day.
  void refreshSuggestionsIfStale() {
    final at = _suggestionsAt;
    final now = DateTime.now();
    if (at != null &&
        now.difference(at) < _suggestionsStaleAfter &&
        now.hour == at.hour) {
      return;
    }
    _loadSuggestions();
  }

  /// Moves to [next] as a new visit, the current one becoming the one Back
  /// returns to. Home is the bottom of the history, so leaving it adds
  /// nothing to return through.
  void _visit(SearchSessionState next) {
    final stack = state.atHome
        ? const <SearchSessionState>[]
        : [...state.previousVisits, state._snapshot];
    state = next.copyWith(
      visitId: ++_lastVisitId,
      previousVisits: stack.length > _maxVisits
          ? stack.sublist(stack.length - _maxVisits)
          : stack,
    );
  }

  /// Return to the previous visit as it was left: its page, filters,
  /// folder, query, results and source shortcut. With none left in this
  /// destination, Home.
  void goBack() {
    final stack = state.previousVisits;
    if (stack.isEmpty) {
      if (state.destination == BrowseDestination.home) {
        backToCatalogsRoot();
      } else {
        showHome();
      }
      return;
    }
    final previous = stack.last;
    var next = previous.copyWith(
      previousVisits: stack.sublist(0, stack.length - 1),
      destination: state.destination,
      parked: state.parked,
      history: state.history,
      aiSuggestions: state.aiSuggestions,
      resultsAvailable:
          state.resultsAvailable ||
          previous.activeView == FindMusicView.results,
    );
    final List<({ResultsLeg leg, String source})> unanswered;
    if (previous.queryGen == _queryGen) {
      // The same search: whatever answered since belongs to it.
      unanswered = const [];
      next = next.copyWith(
        results: state.results,
        clearResults: state.results == null,
        searchLoading: state.searchLoading,
        searchError: state.searchError,
        clearError: state.searchError == null,
        resultsFilter: _fitResultsFilter(
          previous.resultsChoice,
          state.results,
          holding: previous.resultsFilter,
        ),
      );
    } else if (previous.activeView != FindMusicView.results) {
      // A page from before the latest search: that search stays the one
      // Home offers to return to, and keeps running.
      unanswered = const [];
      next = next.copyWith(
        queryGen: _queryGen,
        searchQuery: state.searchQuery,
        results: state.results,
        clearResults: state.results == null,
        searchLoading: state.searchLoading,
        searchError: state.searchError,
        clearError: state.searchError == null,
        resultsFilter: state.resultsFilter,
        resultsChoice: state.resultsChoice,
        resultsGenreNames: state.resultsGenreNames,
        matchSource: state.matchSource,
        clearMatchSource: state.matchSource == null,
        clearExpandedBlock: true,
      );
    } else {
      // A search a newer one replaced: what it still waited for is asked
      // again.
      final gen = ++_queryGen;
      unanswered = [
        for (final source in previous.results?.sources ?? <SourceOption>[])
          for (final leg in ResultsLeg.values)
            if (previous.results!.legsOf(leg)[source.name] is LegLoading)
              (leg: leg, source: source.name),
      ];
      final asking = previous.searchLoading && previous.searchQuery.isNotEmpty;
      // Still loading while it is asked again, as on submit.
      next = next.copyWith(queryGen: gen, searchLoading: asking);
      if (asking) {
        state = next;
        _runQuery(previous.searchQuery, gen);
        return;
      }
    }
    state = next;
    for (final (:leg, :source) in unanswered) {
      _runLeg(_queryGen, state.searchQuery, source, leg);
    }
  }

  /// Starts the session over if another server now answers at the address,
  /// and says whether it did: what was asked of the page shown is then moot.
  bool _followServer() {
    if (_disposed) return false;
    final next = ref.read(serverStorageKeyProvider)?.scope;
    if (next == null || next == _sessionServer) return false;
    final left = _sessionServer;
    _sessionServer = next;
    if (left == null) return false;
    _leaveServer();
    return true;
  }

  void _leaveServer() {
    resetToRoot();
    ref.read(catalogCardsReloadProvider.notifier).bump();
  }

  /// Back to the Catalogs root with the ephemeral workspace (results and the
  /// catalog page) discarded. History is written live on each [submit].
  void resetToRoot() {
    _queryGen++;
    _cameFrom = BrowseDestination.home;
    _savedResultsFilter = const BrowseFilterQuery();
    _savedResultsGenreNames = {};
    state = state.copyWith(
      visitId: 0,
      previousVisits: const [],
      destination: BrowseDestination.home,
      parked: const {},
      queryGen: _queryGen,
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
      folderPath: const [],
      catalogFilter: const BrowseFilterQuery(),
      clearExpandedShelf: true,
      history: _loadHistory(),
    );
  }

  /// Catalogs goes Home. Results reopens the last search, without asking
  /// again; it is inert until a search has run.
  void selectView(FindMusicView view) {
    if (view == FindMusicView.catalogs) {
      backToCatalogsRoot();
      return;
    }
    showResults();
  }

  /// [destination] in place of the one shown, which is kept as it was left
  /// unless [keepShown] is false. With [restore], as it was itself left;
  /// otherwise, or never shown, at the visit [start] makes. Showing the
  /// destination already shown does nothing.
  void _show(
    String destination, {
    required bool restore,
    required SearchSessionState Function() start,
    bool keepShown = true,
  }) {
    _followServer();
    if (destination == state.destination) return;
    final parked = {
      ...state.parked,
      if (keepShown) state.destination: state.copyWith(parked: const {}),
    };
    final left = parked.remove(destination);
    _cameFrom = state.destination;
    final next = restore && left != null
        ? _carry(left)
        : start().copyWith(previousVisits: const []);
    state = next.copyWith(destination: destination, parked: parked);
  }

  /// [visit] brought up to what has happened since it was left: the latest
  /// search and what it has found, the history and the suggestions.
  SearchSessionState _carry(SearchSessionState visit) {
    final next = visit.copyWith(
      history: state.history,
      aiSuggestions: state.aiSuggestions,
      resultsAvailable: state.resultsAvailable,
      queryGen: state.queryGen,
      searchQuery: state.searchQuery,
      results: state.results,
      clearResults: state.results == null,
      searchLoading: state.searchLoading,
      searchError: state.searchError,
      clearError: state.searchError == null,
    );
    if (visit.activeView == FindMusicView.results) {
      if (identical(visit.results, state.results)) return next;
      // Its own narrowing, fitted to what has arrived since.
      return next.copyWith(
        resultsFilter: _fitResultsFilter(
          visit.resultsChoice,
          state.results,
          holding: visit.resultsFilter,
        ),
      );
    }
    return next.copyWith(
      resultsFilter: state.resultsFilter,
      resultsChoice: state.resultsChoice,
      resultsGenreNames: state.resultsGenreNames,
      matchSource: state.matchSource,
      clearMatchSource: state.matchSource == null,
      clearExpandedBlock: true,
    );
  }

  /// Home at its top, with nothing under it.
  SearchSessionState _homeTop() => state.copyWith(
    activeView: FindMusicView.catalogs,
    visitId: 0,
    previousVisits: const [],
    catalogPage: const CatalogPage.root(),
    folderPath: const [],
    catalogFilter: const BrowseFilterQuery(),
    clearExpandedShelf: true,
  );

  /// Home as it was left.
  void showHome() =>
      _show(BrowseDestination.home, restore: true, start: _homeTop);

  /// The latest search's results. With [restore], as they were left, pages
  /// opened from them included; otherwise at the results themselves.
  void showResults({bool restore = true}) {
    if (!state.resultsAvailable ||
        state.destination == BrowseDestination.results) {
      return;
    }
    final left = state.parked[BrowseDestination.results];
    // Its earliest results visit; a long trail may have dropped it.
    final results = left == null
        ? null
        : [
            ...left.previousVisits,
            left,
          ].where((v) => v.activeView == FindMusicView.results).firstOrNull;
    _show(
      BrowseDestination.results,
      restore: restore,
      start: () => results == null
          // Kept nowhere: the search as the shown visit carries it.
          ? state.copyWith(
              activeView: FindMusicView.results,
              visitId: ++_lastVisitId,
              clearExpandedBlock: true,
            )
          : _carry(results),
    );
  }

  /// [source]'s pages. With [restore], as they were left; otherwise at the
  /// source's own page.
  void openSource(CatalogSource source, {bool restore = true}) => _show(
    BrowseDestination.source(source.module.name),
    restore: restore,
    start: () => _pageVisit(
      CatalogPage.fromItem(source.root, provider: source.module.title),
    ).copyWith(visitId: ++_lastVisitId),
  );

  /// The collections listing [plan] is and the collections opened from it.
  /// With [restore], as they were left; otherwise at the listing.
  void openCollections(CatalogCardPlan plan, {bool restore = true}) => _show(
    BrowseDestination.collections,
    restore: restore,
    start: () => _pageVisit(
      _planPage(plan, plan.title),
      restoreFolder: true,
    ).copyWith(visitId: ++_lastVisitId),
  );

  /// Open the page a catalog card stands for, under [provider]'s name.
  void openCatalogPlan(CatalogCardPlan plan, String provider) {
    final page = _planPage(plan, provider);
    openPage(page, restoreFolder: true);
  }

  static CatalogPage _planPage(CatalogCardPlan plan, String provider) =>
      CatalogPage.category(
        id: plan.id,
        title: plan.title,
        provider: provider,
        description: plan.description,
        totalDurationSeconds: plan.totalDurationSeconds,
        artPath: plan.artPath,
        artAspectRatio: plan.artAspectRatio,
        filters: plan.filters,
        sections: plan.sections,
        canEdit: plan.canEdit,
        folderLayout: plan.folderLayout,
        canAdd: plan.canAdd,
        preview: plan.preview,
      );

  /// The shown visit moved to [page], with the filter and folder kept for it.
  SearchSessionState _pageVisit(
    CatalogPage page, {
    BrowseFilterQuery? initialFilter,
    bool restoreFolder = false,
  }) => state.copyWith(
    activeView: FindMusicView.catalogs,
    catalogPage: page,
    folderPath: page.folderLayout && restoreFolder
        ? _savedFolderPath(page.id!, page.provider)
        : const [],
    // The source may have dropped a field since the filter was chosen.
    catalogFilter:
        (initialFilter ?? _savedCatalogFilters[page.id])?.fittedTo(
          page.filterCapabilities,
        ) ??
        const BrowseFilterQuery(),
    clearExpandedShelf: true,
    artistTab: ArtistRelation.albums,
  );

  /// Open a catalog category page directly by its stable browse id. Not
  /// recorded in search history — this is navigation, not a search.
  void openCatalog({
    required String id,
    required String title,
    String? provider,
    String? description,
    int? totalDurationSeconds,
    String? artPath,
    double? artAspectRatio,
    List<FilterSpec> filters = const [],
    List<BrowseItem> sections = const [],
    bool canEdit = false,
    bool folderLayout = false,
    bool canAdd = false,
    Preview? preview,
    BrowseFilterQuery? initialFilter,
    bool restoreFolder = true,
    BrowseItem? item,
  }) {
    _followServer();
    // An item's page already in the history is returned to rather than
    // stacked again, so album → artist → album cannot grow Back without end.
    if (item != null && initialFilter == null) {
      bool shows(SearchSessionState visit) =>
          visit.activeView == FindMusicView.catalogs &&
          visit.catalogPage.id == id &&
          visit.catalogPage.folderLayout == folderLayout &&
          visit.expandedShelf == null;
      final earlier = state.previousVisits.lastIndexWhere(shows);
      if (earlier >= 0) {
        state = state.copyWith(
          previousVisits: state.previousVisits.sublist(0, earlier + 1),
        );
        goBack();
        return;
      }
    }
    final page = CatalogPage.category(
      id: id,
      title: title,
      provider: provider,
      description: description,
      totalDurationSeconds: totalDurationSeconds,
      artPath: artPath,
      artAspectRatio: artAspectRatio,
      filters: filters,
      sections: sections,
      canEdit: canEdit,
      folderLayout: folderLayout,
      canAdd: canAdd,
      preview: preview,
      item: item,
    );
    _visit(
      _pageVisit(
        page,
        initialFilter: initialFilter,
        restoreFolder: restoreFolder,
      ),
    );
  }

  /// Show another of the artist page's relations in the same visit.
  void setArtistTab(ArtistRelation tab) {
    if (state.artistTab == tab) return;
    state = state.copyWith(artistTab: tab);
  }

  void openBrowseItem(BrowseItem item) {
    if (!item.canBrowse) return;
    final source = sourceOfId(item.id);
    final page = CatalogPage.fromItem(
      item,
      provider:
          ref.read(sourceDisplayInfoProvider)[source]?.title ??
          source ??
          state.catalogPage.provider,
    );
    openPage(page);
  }

  void openPage(
    CatalogPage page, {
    BrowseFilterQuery? filter,
    bool restoreFolder = false,
  }) {
    if (page.id == null) return;
    openCatalog(
      id: page.id!,
      title: page.title ?? '',
      provider: page.provider,
      description: page.description,
      totalDurationSeconds: page.totalDurationSeconds,
      artPath: page.artPath,
      artAspectRatio: page.artAspectRatio,
      filters: page.filters,
      sections: page.sections,
      canEdit: page.canEdit,
      folderLayout: page.folderLayout,
      canAdd: page.canAdd,
      preview: page.preview,
      initialFilter: filter,
      restoreFolder: restoreFolder,
      item: page.item,
    );
  }

  /// Calls the page of [id] [title] wherever a visit shows it — after a
  /// collection was renamed.
  void retitlePage(String id, String title) {
    SearchSessionState retitled(SearchSessionState visit) =>
        visit.catalogPage.id == id
        ? visit.copyWith(catalogPage: visit.catalogPage.retitled(title))
        : visit;
    SearchSessionState withStack(SearchSessionState top) => retitled(top)
        .copyWith(
          previousVisits: [
            for (final visit in top.previousVisits) retitled(visit),
          ],
        );
    state = withStack(state).copyWith(
      parked: {
        for (final MapEntry(:key, :value) in state.parked.entries)
          key: withStack(value),
      },
    );
  }

  /// Return one visit; see [goBack].
  void backFromCatalog() => goBack();

  /// Show [folder], listed in the folder shown now, in its place: moving
  /// between folders stays one visit, so Back leaves the page rather than
  /// retracing them. The trail is the folders that hold it.
  void openFolder(BrowseItem folder) {
    if (_followServer()) return;
    if (!state.catalogPage.folderLayout) {
      openBrowseItem(folder);
      return;
    }
    state = state.copyWith(
      folderPath: [
        ...state.folderPath,
        CatalogPage.fromItem(folder, provider: state.catalogPage.provider),
      ],
    );
    _rememberFolderPath();
  }

  /// Show the folder [depth] steps in from the page's top, which zero is.
  void showFolderAt(int depth) {
    if (_followServer()) return;
    if (depth < 0 || depth >= state.folderPath.length) return;
    state = state.copyWith(folderPath: state.folderPath.sublist(0, depth));
    _rememberFolderPath();
  }

  /// Show the folder enclosing the one shown.
  void showEnclosingFolder() => showFolderAt(state.folderPath.length - 1);

  /// Straight to Home's top, past every visit in it. Other destinations
  /// are kept as they were left.
  void backToCatalogsRoot() {
    if (state.destination == BrowseDestination.home) {
      if (state.atHome && state.previousVisits.isEmpty) return;
      state = _homeTop();
      return;
    }
    final parked = {...state.parked}..remove(BrowseDestination.home);
    state = state.copyWith(parked: parked);
    _show(BrowseDestination.home, restore: false, start: _homeTop);
  }

  /// Saves the catalog filter. Choosing a type replaces an expanded shelf.
  void setCatalogFilter(BrowseFilterQuery filter, {bool reset = false}) {
    if (_followServer()) return;
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

  /// Opens one shelf in full as a visit of its own; null returns from it.
  void expandShelf(SearchType? type) {
    if (type != null) {
      _visit(state.copyWith(expandedShelf: type));
      return;
    }
    final previous = state.previousVisits.lastOrNull;
    final filter = state.catalogFilter;
    if (previous != null &&
        previous.activeView == FindMusicView.catalogs &&
        previous.catalogPage.id == state.catalogPage.id &&
        previous.expandedShelf == null) {
      goBack();
      // The filter is the page's, chosen in either visit.
      state = state.copyWith(catalogFilter: filter);
      return;
    }
    state = state.copyWith(clearExpandedShelf: true);
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
  /// Requests name matches and recommendations separately from each source,
  /// with no filter yet.
  void submit(String rawQuery) {
    final query = rawQuery.trim();
    if (query.isEmpty) return;
    // A filter belongs to the search it narrowed: each starts without one.
    _savedResultsFilter = const BrowseFilterQuery();
    _savedResultsGenreNames = {};
    final matchSource = _prefs.getString(_matchSourceKey);

    // Dedup + move-to-front, so a repeated query jumps to the top of Recent
    // searches. Catalog navigation never reaches here, so it stays out of it.
    _appendHistory(query);
    final gen = ++_queryGen;
    // The search before it goes with its pages.
    final parked = {
      ...state.parked,
      if (state.destination != BrowseDestination.results)
        state.destination: state.copyWith(parked: const {}),
    }..remove(BrowseDestination.results);
    if (state.destination != BrowseDestination.results) {
      _cameFrom = state.destination;
    }
    state = state.copyWith(
      visitId: ++_lastVisitId,
      previousVisits: const [],
      destination: BrowseDestination.results,
      parked: parked,
      activeView: FindMusicView.results,
      queryGen: gen,
      resultsAvailable: true,
      searchQuery: query,
      clearResults: true,
      searchLoading: true,
      clearError: true,
      resultsFilter: _savedResultsFilter,
      resultsChoice: _savedResultsFilter,
      resultsGenreNames: _savedResultsGenreNames,
      matchSource: matchSource,
      clearMatchSource: matchSource == null,
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
      // Only a source with catalogs has anything to find, and the server's
      // own (collections), which answers by name without declaring any; the
      // rest would be asked for nothing and offered as a filter that finds
      // nothing.
      final modules = [
        for (final module in await ref.read(sourceModulesProvider.future))
          if (module.builtin || module.can(ModuleCapability.catalogs)) module,
      ];
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
    // Every source is asked: a search starts with no filter to leave one out.
    state = state.copyWith(
      searchLoading: false,
      results: pending,
      resultsFilter: _fitResultsFilter(state.resultsChoice, pending),
    );
    for (final source in sources) {
      for (final leg in ResultsLeg.values) {
        if (pending.legsOf(leg)[source.name] is LegLoading) {
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
  void resetResults() {
    _prefs.remove(_matchSourceKey);
    _narrowResults(
      const BrowseFilterQuery(),
      shown: state.resultsFilter,
      reset: true,
      clearNavigation: true,
    );
  }

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
    final fitted = _fitResultsFilter(choice, state.results, holding: next);
    final picked = state.matchSource;
    final gone =
        picked != null &&
        fitted.sources.isNotEmpty &&
        !fitted.sources.contains(picked);
    final block = state.expandedBlock;
    state = state.copyWith(
      resultsChoice: choice,
      resultsGenreNames: _savedResultsGenreNames,
      resultsFilter: fitted,
      clearMatchSource: clearNavigation || gone,
      clearExpandedBlock:
          clearNavigation ||
          (block != null && !fitted.shows(block.kind, block.source)),
    );
  }

  /// Opens one block of the results in full as a visit of its own; null
  /// returns from it.
  void expandBlock(ExpandedBlock? block) {
    if (block != null) {
      _visit(state.copyWith(expandedBlock: block));
      return;
    }
    final previous = state.previousVisits.lastOrNull;
    if (previous != null &&
        previous.activeView == FindMusicView.results &&
        previous.queryGen == state.queryGen &&
        previous.expandedBlock == null) {
      goBack();
      return;
    }
    state = state.copyWith(clearExpandedBlock: true);
  }

  /// Validates types and genres after all requests finish. [holding] keeps
  /// the current selection during retries.
  static BrowseFilterQuery _fitResultsFilter(
    BrowseFilterQuery choice,
    SearchResults? results, {
    BrowseFilterQuery? holding,
  }) {
    if (results == null) return choice;
    var fitted = choice.fittedTo(
      SearchSessionState._capabilitiesFor(results, gatherHeld: results.settled),
    );
    if (holding != null && !results.settled) {
      fitted = fitted.withFacetsFrom(holding, const {
        BrowseFacet.type,
        BrowseFacet.genre,
      });
    }
    return fitted;
  }

  /// Read one source's name matches, or all of them again with null; the
  /// next search starts on the same.
  void setMatchSource(String? source) {
    if (source == null) {
      _prefs.remove(_matchSourceKey);
    } else {
      _prefs.setString(_matchSourceKey, source);
    }
    state = state.copyWith(
      matchSource: source,
      clearMatchSource: source == null,
    );
  }

  /// Drop the search: leave its results for the visit before them, with no
  /// query left to return to.
  void clearSearch() {
    final parked = {...state.parked}..remove(BrowseDestination.results);
    state = state.copyWith(parked: parked);
    if (state.destination == BrowseDestination.results) {
      final back = parked.containsKey(_cameFrom)
          ? _cameFrom
          : BrowseDestination.home;
      // Past every visit of this search, an opened block's included.
      _show(
        back,
        restore: true,
        keepShown: false,
        // Any other is parked, so restored rather than started.
        start: _homeTop,
      );
    }
    _queryGen++;
    _savedResultsFilter = const BrowseFilterQuery();
    _savedResultsGenreNames = {};
    state = state.copyWith(
      queryGen: _queryGen,
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
    // Taken as fresh while asking, so opening search twice asks once.
    _suggestionsAt = DateTime.now();
    try {
      final api = ref.read(kalinkaProxyProvider);
      final result = await api.searchSuggestions(count: _suggestionCount);
      if (_disposed || result.suggestions.isEmpty) return;
      state = state.copyWith(aiSuggestions: result.suggestions);
    } catch (_) {
      // Zero state must render regardless — the fallback stays.
      _suggestionsAt = null;
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

  void _rememberResultsFilter(BrowseFilterQuery filter) {
    _savedResultsFilter = filter.copyWith(text: '');
    final names = {
      ..._savedResultsGenreNames,
      for (final genre in state.results?.genresPresent ?? <Genre>[])
        genre.id: genre.name,
    };
    _savedResultsGenreNames = {
      for (final id in filter.genreIds) id: ?names[id],
    };
  }

  Map<String, BrowseFilterQuery> _loadCatalogFilters(ServerStorageKey? server) {
    if (server == null) return {};
    final json = _prefs.getString(server.catalogFilters);
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
    final server = _catalogFiltersOf;
    if (server == null || !server.confirmed) return;
    final key = server.catalogFilters;
    if (_savedCatalogFilters.isEmpty) {
      _prefs.remove(key);
    } else {
      _prefs.setString(
        key,
        jsonEncode({
          for (final MapEntry(key: id, value: filter)
              in _savedCatalogFilters.entries)
            id: filter.toJson(),
        }),
      );
    }
  }

  /// Folder paths differ from one server's library to the next, so each is
  /// kept per server as well as per page.
  List<CatalogPage> _savedFolderPath(String pageId, String? provider) {
    final key = _serverKey?.folderPath(pageId);
    return [
      for (final folder in _loadFolderPaths()[key] ?? const [])
        CatalogPage.savedFolder(folder, provider: provider),
    ];
  }

  /// Decoded again whenever the saved string has changed: a server's answer
  /// may have moved entries since.
  Map<String, List<Map<String, dynamic>>> _loadFolderPaths() {
    final json = _prefs.getString(ServerStorageKey.folderPaths);
    if (json != _folderPathsJson) {
      _folderPathsJson = json;
      _folderPaths = _decodeFolderPaths(json);
    }
    return _folderPaths;
  }

  static Map<String, List<Map<String, dynamic>>> _decodeFolderPaths(
    String? json,
  ) {
    if (json == null) return {};
    try {
      return {
        for (final MapEntry(key: key, value: path)
            in (jsonDecode(json) as Map<String, dynamic>).entries)
          if (path is List)
            key: [
              for (final folder in path)
                if (folder is Map<String, dynamic> && folder['id'] is String)
                  folder,
            ],
      };
    } catch (_) {
      return {};
    }
  }

  void _rememberFolderPath() {
    final pageId = state.catalogPage.id;
    final server = _serverKey;
    if (pageId == null || server == null || !server.confirmed) return;
    final key = server.folderPath(pageId);
    final paths = _loadFolderPaths();
    if (state.folderPath.isEmpty) {
      paths.remove(key);
    } else {
      paths[key] = [
        for (final folder in state.folderPath) folder.toFolderJson(),
      ];
    }
    if (paths.isEmpty) {
      _folderPathsJson = null;
      _prefs.remove(ServerStorageKey.folderPaths);
    } else {
      final json = _folderPathsJson = jsonEncode(paths);
      _prefs.setString(ServerStorageKey.folderPaths, json);
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
