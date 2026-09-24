import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/browse_filters.dart';
import '../../providers/catalog_cards_provider.dart';
import '../../providers/indexer_status_provider.dart';
import '../../providers/row_expansion_provider.dart';
import '../../providers/search_session_provider.dart';
import '../../providers/selection_state_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptics.dart';
import '../browse_filters/search_filter_button.dart';
import '../browse_filters/search_filter_overlay.dart';
import '../mini_player.dart';
import '../overlay_card.dart';
import '../selection_overlay.dart';
import '../server_chip.dart';
import 'catalog_page_view.dart';
import 'results_view.dart';
import 'search_composer.dart';
import 'search_zero_state.dart';

/// How far the Discover backdrop reaches below the status inset. The bloom
/// is drawn over all of it and [_kDiscoverFadeOut] dissolves it before the
/// bottom, so this is the bloom's reach and not an edge anything can see.
const double _kDiscoverBackdropHeight = 340;

/// The crimson bloom over the Discover root: off the top-right corner,
/// rising behind the title bar and the status-bar inset.
final _kDiscoverBloom = RadialGradient(
  center: const Alignment(0.85, -0.75),
  radius: 1.35,
  colors: [
    KalinkaColors.accent.withValues(alpha: 0.26),
    KalinkaColors.accent.withValues(alpha: 0),
  ],
);

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

/// Full-screen search session surface. The search bar sits in a header strip
/// at the top — back button on its left, connection dot on its right — with
/// the scrollable content (zero state, then query blocks, newest on top)
/// below it.
///
/// The bar does not take focus when the session opens; it focuses only when
/// tapped.
class SearchSessionView extends ConsumerStatefulWidget {
  /// Opens the server sheet — the connection dot's tap target.
  final VoidCallback? onServerTap;

  const SearchSessionView({super.key, this.onServerTap});

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
  final _entryKey = GlobalKey();
  Rect? _originRect;

  // Tracks the keyboard so its dismissal (e.g. the hardware back that hides it)
  // also closes the overlay — one back drops both.
  bool _keyboardUp = false;

  // Whether the search-and-filters card is unfolded out of its title-bar pill.
  bool _filtersOpen = false;

  // Rotates the example hint: each mount of the search surface advances one
  // step through the suggestion list.
  static int _hintRotation = 0;
  final int _hintIndex = _hintRotation++;

  // Hit-box height for the back button and connection dot, centred in the bar
  // (whose height is the shared kKalinkaTopBarHeight).
  static const double _kBarMinHeight = 46;

  @override
  void initState() {
    super.initState();
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _composerController.removeListener(_onTextChange);
    _overlayCtrl.dispose();
    _filtersCtrl.dispose();
    _composerController.dispose();
    _composerFocus.dispose();
    // Torn down with the overlay still up (session closed externally) would
    // otherwise leave the shared flag stuck true and the mini-player hidden.
    // Clear it after this frame — a synchronous write could land mid-build of
    // whatever removed this surface.
    if (_focused) {
      final notifier = ref.read(searchEntryModeProvider.notifier);
      WidgetsBinding.instance.addPostFrameCallback((_) => notifier.set(false));
    }
    super.dispose();
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
    // the search surface is only the right panel, and the overlay positions
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
  /// the AI router, and never recorded in search history. With [focusItemId]
  /// the page opens on that row, unrolled: a shortcut into a listing, not a
  /// screen of its own.
  void _openCatalog(
    CatalogCardPlan plan,
    String provider, {
    String? focusItemId,
  }) {
    if (focusItemId != null) {
      ref.read(rowExpansionProvider.notifier).unroll(focusItemId);
    }
    ref
        .read(searchSessionProvider.notifier)
        .openCatalog(
          id: plan.id,
          title: plan.title,
          provider: provider,
          description: plan.description,
          artPath: plan.artPath,
          filters: plan.filters,
          sections: plan.sections,
          canEdit: plan.canEdit,
          focusItemId: focusItemId,
        );
  }

  void _openFilters() {
    if (_filtersOpen) return;
    setState(() => _filtersOpen = true);
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
  void _applyFilters(BrowseFilterQuery filter) {
    final notifier = ref.read(searchSessionProvider.notifier);
    final session = ref.read(searchSessionProvider);
    if (session.activeView == FindMusicView.results) {
      // The field holds the query: a changed one is a new search, an emptied
      // one keeps the search and resets the facets.
      final query = filter.text.trim();
      if (query.isNotEmpty && query != session.searchQuery) {
        notifier.submit(query);
      } else {
        notifier.setResultsFilter(filter);
      }
    } else {
      notifier.setCatalogFilter(filter);
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

  /// One back press unwinds one layer (MD §11): overlay → Results/catalog
  /// page → Catalogs root → close to playback. Shared by the title-bar arrow
  /// and the system back gesture.
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
    final session = ref.read(searchSessionProvider);
    if (session.activeView == FindMusicView.results) {
      ref
          .read(searchSessionProvider.notifier)
          .selectView(FindMusicView.catalogs);
      return;
    }
    if (!session.catalogPage.isRoot) {
      ref.read(searchSessionProvider.notifier).backToCatalogsRoot();
      return;
    }
    ref.read(searchSessionProvider.notifier).close();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(searchSessionProvider);

    // ...and drop the flag too, so back does not spend a press closing a card
    // that is no longer on screen.
    if (_filtersOpen && _filterCapabilities(session).isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _closeFilters();
      });
    }

    // A selection belongs to the listing it was gathered from: leaving that
    // listing — for another catalog, the root, the results, or out of Find
    // Music altogether — ends it rather than keeping a batch bar over rows
    // nothing on screen still shows.
    ref.listen(
      searchSessionProvider.select(
        (s) => (s.isOpen, s.activeView, s.catalogPage.id),
      ),
      (_, __) => ref.read(selectionStateProvider.notifier).exitSelectionMode(),
    );

    // The shared tiles long-press into multi-select; surface the same batch
    // bar the old search feed used so the selection can be acted on.
    final selectionActive = ref.watch(
      selectionStateProvider.select((s) => s.isActive),
    );

    // Find Music owns its back handling: the route must not pop while any
    // in-screen layer can still unwind (the parent screen's PopScope leaves it
    // alone).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: ColoredBox(
        color: KalinkaColors.background,
        child: Stack(
          children: [
            // The backdrop behind the Discover root, full surface width and
            // rising behind the bar and the status-bar inset so the two read
            // as one surface: the bloom, and over it the ground colour that
            // ends it under the search entry.
            if (session.activeView == FindMusicView.catalogs &&
                session.catalogPage.isRoot)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height:
                    MediaQuery.paddingOf(context).top +
                    _kDiscoverBackdropHeight,
                child: IgnorePointer(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(gradient: _kDiscoverBloom),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(gradient: _kDiscoverFadeOut),
                      ),
                    ],
                  ),
                ),
              ),
            // On a catalog page the card's blurred art backs the whole top of
            // the screen — status inset and title bar included — fading into
            // the canvas before the rows (same layer as the bloom above).
            if (session.activeView == FindMusicView.catalogs &&
                !session.catalogPage.isRoot &&
                session.catalogPage.artPath != null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: CatalogArtBackdrop(
                    artPath: session.catalogPage.artPath!,
                  ),
                ),
              ),
            Column(
              children: [
                _buildHeader(session),
                // Both views stay mounted (IndexedStack) so scroll and inline
                // expansion survive view switches without a refetch.
                Expanded(
                  child: IndexedStack(
                    index: session.activeView == FindMusicView.results ? 1 : 0,
                    children: [
                      _buildCatalogsTab(session),
                      session.resultsAvailable
                          ? const ResultsView()
                          : const SizedBox.shrink(),
                    ],
                  ),
                ),
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
      ),
    );
  }

  /// The Catalogs view: its root (search invitation + cards) or the one open
  /// catalog page.
  Widget _buildCatalogsTab(SearchSessionState session) {
    if (!session.catalogPage.isRoot) {
      return CatalogPageView(
        page: session.catalogPage,
        onBackToCatalogs: () =>
            ref.read(searchSessionProvider.notifier).backToCatalogsRoot(),
      );
    }
    return _buildCatalogsRoot(session);
  }

  /// Title bar: back arrow · breadcrumb · filter · connection dot. The arrow
  /// is the one navigation control (layered back, [_handleBack]).
  Widget _buildHeader(SearchSessionState session) {
    final onResults = session.activeView == FindMusicView.results;

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
                  onTap: () {
                    KalinkaHaptics.lightImpact();
                    _handleBack();
                  },
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
              // 2, not 8: the DISCOVER crumb brings 6 of its own so its
              // hover outline has somewhere to sit.
              const SizedBox(width: 2),
              Expanded(child: _buildBreadcrumb(session, onResults)),
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

  /// The navigation stack (`DISCOVER › CATEGORY`); the earlier segment is
  /// muted because it is where back returns to — and, being where back
  /// returns to, it is also a target: tapping it unwinds the same layer the
  /// arrow does.
  Widget _buildBreadcrumb(SearchSessionState session, bool onResults) {
    final String? current = onResults
        ? 'RESULTS'
        : (session.catalogPage.isRoot
              ? null
              : (session.catalogPage.title ?? '').toUpperCase());
    final style = KalinkaTextStyles.trayTitle;

    return Row(
      children: [
        _BreadcrumbCrumb(
          label: 'DISCOVER',
          style: style,
          // At the root there is nowhere to go: DISCOVER is the page itself.
          onTap: current == null ? null : _handleBack,
        ),
        if (current != null) ...[
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              '›',
              style: style.copyWith(color: KalinkaColors.textMuted),
            ),
          ),
          Flexible(
            child: Text(
              current,
              style: style.copyWith(color: KalinkaColors.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }

  /// The Catalogs root: one scroll holding the Playfair question, its
  /// description, the resting search entry, your collections, then the
  /// "EXPLORE CATALOGS" divider, catalog cards and favourites. Tapping the
  /// entry lifts the overlay.
  Widget _buildCatalogsRoot(SearchSessionState session) {
    return SearchZeroState(
      onOpenCatalog: _openCatalog,
      leading: [
        // Only present while the library pipeline is still running.
        const _IndexerProgressCard(),
        // The only way back into the last search after backing out of it.
        if (session.resultsAvailable && session.searchQuery.isNotEmpty)
          _ResultsReturnPill(
            query: session.searchQuery,
            onTap: () {
              KalinkaHaptics.lightImpact();
              ref
                  .read(searchSessionProvider.notifier)
                  .selectView(FindMusicView.results);
            },
          ),
        _DiscoverHero(
          entryKey: _entryKey,
          hint: _hintText(session),
          onOpenSearch: _openSearch,
        ),
        const SizedBox(height: 30),
      ],
    );
  }

  /// Rotating example hint — a different real suggestion each time the surface
  /// mounts, teaching the query language.
  String _hintText(SearchSessionState session) {
    final suggestions = session.suggestions;
    if (suggestions.isEmpty) return 'Ask for music…';
    return 'Try “${suggestions[_hintIndex % suggestions.length].query}”';
  }

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
                        applied: _appliedFilter(session),
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
    final topInset = MediaQuery.paddingOf(context).top;
    // Rest the card at the title-bar bottom rather than the screen top, so it
    // never overlaps the "Find Music" bar.
    final targetTop = topInset + kKalinkaTopBarHeight;

    return LayoutBuilder(
      builder: (context, constraints) {
        final surfaceWidth = constraints.maxWidth;
        final origin =
            _originRect ??
            Rect.fromLTWH(16, targetTop + 120, surfaceWidth - 32, 56);
        return AnimatedBuilder(
          animation: _overlayCtrl,
          builder: (context, _) {
            final t = Curves.easeOutCubic.transform(_overlayCtrl.value);
            // The card slides up from the entry and its left/right ease to the
            // surface margins (they already sit at 16, so mostly vertical).
            final top = lerpDouble(origin.top, targetTop, t)!;
            final left = lerpDouble(origin.left, 16, t)!;
            final right = lerpDouble(surfaceWidth - origin.right, 16, t)!;
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
                          icon: Icons.auto_awesome,
                          title: 'SMART SEARCH',
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
                                color: KalinkaColors.accentBorder,
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
                                hint: 'Search music, or describe a mood',
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

/// The Discover hero: the Playfair question, its description, and the resting
/// search entry. The text keeps to the left half (wrapping as needed); the
/// crimson bloom behind it is painted once at the surface level, not here.
class _DiscoverHero extends StatelessWidget {
  final Key entryKey;
  final String hint;
  final VoidCallback onOpenSearch;

  const _DiscoverHero({
    required this.entryKey,
    required this.hint,
    required this.onOpenSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FractionallySizedBox(
            widthFactor: 0.55,
            child: Text(
              'What shall we play?',
              style: KalinkaFonts.display(
                fontSize: KalinkaTypography.baseSize + 17,
                fontWeight: FontWeight.w600,
                color: KalinkaColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          FractionallySizedBox(
            widthFactor: 0.55,
            child: Text(
              'Describe a mood, activity, genre, or anything else you '
              'would like to hear.',
              style: KalinkaTextStyles.trackRowSubtitle,
            ),
          ),
          const SizedBox(height: 34),
          _SearchEntryButton(key: entryKey, hint: hint, onTap: onOpenSearch),
        ],
      ),
    );
  }
}

/// The resting search entry in the Discover scroll: looks like the field
/// (sparkle + hint) but is a button — tapping it lifts the animated overlay.
/// Its screen rect is measured on open so the overlay card rises from here.
class _SearchEntryButton extends StatelessWidget {
  final String hint;
  final VoidCallback onTap;

  const _SearchEntryButton({
    super.key,
    required this.hint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // The main feature of the surface — a crimson-tinted field with a soft
    // glow so it reads as the invitation, not another gray card.
    return Semantics(
      label: 'Search',
      hint: 'Ask for music in plain language',
      button: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: KalinkaColors.accent.withValues(alpha: 0.16),
              blurRadius: 26,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Material(
          color: Color.alphaBlend(
            KalinkaColors.accentSubtle,
            KalinkaColors.surfaceInput,
          ),
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              KalinkaHaptics.lightImpact();
              onTap();
            },
            child: Container(
              height: 54,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: KalinkaColors.accentBorder, width: 1),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 26,
                    child: Icon(
                      Icons.auto_awesome,
                      size: 16,
                      color: KalinkaColors.gold,
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
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: KalinkaColors.accentTint,
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

/// The parent segment of the breadcrumb: a plain label until the pointer finds
/// it, then an outlined target. Tapping it goes back a layer — the same action
/// as the arrow beside it — so the crumb is not merely a caption.
class _BreadcrumbCrumb extends StatefulWidget {
  final String label;
  final TextStyle style;

  /// Null at the root, where this crumb names the page you are already on.
  final VoidCallback? onTap;

  const _BreadcrumbCrumb({
    required this.label,
    required this.style,
    required this.onTap,
  });

  @override
  State<_BreadcrumbCrumb> createState() => _BreadcrumbCrumbState();
}

class _BreadcrumbCrumbState extends State<_BreadcrumbCrumb> {
  bool _hovering = false;

  void _setHovering(bool value) {
    if (value == _hovering) return;
    setState(() => _hovering = value);
  }

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null;

    final crumb = AnimatedContainer(
      duration: const Duration(milliseconds: 130),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        // White alpha rather than a surface tone: the bar is transparent, so
        // on a catalog page this plate sits over blurred art, and only
        // lightening whatever is behind it reads on both.
        color: _hovering && interactive
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.transparent,
      ),
      child: Text(
        widget.label,
        style: widget.style.copyWith(
          color: interactive
              ? KalinkaColors.textMuted
              : KalinkaColors.textPrimary,
        ),
      ),
    );

    if (!interactive) return crumb;

    return Semantics(
      button: true,
      label: 'Back to Discover',
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHovering(true),
        onExit: (_) => _setHovering(false),
        child: GestureDetector(
          onTap: () {
            KalinkaHaptics.lightImpact();
            widget.onTap!();
          },
          behavior: HitTestBehavior.opaque,
          child: crumb,
        ),
      ),
    );
  }
}
