import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/browse_filters.dart';
import '../../data_model/data_model.dart';
import '../../providers/catalog_cards_provider.dart';
import '../../providers/collections_provider.dart';
import '../../providers/kalinka_player_api_provider.dart';
import '../../providers/search_session_provider.dart';
import '../../providers/source_modules_provider.dart';
import '../../providers/url_resolver.dart';
import '../../theme/app_theme.dart';
import '../browse_filters/active_filter_chips.dart';
import '../browse_filters/browse_filter_form.dart' show filterTypeLabel;
import '../browse_filters/filters_match_nothing.dart';
import '../browse_rows_shimmer.dart';
import '../fitted_title.dart';
import '../infinite_list_view.dart';
import '../search_cards/action_pill_button.dart';
import '../search_cards/browse_item_rows.dart';
import '../shelf_heading.dart';
import '../source_badge.dart';
import 'catalog_sections_view.dart';
import 'collections_edit_bar.dart';
import 'collections_section.dart';
import 'folder_trail.dart';
import 'track_group_actions.dart';

/// One selected catalog page — the single navigation level below the
/// Catalogs root (back lives in the title bar). The banner scrolls away with
/// the items; albums/artists/playlists unroll inline. A page of folders shows
/// one folder at a time under a breadcrumb, its subfolders above its tracks.
/// Items are pulled in chunks by an [InfiniteListView] straight off the
/// browse endpoint (deterministic — never the AI router).
class CatalogPageView extends ConsumerStatefulWidget {
  final CatalogPage page;

  /// Returns to the Catalogs root — used by the error state's action.
  final VoidCallback onBackToCatalogs;

  const CatalogPageView({
    super.key,
    required this.page,
    required this.onBackToCatalogs,
  });

  @override
  ConsumerState<CatalogPageView> createState() => _CatalogPageViewState();
}

class _CatalogPageViewState extends ConsumerState<CatalogPageView> {
  /// How many rows the listing has, as the list last reported it; -1 until it
  /// has said. What the head needs to know is only whether there are any —
  /// an action on the listing has nothing to act on when there are not.
  int _rows = -1;

  /// The listing's size as the server last said, -1 before it has.
  int _total = -1;

  void _countRows(int rows) {
    if (rows != _rows) setState(() => _rows = rows);
  }

  /// A folder's header and the actions in it. Where the actions sit in the
  /// header is measured while both are laid out, since a header scrolled far
  /// enough away is kept without being laid out again.
  final _headerKey = GlobalKey();
  final _actionsKey = GlobalKey();
  double? _actionsTop;

  /// The folder's actions have scrolled up to the trail and are held there.
  bool _actionsHeld = false;

  static const _heldInset = 8.0;

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
  Widget build(BuildContext context) {
    final page = widget.page;
    final capabilities = page.filterCapabilities;
    final (filter, expandedShelf) = ref.watch(
      searchSessionProvider.select((s) => (s.catalogFilter, s.expandedShelf)),
    );
    final query = filter.copyWith(type: expandedShelf);
    // A listing the server takes writes for can change under the page, so a
    // write restarts it the way a filter does.
    final revision = ref.watch(collectionsRevisionProvider);
    ref.listen(collectionsRevisionProvider, (_, __) => _artPolls = 0);
    // Recomputed per chunk, not per row (O(n²) otherwise).
    final trackIdsMemo = _TrackIdsMemo();

    final notifier = ref.read(searchSessionProvider.notifier);
    void setQuery(BrowseFilterQuery next) => notifier.setCatalogFilter(next);

    final listing = page.folderLayout
        ? ref.watch(searchSessionProvider.select((s) => s.shownListing))
        : page;
    // Any folder shown, the same one again included, opens at its top.
    ref.listen(searchSessionProvider.select((s) => s.shownListing), (_, __) {
      _actionsTop = null;
      if (_actionsHeld) setState(() => _actionsHeld = false);
    });

    final Widget header = page.folderLayout
        ? _FolderHeader(
            key: _headerKey,
            page: page,
            listing: listing,
            actionsKey: _actionsKey,
          )
        : _CatalogHeader(
            page: page,
            capabilities: capabilities,
            query: filter,
            onQueryChanged: setQuery,
            expandedShelf: expandedShelf,
            onCollapse: () => notifier.expandShelf(null),
            hasRows: _rows > 0,
          );

    // A catalog made of shelves shows them until a kind is chosen; choosing
    // one narrows the catalog to that kind's flat listing, which is the same
    // listing its shelf was previewing.
    if (!page.folderLayout && page.sections.isNotEmpty && query.type == null) {
      return CatalogSectionsView(
        page: page,
        query: query,
        revision: revision,
        header: header,
        empty: _emptyState(page, filter, onReset: setQuery),
        onViewAll: notifier.expandShelf,
      );
    }

    final listView = InfiniteListView<BrowseItem>(
      key: ValueKey(listing.id),
      // Only the facets the server honours restart the list, so touching an
      // inert placeholder never costs a refetch.
      reloadKey: '${listing.id}|${query.serverKey(capabilities)}|$revision',
      refreshKey: _artRefresh,
      onLoadedCount: _countRows,
      // No horizontal list padding — the banner bleeds edge to edge; rows and
      // separators carry their own 16px inset instead.
      padding: const EdgeInsets.only(bottom: 24),
      header: header,
      fetchChunk: (offset, limit) async {
        final api = ref.read(kalinkaProxyProvider);
        final list = await api.browse(
          listing.id!,
          offset: offset,
          limit: limit,
          filter: query.encoded(capabilities),
        );
        _pollWhileComposing(list.items);
        _total = list.total;
        return ItemChunk(items: list.items, total: list.total);
      },
      // Inset past the artwork of the row it follows, so the thumbnails read
      // as one uninterrupted column down the page.
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
        // Track rows play the whole loaded list as a queue from the
        // tapped row; as more chunks scroll in, the context grows.
        final trackIds = trackIdsMemo.of(loaded);
        final row = BrowseItemRows.buildRow(
          item,
          queueContextIds: trackIds.isEmpty ? null : trackIds,
        );
        final heading = page.folderLayout ? _groupHeading(index, loaded) : null;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: heading == null
              ? row
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [heading, row],
                ),
        );
      },
      initialPlaceholder: const Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: BrowseRowsShimmer(count: 8),
      ),
      loadMorePlaceholder: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: BrowseRowsShimmer(count: 3, leadingDivider: true),
      ),
      emptyBuilder: (context) => _emptyState(page, filter, onReset: setQuery),
      // The error state replaces only the rows, never the header — a filter
      // that failed has to stay reachable to be undone.
      errorBuilder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(child: _CatalogError(onReturn: widget.onBackToCatalogs)),
        ],
      ),
    );
    if (!page.folderLayout) return listView;

    // Outside the list, so the way back stays in reach however far it scrolls.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FolderTrail(),
        Expanded(
          child: Stack(
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
          ),
        ),
      ],
    );
  }

  /// The heading over the first of a folder's subfolders and over the first
  /// of its tracks; a folder lists all its subfolders first, so once a track
  /// has loaded both counts are known.
  Widget? _groupHeading(int index, List<BrowseItem> loaded) {
    bool isFolder(BrowseItem item) => item.browseType == BrowseType.folder;
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

/// Banner plus the active-filter chips — the whole page head, shared by the
/// list header and the error state. The filter *controls* live in the title
/// bar; only what they produced shows here.
class _CatalogHeader extends StatelessWidget {
  final CatalogPage page;
  final BrowseFilterCapabilities capabilities;
  final BrowseFilterQuery query;
  final ValueChanged<BrowseFilterQuery> onQueryChanged;
  final SearchType? expandedShelf;
  final VoidCallback onCollapse;

  /// Whether the listing under it has anything in it.
  final bool hasRows;

  const _CatalogHeader({
    required this.page,
    required this.capabilities,
    required this.query,
    required this.onQueryChanged,
    required this.expandedShelf,
    required this.onCollapse,
    required this.hasRows,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CatalogBanner(page: page),
        if (page.canEdit) CollectionsActions(hasRows: hasRows),
        ActiveFilterChips(
          capabilities: capabilities,
          query: query,
          onChanged: onQueryChanged,
          leading: [
            if (expandedShelf case final type?)
              ActiveFilterChip(
                label: filterTypeLabel(type),
                onRemove: onCollapse,
              ),
          ],
        ),
      ],
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

  const _FolderHeader({
    super.key,
    required this.page,
    required this.listing,
    required this.actionsKey,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CatalogBanner(page: listing),
        if (_FolderActions.anyFor(page, listing))
          Padding(
            key: actionsKey,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
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
  List<String> _ids = const [];
  int _forLength = -1;

  List<String> of(List<BrowseItem> loaded) {
    if (loaded.length != _forLength) {
      _forLength = loaded.length;
      _ids = [
        for (final i in loaded)
          if (i.track != null) i.id,
      ];
    }
    return _ids;
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
class _CatalogBanner extends StatelessWidget {
  final CatalogPage page;

  const _CatalogBanner({required this.page});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Type scales with width, gently.
        return _buildBanner((constraints.maxWidth / 420).clamp(1.0, 1.25));
      },
    );
  }

  Widget _buildBanner(double scale) {
    // One attribution line, not two: the provider name and the description
    // said much the same thing ("Local Library" over "Recently added
    // tracks"). The badge keeps the attribution; the description carries the
    // words, and only stands in for itself when there is none.
    final description = page.description?.trim() ?? '';
    final subtitle = description.isNotEmpty
        ? description
        : (page.provider ?? '');

    return Consumer(
      builder: (context, ref, _) {
        return Container(
          // The text block is content-sized — no zone to be centred in, so
          // these insets are the whole vertical spacing and nothing drifts
          // with window width.
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: FractionallySizedBox(
            // Wide enough that ordinary category names ("Recently Added")
            // stay on one line; longer ones still wrap rather than shrink.
            widthFactor: 0.82,
            // The box defaults to centring its child — the text column hugs
            // the left edge, whatever fraction of the width it takes.
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedTitle(
                  page.title ?? '',
                  style: KalinkaFonts.display(
                    fontSize: (KalinkaTypography.baseSize + 21) * scale,
                    fontWeight: FontWeight.w600,
                    color: KalinkaColors.textPrimary,
                  ),
                  minFontSize: (KalinkaTypography.baseSize + 7) * scale,
                ),
                if (subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Row(
                      children: [
                        SourceBadge(entityId: page.id!),
                        if (sourceBadgeVisible(ref, page.id!))
                          const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            subtitle,
                            style: KalinkaTextStyles.trackRowSubtitle
                                .copyWith(color: KalinkaColors.textSecondary)
                                .apply(fontSizeFactor: scale),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
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
      onError: (_, __) {}, // No art is a valid banner — keep what's shown.
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
