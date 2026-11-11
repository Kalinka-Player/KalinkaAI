import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/artist_relations_provider.dart';
import '../../providers/catalog_section_provider.dart';
import '../../providers/collections_provider.dart';
import '../../providers/indexer_status_provider.dart';
import '../../providers/home_pin_content_provider.dart';
import '../../providers/home_preview_cache.dart';
import '../../providers/pinned_catalogs_provider.dart';
import '../../providers/search_session_provider.dart';
import '../../providers/source_modules_provider.dart';
import '../../theme/app_theme.dart';
import '../search_cards/browse_navigation_scope.dart';
import '../shelf_heading.dart';
import 'catalog_tile.dart';
import 'catalog_artwork.dart';
import 'home_layout.dart';
import 'home_list_preview.dart';
import 'home_preview_layout.dart';
import 'home_section_plan.dart';
import 'planned_home_sections.dart';
import 'preview_shelf.dart';

/// Group adjacent shortcuts and same-size recognised album folders without
/// crossing any intervening pin. Saved pins and destinations remain independent.
class PinnedCatalogsSection extends ConsumerWidget {
  final List<PinnedCatalog> pins;

  const PinnedCatalogsSection({super.key, required this.pins});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modules = ref.watch(sourceModulesProvider);
    var loading = modules.isLoading && !modules.hasValue;
    final albums = <String, BrowseItem>{};
    bool candidate(PinnedCatalog pin) =>
        pin.preview.adaptive &&
        !pin.shortcut &&
        pin.page.folderLayout &&
        sourceOfId(pin.page.id!) == 'localfiles';
    // Only probe possible runs. Individual previews use the same canonical
    // verification, independent of their display width or saved filter.
    for (var i = 0; i < pins.length; i++) {
      final pin = pins[i];
      if (!candidate(pin) ||
          !((i > 0 && candidate(pins[i - 1])) ||
              (i + 1 < pins.length && candidate(pins[i + 1])))) {
        continue;
      }
      final available = _sourceAvailable(modules.value, pin);
      if (!available) continue;
      final album = ref.watch(
        homeFolderAlbumProvider((
          id: pin.page.id!,
          revision:
              ref.watch(collectionsRevisionProvider) +
              ref.watch(
                indexerStatusProvider.select((state) => state.libraryRevision),
              ),
        )),
      );
      loading = loading || album.isLoading;
      if (album.asData?.value case final value?) albums[pin.key] = value;
    }
    final blocks = <List<PinnedCatalog>>[];
    for (final pin in pins) {
      if (albums.containsKey(pin.key) &&
          blocks.isNotEmpty &&
          albums.containsKey(blocks.last.last.key) &&
          (pin.preview == HomePreviewType.large) ==
              (blocks.last.last.preview == HomePreviewType.large)) {
        blocks.last.add(pin);
      } else {
        blocks.add([pin]);
      }
    }
    return LayoutBuilder(
      builder: (context, constraints) => Consumer(
        // These subscriptions belong to this constraint-dependent build. Old
        // width buckets are released even while the next request is loading.
        builder: (context, ref, _) {
          final width = constraints.maxWidth;
          final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final caption = homeAlbumCaptionExtent(context);
          final wide = width >= 800 * textScale;
          var pending = loading;
          final limits = <String, int>{};
          final shapes = <HomePreviewBlock>[];
          for (final block in blocks) {
            final pin = block.first;
            var kind = pin.shortcut
                ? HomePreviewBlockKind.shortcut
                : !pin.preview.adaptive
                ? HomePreviewBlockKind.standalone
                : block.length > 1
                ? (pin.preview == HomePreviewType.large
                      ? HomePreviewBlockKind.largeFolders
                      : HomePreviewBlockKind.folders)
                : pin.largePreview && !pin.page.folderLayout
                ? HomePreviewBlockKind.collage
                : HomePreviewBlockKind.ordinary;
            var count = block.length > 1 ? block.length : 8;
            if (block.length == 1 && pin.preview.adaptive && !pin.shortcut) {
              // Fetch enough for the widest candidate once, rather than making
              // network requests for each layout the optimiser considers. The
              // child reuses exactly this request, including its bucket/revision.
              final limit = pin.page.isArtist
                  ? artistProbe
                  : homePreviewFetchLimit(
                      wide
                          ? homePreviewCapacity(
                              width,
                              large: pin.largePreview,
                              captionExtent: caption,
                              textScale: textScale,
                              listRowsPerColumn: _listRowsFor(pin, wide: wide),
                            )
                          : 8,
                    );
              limits[pin.key] = limit;
              final available = _sourceAvailable(modules.value, pin);
              if (available) {
                final state = ref.watch(
                  homePinContentProvider((
                    listing: _previewRequest(ref, pin, limit),
                    folder: pin.page.folderLayout,
                  )),
                );
                pending = pending || state.isLoading;
                final content = state.asData?.value;
                if (content != null) {
                  final items = _previewItems(pin, content);
                  // Use loaded, displayable items, never an optimistic total from
                  // a paginated or mixed listing. Growing the pane fetches the
                  // next bounded bucket before requesting a more spacious plan.
                  count = content.folderAlbum != null ? 1 : items.length;
                  kind = content.folderAlbum != null
                      ? (pin.preview == HomePreviewType.large
                            ? HomePreviewBlockKind.collage
                            : HomePreviewBlockKind.ordinary)
                      : _usesArtworkPreview(items)
                      ? (pin.largePreview
                            ? HomePreviewBlockKind.collage
                            : HomePreviewBlockKind.ordinary)
                      : switch (pin.preview) {
                          HomePreviewType.preview =>
                            HomePreviewBlockKind.shortTracks,
                          HomePreviewType.large =>
                            HomePreviewBlockKind.longTracks,
                          _ => HomePreviewBlockKind.tracks,
                        };
                }
              }
            } else if (block.length == 1 &&
                pin.preview != HomePreviewType.artwork &&
                _sourceAvailable(modules.value, pin) &&
                (!pin.shortcut || pin.page.sections.isEmpty)) {
              // Legacy previews and shortcut counts must settle too: a late
              // count can wrap a shortcut's footer and move the whole row.
              final limit = pin.shortcut
                  ? 1
                  : pin.preview == HomePreviewType.cards
                  ? 8
                  : homeListCapacity(
                      width,
                      rowsPerColumn: 5,
                      textScale: textScale,
                    );
              limits[pin.key] = limit;
              final state = ref.watch(
                pinnedPreviewProvider(_previewRequest(ref, pin, limit)),
              );
              pending = pending || state.isLoading;
            }
            if (kind == HomePreviewBlockKind.ordinary &&
                pin.preview == HomePreviewType.automatic) {
              kind = HomePreviewBlockKind.automatic;
            }
            shapes.add((
              kind: kind,
              count: count,
              extraCaption:
                  block.length > 1 && block.any((pin) => pin.homeName != null)
                  ? 2 * 20 * textScale
                  : 0,
            ));
          }
          return PlannedHomeSections(
            ready: !pending,
            request: HomeSectionRequest(
              width: width,
              textScale: textScale,
              captionExtent: caption,
              blocks: shapes,
            ),
            builder: (plan) {
              Widget preview(
                int index, {
                double largeCover = homeAlbumLargeCover,
                bool promoteToLarge = false,
                int? automaticListRows,
              }) {
                final block = blocks[index];
                return block.length == 1
                    ? PinnedCatalogPreview(
                        key: ValueKey(block.first.key),
                        pin: block.first,
                        wide: plan.wide,
                        requestLimit: limits[block.first.key],
                        largeCover: largeCover,
                        promoteToLarge: promoteToLarge,
                        automaticListRows: automaticListRows,
                      )
                    : HomeAlbumFolderGroup(
                        key: ValueKey('album-folders:${block.first.key}'),
                        pins: block,
                        albums: albums,
                        wide: plan.wide,
                      );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final row in plan.rows)
                    if (row.shortcuts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: kHomePinGap),
                        child: CatalogTileGrid(
                          children: row.columns.single.blocks
                              .map(preview)
                              .toList(),
                        ),
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < row.columns.length; i++) ...[
                            if (i > 0)
                              const SizedBox(width: homePreviewColumnGap),
                            SizedBox(
                              width: row.columns[i].width,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: row.columns[i].blocks
                                    .map(
                                      (index) => preview(
                                        index,
                                        largeCover: row.largeCover,
                                        promoteToLarge: row.promotedBlocks
                                            .contains(index),
                                        automaticListRows:
                                            row.automaticListRows[index],
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          ],
                        ],
                      ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// Album-folder pins share a row at their chosen size, keeping names and links.
class HomeAlbumFolderGroup extends ConsumerWidget {
  final List<PinnedCatalog> pins;
  final Map<String, BrowseItem> albums;
  final bool wide;

  const HomeAlbumFolderGroup({
    super.key,
    required this.pins,
    required this.albums,
    required this.wide,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigation = ref.read(searchSessionProvider.notifier);
    return Padding(
      padding: const EdgeInsets.only(bottom: kHomePinGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ShelfHeading(
            title: 'PINNED FOLDERS',
            source: 'localfiles',
            subtitle:
                '${ref.watch(sourceDisplayInfoProvider)['localfiles']?.title ?? 'My Library'} · Folders',
          ),
          const SizedBox(height: kHomeHeadingGap),
          HomeAlbumFolderCards(
            wide: wide,
            large: pins.first.preview == HomePreviewType.large,
            storageId: pins.first.key,
            entries: [
              for (final pin in pins)
                (
                  key: pin.key,
                  album: albums[pin.key]!,
                  homeName: pin.homeName,
                  onOpen: () =>
                      navigation.openPage(pin.page, filter: pin.filter),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class PinnedCatalogPreview extends StatelessWidget {
  final PinnedCatalog pin;
  final bool wide;
  final int? requestLimit;
  final double largeCover;
  final bool promoteToLarge;
  final int? automaticListRows;
  const PinnedCatalogPreview({
    super.key,
    required this.pin,
    this.wide = false,
    this.requestLimit,
    this.largeCover = homeAlbumLargeCover,
    this.promoteToLarge = false,
    this.automaticListRows,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Consumer(
      builder: (context, ref, _) => _build(context, ref, constraints.maxWidth),
    ),
  );

  Widget _build(BuildContext context, WidgetRef ref, double width) {
    final modules = ref.watch(sourceModulesProvider);
    final loadingSources = modules.isLoading && !modules.hasValue;
    final source = sourceOfId(pin.page.id!)!;
    final info = ref.watch(sourceDisplayInfoProvider)[source];
    final sourceTitle = info?.title ?? source;
    final available = _sourceAvailable(modules.value, pin);
    final notifier = ref.read(searchSessionProvider.notifier);
    void open() => notifier.openPage(pin.page, filter: pin.filter);
    CatalogSectionRequest requestOf(int limit) =>
        _previewRequest(ref, pin, limit);

    if (pin.shortcut) {
      if (loadingSources) {
        return const CatalogTileShimmer(hasSubtitle: true, shortcut: true);
      }
      // A sectioned catalog's own total counts its shelves, not its items.
      final list = available && pin.page.sections.isEmpty
          ? ref.watch(pinnedPreviewProvider(requestOf(1))).value
          : null;
      final total = list?.total;
      final first = list?.items.firstOrNull;
      final kind = !pin.page.isArtist
          ? pin.page.preview?.contentType
          : first != null && !isArtistRelease(first)
          ? PreviewContentType.track
          : PreviewContentType.album;
      return CatalogTile(
        shortcut: true,
        title: pin.title,
        subtitle: [
          sourceTitle,
          if (pin.filterDescription.isNotEmpty) pin.filterDescription,
          if (total != null && total >= 0) _countLabel(total, kind),
          if (!available) 'Unavailable',
        ].join(' · '),
        icons: info?.icons,
        icon: info?.icon ?? Icons.library_music_outlined,
        tint: info?.color ?? colorForSourceName(source),
        onTap: available ? open : null,
      );
    }
    final title = pin.title;
    final description = pin.page.description?.trim() ?? '';
    final about =
        description.isEmpty ||
            description.toLowerCase() == title.trim().toLowerCase()
        ? null
        : description;
    final subtitle = !available && !loadingSources ? 'Unavailable' : about;
    if (pin.preview == HomePreviewType.artwork) {
      return Padding(
        padding: const EdgeInsets.only(bottom: kHomePinGap),
        child: CatalogArtwork(
          page: pin.page,
          description: subtitle,
          sourceIcon: info?.icon ?? Icons.library_music_outlined,
          sourceColor: info?.color ?? colorForSourceName(source),
          onOpen: available ? open : null,
        ),
      );
    }
    // The source's tile before the title says where it's from; the subtitle
    // says what of it, where there is more to say.
    final detail = [
      if (pin.preview.adaptive) sourceTitle,
      if (pin.preview.adaptive && pin.page.folderLayout) 'Folder',
      if (pin.preview.adaptive && pin.page.isArtist) 'Artist',
      if (pin.filterDescription.isNotEmpty) pin.filterDescription,
      if (!available && !loadingSources) 'Unavailable',
      ?about,
    ].join(' · ');
    final sourceArtwork = info?.icons?.standard;
    final sourceWidth =
        ((sourceArtwork?.minHeight ?? 0) * (sourceArtwork?.aspectRatio ?? 1))
            .clamp(20.0, double.infinity);
    final headingWidth =
        homeLabelWidth(
          context,
          title.toUpperCase(),
          KalinkaTextStyles.sectionLabel,
        ) +
        sourceWidth +
        10 +
        12 +
        (available
            ? 12 +
                  24 +
                  homeLabelWidth(
                    context,
                    'View All',
                    KalinkaFonts.sans(
                      fontSize: KalinkaTypography.baseSize,
                      fontWeight: FontWeight.w500,
                    ),
                  )
            : 0);
    final heading = ShelfHeading(
      title: title.toUpperCase(),
      source: source,
      showDivider: headingWidth < width,
      subtitle: detail.isEmpty ? null : detail,
      onViewAll: available ? open : null,
    );
    if (!available && !loadingSources) {
      return Padding(
        padding: const EdgeInsets.only(bottom: kHomePinGap),
        child: heading,
      );
    }
    if (pin.preview.adaptive) {
      final rowsPerColumn =
          pin.preview == HomePreviewType.automatic && automaticListRows != null
          ? automaticListRows!
          : _listRowsFor(pin, wide: wide);
      final limit =
          requestLimit ??
          homePreviewFetchLimit(
            wide
                ? homePreviewCapacity(
                    width,
                    large: pin.largePreview,
                    captionExtent: homeAlbumCaptionExtent(context),
                    textScale: MediaQuery.textScalerOf(context).scale(14) / 14,
                    listRowsPerColumn: rowsPerColumn,
                  )
                : 8,
          );
      final request = (
        listing: requestOf(limit),
        folder: pin.page.folderLayout,
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: kHomePinGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            heading,
            const SizedBox(height: kHomeHeadingGap),
            loadingSources
                ? HomeListPreviewShimmer(rowsPerColumn: rowsPerColumn)
                : ref
                      .watch(homePinContentProvider(request))
                      .when(
                        skipLoadingOnReload: false,
                        skipLoadingOnRefresh: false,
                        loading: () => HomeListPreviewShimmer(
                          rowsPerColumn: rowsPerColumn,
                        ),
                        error: (_, _) => TextButton.icon(
                          onPressed: () {
                            ref.invalidate(
                              pinnedPreviewProvider(request.listing),
                            );
                            ref.invalidate(homePinContentProvider(request));
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Could not load preview. Retry'),
                        ),
                        data: (content) {
                          final album = content.folderAlbum;
                          final items = _previewItems(pin, content);
                          if (items.isEmpty) {
                            return Text(
                              'No items match this catalog.',
                              style: KalinkaTextStyles.trackRowSubtitle,
                            );
                          }
                          final artwork = _usesArtworkPreview(items);
                          return BrowseNavigationScope(
                            onOpen: notifier.openBrowseItem,
                            child: album != null || artwork
                                ? AdaptiveAlbumPreview(
                                    items: album == null ? items : [album],
                                    wide: wide,
                                    single: album != null,
                                    largeCover: largeCover,
                                    large:
                                        (promoteToLarge &&
                                            pin.preview ==
                                                HomePreviewType.automatic) ||
                                        (album != null
                                            ? pin.preview ==
                                                  HomePreviewType.large
                                            : pin.largePreview),
                                    storageId: pin.key,
                                    // The album-folder remains a folder destination.
                                    onOpen: album != null
                                        ? (_) => open()
                                        : notifier.openBrowseItem,
                                  )
                                : HomeListPreview(
                                    items: items,
                                    rowsPerColumn: rowsPerColumn,
                                    labelled: !items.every(
                                      (item) => item.track != null,
                                    ),
                                    inFolder: pin.page.folderLayout,
                                  ),
                          );
                        },
                      ),
          ],
        ),
      );
    }
    final limit =
        requestLimit ??
        (pin.preview == HomePreviewType.cards
            ? 8
            : homeListCapacity(
                width,
                rowsPerColumn: 5,
                textScale: MediaQuery.textScalerOf(context).scale(14) / 14,
              ));
    final request = requestOf(limit);
    final preview = Preview(
      type: pin.preview == HomePreviewType.cards
          ? PreviewType.imageText
          : PreviewType.tile,
      itemsCount: limit,
      // The shape and size of card its catalog asks for.
      aspectRatio: pin.page.preview?.aspectRatio,
      cardSize: pin.page.preview?.cardSize,
    );
    Widget placeholder() => pin.preview == HomePreviewType.list
        ? const HomeListPreviewShimmer(rowsPerColumn: 5)
        : PreviewShelfShimmer(preview: preview);
    return Padding(
      padding: const EdgeInsets.only(bottom: kHomePinGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading,
          const SizedBox(height: kHomeHeadingGap),
          loadingSources
              ? placeholder()
              : ref
                    .watch(pinnedPreviewProvider(request))
                    .when(
                      // A pull to refresh reloads in view, not behind
                      // the previous items.
                      skipLoadingOnReload: false,
                      skipLoadingOnRefresh: false,
                      loading: placeholder,
                      error: (_, _) => TextButton.icon(
                        onPressed: () =>
                            ref.invalidate(pinnedPreviewProvider(request)),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Could not load preview. Retry'),
                      ),
                      data: (list) => list.items.isEmpty
                          ? Text(
                              'No items match this catalog.',
                              style: KalinkaTextStyles.trackRowSubtitle,
                            )
                          : BrowseNavigationScope(
                              onOpen: notifier.openBrowseItem,
                              child: pin.preview == HomePreviewType.list
                                  ? HomeListPreview(
                                      items: list.items,
                                      rowsPerColumn: 5,
                                      inFolder: pin.page.folderLayout,
                                    )
                                  : PreviewShelf(
                                      items: list.items.take(limit).toList(),
                                      preview: preview,
                                      storageId: pin.key,
                                      onOpenItem: notifier.openBrowseItem,
                                      inFolder: pin.page.folderLayout,
                                    ),
                            ),
                    ),
        ],
      ),
    );
  }
}

bool _sourceAvailable(List<ModuleInfo>? modules, PinnedCatalog pin) =>
    modules?.any(
      (module) =>
          module.enabled &&
          module.name == sourceOfId(pin.page.id!) &&
          // An artist opens by id, without the source's catalogs.
          (pin.page.isArtist || module.can(ModuleCapability.catalogs)),
    ) ??
    false;

CatalogSectionRequest _previewRequest(
  WidgetRef ref,
  PinnedCatalog pin,
  int limit,
) => (
  id: pin.page.id!,
  filter: pin.filter.encoded(pin.page.filterCapabilities),
  limit: pin.page.isArtist ? artistProbe : limit,
  revision:
      ref.watch(collectionsRevisionProvider) +
      (sourceOfId(pin.page.id!) == 'localfiles'
          ? ref.watch(indexerStatusProvider.select((s) => s.libraryRevision))
          : 0),
);

int _listRowsFor(PinnedCatalog pin, {required bool wide}) =>
    homePreviewRowCount(
      wide: wide,
      small: pin.preview == HomePreviewType.preview,
      large: pin.preview == HomePreviewType.large,
    );

// Library album catalogues can begin with the loose-tracks playlist. Keep
// those browsable covers together, preserving order and their destinations.
bool _usesArtworkPreview(List<BrowseItem> items) =>
    items.isNotEmpty &&
    items.every((item) => item.album != null || item.playlist != null);

String _countLabel(int count, PreviewContentType? kind) {
  final (one, many) = switch (kind) {
    PreviewContentType.album => ('album', 'albums'),
    PreviewContentType.artist => ('artist', 'artists'),
    PreviewContentType.playlist => ('playlist', 'playlists'),
    PreviewContentType.track => ('track', 'tracks'),
    _ => ('item', 'items'),
  };
  return '$count ${count == 1 ? one : many}';
}

List<BrowseItem> _previewItems(PinnedCatalog pin, HomePinContent content) {
  if (!pin.page.isArtist || sourceOfId(pin.page.id!) != 'localfiles') {
    return content.listing.items;
  }
  final local = content.listing.items.where(
    (item) => sourceOfId(item.id) == 'localfiles',
  );
  final albums = local.where((item) => item.album != null).toList();
  // artistPreviewOf returns tracks when the artist has no releases. Keep that
  // fallback: a compilation track's album metadata is not an album child.
  return albums.isNotEmpty
      ? albums
      : local.where((item) => item.track != null).toList();
}
