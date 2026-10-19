import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../data_model/browse_filters.dart';
import '../browse_filters/browse_filter_form.dart' show resultKindLabel;
import '../../providers/catalog_cards_provider.dart';
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
import 'album_page_header.dart';
import 'browse_visit_scope.dart';
import 'catalog_page_view.dart';
import 'collections_edit_bar.dart' show leaveCollectionEditing;
import '../home/catalog_pin_button.dart';
import '../home/home_layout.dart';
import 'results_view.dart';
import 'search_composer.dart';
import 'search_zero_state.dart';

/// The resting search entry's widest: a readable field, not a bar across a
/// desktop-wide pane. The overlay it lifts into keeps its width.
const double _kSearchEntryMaxWidth = 600;

/// How far a backdrop fades out before browsing's right edge, where it meets
/// the player's pane, so it does not end in a cut.
const double _kPaneEdgeFade = 165;

/// How far the Discover backdrop reaches below the status inset. The bloom
/// is drawn over all of it and [_kDiscoverFadeOut] dissolves it before the
/// bottom, so this is the bloom's reach and not an edge anything can see.
const double _kDiscoverBackdropHeight = 340;

const _kBloomCentre = Alignment(-0.85, -0.75);
const double _kBloomRadius = 1.35;

/// The crimson bloom over the Discover root: off the top-left corner, at the
/// window's edge rather than the player's pane, rising behind the title bar
/// and the status-bar inset, and across a wide pane to near its right edge.
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
/// reaches it is gone just short of the right edge.
class _AcrossPane extends GradientTransform {
  const _AcrossPane();

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    final stretch = 0.95 * bounds.width / (_kBloomRadius * bounds.shortestSide);
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

  const SearchSessionView({
    super.key,
    this.onServerTap,
    this.entryKey,
    this.connectionKey,
    this.handlesBack = true,
  });

  @override
  ConsumerState<SearchSessionView> createState() => _SearchSessionViewState();
}

class _SearchSessionViewState extends ConsumerState<SearchSessionView>
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
  static const double _kBarMinHeight = 46;

  // Read up front: `ref` is off limits in dispose, where it is needed.
  late final SearchEntryModeNotifier _entryMode;

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
    _albumHeaderHeight.dispose();
    _composerController.removeListener(_onTextChange);
    _overlayCtrl.dispose();
    _filtersCtrl.dispose();
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
  void _openCatalog(CatalogCardPlan plan, String provider) {
    ref
        .read(searchSessionProvider.notifier)
        .openCatalog(
          id: plan.id,
          title: plan.title,
          provider: provider,
          description: plan.description,
          totalDurationSeconds: plan.totalDurationSeconds,
          artPath: plan.artPath,
          filters: plan.filters,
          sections: plan.sections,
          canEdit: plan.canEdit,
          folderLayout: plan.folderLayout,
          canAdd: plan.canAdd,
          preview: plan.preview,
        );
  }

  void _openFilters() {
    if (_filtersOpen) return;
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
      notifier.setCatalogFilter(filter, reset: reset);
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

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(searchSessionProvider);
    final albumPage =
        session.activeView == FindMusicView.catalogs &&
        session.catalogPage.isAlbum;
    ref.listen(searchSessionProvider.select((s) => s.visitId), (_, visit) {
      _albumOffset.value = _albumOffsets[visit] ?? 0;
      _albumHeaderHeight.value = _albumHeaderHeights[visit] ?? 0;
      final kept = {
        for (final previous in ref.read(searchSessionProvider).previousVisits)
          previous.visitId,
        visit,
      };
      _albumOffsets.removeWhere((id, _) => !kept.contains(id));
      _albumHeaderHeights.removeWhere((id, _) => !kept.contains(id));
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
                                child: ExcludeSemantics(child: _HeroArtwork()),
                              ),
                            ],
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
    final retained = visits.length > _retainedVisits
        ? visits.sublist(visits.length - _retainedVisits)
        : visits;
    return Stack(
      fit: StackFit.expand,
      children: [
        _shownIf(session.atHome, _buildCatalogsRoot(session)),
        for (final visit in retained)
          KeyedSubtree(
            key: ValueKey(visit.visitId),
            child: _shownIf(
              visit.visitId == session.visitId,
              BrowseVisitScope(visit: visit, child: _buildVisit(visit)),
            ),
          ),
      ],
    );
  }

  static Widget _shownIf(bool shown, Widget child) => Offstage(
    offstage: !shown,
    child: TickerMode(enabled: shown, child: child),
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
        }
        return false;
      },
      child: CatalogPageView(
        page: page,
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
  /// Deeper, it is back arrow · breadcrumb · filter · connection dot, the
  /// arrow being the one navigation control (layered back, [_handleBack]).
  Widget _buildHeader(SearchSessionState session) {
    final onResults = session.activeView == FindMusicView.results;
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
              connectionKey: widget.connectionKey,
            ),
            const ConnectionBanner(),
          ],
        ),
      );
    }

    // No opaque fill and no bottom rule — the bar and the content below it
    // read as one surface, with the Discover glow showing through both.
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: kKalinkaTopBarHeight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 3, 6, 3),
          child: Row(
            children: [
              Semantics(
                label: 'Back',
                button: true,
                child: GestureDetector(
                  onTap: _handleBack,
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox(
                    width: 42,
                    height: _kBarMinHeight,
                    child: Icon(
                      Icons.arrow_back,
                      size: 22,
                      color: KalinkaColors.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _buildTitle(session)),
              if (!onResults && session.shownListing.isCatalog)
                CatalogPinButton(
                  page: session.shownListing,
                  filter: session.catalogFilter.copyWith(
                    type: session.expandedShelf,
                  ),
                ),
              // Only where there is something to narrow: the Catalogs root
              // has no listing of its own.
              if (!_filterCapabilities(session).isEmpty)
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
  }

  /// What the shown visit is, and nothing about how it was reached: Back
  /// returns along the way it came, which a fixed path would misstate.
  Widget _buildTitle(SearchSessionState session) {
    final String title;
    if (session.activeView == FindMusicView.results) {
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
      leading: [
        // Only present while the library pipeline is still running.
        const _IndexerProgressCard(),
        // The only way back into the last search after backing out of it.
        if (session.resultsAvailable && session.searchQuery.isNotEmpty)
          _ResultsReturnPill(
            query: session.searchQuery,
            onTap: () {
              ref
                  .read(searchSessionProvider.notifier)
                  .selectView(FindMusicView.results);
            },
          ),
        _DiscoverHero(
          entryKey: _entryKey,
          hint: _hintText(session, smart: smart),
          smartSearch: smart,
          smartSources: smart ? ref.watch(smartSearchSourcesProvider) : '',
          onOpenSearch: _openSearch,
        ),
        const SizedBox(height: kHomeSectionGap),
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
    final targetTop = topInset + kKalinkaTopBarHeight;

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
                        title: onResults
                            ? 'REFINE RESULTS'
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
        final origin =
            _originRect ??
            Rect.fromLTWH(
              16,
              targetTop + 120,
              math.min(surfaceWidth - 32, _kSearchEntryMaxWidth),
              56,
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

/// Return-to-results pill on the Catalogs root; re-enters the Results layer
/// without re-running the query.
class _ResultsReturnPill extends StatelessWidget {
  final String query;
  final VoidCallback onTap;

  const _ResultsReturnPill({required this.query, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 14),
      child: Semantics(
        label: 'Back to results',
        button: true,
        child: Material(
          color: KalinkaColors.surfaceRaised,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: KalinkaColors.borderDefault),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.auto_awesome,
                    size: 15,
                    color: KalinkaColors.gold,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      query,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KalinkaTextStyles.trackRowSubtitle.copyWith(
                        color: KalinkaColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'RESULTS',
                    style: KalinkaTextStyles.sectionLabel.copyWith(
                      color: KalinkaColors.textSecondary,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: KalinkaColors.textSecondary,
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
  final VoidCallback onOpenSearch;

  const _DiscoverHero({
    required this.entryKey,
    required this.hint,
    required this.smartSearch,
    required this.smartSources,
    required this.onOpenSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What shall we play?',
            style: KalinkaFonts.display(
              fontSize: KalinkaTypography.baseSize + 17,
              fontWeight: FontWeight.w600,
              color: KalinkaColors.textPrimary,
            ),
          ),
          const SizedBox(height: 18),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kSearchEntryMaxWidth),
            child: _SearchEntryButton(
              key: entryKey,
              hint: hint,
              smart: smartSearch,
              onTap: onOpenSearch,
            ),
          ),
          if (smartSources.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Smart search works with $smartSources.',
                style: KalinkaTextStyles.trackRowSubtitle.copyWith(
                  fontSize: KalinkaTypography.baseSize,
                  color: KalinkaColors.textMuted,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The header artwork, from the top of the bar across the pane from its left
/// edge; mirrored, so it fades out rightwards, near the right edge, and
/// downwards. A pane wider than 16:9 allows stretches it rather than growing
/// it taller than the hero.
class _HeroArtwork extends StatelessWidget {
  const _HeroArtwork();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
            child: Transform.flip(
              flipX: true,
              child: SizedBox(
                width: width,
                height: math.min(width * 9 / 16, 300.0),
                // Toned in the bloom's family: deep berry where it fades in,
                // warming to blush on the bright threads.
                child: ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (bounds) => LinearGradient(
                    begin: Alignment.bottomLeft,
                    end: Alignment.topRight,
                    colors: [
                      KalinkaColors.accent.withValues(alpha: 0.7),
                      KalinkaColors.accentTint.withValues(alpha: 0.75),
                      Color.lerp(
                        KalinkaColors.accentTint,
                        KalinkaColors.textPrimary,
                        0.6,
                      )!.withValues(alpha: 0.8),
                    ],
                    stops: const [0, 0.5, 1],
                  ).createShader(bounds),
                  child: SvgPicture.asset(
                    'assets/images/header_artwork.svg',
                    fit: BoxFit.fill,
                  ),
                ),
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
