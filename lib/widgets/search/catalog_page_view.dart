import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/browse_filters.dart';
import '../../data_model/data_model.dart';
import '../../providers/catalog_cards_provider.dart';
import '../../providers/artist_relations_provider.dart';
import '../../providers/collection_edit_provider.dart';
import '../../providers/collections_provider.dart';
import '../../providers/indexer_status_provider.dart';
import '../../providers/kalinka_player_api_provider.dart';
import '../../providers/listing_presentation_provider.dart';
import '../../providers/search_session_provider.dart';
import '../../providers/source_modules_provider.dart';
import '../../providers/url_resolver.dart';
import '../../theme/app_theme.dart';
import '../browse_filters/active_filter_chips.dart';
import '../browse_filters/browse_filter_form.dart' show filterTypeLabel;
import '../browse_filters/filters_match_nothing.dart';
import '../browse_filters/presentation_toggle.dart';
import '../browse_rows_shimmer.dart';
import '../infinite_list_view.dart';
import '../loading_shimmer.dart';
import '../measure_size.dart';
import '../page_banner.dart';
import '../search_cards/action_pill_button.dart';
import '../search_cards/artwork_grid_card.dart';
import '../search_cards/browse_item_rows.dart';
import '../search_cards/browse_navigation_scope.dart';
import '../search_cards/editable_track_list.dart';
import '../search_cards/row_columns.dart';
import '../search_cards/search_track_row.dart';
import '../shelf_heading.dart';
import '../source_badge.dart';
import 'add_queue_chip.dart';
import 'album_page_header.dart';
import 'artist_page_header.dart';
import 'browse_visit_scope.dart';
import 'catalog_sections_view.dart';
import 'catalog_sliver_header.dart';
import 'collections_edit_bar.dart';
import 'collections_section.dart';
import 'container_page_actions.dart';
import 'library_rescan_control.dart';
import 'track_group_actions.dart';

/// One browsed page in the browsing history (back lives in the title bar).
/// The banner scrolls away with the items; every row opens its own page. A
/// page of folders shows one folder at a time under a breadcrumb, its
/// subfolders above its tracks. An album, playlist or collection lists its
/// tracks, and a collection is edited here.
/// Items are pulled in chunks by an [InfiniteListView] straight off the
/// browse endpoint (deterministic — never the AI router).
class CatalogPageView extends ConsumerStatefulWidget {
  final CatalogPage page;

  /// When supplied, Home owns the album cover behind the system inset and
  /// navigation. The header reports its height so that cover ends at the list.
  final ValueChanged<double>? onAlbumHeaderHeight;

  /// Where in that header the album's title ends and its shade starts.
  final ValueChanged<AlbumHeaderInsets>? onAlbumInsets;
  final ValueChanged<bool>? onHeaderCollapsed;

  /// How far a catalog's header scrolls before it is fully collapsed.
  final ValueChanged<double>? onHeaderCollapseExtent;

  /// Returns to the Catalogs root — used by the error state's action.
  final VoidCallback onBackToCatalogs;

  const CatalogPageView({
    super.key,
    required this.page,
    required this.onBackToCatalogs,
    this.onAlbumHeaderHeight,
    this.onAlbumInsets,
    this.onHeaderCollapsed,
    this.onHeaderCollapseExtent,
  });

  /// The Grid/List choice a visit's listing offers, if any. Folders, albums
  /// and playlists list tracks, and a catalog of shelves lays them out
  /// itself until one is opened.
  static ListingLayout? presentationLayoutOf(SearchSessionState visit) {
    final page = visit.catalogPage;
    final shelf = visit.expandedShelf;
    final shelves =
        !page.folderLayout &&
        !page.isAlbum &&
        !page.isPlaylist &&
        page.sections.isNotEmpty &&
        visit.catalogFilter.copyWith(type: shelf).type == null;
    if (page.folderLayout || page.isAlbum || page.isPlaylist || shelves) {
      return null;
    }
    return _CatalogPageViewState._layoutOf(page, shelf);
  }

  @override
  ConsumerState<CatalogPageView> createState() => _CatalogPageViewState();
}

class _CatalogPageViewState extends ConsumerState<CatalogPageView> {
  /// The listing's size as the server last said, -1 before it has. The head
  /// shows it, and its actions have nothing to act on when it is 0.
  int _total = -1;

  /// What each listing shown here led with. Where its catalog does not say
  /// what it holds, the first item decides how it lays out a grid and how
  /// it shimmers when it loads again, never the rest of the listing.
  final _firstKinds = <String, BrowseType>{};
  String? _listingKey;
  BrowseType? get _firstKind => _firstKinds[_listingKey];

  final _albumTrackDurations = <int, int>{};
  int? _reportedAlbumDuration;
  int? _albumDuration;

  /// What this page's own build last read of what the fetches found.
  Object? _builtFrom;
  Object get _fetched => (_total, _albumDuration, _firstKind);

  void _countRows(int rows, bool appended) {
    // The head reads the total and duration a fetch just read; a refresh may
    // correct them without changing how many rows there are. A chunk that
    // only adds rows leaves the page, and the rows already built, alone.
    if (appended && _fetched == _builtFrom) return;
    setState(() {});
  }

  void _readAlbumDuration(BrowseItemsList list, int offset) {
    if (offset == 0) {
      _albumTrackDurations.clear();
      final reported = widget.page.totalDurationSeconds;
      _reportedAlbumDuration = reported != null && reported > 0
          ? reported
          : null;
    }
    for (var i = 0; i < list.items.length; i++) {
      final track = list.items[i].track;
      _albumTrackDurations[offset + i] = track?.duration ?? 0;
      final reported = track?.album?.duration;
      if (reported != null && reported > 0) _reportedAlbumDuration ??= reported;
    }
    // Never present a paginated subtotal as the album's length. Zero/missing
    // track durations also mean that a reliable sum is not available yet.
    final complete =
        list.total > 0 && _albumTrackDurations.length == list.total;
    _albumDuration =
        _reportedAlbumDuration ??
        (complete && _albumTrackDurations.values.every((seconds) => seconds > 0)
            ? _albumTrackDurations.values.fold<int>(
                0,
                (sum, seconds) => sum + seconds,
              )
            : null);
  }

  /// A folder's header and the actions in it. Where the actions sit in the
  /// header is measured while both are laid out, since a header scrolled far
  /// enough away is kept without being laid out again.
  final _headerKey = GlobalKey();
  final _actionsKey = GlobalKey();
  double? _actionsTop;

  /// The folder's actions have scrolled up to the trail and are held there.
  bool _actionsHeld = false;
  String? _shownListingId;

  static const _heldInset = 4.0;

  bool _holdActions(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final actions = _actionsKey.currentContext?.findRenderObject();
    final header = _headerKey.currentContext?.findRenderObject();
    if (actions is RenderBox && header is RenderBox && actions.hasSize) {
      _actionsTop = actions.localToGlobal(Offset.zero, ancestor: header).dy;
    }
    final top = _actionsTop;
    // The header is the list's first row, so its offsets are scroll offsets.
    final reached =
        top != null && notification.metrics.pixels >= top - _heldInset;
    if (reached != _actionsHeld) setState(() => _actionsHeld = reached);
    return false;
  }

  /// See [_pollWhileComposing].
  static const _artPollInterval = Duration(seconds: 4);
  static const _maxArtPolls = 8;
  int _artRefresh = 0;
  int _artPolls = 0;
  Timer? _artTimer;

  /// The server composes a collection's cover in the background after the
  /// first listing that shows it with tracks, and nothing announces it. So
  /// while a collection is listed with tracks and no cover, ask again every
  /// few seconds, refreshing in place — bounded like the Discover cards' art
  /// poll, and renewed by each write.
  void _pollWhileComposing(List<BrowseItem> items) {
    if (!mounted) return;
    _artTimer?.cancel();
    final builtin = ref.read(builtinSourcesProvider);
    final composing = items.any(
      (item) =>
          ownedByServer(builtin, item.id) &&
          (item.playlist?.trackCount ?? 0) > 0 &&
          artPathOf(item) == null,
    );
    if (!composing || _artPolls >= _maxArtPolls) return;
    _artTimer = Timer(_artPollInterval, () {
      if (!mounted) return;
      _artPolls++;
      setState(() => _artRefresh++);
    });
  }

  @override
  void dispose() {
    _artTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BrowseNavigationScope(
    onOpen: ref.read(searchSessionProvider.notifier).openBrowseItem,
    child: _buildPage(context),
  );

  Widget _buildPage(BuildContext context) {
    final page = widget.page;
    // Parses the id; read once rather than per row.
    final isAlbum = page.isAlbum;
    final catalogChrome = CatalogSliverHeader.appliesTo(page);
    final capabilities = page.filterCapabilities;
    final visit = visitOf(context, ref);
    final filter = visit.catalogFilter;
    final expandedShelf = visit.expandedShelf;
    final query = filter.copyWith(type: expandedShelf);
    // Per filter too: a shelf or a filter can lead with another kind, and a
    // response to an earlier one must not decide this one's layout.
    final listingKey =
        '${(page.folderLayout ? visit.shownListing : page).id}|'
        '${query.serverKey(capabilities)}';
    _listingKey = listingKey;
    _builtFrom = _fetched;
    // A listing the server takes writes for can change under the page, so a
    // write restarts it the way a filter does.
    final revision = ref.watch(collectionsRevisionProvider);
    final libraryRevision = sourceOfId(page.id ?? '') == 'localfiles'
        ? ref.watch(indexerStatusProvider.select((s) => s.libraryRevision))
        : 0;
    ref.listen(collectionsRevisionProvider, (_, _) => _artPolls = 0);
    // Recomputed per chunk, not per row (O(n²) otherwise).
    final trackIdsMemo = _TrackIdsMemo();

    final notifier = ref.read(searchSessionProvider.notifier);
    void setQuery(BrowseFilterQuery next) {
      // A pending text debounce must not edit another visit after navigation.
      if (ref.read(searchSessionProvider).visitId == visit.visitId) {
        notifier.setCatalogFilter(next);
      }
    }

    if (page.isArtist) return _buildArtist(page, visit);
    final listing = page.folderLayout ? visit.shownListing : page;
    // A catalog made of shelves shows them until a kind is chosen; choosing
    // one narrows the catalog to that kind's flat listing, which is the same
    // listing its shelf was previewing.
    // An album is its tracks, whatever sections it claims.
    final shelves =
        !page.folderLayout &&
        !isAlbum &&
        !page.isPlaylist &&
        page.sections.isNotEmpty &&
        query.type == null;
    // A listing laid out as its catalog's preview says, or as chosen for it
    // on this device.
    final layout = CatalogPageView.presentationLayoutOf(visit);
    final grid =
        layout != null &&
        watchPresentation(ref, layout) == ListingPresentation.grid;
    // What a grid holds: what its catalog says, else what it led with.
    final gridKind = switch (layout?.contentType) {
      PreviewContentType.album => BrowseType.album,
      PreviewContentType.artist => BrowseType.artist,
      PreviewContentType.playlist => BrowseType.playlist,
      PreviewContentType.catalog => BrowseType.catalog,
      PreviewContentType.track => BrowseType.track,
      _ => _firstKind,
    };
    // Any folder shown, the same one again included, opens at its top.
    if (listing.id != _shownListingId) {
      _shownListingId = listing.id;
      _actionsTop = null;
      _actionsHeld = false;
    }

    final sliverHeader = catalogChrome
        ? CatalogSliverHeader(
            page: listing,
            query: query,
            onCollapsed: widget.onHeaderCollapsed,
            onCollapseExtent: widget.onHeaderCollapseExtent,
            actions: page.folderLayout && _FolderActions.anyFor(page, listing)
                ? _FolderActions(page: page, listing: listing)
                : null,
          )
        : null;
    final Widget header = isAlbum
        ? MeasureSize(
            onChange: (size) => widget.onAlbumHeaderHeight?.call(size.height),
            child: AlbumPageHeader(
              page: page,
              trackCount: _total < 0 ? null : _total,
              totalDurationSeconds: _albumDuration,
              showArtwork: widget.onAlbumHeaderHeight == null,
              onInsets: widget.onAlbumInsets,
            ),
          )
        : page.folderLayout
        ? _FolderHeader(
            key: _headerKey,
            page: page,
            listing: listing,
            actionsKey: _actionsKey,
            showIdentity: !catalogChrome,
          )
        : _CatalogHeader(
            page: page,
            capabilities: capabilities,
            query: filter,
            onQueryChanged: setQuery,
            expandedShelf: expandedShelf,
            onCollapse: () => notifier.expandShelf(null),
            total: _total < 0 ? null : _total,
            layout: catalogChrome ? null : layout,
            showBanner: !catalogChrome,
          );

    // A collection being edited lists its tracks to be moved and dropped
    // rather than played, all of them at once, since an edit names them all.
    // Only the shown visit: one kept for Back would load its whole list too.
    if (ContainerPageActions.isCollection(page) &&
        ref.watch(collectionEditProvider.select((s) => s.active)) &&
        ref.watch(searchSessionProvider.select((s) => s.visitId)) ==
            visit.visitId) {
      return CustomScrollView(
        slivers: [
          ?sliverHeader,
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 24),
            sliver: SliverList.list(
              children: [
                header,
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: EditableTrackList(
                    item: ContainerPageActions.itemOf(page),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (shelves) {
      return CatalogSectionsView(
        page: page,
        query: query,
        revision: revision + libraryRevision,
        header: header,
        sliverHeader: sliverHeader,
        empty: _emptyState(page, filter, onReset: setQuery),
        onViewAll: notifier.expandShelf,
      );
    }

    // Tracks on a folder page carry a position column before their cover.
    bool numberedInFolder(BrowseItem item) =>
        page.folderLayout && item.track != null;

    InfiniteListView<BrowseItem> listOf(
      Widget? head, {
      int columns = 1,
      bool grid = false,
      Widget? sideHeader,
      double sideHeaderWidth = 0,
    }) => InfiniteListView(
      // Scroll kept for this visit only: the same page opened again starts
      // at its top.
      key: page.folderLayout
          ? ValueKey(listing.id)
          : PageStorageKey((visit.visitId, listing.id)),
      // Only the facets the server honours restart the list, so touching an
      // inert placeholder never costs a refetch.
      reloadKey: '${listing.id}|${query.serverKey(capabilities)}|$revision',
      refreshKey: (_artRefresh, libraryRevision),
      onLoadedCount: _countRows,
      // Album and folder headings change as later chunks land.
      rowsDependOn: isAlbum || page.folderLayout
          ? null
          : (loaded) => (
              trackIdsMemo.source(loaded),
              trackIdsMemo.details(loaded),
              trackIdsMemo.artists(loaded),
              trackIdsMemo.tracksOnly(loaded),
            ),
      // No horizontal list padding — the banner bleeds edge to edge; rows and
      // separators carry their own 16px inset instead.
      padding: const EdgeInsets.only(bottom: 24),
      header: head,
      sliverHeader: sliverHeader,
      sideHeader: sideHeader,
      sideHeaderWidth: sideHeaderWidth,
      columns: columns,
      rowPadding: EdgeInsets.symmetric(
        horizontal: grid ? 16 - ArtworkGridCard.inset : 16,
      ),
      // A grid's frames abut, as a Home rail's do.
      columnGap: grid ? 0 : 16,
      rowGap: grid ? 0 : 6,
      fetchChunk: (offset, limit) async {
        final api = ref.read(kalinkaProxyProvider);
        final list = await api.browse(
          listing.id!,
          offset: offset,
          limit: limit,
          filter: query.encoded(capabilities),
        );
        _pollWhileComposing(list.items);
        if (offset == 0 && list.items.isNotEmpty) {
          _firstKinds[listingKey] = list.items.first.browseType;
        }
        _total = list.total;
        if (isAlbum) _readAlbumDuration(list, offset);
        return ItemChunk(items: list.items, total: list.total);
      },
      // Inset past the artwork of the row it follows, so the thumbnails read
      // as one uninterrupted column down the page.
      separatorBuilder: (context, _, above) => grid
          ? const SizedBox.shrink()
          : Padding(
              padding: EdgeInsets.only(
                left:
                    16 +
                    BrowseItemRows.textInsetOf(
                      above,
                      inFolder: page.folderLayout,
                    ) +
                    (numberedInFolder(above)
                        ? SearchTrackRow.folderNumberWidth
                        : 0),
                right: 16,
              ),
              child: Divider(
                color: KalinkaColors.borderSubtle,
                thickness: 1,
                height: isAlbum ? 1 : 14,
              ),
            ),
      itemBuilder: (context, item, index, loaded) {
        Widget attributed(Widget child) => SourceAttributionScope(
          source:
              page.isCatalog &&
                  (listing.provider?.trim().isNotEmpty == true ||
                      listing.description?.trim().isNotEmpty == true) &&
                  trackIdsMemo.source(loaded) == sourceOfId(listing.id!)
              ? sourceOfId(listing.id!)
              : null,
          child: child,
        );
        if (grid && _inGrid(item)) {
          final card = ArtworkGridCard(
            item: item,
            catalogAspectRatio: page.preview?.aspectRatio,
          );
          return attributed(
            columns == 1
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16 - ArtworkGridCard.inset,
                    ),
                    child: card,
                  )
                : card,
          );
        }
        // Track rows play the whole loaded list as a queue from the
        // tapped row; as more chunks scroll in, the context grows.
        final trackIds = trackIdsMemo.of(loaded);
        if (grid && columns > 1) {
          return attributed(
            _GridTrack(
              item: item,
              queueContextIds: trackIds.isEmpty ? null : trackIds,
            ),
          );
        }
        // Unfiltered, a row's place in the listing is its place in the
        // container, which then plays whole from it.
        final inContainer =
            (isAlbum || page.isPlaylist) && item.track != null && query.isEmpty;
        final row = isAlbum && item.track != null
            ? SearchTrackRow(
                item: item,
                queueContextIds: trackIds.isEmpty ? null : trackIds,
                containerId: inContainer ? page.id : null,
                containerIndex: inContainer ? index : null,
                containerSize: _total < 0 ? null : _total,
                albumTrackNumber: trackIdsMemo.albumNumberAt(index, loaded),
                albumArtist: page.description,
                labelled: false,
              )
            : inContainer
            ? SearchTrackRow(
                item: item,
                queueContextIds: trackIds.isEmpty ? null : trackIds,
                containerId: page.id,
                containerIndex: index,
                containerSize: _total < 0 ? null : _total,
              )
            : numberedInFolder(item)
            ? SearchTrackRow(
                item: item,
                queueContextIds: trackIds.isEmpty ? null : trackIds,
                folderTrackNumber: trackIdsMemo.folderNumberAt(index, loaded),
              )
            : BrowseItemRows.buildRow(
                item,
                queueContextIds: trackIds.isEmpty ? null : trackIds,
                // A folder draws the folders it holds as folders; anywhere
                // else they are the catalogs they are.
                inFolder: page.folderLayout,
              );
        final heading = isAlbum
            ? _discHeading(index, loaded, trackIdsMemo.multiDisc(loaded))
            : page.folderLayout
            ? _groupHeading(index, loaded)
            : null;
        // An album's numbered rows keep no columns to name; a folder names
        // them under each group's heading, in that group's terms.
        final titles = isAlbum
            ? null
            : page.folderLayout
            ? (heading == null
                  ? null
                  : RowColumnsHeader(
                      tracks: item.browseType == BrowseType.track,
                      titleInset:
                          BrowseItemRows.textInsetOf(item, inFolder: true) +
                          (numberedInFolder(item)
                              ? SearchTrackRow.folderNumberWidth
                              : 0),
                    ))
            : index == 0
            ? _columnTitles(loaded)
            : null;
        return attributed(
          RowColumnsListing(
            details: trackIdsMemo.details(loaded),
            artists: trackIdsMemo.artists(loaded),
            tracks: trackIdsMemo.tracksOnly(loaded),
            hideTrackType: trackIdsMemo.tracksOnly(loaded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: heading == null && titles == null
                  ? row
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [?heading, ?titles, row],
                    ),
            ),
          ),
        );
      },
      // A grid shimmers as what it will hold: covers, or rows for tracks;
      // until that is known, a spinner. Rows are rows whatever they hold.
      initialPlaceholder: !grid || gridKind == BrowseType.track
          ? const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: BrowseRowsShimmer(count: 8),
            )
          : gridKind == null
          ? const LoadingSpinner()
          : _GridShimmer(columns: columns, rows: 3),
      loadMorePlaceholder: !grid || gridKind == BrowseType.track
          ? const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: BrowseRowsShimmer(count: 3, leadingDivider: true),
            )
          : _GridShimmer(columns: columns, rows: 1),
      emptyBuilder: (context) => _emptyState(page, filter, onReset: setQuery),
      // The error state replaces only the rows, never the header — a filter
      // that failed has to stay reachable to be undone.
      errorBuilder: (context, _) => sideHeader != null || sliverHeader != null
          ? _CatalogError(onReturn: widget.onBackToCatalogs)
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: header),
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _CatalogError(onReturn: widget.onBackToCatalogs),
                ),
              ],
            ),
    );
    if (isAlbum) {
      // A wide pane sets the album's cover and details beside its tracks,
      // with one viewport scrolling both columns.
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          if (width < kAlbumSideLayoutWidth) return listOf(header);
          return listOf(
            AlbumTrackActions(
              page: page,
              trackCount: _total < 0 ? null : _total,
            ),
            sideHeaderWidth: (width * 0.4).clamp(220.0, 520.0),
            sideHeader: AlbumIdentityColumn(
              page: page,
              trackCount: _total < 0 ? null : _total,
              totalDurationSeconds: _albumDuration,
            ),
          );
        },
      );
    }
    // List is always a table, one row per line; only Grid goes across. Both
    // share one tree, so switching keeps what has loaded and where it is.
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final listView = LayoutBuilder(
      builder: (context, constraints) => grid
          ? listOf(
              header,
              grid: true,
              columns: _gridColumns(
                constraints.maxWidth - 2 * (16 - ArtworkGridCard.inset),
                scale,
                catalogs: gridKind == BrowseType.catalog,
                tracks: gridKind == BrowseType.track,
              ),
            )
          : listOf(header),
    );
    // A folder's trail is the bar's, in place of its title.
    if (!page.folderLayout || catalogChrome) return listView;

    return Stack(
      fit: StackFit.expand,
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _holdActions,
          child: listView,
        ),
        if (_actionsHeld && _FolderActions.anyFor(page, listing))
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: KalinkaColors.background,
                border: Border(
                  bottom: BorderSide(color: KalinkaColors.borderSubtle),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: _heldInset,
                ),
                child: _FolderActions(page: page, listing: listing),
              ),
            ),
          ),
      ],
    );
  }

  /// How far into the artist's mixed listing each relation has read.
  final _relationOffsets = <ArtistRelation, int>{};

  /// One of an artist's relations as a listing of its own, paged through the
  /// artist's mixed listing so its order is the source's.
  ChunkFetcher<BrowseItem> _relationFetch(String id, ArtistRelation relation) {
    bool keep(BrowseItem item) =>
        isArtistRelease(item) == (relation == ArtistRelation.albums);
    return (offset, limit) async {
      final api = ref.read(kalinkaProxyProvider);
      final kept = <BrowseItem>[];
      // Advanced only once the chunk is whole, so a failed read is retried
      // from where it began rather than skipping what it had kept.
      var from = offset == 0 ? 0 : (_relationOffsets[relation] ?? 0);
      while (kept.length < limit) {
        final list = await api.browse(id, offset: from, limit: limit);
        from += list.items.length;
        kept.addAll(list.items.where(keep));
        // A source that does not say its total ends on a short page.
        final ended = list.total < 0
            ? list.items.length < limit
            : from >= list.total;
        if (list.items.isEmpty || ended) {
          _relationOffsets[relation] = from;
          // Read to its end: what is kept is all there is.
          return ItemChunk(items: kept, total: offset + kept.length);
        }
      }
      _relationOffsets[relation] = from;
      return ItemChunk(items: kept);
    };
  }

  /// An artist's page: who they are, then their releases or their tracks,
  /// a tab apiece only where they have both.
  Widget _buildArtist(CatalogPage page, SearchSessionState visit) {
    final relations = ref.watch(artistRelationsProvider(page.id!));
    final notifier = ref.read(searchSessionProvider.notifier);
    final available =
        relations.value ??
        (relations.hasError ? ArtistRelation.values : const <ArtistRelation>[]);
    final shown = available.contains(visit.artistTab)
        ? visit.artistTab
        : (available.firstOrNull ?? ArtistRelation.albums);
    final releases = shown == ArtistRelation.albums;
    // Kept under the artist: one artist's releases may read best as covers,
    // another's as rows.
    final layout = ListingLayout(
      page.id!,
      contentType: PreviewContentType.album,
      byDefault: ListingPresentation.grid,
    );
    final grid =
        releases && watchPresentation(ref, layout) == ListingPresentation.grid;
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Offered once it is known the page lists releases.
        ArtistPageHeader(
          page: page,
          presentation: releases && relations.hasValue ? layout : null,
        ),
        if (available.length > 1)
          ArtistRelationTabs(
            relations: available,
            shown: shown,
            onShow: notifier.setArtistTab,
          ),
      ],
    );
    // Whether it lists releases or tracks is not known yet, so not how they
    // will look either.
    if (relations.isLoading) {
      return ListView(children: [header, const LoadingSpinner()]);
    }
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final trackIdsMemo = _TrackIdsMemo();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = grid
            ? _gridColumns(width - 2 * (16 - ArtworkGridCard.inset), scale)
            : 1;
        return InfiniteListView<BrowseItem>(
          key: ValueKey('${page.id}|$shown'),
          padding: const EdgeInsets.only(bottom: 24),
          header: header,
          columns: columns,
          rowPadding: EdgeInsets.symmetric(
            horizontal: grid ? 16 - ArtworkGridCard.inset : 16,
          ),
          columnGap: grid ? 0 : 16,
          rowGap: grid ? 0 : 6,
          fetchChunk: _relationFetch(page.id!, shown),
          rowsDependOn: (loaded) => (
            trackIdsMemo.details(loaded),
            trackIdsMemo.artists(loaded),
            trackIdsMemo.tracksOnly(loaded),
          ),
          separatorBuilder: (context, _, above) => Padding(
            padding: EdgeInsets.only(
              left: 16 + BrowseItemRows.textInsetOf(above),
              right: 16,
            ),
            child: const Divider(
              color: KalinkaColors.borderSubtle,
              thickness: 1,
              height: 14,
            ),
          ),
          itemBuilder: (context, item, index, loaded) {
            if (grid && _inGrid(item)) return ArtworkGridCard(item: item);
            final trackIds = trackIdsMemo.of(loaded);
            if (grid && columns > 1) {
              return _GridTrack(
                item: item,
                queueContextIds: trackIds.isEmpty ? null : trackIds,
              );
            }
            final row = BrowseItemRows.buildRow(
              item,
              queueContextIds: trackIds.isEmpty ? null : trackIds,
            );
            return RowColumnsListing(
              details: trackIdsMemo.details(loaded),
              artists: trackIdsMemo.artists(loaded),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: index == 0
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [_columnTitles(loaded), row],
                      )
                    : row,
              ),
            );
          },
          initialPlaceholder: grid
              ? _GridShimmer(columns: columns, rows: 2)
              : const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: BrowseRowsShimmer(count: 6),
                ),
          loadMorePlaceholder: grid
              ? _GridShimmer(columns: columns, rows: 1)
              : const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: BrowseRowsShimmer(count: 3, leadingDivider: true),
                ),
          emptyBuilder: (context) => const _CatalogEmpty(),
          errorBuilder: (context, _) => CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: header),
              SliverFillRemaining(
                hasScrollBody: false,
                child: _CatalogError(onReturn: widget.onBackToCatalogs),
              ),
            ],
          ),
        );
      },
    );
  }

  static PreviewContentType? _contentTypeOf(SearchType? type) => switch (type) {
    SearchType.album => PreviewContentType.album,
    SearchType.artist => PreviewContentType.artist,
    SearchType.playlist => PreviewContentType.playlist,
    SearchType.track => PreviewContentType.track,
    _ => null,
  };

  /// How [page] lays out, or the shelf it was narrowed to: that shelf's own
  /// listing, under its own id and as its own preview says.
  static ListingLayout? _layoutOf(CatalogPage page, SearchType? shelf) {
    final id = page.id;
    if (id == null) return null;
    if (shelf == null) return ListingLayout.of(id, page.preview);
    final section = page.sections
        .where((section) => CatalogPage.typeOf(section) == shelf)
        .firstOrNull;
    return ListingLayout.of(
      section?.id ?? '$id#${shelf.name}',
      section?.catalog?.previewConfig ??
          Preview(type: PreviewType.none, contentType: _contentTypeOf(shelf)),
    );
  }

  /// What an artwork grid shows as a card: anything but a track, which keeps
  /// its row.
  static bool _inGrid(BrowseItem item) => item.browseType != BrowseType.track;

  /// The names of the listing's columns, over its first row; nothing while
  /// its rows are too narrow for any.
  static Widget _columnTitles(List<BrowseItem> loaded) => RowColumnsHeader(
    tracks: loaded.every((item) => item.browseType == BrowseType.track),
    titleInset: BrowseItemRows.textInsetOf(loaded.first),
  );

  /// Covers of about 180–220 across, more columns as the pane grows, never
  /// narrower than a readable caption. A track keeps its row, which needs
  /// 68% more room than a cover to read.
  static int _gridColumns(
    double width,
    double scale, {
    bool catalogs = false,
    bool tracks = false,
  }) {
    // Each card is its cover with a frame inset either side.
    const frame = 2 * ArtworkGridCard.inset;
    final grow = tracks ? 1.68 : 1.0;
    final wanted = (width / ((catalogs ? 340 : 220) * grow * scale + frame))
        .ceil();
    final fits = (width / ((catalogs ? 220 : 140) * grow * scale + frame))
        .floor();
    return wanted.clamp(1, fits < 1 ? 1 : fits).clamp(1, 10);
  }

  /// Over each disc's first track, a section heading from the rows' own
  /// edge, a shade under the titles so it reads apart from them.
  Widget? _discHeading(int index, List<BrowseItem> loaded, bool multiDisc) {
    final disc = loaded[index].track?.discNumber;
    // A single-disc album needs no "Disc 1" heading.
    if (!multiDisc ||
        disc == null ||
        (index > 0 && loaded[index - 1].track?.discNumber == disc)) {
      return null;
    }
    return Padding(
      padding: EdgeInsets.only(top: index == 0 ? 8 : 24, bottom: 10),
      child: Semantics(
        header: true,
        child: ShelfHeading(
          title: 'DISC $disc',
          titleColor: KalinkaColors.textSectionLabel,
          showDivider: false,
        ),
      ),
    );
  }

  /// The heading over the first of a folder's subfolders and over the first
  /// of its tracks; a folder lists all its subfolders first, so once a track
  /// has loaded both counts are known.
  Widget? _groupHeading(int index, List<BrowseItem> loaded) {
    bool isFolder(BrowseItem item) =>
        item.browseTypeIn(folder: true) == BrowseType.folder;
    final folder = isFolder(loaded[index]);
    if (index > 0 && isFolder(loaded[index - 1]) == folder) return null;

    final folders = loaded.takeWhile(isFolder).length;
    final settled = folders < loaded.length || loaded.length == _total;
    final int? count = folder
        ? (settled ? folders : null)
        : (_total >= 0 ? _total - folders : null);
    return Padding(
      padding: EdgeInsets.only(top: index == 0 ? 4 : 18, bottom: 10),
      child: ShelfHeading(title: folder ? 'FOLDERS' : 'TRACKS', count: count),
    );
  }

  /// What stands where the rows would be. A filter that matched nothing says
  /// so; a listing the server would take writes for — the collections screen
  /// with none made yet — shows what a collection is; anything else is plain
  /// empty.
  Widget _emptyState(
    CatalogPage page,
    BrowseFilterQuery query, {
    required ValueChanged<BrowseFilterQuery> onReset,
  }) {
    if (!query.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: FiltersMatchNothing(
            onReset: () => onReset(const BrowseFilterQuery()),
          ),
        ),
      );
    }
    if (ContainerPageActions.isCollection(page)) {
      return Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Nothing in this collection yet',
                style: KalinkaTextStyles.trackRowSubtitle,
              ),
              const SizedBox(height: 10),
              AddQueueChip(item: ContainerPageActions.itemOf(page)),
            ],
          ),
        ),
      );
    }
    if (page.canEdit) {
      return const Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: CollectionsEmptyCard(),
        ),
      );
    }
    return const _CatalogEmpty();
  }
}

/// Content following the catalog's pinned header: presentation, container
/// actions and active filters. Other entity pages can retain a plain banner.
class _CatalogHeader extends StatelessWidget {
  final CatalogPage page;
  final BrowseFilterCapabilities capabilities;
  final BrowseFilterQuery query;
  final ValueChanged<BrowseFilterQuery> onQueryChanged;
  final SearchType? expandedShelf;
  final VoidCallback onCollapse;

  /// How many items the listing holds, once its source has said.
  final int? total;

  /// How the listing lays out, offered as a Grid/List choice; null where it
  /// has only rows.
  final ListingLayout? layout;
  final bool showBanner;

  const _CatalogHeader({
    required this.page,
    required this.capabilities,
    required this.query,
    required this.onQueryChanged,
    required this.expandedShelf,
    required this.onCollapse,
    required this.total,
    this.layout,
    this.showBanner = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showBanner)
          _CatalogBanner(
            page: page,
            showLibraryRescan: LibraryRescanControl.isLibraryPage(page.id),
          )
        else if (LibraryRescanControl.isLibraryPage(page.id))
          const LibraryRescanControl(),
        if (layout case final layout?)
          Padding(
            padding: EdgeInsets.fromLTRB(16, showBanner ? 0 : 12, 16, 12),
            child: Align(
              alignment: Alignment.centerRight,
              child: PresentationToggle(layout: layout),
            ),
          ),
        if (ContainerPageActions.appliesTo(page))
          ContainerPageActions(
            page: page,
            total: total,
            narrowed: query.activeCount > 0 || expandedShelf != null,
          )
        else if (page.canEdit)
          const CollectionsActions(),
        // The search is a chip of its own where no field in the bar shows it.
        LayoutBuilder(
          builder: (context, constraints) => ActiveFilterChips(
            capabilities: capabilities,
            query: query,
            showText:
                capabilities.text == FacetSupport.hidden ||
                (!showBanner &&
                    !CatalogSliverHeader.searchInBar(
                      constraints.maxWidth,
                      MediaQuery.textScalerOf(context).scale(16) / 16,
                    )),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            onChanged: onQueryChanged,
            leading: [
              if (expandedShelf case final type?)
                ActiveFilterChip(
                  label: filterTypeLabel(type),
                  onRemove: onCollapse,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A track among a grid's artwork cards, which stays a row: in the cards'
/// frame, so it keeps their gutters and the room between them.
class _GridTrack extends StatelessWidget {
  final BrowseItem item;
  final List<String>? queueContextIds;

  const _GridTrack({required this.item, this.queueContextIds});

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Less what the row already keeps beside its cover and its duration,
      // so both line up with the cards' art.
      padding: const EdgeInsets.fromLTRB(
        ArtworkGridCard.inset - 3,
        ArtworkGridCard.inset,
        ArtworkGridCard.inset - 8,
        ArtworkGridCard.inset,
      ),
      child: SearchTrackRow(item: item, queueContextIds: queueContextIds),
    );
  }
}

/// The head of a page of folders under its breadcrumb: the folder shown's
/// banner, its actions, and — at the page's own top — the page's shelves.
class _FolderHeader extends StatelessWidget {
  final CatalogPage page;

  /// The folder shown, or [page] at its top.
  final CatalogPage listing;

  /// Marks the actions, which are held under the trail once scrolled to it.
  final GlobalKey actionsKey;
  final bool showIdentity;

  const _FolderHeader({
    super.key,
    required this.page,
    required this.listing,
    required this.actionsKey,
    this.showIdentity = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showIdentity)
          _CatalogBanner(
            page: listing,
            showLibraryRescan:
                identical(page, listing) &&
                LibraryRescanControl.isLibraryPage(page.id),
          )
        else if (identical(listing, page) &&
            LibraryRescanControl.isLibraryPage(page.id))
          const LibraryRescanControl(),
        if (showIdentity && _FolderActions.anyFor(page, listing))
          Padding(
            key: actionsKey,
            padding: kKalinkaActionRowPadding,
            child: _FolderActions(page: page, listing: listing),
          ),
        if (identical(listing, page) && page.sections.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SectionShelves(sections: page.sections),
          ),
      ],
    );
  }
}

/// What can be done from the folder shown: play or enqueue everything in it,
/// and, at the far end, go up to the folder enclosing it — away from Play
/// all, which replaces the queue.
class _FolderActions extends ConsumerWidget {
  final CatalogPage page;
  final CatalogPage listing;

  const _FolderActions({required this.page, required this.listing});

  static bool anyFor(CatalogPage page, CatalogPage listing) =>
      !identical(listing, page) || listing.canAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        if (listing.canAdd) ...[
          PlayAllChip(trackIds: [listing.id!]),
          const SizedBox(width: 8),
          AddAllChip(trackIds: [listing.id!], name: listing.title),
        ],
        const Spacer(),
        if (!identical(listing, page))
          ActionPillButton(
            icon: Icons.drive_folder_upload_outlined,
            semanticsLabel: 'Up one folder',
            onTap: () {
              ref.read(searchSessionProvider.notifier).showEnclosingFolder();
            },
          ),
      ],
    );
  }
}

/// Caches the queue-context track ids per loaded-chunk count, so row builds
/// share one list instead of rescanning all loaded items each time.
class _TrackIdsMemo {
  bool _tracksOnly = false;
  int _tracksForLength = -1;

  bool tracksOnly(List<BrowseItem> loaded) {
    if (_tracksForLength != loaded.length) {
      _tracksForLength = loaded.length;
      _tracksOnly =
          loaded.isNotEmpty &&
          loaded.every((item) => item.browseType == BrowseType.track);
    }
    return _tracksOnly;
  }

  String? _source;
  int _sourceForLength = -1;

  String? source(List<BrowseItem> loaded) {
    if (_sourceForLength != loaded.length) {
      _sourceForLength = loaded.length;
      final first = loaded.isEmpty ? null : sourceOfId(loaded.first.id);
      _source =
          first != null && loaded.every((item) => sourceOfId(item.id) == first)
          ? first
          : null;
    }
    return _source;
  }

  List<String> _ids = [];
  int _forLength = 0;
  bool _details = true;
  int _detailsForLength = -1;

  /// Whether any loaded row would fill the Details column.
  bool details(List<BrowseItem> loaded) {
    if (loaded.length != _detailsForLength) {
      _detailsForLength = loaded.length;
      _details = RowColumnsListing.anyDetails(loaded);
    }
    return _details;
  }

  bool _artists = true;
  int _artistsForLength = -1;

  /// Whether any loaded row would fill the Artist column.
  bool artists(List<BrowseItem> loaded) {
    if (loaded.length != _artistsForLength) {
      _artistsForLength = loaded.length;
      _artists = RowColumnsListing.anyArtists(loaded);
    }
    return _artists;
  }

  List<int> _albumNumbers = const [];
  int _albumForLength = -1;
  bool _multiDisc = false;

  /// Grown in place as more items arrive, so a row kept from before queues
  /// them too.
  List<String> of(List<BrowseItem> loaded) {
    if (loaded.length < _forLength) {
      _ids = [];
      _forLength = 0;
    }
    if (loaded.length != _forLength) {
      _ids.addAll([
        for (final i in loaded.skip(_forLength))
          if (i.track != null) i.id,
      ]);
      _forLength = loaded.length;
    }
    return _ids;
  }

  /// Album positions and whether more than one disc is loaded; album pages only.
  void _album(List<BrowseItem> loaded) {
    if (loaded.length == _albumForLength) return;
    _albumForLength = loaded.length;
    var position = 0;
    int? previousDisc;
    int? firstDisc;
    _multiDisc = false;
    _albumNumbers = [];
    for (final item in loaded) {
      final track = item.track;
      final disc = track?.discNumber;
      if (disc != null) {
        firstDisc ??= disc;
        if (disc != firstDisc) _multiDisc = true;
      }
      if (disc != previousDisc) position = 0;
      previousDisc = disc;
      final tagged = track?.trackNumber;
      position = tagged != null && tagged > 0 ? tagged : position + 1;
      _albumNumbers.add(position);
    }
  }

  int albumNumberAt(int index, List<BrowseItem> loaded) {
    _album(loaded);
    return _albumNumbers[index];
  }

  bool multiDisc(List<BrowseItem> loaded) {
    _album(loaded);
    return _multiDisc;
  }

  List<int?> _folderNumbers = const [];
  int _folderForLength = -1;

  /// Folder pages only. The tags are shown only when every loaded track has
  /// one and they rise in listing order; anything else numbers the whole
  /// folder by position, so the two are never mixed.
  int? folderNumberAt(int index, List<BrowseItem> loaded) {
    if (loaded.length != _folderForLength) {
      _folderForLength = loaded.length;
      var previous = 0;
      var tagged = true;
      for (final item in loaded) {
        final track = item.track;
        if (track == null) continue;
        final tag = track.trackNumber;
        if (tag == null || tag <= previous) {
          tagged = false;
          break;
        }
        previous = tag;
      }
      var position = 0;
      _folderNumbers = [
        for (final item in loaded)
          if (item.track == null)
            null
          else
            tagged ? item.track!.trackNumber : ++position,
      ];
    }
    return _folderNumbers[index];
  }
}

/// Height of the blurred-art zone below the title bar. Sizes the backdrop
/// only: the title block is content-sized and much shorter, so the art runs on
/// behind the first rows and fades out among them. Tying the two together
/// meant a wash big enough to see forced dead space above the title.
double _artZoneHeight(double width) => (120 + width * 0.12).clamp(150.0, 230.0);

/// The blurred catalog art as a full-bleed backdrop for the page — painted at
/// the surface Stack level (like the Discover-root bloom) so it runs from the
/// very top of the screen, behind the status inset and title bar, and fades
/// into the page canvas before the first rows. The scrolling content passes
/// over it; at 0.45 opacity under a bake-time blur it reads as a colour wash.
class CatalogArtBackdrop extends ConsumerWidget {
  final String artPath;

  /// The art is a square cover rather than a card's wide art, so it is laid
  /// on the right and fades in from the left the way card art does, leaving
  /// the text column dark.
  final bool fromCover;

  /// Where card art starts to clear from black, and where it is fully clear
  /// (the server's card renderer, `_LEFT_DARK_HOLD` and `_LEFT_DARK_END`).
  static const _coverStart = 0.38;
  static const _coverClear = 0.60;

  const CatalogArtBackdrop({
    super.key,
    required this.artPath,
    this.fromCover = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (artPath.isEmpty) return const SizedBox.shrink();
    final url = ref.watch(urlResolverProvider).abs(artPath);
    final topInset = MediaQuery.paddingOf(context).top;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Chrome above + the banner zone (matching _CatalogBanner's height
        // curve), so the fade lands right where the rows begin.
        final height =
            topInset +
            kKalinkaTopBarHeight +
            _artZoneHeight(constraints.maxWidth);
        return SizedBox(
          height: height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Opacity(
                opacity: 0.45,
                child: fromCover
                    ? _onTheRight(_BakedBlurImage(url: url))
                    : _BakedBlurImage(url: url),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  // Full strength across the title bar and the title, then
                  // clear before the rows get far — the text block no longer
                  // fills the zone, so the fade has to do that job itself.
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.30, 0.90],
                    colors: [Color(0x00080808), KalinkaColors.background],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

Widget _onTheRight(Widget art) => FractionallySizedBox(
  alignment: Alignment.centerRight,
  widthFactor: 1 - CatalogArtBackdrop._coverStart,
  child: ShaderMask(
    blendMode: BlendMode.dstIn,
    shaderCallback: (bounds) => const LinearGradient(
      stops: [
        0,
        (CatalogArtBackdrop._coverClear - CatalogArtBackdrop._coverStart) /
            (1 - CatalogArtBackdrop._coverStart),
      ],
      colors: [Colors.transparent, Colors.white],
    ).createShader(bounds),
    child: art,
  ),
);

/// The scrolling page banner: the Playfair title + attribution over the
/// left half of [CatalogArtBackdrop]'s art zone (the art itself is fixed at
/// the surface level and does not scroll with this header).
class _CatalogBanner extends ConsumerWidget {
  final CatalogPage page;
  final bool showLibraryRescan;

  const _CatalogBanner({required this.page, this.showLibraryRescan = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // One attribution line, not two: the provider name and the description
    // said much the same thing ("Local Library" over "Recently added
    // tracks"). The badge keeps the attribution; the description carries the
    // words, and only stands in for itself when there is none.
    final description = page.description?.trim() ?? '';
    final subtitle = description.isNotEmpty
        ? description
        : (page.provider ?? '');

    final rescanSupported =
        showLibraryRescan &&
        ref.watch(
          indexerStatusProvider.select((s) => s.scan?.rescanSupported == true),
        );
    final banner = PageBanner(
      title: page.title ?? '',
      subtitle: subtitle,
      padding: EdgeInsets.fromLTRB(16, 8, 16, rescanSupported ? 8 : 24),
      subtitleLeading: subtitle.isEmpty
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SourceBadge(entityId: page.id!),
                if (sourceBadgeVisible(ref, page.id!)) const SizedBox(width: 7),
              ],
            ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [banner, if (showLibraryRescan) const LibraryRescanControl()],
    );
  }
}

/// The banner art blurred ONCE into an offscreen raster when it loads, then
/// drawn as a plain texture. A live ImageFiltered re-ran its Gaussian pass on
/// the raster thread every scrolled frame (120→60fps while visible); a tiny
/// decode upscaled by the sampler was cheap but read pixelated on wide
/// windows. Shows nothing until the bake lands (same as the old load/error
/// behaviour); a url change keeps the previous bake until the new one is in.
class _BakedBlurImage extends StatefulWidget {
  final String url;

  const _BakedBlurImage({required this.url});

  @override
  State<_BakedBlurImage> createState() => _BakedBlurImageState();
}

class _BakedBlurImageState extends State<_BakedBlurImage> {
  // Bake resolution: small enough that the one-shot blur is negligible, big
  // enough that the cover-fit upscale stays smooth. Sigma is in bake pixels,
  // so on-screen softness grows with the window — fine, it's a backdrop.
  static const int _bakeWidth = 320;
  static const double _sigma = 14;

  ImageStream? _stream;
  ImageStreamListener? _listener;
  ui.Image? _baked;

  /// Bumped per resolve; a bake finishing under an older generation (url
  /// changed, widget reused) drops its result.
  int _bakeGen = 0;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(_BakedBlurImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _resolve();
  }

  void _resolve() {
    final oldStream = _stream;
    final oldListener = _listener;
    final gen = ++_bakeGen;
    _listener = ImageStreamListener(
      (info, _) => _bake(info, gen),
      onError: (_, _) {}, // No art is a valid banner — keep what's shown.
    );
    _stream = ResizeImage(
      NetworkImage(widget.url),
      width: _bakeWidth,
    ).resolve(ImageConfiguration.empty);
    _stream!.addListener(_listener!);
    if (oldStream != null && oldListener != null) {
      oldStream.removeListener(oldListener);
    }
  }

  Future<void> _bake(ImageInfo info, int gen) async {
    final src = info.image;
    final outW = _bakeWidth;
    final outH = (outW * src.height / src.width).round().clamp(1, 1024);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()
      ..imageFilter = ui.ImageFilter.blur(
        sigmaX: _sigma,
        sigmaY: _sigma,
        tileMode: TileMode.clamp,
      );
    canvas.drawImageRect(
      src,
      Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
      Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
      paint,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(outW, outH);
    picture.dispose();
    info.dispose();
    if (!mounted || gen != _bakeGen) {
      image.dispose();
      return;
    }
    setState(() {
      _baked?.dispose();
      _baked = image;
    });
  }

  @override
  void dispose() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _baked?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baked = _baked;
    if (baked == null) return const SizedBox.shrink();
    return RawImage(
      image: baked,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
    );
  }
}

/// Inline failure state with a visible way back to Catalogs (MD §13).
class _CatalogError extends StatelessWidget {
  final VoidCallback onReturn;

  const _CatalogError({required this.onReturn});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 40,
              color: KalinkaColors.textSecondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'This catalog is unavailable',
              style: KalinkaTextStyles.cardTitle,
            ),
            const SizedBox(height: 4),
            Text(
              'It may be offline or still indexing.',
              style: KalinkaTextStyles.trackRowSubtitle,
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: onReturn,
              icon: const Icon(Icons.chevron_left_rounded, size: 20),
              label: const Text('Return to Catalogs'),
              style: TextButton.styleFrom(
                foregroundColor: KalinkaColors.accentTint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A catalog that resolved but holds nothing.
class _CatalogEmpty extends StatelessWidget {
  const _CatalogEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.library_music_outlined,
              size: 40,
              color: KalinkaColors.textSecondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text('Nothing here yet', style: KalinkaTextStyles.cardTitle),
          ],
        ),
      ),
    );
  }
}

/// Where a grid's covers will be, while they load.
class _GridShimmer extends StatelessWidget {
  final int columns;
  final int rows;

  const _GridShimmer({required this.columns, required this.rows});

  @override
  Widget build(BuildContext context) {
    return ShimmerPulse(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Column(
          children: [
            for (var r = 0; r < rows; r++)
              Padding(
                padding: const EdgeInsets.only(bottom: 22),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var c = 0; c < columns; c++) ...[
                      if (c > 0) const SizedBox(width: 22),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AspectRatio(
                              aspectRatio: 1,
                              child: ShimmerBlock(radius: 10),
                            ),
                            SizedBox(height: 10),
                            FractionallySizedBox(
                              widthFactor: 0.7,
                              child: ShimmerBlock(height: 14, radius: 4),
                            ),
                            SizedBox(height: 6),
                            FractionallySizedBox(
                              widthFactor: 0.45,
                              child: ShimmerBlock(height: 12, radius: 4),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
