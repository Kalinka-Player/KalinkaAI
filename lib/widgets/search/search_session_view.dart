import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/browse_filters.dart';
import '../../data_model/data_model.dart' show SearchSuggestion;
import '../browse_filters/browse_filter_form.dart' show resultKindLabel;
import '../../providers/catalog_cards_provider.dart';
import '../../providers/catalog_sources_provider.dart';
import '../../providers/collection_edit_provider.dart';
import '../../providers/connection_state_provider.dart';
import '../../providers/indexer_status_provider.dart';
import '../../providers/search_session_provider.dart';
import '../../providers/source_modules_provider.dart';
import '../../providers/selection_state_provider.dart';
import '../../providers/shell_nav_provider.dart';
import '../../theme/app_theme.dart';
import '../connection_banner.dart';
import '../kalinka_top_bar.dart';
import '../browse_filters/search_filter_button.dart';
import '../browse_filters/search_filter_overlay.dart';
import '../mini_player.dart';
import '../overlay_card.dart';
import '../selection_overlay.dart';
import '../server_chip.dart';
import '../tap_highlight.dart' show kalinkaOverlay;
import 'album_page_header.dart';
import 'browse_visit_scope.dart';
import 'catalog_page_view.dart';
import 'catalog_sliver_header.dart';
import 'collections_edit_bar.dart' show leaveCollectionEditing;
import '../home/home_layout.dart';
import '../home/catalog_pin_button.dart';
import '../home/home_source_list.dart';
import 'results_view.dart';
import 'search_composer.dart';
import 'search_zero_state.dart';

/// How far a backdrop fades out before browsing's right edge, where it meets
/// the player's pane, so it does not end in a cut.
const double _kPaneEdgeFade = 165;

/// How far the Discover backdrop reaches below the status inset. The bloom
/// is drawn over all of it and [_kDiscoverFadeOut] dissolves it before the
/// bottom, so this is the bloom's reach and not an edge anything can see.
const double _kDiscoverBackdropHeight = 340;

const _kBloomCentre = Alignment(0, -0.8);
const double _kBloomRadius = 1.0;

/// The crimson bloom over the Discover root: centred at the top, rising
/// behind the title bar and the status-bar inset, and fading out just short
/// of both sides.
final _kDiscoverBloom = RadialGradient(
  center: _kBloomCentre,
  radius: _kBloomRadius,
  transform: const _AcrossPane(),
  colors: [
    KalinkaColors.accent.withValues(alpha: 0.26),
    KalinkaColors.accent.withValues(alpha: 0),
  ],
);

/// Widens the bloom about its centre, so on a pane wider than its circle
/// reaches it is gone just short of each side.
class _AcrossPane extends GradientTransform {
  const _AcrossPane();

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    final stretch =
        0.95 * bounds.width / 2 / (_kBloomRadius * bounds.shortestSide);
    if (stretch <= 1) return null;
    final centre = _kBloomCentre.withinRect(bounds).dx;
    return Matrix4.diagonal3Values(stretch, 1, 1)
      ..setTranslationRaw(centre * (1 - stretch), 0, 0);
  }
}

/// What ends the bloom: the ground colour brought up over it just under the
/// search entry, in about sixty pixels. The bloom is still tinted where its
/// box stops, so without this it is clipped there and the cut reads as a
/// line across the surface.
final _kDiscoverFadeOut = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    KalinkaColors.background.withValues(alpha: 0),
    KalinkaColors.background,
  ],
  stops: const [0.80, 0.98],
);

/// Home: the app's top level. Its root is the Discover scroll — the search
/// invitation, collections and catalogs — under the wordmark bar;
/// a catalog page or the results below it trade that bar for a back arrow
/// and breadcrumb.
///
/// The search entry does not take focus on its own; tapping it lifts the
/// search overlay.
class SearchSessionView extends ConsumerStatefulWidget {
  /// Opens the server sheet — the connection chip's tap target.
  final VoidCallback? onServerTap;

  /// The resting search entry, for the first-run tour to point at.
  final GlobalKey? entryKey;

  /// The connection chip in the top-level bar, for the first-run tour.
  final GlobalKey? connectionKey;

  /// False while a panel opened over Home owns the system back: every
  /// PopScope on a route hears it, so both would unwind.
  final bool handlesBack;

  /// The shell supplies this from its actual layout, not the browsing width.
  final bool navigationVisible;

  const SearchSessionView({
    super.key,
    this.onServerTap,
    this.entryKey,
    this.connectionKey,
    this.handlesBack = true,
    this.navigationVisible = false,
  });

  @override
  SearchSessionViewState createState() => SearchSessionViewState();
}

class SearchSessionViewState extends ConsumerState<SearchSessionView>
    with
        IndexerPollHolder,
        // Two controllers: the search overlay and the filter card.
        TickerProviderStateMixin,
        WidgetsBindingObserver {
  final _composerController = TextEditingController();
  final _composerFocus = FocusNode();

  // The backdrop spans the pinned header and the list, so it is painted at
  // surface level but follows the list's exact offset. Retained while a
  // catalog replaces the root, and the list comes back at it.
  final _discoverOffset = ValueNotifier<double>(0);
  late final ScrollController _discoverScroll;
  // The album backdrop follows the shown visit's scroll and header; each
  // retained visit keeps its own, so Back lands with them as they were.
  final _albumOffset = ValueNotifier<double>(0);
  final _albumHeaderHeight = ValueNotifier<double>(0);
  final _albumOffsets = <int, double>{};
  final _albumHeaderHeights = <int, double>{};
  final _visitPages = <int, (SearchSessionState, Widget)>{};
  final _catalogHeadersCollapsed = <int, bool>{};
  // A catalog's bar takes on its collapsing header's surface at the same
  // pace, so once collapsed the two read as one over the art.
  final _catalogSurface = ValueNotifier<double>(0);
  final _catalogOffsets = <int, double>{};
  final _catalogExtents = <int, double>{};

  /// How many of the latest visits stay built under the shown one.
  static const _retainedVisits = 6;

  // Whether the animated search overlay is up. Driven by _openSearch /
  // _closeSearch (not by raw focus), so dismissing the keyboard alone keeps
  // the overlay open, like Material's search view.
  bool _focused = false;

  // Live composer text, mirrored here to filter the suggestion list. This
  // never fires a query — search still runs only on submit.
  String _typed = '';

  // Drives the open/close transition: scrim dim, the card rising from the
  // resting entry and stretching, and the staggered suggestions.
  late final AnimationController _overlayCtrl;

  // Drives the filter card unfolding out of its title-bar pill.
  late final AnimationController _filtersCtrl;

  // Opening a source from Home: the search half folds away, then the
  // source's page opens down into the area under the bar.
  late final AnimationController _heroFold;
  late final CurvedAnimation _fold;
  late final AnimationController _pageReveal;
  int? _revealedVisit;

  // The resting search entry's screen rect, measured on open so the overlay
  // card can rise out of exactly where the entry sat.
  final _ownEntryKey = GlobalKey();
  GlobalKey get _entryKey => widget.entryKey ?? _ownEntryKey;
  Rect? _originRect;

  // Tracks the keyboard so its dismissal (e.g. the hardware back that hides it)
  // also closes the overlay — one back drops both.
  bool _keyboardUp = false;

  // Whether the search-and-filters card is unfolded out of its title-bar pill.
  bool _filtersOpen = false;

  // Compare edits with the selection shown when the card opened.
  BrowseFilterQuery _filtersOpenedOn = const BrowseFilterQuery();

  // Rotates the example hint: each mount of the search surface advances one
  // step through the suggestion list.
  static int _hintRotation = 0;
  final int _hintIndex = _hintRotation++;

  // Hit-box height for the back button and connection dot, centred in the bar
  // (whose height is the shared kKalinkaTopBarHeight).
  static const double _kBarMinHeight = 48;

  // Read up front: `ref` is off limits in dispose, where it is needed.
  late final SearchEntryModeNotifier _entryMode;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    _overlayCtrl.duration = reduced
        ? Duration.zero
        : const Duration(milliseconds: 300);
    _overlayCtrl.reverseDuration = reduced
        ? Duration.zero
        : const Duration(milliseconds: 230);
    _filtersCtrl.duration = reduced
        ? Duration.zero
        : const Duration(milliseconds: 240);
    _filtersCtrl.reverseDuration = reduced
        ? Duration.zero
        : const Duration(milliseconds: 180);
  }

  @override
  void initState() {
    super.initState();
    _discoverScroll = _ResumingScrollController(
      _discoverOffset,
      onAttach: (_) {
        // Synchronise after layout, in case the viewport has changed while
        // away and clamped the offset.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncDiscoverOffset();
        });
      },
    )..addListener(_syncDiscoverOffset);
    _entryMode = ref.read(searchEntryModeProvider.notifier);
    _overlayCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 230),
    );
    _filtersCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _heroFold = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _fold = CurvedAnimation(parent: _heroFold, curve: Curves.easeInOutCubic);
    _pageReveal = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: 1,
    );
    _composerController.addListener(_onTextChange);
    WidgetsBinding.instance.addObserver(this);
    // Mounted while connecting, Home waits for the connection instead.
    if (ref.read(connectionStateProvider) == ConnectionStatus.connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(searchSessionProvider.notifier).refresh();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _discoverScroll.dispose();
    _discoverOffset.dispose();
    _albumOffset.dispose();
    _catalogSurface.dispose();
    _albumHeaderHeight.dispose();
    _composerController.removeListener(_onTextChange);
    _overlayCtrl.dispose();
    _filtersCtrl.dispose();
    _fold.dispose();
    _heroFold.dispose();
    _pageReveal.dispose();
    _composerController.dispose();
    _composerFocus.dispose();
    // Torn down with the overlay still up (the server went away) would
    // otherwise leave the shared flag stuck true and the mini-player hidden.
    // Clear it after this frame — a synchronous write could land mid-build of
    // whatever removed this surface.
    if (_focused) {
      final notifier = _entryMode;
      WidgetsBinding.instance.addPostFrameCallback((_) => notifier.set(false));
    }
    super.dispose();
  }

  void _syncDiscoverOffset() {
    if (_discoverScroll.hasClients) {
      _discoverOffset.value = _discoverScroll.offset;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ref.read(connectionStateProvider) == ConnectionStatus.connected) {
      ref.read(searchSessionProvider.notifier).refreshIfStale();
    }
  }

  @override
  void didChangeMetrics() {
    // While the overlay is up, the hardware back first dismisses the keyboard
    // (Android consumes it before our PopScope). Treat that dismissal as the
    // close gesture so a single back drops both the keyboard and the overlay.
    if (!_focused) {
      _keyboardUp = false;
      return;
    }
    final view = View.maybeOf(context);
    if (view == null) return;
    final up = view.viewInsets.bottom > 100;
    if (_keyboardUp && !up) _closeSearch();
    _keyboardUp = up;
  }

  void _onTextChange() {
    final text = _composerController.text;
    if (text != _typed && mounted) setState(() => _typed = text);
  }

  /// Lift the search overlay out of the resting entry: measure where the entry
  /// sits, fade the scrim in, and forward the transition while the field takes
  /// focus.
  void _openSearch() {
    if (_focused) return;
    // Measure the entry in THIS surface's local space (not global): on tablet
    // the search surface is only the browsing pane, and the overlay positions
    // itself within it, so the origin must be panel-relative.
    final selfBox = context.findRenderObject() as RenderBox?;
    final entryBox = _entryKey.currentContext?.findRenderObject() as RenderBox?;
    _originRect =
        (selfBox != null &&
            selfBox.attached &&
            entryBox != null &&
            entryBox.hasSize)
        ? selfBox.globalToLocal(entryBox.localToGlobal(Offset.zero)) &
              entryBox.size
        : null;
    _keyboardUp = false;
    ref.read(searchSessionProvider.notifier).refreshSuggestionsIfStale();
    // Flips searchEntryModeProvider → the mini-player starts sliding down.
    ref.read(searchEntryModeProvider.notifier).set(true);
    setState(() => _focused = true);
    _overlayCtrl.forward(from: 0);
    // Hold the keyboard until the mini-player has cleared: raising focus is
    // what triggers the IME, so defer it by the bar's slide-down duration.
    Future.delayed(kMiniPlayerHideDuration, () {
      if (mounted && _focused) _composerFocus.requestFocus();
    });
  }

  /// Reverse the overlay away. [animate] false when a query is being submitted
  /// (the screen swaps to results, so there is nothing to animate back to).
  void _closeSearch({bool animate = true}) {
    // Re-entrant: the back arrow / scrim tap unfocuses, which fires
    // didChangeMetrics → here again. Ignore once a close is already running.
    if (!_focused || _overlayCtrl.status == AnimationStatus.reverse) return;
    _composerFocus.unfocus();
    _composerController.clear();
    if (!animate) {
      _overlayCtrl.value = 0;
      ref.read(searchEntryModeProvider.notifier).set(false);
      if (mounted) setState(() => _focused = false);
      return;
    }
    _overlayCtrl.reverse().whenComplete(() {
      if (!mounted) return;
      ref.read(searchEntryModeProvider.notifier).set(false);
      setState(() => _focused = false);
    });
  }

  void _submit(String text) {
    ref.read(searchSessionProvider.notifier).submit(text);
    // Submitting swaps to the results screen, so drop the overlay without a
    // reverse animation.
    if (_focused) _closeSearch(animate: false);
  }

  /// Submit from a zero-state tile (history / suggestion run arrow).
  void _submitFromTile(String text) {
    ref.read(searchSessionProvider.notifier).submit(text);
    if (_focused) _closeSearch(animate: false);
  }

  /// Insert a suggestion into the composer for editing (does not send).
  void _insert(String text) {
    _composerController.text = text;
    _composerController.selection = TextSelection.collapsed(
      offset: text.length,
    );
    _composerFocus.requestFocus();
  }

  /// Open a catalog page directly from a card tap — deterministic browse, never
  /// the AI router, and never recorded in search history.
  void _openCatalog(CatalogCardPlan plan, String provider) =>
      ref.read(searchSessionProvider.notifier).openCatalogPlan(plan, provider);

  /// Folds Home's search half away, then opens [source] in the room it left.
  Future<void> _openSourceFromHome(CatalogSource source) async {
    if (_heroFold.isAnimating) return;
    final browsing = ref.read(searchSessionProvider.notifier);
    // Without the rail there is no way back to where it was left, so it
    // starts at its own page.
    void open() => browsing.openSource(source, restore: false);
    if (MediaQuery.disableAnimationsOf(context)) {
      open();
      return;
    }
    final visit = ref.read(searchSessionProvider).visitId;
    await _heroFold.forward(from: 0);
    if (!mounted) return;
    // Somewhere else was opened meanwhile.
    if (ref.read(searchSessionProvider).visitId == visit) {
      open();
      _revealedVisit = ref.read(searchSessionProvider).visitId;
      _pageReveal.forward(from: 0);
    }
    // Home is hidden now; it is whole again for Back.
    _heroFold.value = 0;
  }

  void _openFilters() {
    if (_filtersOpen) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _filtersOpen = true;
      _filtersOpenedOn = _appliedFilter(ref.read(searchSessionProvider));
    });
    _filtersCtrl.forward(from: 0);
  }

  void _closeFilters() {
    // Re-entrant: the scrim tap and the Cancel button can both land.
    if (!_filtersOpen || _filtersCtrl.status == AnimationStatus.reverse) return;
    _filtersCtrl.reverse().whenComplete(() {
      if (mounted) setState(() => _filtersOpen = false);
    });
  }

  /// Commit the staged selection and fold the card away. A catalog page
  /// reloads only if the part of the filter the backend honours actually
  /// changed; results narrow in hand.
  void _applyFilters(BrowseFilterQuery filter, {required bool reset}) {
    final notifier = ref.read(searchSessionProvider.notifier);
    final session = ref.read(searchSessionProvider);
    if (session.activeView == FindMusicView.results) {
      // The field holds the query: a changed one is a new search, an emptied
      // one keeps the search and resets the facets.
      final query = filter.text.trim();
      if (query.isNotEmpty && query != session.searchQuery) {
        notifier.submit(
          query,
          filter: filter,
          shown: _filtersOpenedOn,
          reset: reset,
        );
      } else {
        notifier.setResultsFilter(
          filter,
          shown: _filtersOpenedOn,
          reset: reset,
        );
      }
    } else {
      // The inline field can finish its debounce after this card opens.
      // Applying facets must preserve that text unless Reset was explicit.
      final next = CatalogSliverHeader.appliesTo(session.catalogPage) && !reset
          ? filter.copyWith(text: session.catalogFilter.text)
          : filter;
      notifier.setCatalogFilter(next, reset: reset);
    }
    _closeFilters();
  }

  /// What the filter card narrows: the open catalog page, or the results.
  BrowseFilterCapabilities _filterCapabilities(SearchSessionState session) =>
      session.activeView == FindMusicView.results
      ? session.resultsFilterCapabilities
      : session.catalogPage.filterCapabilities;

  BrowseFilterQuery _appliedFilter(SearchSessionState session) =>
      session.activeView == FindMusicView.results
      ? session.resultsFilter.copyWith(text: session.searchQuery)
      : session.catalogFilter;

  /// Whether nothing is left to unwind: the system back may leave the app.
  bool _atTopLevel(SearchSessionState session, {required bool selecting}) =>
      !_focused &&
      !_filtersOpen &&
      !selecting &&
      !ref.watch(collectionEditProvider.select((s) => s.active)) &&
      session.atHome;

  /// One back press unwinds one layer: the search overlay, the filter card,
  /// a selection or a collection edit, then the previous visit. Shared by the title-bar arrow and
  /// the system back gesture; at Home the back leaves the app.
  void _handleBack() {
    if (_focused) {
      _closeSearch();
      return;
    }
    if (_filtersOpen) {
      // Back is Cancel: the staged edits go with the card.
      _closeFilters();
      return;
    }
    final selection = ref.read(selectionStateProvider.notifier);
    if (ref.read(selectionStateProvider).isActive) {
      selection.exitSelectionMode();
      return;
    }
    if (ref.read(collectionEditProvider).active) {
      // Asks first when anything is staged; the page stays either way.
      leaveCollectionEditing(context, ref);
      return;
    }
    ref.read(searchSessionProvider.notifier).goBack();
  }

  /// Global navigation must honour editing guards and discard only transient
  /// overlays, leaving the current visit available to Back.
  Future<bool> prepareToNavigate() async {
    if (ref.read(collectionEditProvider).active &&
        !await leaveCollectionEditing(context, ref)) {
      return false;
    }
    if (!mounted) return false;
    ref.read(selectionStateProvider.notifier).exitSelectionMode();
    _composerFocus.unfocus();
    _composerController.clear();
    _overlayCtrl.value = 0;
    _filtersCtrl.value = 0;
    _entryMode.set(false);
    setState(() {
      _focused = false;
      _filtersOpen = false;
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(searchSessionProvider);
    final albumPage =
        session.activeView == FindMusicView.catalogs &&
        session.catalogPage.isAlbum;
    ref.listen(searchSessionProvider.select((s) => s.visitId), (_, visit) {
      _albumOffset.value = _albumOffsets[visit] ?? 0;
      _albumHeaderHeight.value = _albumHeaderHeights[visit] ?? 0;
      _catalogSurface.value = _catalogSurfaceOf(visit);
      final kept = {
        for (final each in ref.read(searchSessionProvider).allVisits)
          each.visitId,
      };
      _albumOffsets.removeWhere((id, _) => !kept.contains(id));
      _albumHeaderHeights.removeWhere((id, _) => !kept.contains(id));
      _catalogOffsets.removeWhere((id, _) => !kept.contains(id));
      _catalogExtents.removeWhere((id, _) => !kept.contains(id));
    });

    // ...and drop the flag too, so back does not spend a press closing a card
    // that is no longer on screen.
    if (_filtersOpen && _filterCapabilities(session).isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _closeFilters();
      });
    }

    // A selection belongs to the listing it was gathered from: leaving that
    // listing — for another catalog, the root or the results — ends it
    // rather than keeping a batch bar over rows nothing on screen still shows.
    ref.listen(
      searchSessionProvider.select((s) => s.visitId),
      (_, _) => ref.read(selectionStateProvider.notifier).exitSelectionMode(),
    );

    ref.listen(connectionStateProvider, (previous, next) {
      if (next == ConnectionStatus.connected &&
          previous != ConnectionStatus.connected) {
        ref.read(searchSessionProvider.notifier).refresh();
      }
    });

    ref.listen(homeSearchRequestProvider, (_, _) => _openSearch());

    // The shared tiles long-press into multi-select; surface the same batch
    // bar the old search feed used so the selection can be acted on.
    final selectionActive = ref.watch(
      selectionStateProvider.select((s) => s.isActive),
    );

    // Home owns its back handling: the route must not pop while any
    // in-screen layer can still unwind (the parent screen's PopScope leaves it
    // alone).
    return PopScope(
      canPop:
          !widget.handlesBack ||
          _atTopLevel(session, selecting: selectionActive),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.handlesBack) _handleBack();
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          // A wide album sets its cover beside the tracks, not behind them.
          final onAlbum =
              albumPage && constraints.maxWidth < kAlbumSideLayoutWidth;
          // Beside the player's pane, backdrops fade out before meeting it.
          final besidePlayer = kalinkaSplitLayout(
            MediaQuery.sizeOf(context).width,
            textScaler: MediaQuery.textScalerOf(context),
          );
          return ColoredBox(
            color: KalinkaColors.background,
            child: Stack(
              children: [
                if (onAlbum)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: AlbumPageBackdrop(
                      page: session.catalogPage,
                      headerHeight: _albumHeaderHeight,
                      scrollOffset: _albumOffset,
                    ),
                  ),
                // The backdrop behind the Discover root, full surface width and
                // rising behind the bar and the status-bar inset so the two read
                // as one surface. It moves one-for-one with the introduction,
                // including overscroll, without rebuilding the content below.
                if (session.atHome)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height:
                        MediaQuery.paddingOf(context).top +
                        _kDiscoverBackdropHeight,
                    child: IgnorePointer(
                      child: ValueListenableBuilder<double>(
                        valueListenable: _discoverOffset,
                        builder: (context, offset, child) =>
                            Transform.translate(
                              offset: Offset(0, -offset),
                              child: child,
                            ),
                        child: RepaintBoundary(
                          key: const ValueKey('discover-backdrop'),
                          child: FadeTransition(
                            opacity: ReverseAnimation(_heroFold),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: _kDiscoverBloom,
                                  ),
                                ),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: _kDiscoverFadeOut,
                                  ),
                                ),
                                const IgnorePointer(
                                  child: ExcludeSemantics(
                                    child: _HeroArtwork(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                // On a catalog page the card's blurred art backs the whole top of
                // the screen — status inset and title bar included — fading into
                // the canvas before the rows (same layer as the bloom above).
                if (session.activeView == FindMusicView.catalogs &&
                    !session.catalogPage.isRoot &&
                    !onAlbum &&
                    session.shownListing.artPath != null)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: FadeTransition(
                        opacity: _pageReveal,
                        child: _PaneEdgeFade(
                          enabled: besidePlayer,
                          child: CatalogArtBackdrop(
                            artPath: session.shownListing.artPath!,
                            // A folder uses cover art; albums carry their own
                            // crisp backdrop inside the scrolling header.
                            fromCover: session.folderPath.isNotEmpty,
                          ),
                        ),
                      ),
                    ),
                  ),
                Column(
                  children: [
                    if (onAlbum)
                      AnnotatedRegion<SystemUiOverlayStyle>(
                        value: const SystemUiOverlayStyle(
                          statusBarColor: Colors.transparent,
                          statusBarIconBrightness: Brightness.light,
                          statusBarBrightness: Brightness.dark,
                          systemStatusBarContrastEnforced: false,
                        ),
                        child: ValueListenableBuilder<double>(
                          valueListenable: _albumOffset,
                          builder: (context, offset, child) => ColoredBox(
                            key: const ValueKey('album-header-surface'),
                            color: KalinkaColors.background.withValues(
                              alpha: (offset / kKalinkaTopBarHeight).clamp(
                                0.0,
                                1.0,
                              ),
                            ),
                            child: child,
                          ),
                          child: _buildHeader(session),
                        ),
                      )
                    else
                      _buildHeader(session),
                    Expanded(child: _buildVisits(session)),
                  ],
                ),
                // Only while there is something to narrow: a reconnect can reset
                // the session under an open card.
                if (_filtersOpen && !_filterCapabilities(session).isEmpty)
                  _buildFiltersOverlay(session),
                // The animated search overlay floats above the header too, so its
                // dim scrim covers the top bar — the in-field arrow is the
                // only back affordance while it is up.
                if (_focused) _buildSearchOverlay(session),
                if (selectionActive)
                  const Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: MultiSelectBottomBar(),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Home, with the latest visits built over it and only the shown one on
  /// screen. A visit Back returns to keeps its loaded rows, filters and
  /// scroll; older ones are built again when reached.
  Widget _buildVisits(SearchSessionState session) {
    final visits = [
      for (final visit in [...session.previousVisits, session])
        if (!visit.atHome) visit,
    ];
    final retained = [
      // What each other destination shows, so going back to it is instant
      // and finds it scrolled as it was left.
      for (final top in session.parked.values)
        if (!top.atHome) top,
      ...visits.length > _retainedVisits
          ? visits.sublist(visits.length - _retainedVisits)
          : visits,
    ];
    final kept = {for (final visit in retained) visit.visitId};
    _visitPages.removeWhere((id, _) => !kept.contains(id));
    _catalogHeadersCollapsed.removeWhere((id, _) => !kept.contains(id));
    return Stack(
      fit: StackFit.expand,
      children: [
        _shownIf(session.atHome, _buildCatalogsRoot(session)),
        for (final visit in retained)
          KeyedSubtree(
            key: ValueKey(visit.visitId),
            child: _shownIf(
              visit.visitId == session.visitId,
              _OpenDown(
                reveal: visit.visitId == _revealedVisit
                    ? _pageReveal
                    : kAlwaysCompleteAnimation,
                child: _visitPage(visit),
              ),
            ),
          ),
      ],
    );
  }

  /// A visit's page, reused while its visit is unchanged, so a kept visit is
  /// not rebuilt each time the shown one changes.
  Widget _visitPage(SearchSessionState visit) {
    final cached = _visitPages[visit.visitId];
    if (cached != null && identical(cached.$1, visit)) return cached.$2;
    final page = BrowseVisitScope(visit: visit, child: _buildVisit(visit));
    _visitPages[visit.visitId] = (visit, page);
    return page;
  }

  // ExcludeFocus, as IndexedStack does: keys must not reach a hidden visit.
  static Widget _shownIf(bool shown, Widget child) => Offstage(
    offstage: !shown,
    child: TickerMode(
      enabled: shown,
      child: ExcludeFocus(excluding: !shown, child: child),
    ),
  );

  bool _isShown(int visitId) =>
      ref.read(searchSessionProvider).visitId == visitId;

  Widget _buildVisit(SearchSessionState visit) {
    if (visit.activeView == FindMusicView.results) {
      return visit.resultsAvailable
          ? const ResultsView()
          : const SizedBox.shrink();
    }
    final page = visit.catalogPage;
    final id = visit.visitId;
    // Metrics notifications also cover a list replaced by its loading,
    // empty or error state, which starts at the top without scrolling.
    return NotificationListener<Notification>(
      onNotification: (notification) {
        final (depth, metrics) = switch (notification) {
          ScrollNotification n => (n.depth, n.metrics),
          ScrollMetricsNotification n => (n.depth, n.metrics),
          _ => (-1, null),
        };
        if (page.isAlbum &&
            depth == 0 &&
            metrics != null &&
            metrics.axis == Axis.vertical) {
          // Overscroll at the top keeps the cover in place.
          final offset = math.max(0.0, metrics.pixels);
          _albumOffsets[id] = offset;
          if (_isShown(id)) _albumOffset.value = offset;
        } else if (CatalogSliverHeader.appliesTo(page) &&
            depth == 0 &&
            metrics != null &&
            metrics.axis == Axis.vertical) {
          _catalogOffsets[id] = math.max(0.0, metrics.pixels);
          if (_isShown(id)) _catalogSurface.value = _catalogSurfaceOf(id);
        }
        return false;
      },
      child: CatalogPageView(
        page: page,
        onOpenFilters: _openFilters,
        onHeaderCollapsed: (collapsed) {
          if (_catalogHeadersCollapsed[id] == collapsed) return;
          _catalogHeadersCollapsed[id] = collapsed;
          if (mounted && _isShown(id)) setState(() {});
        },
        onHeaderCollapseExtent: (extent) {
          _catalogExtents[id] = extent;
          if (_isShown(id)) _catalogSurface.value = _catalogSurfaceOf(id);
        },
        onAlbumHeaderHeight: page.isAlbum
            ? (height) {
                _albumHeaderHeights[id] = height;
                if (_isShown(id)) _albumHeaderHeight.value = height;
              }
            : null,
        onBackToCatalogs: () =>
            ref.read(searchSessionProvider.notifier).backToCatalogsRoot(),
      ),
    );
  }

  /// The top level's bar is the app's own: wordmark and connection chip.
  /// Catalog filters stay in their sliver; title and Pin join Back on collapse.
  /// Results retain their search-and-filters control in this bar.
  double _barHeight(SearchSessionState session) =>
      session.activeView == FindMusicView.catalogs &&
          CatalogSliverHeader.appliesTo(session.catalogPage)
      ? math.max(
          kKalinkaTopBarHeight,
          MediaQuery.textScalerOf(context)
                      .scale(KalinkaTextStyles.trayTitle.fontSize!) *
                  1.5 +
              4,
        )
      : kKalinkaTopBarHeight;

  Widget _buildHeader(SearchSessionState session) {
    final onResults = session.activeView == FindMusicView.results;
    final catalogChrome =
        !onResults && CatalogSliverHeader.appliesTo(session.catalogPage);
    if (session.atHome) {
      return ValueListenableBuilder<double>(
        valueListenable: _discoverOffset,
        builder: (context, offset, child) => ColoredBox(
          key: const ValueKey('discover-header-surface'),
          // Directly tied to scroll, with no delayed animation or parallax.
          color: KalinkaColors.background.withValues(
            alpha: (offset / kKalinkaTopBarHeight).clamp(0.0, 1.0),
          ),
          child: child,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            KalinkaTopBar(
              transparent: true,
              onServerChipTap: widget.onServerTap,
              onResultsTap:
                  session.resultsAvailable && !widget.navigationVisible
                  ? () async {
                      if (!await prepareToNavigate() || !mounted) return;
                      ref
                          .read(searchSessionProvider.notifier)
                          .showResults(restore: false);
                    }
                  : null,
              connectionKey: widget.connectionKey,
            ),
            const ConnectionBanner(),
          ],
        ),
      );
    }

    // No opaque fill and no bottom rule — the bar and the content below it
    // read as one surface, with the Discover glow showing through both. On
    // a catalog it fills as the header's surface does, over the art.
    final bar = SafeArea(
      bottom: false,
      child: SizedBox(
        height: _barHeight(session),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Back',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: _handleBack,
                icon: const Icon(
                  Icons.arrow_back,
                  size: 22,
                  color: KalinkaColors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _buildTitle(session)),
              if (catalogChrome &&
                  _catalogHeadersCollapsed[session.visitId] == true)
                CatalogPinButton(
                  page: session.shownListing,
                  filter: session.catalogFilter.copyWith(
                    type: session.expandedShelf,
                  ),
                ),
              // Only where there is something to narrow: the Catalogs root
              // has no listing of its own.
              if (!catalogChrome && !_filterCapabilities(session).isEmpty)
                SearchFilterButton(
                  activeCount: _appliedFilter(session).activeCount,
                  open: _filtersOpen,
                  onTap: _openFilters,
                ),
              SizedBox(
                height: _kBarMinHeight,
                width: 42,
                child: Center(
                  child: ServerChip(compact: true, onTap: widget.onServerTap),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!catalogChrome) return bar;
    return ValueListenableBuilder<double>(
      valueListenable: _catalogSurface,
      builder: (context, surface, child) => ColoredBox(
        key: const ValueKey('catalog-bar-surface'),
        color: KalinkaColors.background.withValues(alpha: surface),
        child: child,
      ),
      child: bar,
    );
  }

  /// How far visit [id]'s catalog header has collapsed, as the opacity of
  /// its surface.
  double _catalogSurfaceOf(int id) {
    final offset = _catalogOffsets[id] ?? 0;
    final extent = _catalogExtents[id];
    if (extent == null) return 0;
    if (extent <= 0) return offset > 0 ? 1 : 0;
    return (offset / extent).clamp(0.0, 1.0);
  }

  /// What the shown visit is, and nothing about how it was reached: Back
  /// returns along the way it came, which a fixed path would misstate.
  Widget _buildTitle(SearchSessionState session) {
    final catalogChrome =
        session.activeView == FindMusicView.catalogs &&
        CatalogSliverHeader.appliesTo(session.catalogPage);
    final String title;
    if (catalogChrome) {
      if (_catalogHeadersCollapsed[session.visitId] != true) {
        return const SizedBox.shrink();
      }
      title = session.shownListing.title ?? '';
    } else if (session.activeView == FindMusicView.results) {
      title = switch (session.expandedBlock) {
        null => 'Results',
        (:final kind, :final source) => [
          resultKindLabel(kind),
          if (source != null && (session.results?.sources.length ?? 0) > 1)
            session.results!.sources.titleOf(source),
        ].join(' · '),
      };
    } else {
      title = session.catalogPage.title ?? '';
    }
    return Semantics(
      header: true,
      child: Text(
        title.toUpperCase(),
        key: catalogChrome ? const ValueKey('catalog-collapsed-title') : null,
        style: KalinkaTextStyles.trayTitle.copyWith(
          color: KalinkaColors.textPrimary,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// The Catalogs root: one scroll holding the Playfair question, its
  /// description, the resting search entry, your collections, source tiles,
  /// then pinned previews. Tapping the entry lifts the overlay.
  Widget _buildCatalogsRoot(SearchSessionState session) {
    final smart = ref.watch(smartSearchAvailableProvider) ?? true;
    return SearchZeroState(
      controller: _discoverScroll,
      onOpenCatalog: _openCatalog,
      // The rail carries sources and collections where it shows.
      showCollections: !widget.navigationVisible,
      leading: [
        // Folds up under the bar as a source opens, the sources rising with it.
        SizeTransition(
          sizeFactor: ReverseAnimation(_fold),
          alignment: const Alignment(-1, 1),
          child: FadeTransition(
            opacity: ReverseAnimation(_fold),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Only present while the library pipeline is still running.
                const _IndexerProgressCard(),
                _DiscoverHero(
                  entryKey: _entryKey,
                  hint: _hintText(session, smart: smart),
                  smartSearch: smart,
                  smartSources: smart
                      ? ref.watch(smartSearchSourcesProvider)
                      : '',
                  // The server's curated prompts, not the static stand-ins or
                  // the unvalidated pick, and only once smart search is known
                  // to answer.
                  suggestions: ref.watch(smartSearchAvailableProvider) == true
                      ? [
                          for (final s in session.aiSuggestions)
                            if (!s.experimental) s,
                        ]
                      : const [],
                  onSuggestion: _submitFromTile,
                  onOpenSearch: _openSearch,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        if (!widget.navigationVisible) ...[
          HomeSourceList(onOpen: _openSourceFromHome),
          const SizedBox(height: kHomeSectionGap),
        ],
      ],
    );
  }

  /// Rotating example hint — a different real suggestion each time the surface
  /// mounts, teaching the query language.
  String _hintText(SearchSessionState session, {required bool smart}) {
    if (!smart) return _plainHint;
    final suggestions = session.suggestions;
    if (suggestions.isEmpty) return 'Ask for music…';
    return 'Try “${suggestions[_hintIndex % suggestions.length].query}”';
  }

  static const _plainHint = 'Artist, album or track…';

  /// The unfolded search-and-filters card, resting under the title bar so the
  /// pill it came from stays visible above it. The scrim is lighter than the
  /// search overlay's: the rows behind stay legible, since the whole point of
  /// the card is to narrow them.
  Widget _buildFiltersOverlay(SearchSessionState session) {
    final page = session.catalogPage;
    final onResults = session.activeView == FindMusicView.results;
    final topInset = MediaQuery.paddingOf(context).top;
    final targetTop = topInset + _barHeight(session);

    return LayoutBuilder(
      builder: (context, constraints) {
        return AnimatedBuilder(
          animation: _filtersCtrl,
          builder: (context, _) {
            final t = Curves.easeOutCubic.transform(_filtersCtrl.value);
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: _closeFilters,
                    behavior: HitTestBehavior.opaque,
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.72 * t),
                    ),
                  ),
                ),
                Positioned(
                  top: targetTop,
                  left: 16,
                  right: 16,
                  child: Opacity(
                    opacity: t,
                    child: Transform.scale(
                      scale: lerpDouble(0.92, 1, t)!,
                      // Unfolds out of the pill it replaced, top-right.
                      alignment: Alignment.topRight,
                      child: SearchFilterOverlay(
                        capabilities: _filterCapabilities(session),
                        applied: _filtersOpenedOn,
                        showSearch:
                            onResults || !CatalogSliverHeader.appliesTo(page),
                        title: onResults
                            ? 'REFINE RESULTS'
                            : CatalogSliverHeader.appliesTo(page)
                            ? 'FILTERS'
                            : 'SEARCH & FILTERS',
                        searchHint:
                            onResults ||
                                page.title == null ||
                                page.title!.isEmpty
                            ? 'Search'
                            : 'Search ${page.title}',
                        searchCaption: onResults
                            ? 'A new query starts a new search.'
                            : null,
                        // Clamped: a window short enough to make this
                        // negative would assert on the card's constraints.
                        maxHeight: (constraints.maxHeight - targetTop - 24)
                            .clamp(120.0, double.infinity),
                        onApply: _applyFilters,
                        onCancel: _closeFilters,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// The focused search view: a dim scrim over the search surface (top bar
  /// included) and a card that rises out of the resting entry, stretches, and
  /// reveals the staggered suggestions. Back arrow / hardware back reverse it.
  ///
  /// All geometry is in this surface's own coordinate space (see the local
  /// origin measured in [_openSearch]) — on tablet the surface is only the
  /// right half, so the overlay stays inside it and unrolls exactly as on
  /// phone rather than sweeping across the whole screen.
  Widget _buildSearchOverlay(SearchSessionState session) {
    final smart = ref.watch(smartSearchAvailableProvider) ?? true;
    final topInset = MediaQuery.paddingOf(context).top;
    // Rest the card at the title-bar bottom rather than the screen top, so it
    // never overlaps the "Find Music" bar.
    final targetTop = topInset + kKalinkaTopBarHeight;

    return LayoutBuilder(
      builder: (context, constraints) {
        final surfaceWidth = constraints.maxWidth;
        // Remeasure the width on resize, including while the composer is open.
        final width = (surfaceWidth - 32).clamp(0.0, kHomeSearchMaxWidth);
        final origin = Rect.fromLTWH(
          (surfaceWidth - width) / 2,
          _originRect?.top ?? targetTop + 120,
          width,
          _originRect?.height ?? 56,
        );
        return AnimatedBuilder(
          animation: _overlayCtrl,
          builder: (context, _) {
            final t = Curves.easeOutCubic.transform(_overlayCtrl.value);
            // The card slides up from the entry, as wide as the entry.
            final top = lerpDouble(origin.top, targetTop, t)!;
            final left = origin.left;
            final right = surfaceWidth - origin.right;
            // The panel unfurls (height grows) so the card stretches as it
            // opens.
            final panelReveal = Curves.easeOutCubic.transform(
              ((_overlayCtrl.value - 0.15) / 0.85).clamp(0.0, 1.0),
            );
            // Cap the suggestion list to the room left between the card top and
            // the keyboard (the surface itself is not resized by the IME), so
            // it scrolls internally instead of running off-screen. ~160 leaves
            // the header, the field and the card margins above it.
            final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
            final listMaxHeight =
                (constraints.maxHeight - targetTop - keyboardInset - 160).clamp(
                  80.0,
                  double.infinity,
                );

            return Stack(
              children: [
                // Dim scrim — almost opaque at rest — over the whole screen. Tap to
                // dismiss.
                Positioned.fill(
                  child: GestureDetector(
                    onTap: _closeSearch,
                    behavior: HitTestBehavior.opaque,
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.92 * t),
                    ),
                  ),
                ),
                Positioned(
                  top: top,
                  left: left,
                  right: right,
                  child: KalinkaOverlayCard(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // The card names itself and carries its own dismiss,
                        // like every other surface that opens over the title
                        // bar; the field below is then only a field.
                        OverlayCardHeader(
                          icon: smart
                              ? Icons.auto_awesome
                              : Icons.search_rounded,
                          title: smart ? 'SMART SEARCH' : 'SEARCH',
                          onClose: _closeSearch,
                          closeLabel: 'Close search',
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                          child: DecoratedBox(
                            // The field is drawn as a field: the composer is
                            // chromeless, so the outline belongs here.
                            decoration: BoxDecoration(
                              color: KalinkaColors.surfaceInput,
                              borderRadius: BorderRadius.circular(26),
                              border: Border.all(
                                color: smart
                                    ? KalinkaColors.accentBorder
                                    : KalinkaColors.borderDefault,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              child: SearchComposer(
                                controller: _composerController,
                                focusNode: _composerFocus,
                                onSubmit: _submit,
                                hint: smart
                                    ? 'Search music, or describe a mood'
                                    : _plainHint,
                              ),
                            ),
                          ),
                        ),
                        // The suggestion panel grows top-down; rows fade/slide
                        // in staggered inside it.
                        ClipRect(
                          child: Align(
                            alignment: Alignment.topCenter,
                            heightFactor: panelReveal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: listMaxHeight,
                              ),
                              child: SearchSuggestionsList(
                                query: _typed,
                                onInsert: _insert,
                                onSubmit: _submitFromTile,
                                reveal: _overlayCtrl,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Fades [child] out over its last [_kPaneEdgeFade] at the right while
/// [enabled].
class _PaneEdgeFade extends StatelessWidget {
  final bool enabled;
  final Widget child;

  const _PaneEdgeFade({required this.enabled, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => LinearGradient(
        colors: const [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
        stops: [
          bounds.width > 0
              ? (1 - _kPaneEdgeFade / bounds.width).clamp(0.0, 1.0)
              : 0.0,
          1,
        ],
      ).createShader(bounds),
      child: child,
    );
  }
}

/// The Discover hero: the Playfair question and the resting
/// search entry, over the tinted header artwork on the left. The text keeps
/// to the left half (wrapping as needed); the crimson bloom behind it is
/// painted once at the surface level, not here.
class _DiscoverHero extends StatelessWidget {
  final Key entryKey;
  final String hint;

  /// Whether a source answers smart search; controls the search entry icon.
  final bool smartSearch;

  /// Which sources answer smart search; empty hides the note.
  final String smartSources;

  /// Prompts that each run as a search as they stand.
  final List<SearchSuggestion> suggestions;
  final ValueChanged<String> onSuggestion;
  final VoidCallback onOpenSearch;

  const _DiscoverHero({
    required this.entryKey,
    required this.hint,
    required this.smartSearch,
    required this.smartSources,
    required this.suggestions,
    required this.onSuggestion,
    required this.onOpenSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        children: [
          Text(
            'What shall we play?',
            textAlign: TextAlign.center,
            style: KalinkaFonts.display(
              fontSize: KalinkaTypography.baseSize + 17,
              fontWeight: FontWeight.w600,
              color: KalinkaColors.textPrimary,
            ),
          ),
          const SizedBox(height: 18),
          // The overlay it lifts into keeps its width.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kHomeSearchMaxWidth),
            child: SizedBox(
              width: double.infinity,
              child: _SearchEntryButton(
                key: entryKey,
                hint: hint,
                smart: smartSearch,
                onTap: onOpenSearch,
              ),
            ),
          ),
          if (smartSources.isNotEmpty) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kHomeSearchMaxWidth),
              child: Text(
                'Smart search works with $smartSources.',
                textAlign: TextAlign.center,
                style: KalinkaTextStyles.trackRowSubtitle.copyWith(
                  fontSize: KalinkaTypography.baseSize,
                  color: KalinkaColors.textMuted,
                ),
              ),
            ),
          ],
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 14),
            // Lower than the search entry, wrapping within its width.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kHomeSearchMaxWidth),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final suggestion in suggestions)
                    _SuggestionChip(
                      suggestion: suggestion,
                      onTap: () => onSuggestion(suggestion.query),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A curated prompt under the search entry, as wide as its words, that runs
/// as a search when tapped. Its mark comes from what it asks for, else the
/// time of day it was offered for.
class _SuggestionChip extends StatelessWidget {
  final SearchSuggestion suggestion;
  final VoidCallback onTap;

  const _SuggestionChip({required this.suggestion, required this.onTap});

  /// First match wins: the activity is the more telling word. Each set of
  /// words is one pattern, compiled once.
  static final _marks = [
    for (final (words, icon) in _markWords)
      (RegExp('\\b(?:${words.join('|')})\\b'), icon),
  ];

  static const _markWords = <(List<String>, IconData)>[
    (['focus', 'study', 'studying', 'work', 'read'], Icons.menu_book_outlined),
    (['drive'], Icons.directions_car_outlined),
    (['dinner'], Icons.restaurant_outlined),
    (['coffee'], Icons.coffee_outlined),
    (['run', 'workout'], Icons.directions_run_rounded),
    (['sleep', 'asleep', 'wind down', 'quiet'], Icons.bedtime_outlined),
    (
      ['party', 'dance', 'celebrate', 'upbeat', 'energetic', 'anthems'],
      Icons.equalizer_rounded,
    ),
    (['christmas', 'winter', 'festive', 'carols'], Icons.ac_unit_rounded),
  ];

  static const _dayparts = <String, IconData>{
    'morning': Icons.wb_sunny_outlined,
    'afternoon': Icons.light_mode_outlined,
    'evening': Icons.bedtime_outlined,
    'night': Icons.nights_stay_outlined,
  };

  IconData get _mark {
    final words = suggestion.query.toLowerCase();
    for (final (pattern, icon) in _marks) {
      if (pattern.hasMatch(words)) return icon;
    }
    if (suggestion.context.startsWith('holiday:')) {
      return Icons.celebration_outlined;
    }
    return _dayparts[suggestion.context] ?? Icons.auto_awesome;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Search for ${suggestion.query}',
      excludeSemantics: true,
      child: Material(
        color: KalinkaColors.surfaceRaised,
        // A pill on one line; a prompt that wraps keeps the same corners.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kKalinkaPillRadius),
          side: const BorderSide(color: KalinkaColors.borderDefault),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: onTap,
          overlayColor: kalinkaOverlay,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kKalinkaPillHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_mark, size: 18, color: KalinkaColors.accentTint),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      suggestion.query,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KalinkaTextStyles.trackRowSubtitle.copyWith(
                        fontSize: KalinkaTypography.baseSize + 1,
                        color: KalinkaColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One continuous panorama, with quiet space behind the central search entry.
/// Keep both sides visible as the pane changes shape and fade into the page.
class _HeroArtwork extends StatelessWidget {
  const _HeroArtwork();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = (width / 3).clamp(200.0, 300.0);
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            // Continue behind the status bar without a seam at the safe inset.
            height: height + MediaQuery.paddingOf(context).top,
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xBFFFFFFF),
                  Color(0xBFFFFFFF),
                  Colors.transparent,
                ],
                stops: [0, 0.65, 1],
              ).createShader(bounds),
              child: Image.asset(
                'assets/images/home_header_artwork.png',
                key: const ValueKey('home-header-artwork'),
                // Stretch abstract ribbons rather than crop away the sides
                // and the negative space composed for the search controls.
                fit: BoxFit.fill,
                cacheWidth: (width * MediaQuery.devicePixelRatioOf(context))
                    .ceil()
                    .clamp(1, 2172),
                excludeFromSemantics: true,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The resting search entry in the Discover scroll: looks like the field
/// (sparkle + hint) but is a button — tapping it lifts the animated overlay.
/// Its screen rect is measured on open so the overlay card rises from here.
class _SearchEntryButton extends StatelessWidget {
  final String hint;

  /// Smart search gets the crimson invitation; a name search is a plain field.
  final bool smart;
  final VoidCallback onTap;

  const _SearchEntryButton({
    super.key,
    required this.hint,
    required this.smart,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // With smart search, the main feature of the surface — a crimson-tinted
    // field with a soft glow so it reads as the invitation, not a gray card.
    return Semantics(
      label: 'Search',
      hint: smart
          ? 'Ask for music in plain language'
          : 'Search by artist, album or track',
      button: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            if (smart)
              BoxShadow(
                color: KalinkaColors.accent.withValues(alpha: 0.16),
                blurRadius: 26,
                spreadRadius: 1,
              ),
          ],
        ),
        child: Material(
          color: smart
              ? Color.alphaBlend(
                  KalinkaColors.accentSubtle,
                  KalinkaColors.surfaceInput,
                )
              : KalinkaColors.surfaceInput,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            onTap: onTap,
            child: Container(
              height: 54,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: smart
                      ? KalinkaColors.accentBorder
                      : KalinkaColors.borderDefault,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 26,
                    child: smart
                        ? const Icon(
                            Icons.auto_awesome,
                            size: 16,
                            color: KalinkaColors.gold,
                          )
                        : const Icon(
                            Icons.search_rounded,
                            size: 18,
                            color: KalinkaColors.textMuted,
                          ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hint,
                      style: KalinkaTextStyles.searchPlaceholder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: smart
                        ? KalinkaColors.accentTint
                        : KalinkaColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pipeline progress as a card at the top of the Catalogs scroll: a spinner +
/// stage caption ("Indexing · 45%") over a crimson progress line, shown while
/// the library is indexing / enriching / embedding and gone when the pipeline
/// is idle. Placed in-scroll (above "What shall we play?") so it's actually
/// visible rather than a hairline strip under the header. Its own consumer so
/// the 5s poll ticks rebuild only this card, not the whole search surface.
class _IndexerProgressCard extends ConsumerWidget {
  const _IndexerProgressCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(indexerStatusProvider);
    final stage = status.stage;
    if (stage == null) return const SizedBox.shrink();
    final pct = status.progressPct;
    final progress = pct != null ? (pct / 100).clamp(0.0, 1.0) : null;

    // Name the stage but always make clear it's My Library being built.
    final String action = switch (stage) {
      IndexerDisplayStage.indexing => 'Indexing My Library',
      IndexerDisplayStage.analyzingAudio => 'Analyzing audio in My Library',
      IndexerDisplayStage.enrichment => 'Enriching My Library',
      IndexerDisplayStage.preparingAi => 'Preparing My Library for AI',
    };
    final label = pct != null
        ? '$action · ${pct.toStringAsFixed(0)}%'
        : '$action…';

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 9, 14, 10),
      decoration: BoxDecoration(
        color: KalinkaColors.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KalinkaColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.travel_explore_rounded,
                size: 17,
                color: KalinkaColors.accent,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  label,
                  // Screen readers skip or literalize '·'.
                  semanticsLabel: label.replaceAll(' · ', ', '),
                  style: KalinkaTextStyles.trackRowSubtitle.copyWith(
                    color: KalinkaColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          // Bar aligns under the text, not the icon (icon 17 + 11 gap = 28).
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: KalinkaColors.borderSubtle,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  KalinkaColors.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reattaches at the last offset the list was seen at. PageStorage keeps only
/// where a scroll last came to rest, which is stale when the root is left
/// mid-fling: coming back would land further down than it was left.
class _ResumingScrollController extends ScrollController {
  final ValueNotifier<double> resumeAt;

  _ResumingScrollController(this.resumeAt, {super.onAttach})
    : super(keepScrollOffset: false);

  @override
  double get initialScrollOffset => resumeAt.value;
}

/// Opens a page down from the bar into the area under it.
class _OpenDown extends StatelessWidget {
  final Animation<double> reveal;
  final Widget child;

  const _OpenDown({required this.reveal, required this.child});

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: reveal,
    child: ClipRect(clipper: _TopPart(reveal), child: child),
  );
}

class _TopPart extends CustomClipper<Rect> {
  final Animation<double> reveal;

  _TopPart(this.reveal) : super(reclip: reveal);

  @override
  Rect getClip(Size size) => Rect.fromLTWH(
    0,
    0,
    size.width,
    size.height * Curves.easeOutCubic.transform(reveal.value),
  );

  @override
  bool shouldReclip(_TopPart oldClipper) => oldClipper.reveal != reveal;
}
