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
import '../browse_rows_shimmer.dart';
import '../infinite_list_view.dart';
import '../kalinka_button.dart';
import '../search_cards/browse_item_rows.dart';
import '../source_badge.dart';
import 'catalog_sections_view.dart';
import 'collections_edit_bar.dart';
import 'collections_section.dart';

/// One selected catalog page — the single navigation level below the
/// Catalogs root (back lives in the title bar). The banner scrolls away with
/// the items; albums/artists/playlists unroll inline. Items are pulled in
/// chunks by an [InfiniteListView] straight off the browse endpoint
/// (deterministic — never the AI router).
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

  void _countRows(int rows) {
    if (rows != _rows) setState(() => _rows = rows);
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
    final query = ref.watch(
      searchSessionProvider.select((s) => s.catalogFilter),
    );
    // A listing the server takes writes for can change under the page, so a
    // write restarts it the way a filter does.
    final revision = ref.watch(collectionsRevisionProvider);
    ref.listen(collectionsRevisionProvider, (_, __) => _artPolls = 0);
    // Recomputed per chunk, not per row (O(n²) otherwise).
    final trackIdsMemo = _TrackIdsMemo();

    void setQuery(BrowseFilterQuery next) =>
        ref.read(searchSessionProvider.notifier).setCatalogFilter(next);

    final header = _CatalogHeader(
      page: page,
      capabilities: capabilities,
      query: query,
      onQueryChanged: setQuery,
      hasRows: _rows > 0,
    );

    // A catalog made of shelves shows them until a kind is chosen; choosing
    // one narrows the catalog to that kind's flat listing, which is the same
    // listing its shelf was previewing.
    if (page.sections.isNotEmpty && query.type == null) {
      return CatalogSectionsView(
        page: page,
        query: query,
        header: header,
        empty: _emptyState(page, query, onReset: setQuery),
        onViewAll: (type) => ref
            .read(searchSessionProvider.notifier)
            .setCatalogFilter(query.copyWith(type: type), remember: false),
      );
    }

    return InfiniteListView<BrowseItem>(
      key: ValueKey(page.id),
      // Only the facets the server honours restart the list, so touching an
      // inert placeholder never costs a refetch.
      reloadKey: '${page.id}|${query.serverKey(capabilities)}|$revision',
      refreshKey: _artRefresh,
      onLoadedCount: _countRows,
      // No horizontal list padding — the banner bleeds edge to edge; rows and
      // separators carry their own 16px inset instead.
      padding: const EdgeInsets.only(bottom: 24),
      header: header,
      fetchChunk: (offset, limit) async {
        final api = ref.read(kalinkaProxyProvider);
        final list = await api.browse(
          page.id!,
          offset: offset,
          limit: limit,
          filter: query.encoded(capabilities),
        );
        _pollWhileComposing(list.items);
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
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: BrowseItemRows.buildRow(
            item,
            queueContextIds: trackIds.isEmpty ? null : trackIds,
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
      emptyBuilder: (context) => _emptyState(page, query, onReset: setQuery),
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
  }

  /// What stands where the rows would be. A filter that matched nothing says
  /// so, and offers to drop it — it may have been remembered from a visit
  /// long ago; a listing the server would take writes for — the collections
  /// screen with none made yet — shows what a collection is; anything else is
  /// plain empty.
  Widget _emptyState(
    CatalogPage page,
    BrowseFilterQuery query, {
    required ValueChanged<BrowseFilterQuery> onReset,
  }) {
    if (!query.isEmpty) {
      return _CatalogEmpty(onReset: () => onReset(const BrowseFilterQuery()));
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

  /// Whether the listing under it has anything in it.
  final bool hasRows;

  const _CatalogHeader({
    required this.page,
    required this.capabilities,
    required this.query,
    required this.onQueryChanged,
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

  const CatalogArtBackdrop({super.key, required this.artPath});

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
              Opacity(opacity: 0.45, child: _BakedBlurImage(url: url)),
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
                Text(
                  page.title ?? '',
                  style: KalinkaFonts.display(
                    fontSize: (KalinkaTypography.baseSize + 21) * scale,
                    fontWeight: FontWeight.w600,
                    color: KalinkaColors.textPrimary,
                  ),
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

/// A catalog that resolved but holds nothing — [onReset] is there when it is
/// filters that matched none of it rather than an empty category.
class _CatalogEmpty extends StatelessWidget {
  /// Drops the filters that emptied the page; null when none did.
  final VoidCallback? onReset;

  const _CatalogEmpty({this.onReset});

  @override
  Widget build(BuildContext context) {
    final filtered = onReset != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              filtered
                  ? Icons.filter_list_off_rounded
                  : Icons.library_music_outlined,
              size: 40,
              color: KalinkaColors.textSecondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              filtered ? 'Nothing matches these filters' : 'Nothing here yet',
              style: KalinkaTextStyles.cardTitle,
            ),
            if (filtered) ...[
              const SizedBox(height: 16),
              // Neutral: dropping filters destroys nothing.
              KalinkaButton(
                label: 'Reset filters',
                variant: KalinkaButtonVariant.neutral,
                size: KalinkaButtonSize.compact,
                onTap: onReset,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
