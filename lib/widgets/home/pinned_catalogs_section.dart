import 'dart:math' as math;

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
import '../search_cards/browse_item_rows.dart';
import '../shelf_heading.dart';
import 'catalog_tile.dart';
import 'catalog_artwork.dart';
import 'home_layout.dart';
import 'preview_shelf.dart';

/// Group adjacent shortcuts and recognised album folders without crossing any
/// intervening pin. Saved pins and destinations remain independent.
class PinnedCatalogsSection extends ConsumerWidget {
  final List<PinnedCatalog> pins;

  const PinnedCatalogsSection({super.key, required this.pins});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      final available =
          ref
              .watch(sourceModulesProvider)
              .value
              ?.any(
                (source) =>
                    source.name == 'localfiles' &&
                    source.enabled &&
                    source.can(ModuleCapability.catalogs),
              ) ??
          false;
      if (!available) continue;
      final album = ref
          .watch(
            homeFolderAlbumProvider((
              id: pin.page.id!,
              revision:
                  ref.watch(collectionsRevisionProvider) +
                  ref.watch(
                    indexerStatusProvider.select(
                      (state) => state.libraryRevision,
                    ),
                  ),
            )),
          )
          .asData
          ?.value;
      if (album != null) albums[pin.key] = album;
    }
    final blocks = <List<PinnedCatalog>>[];
    for (final pin in pins) {
      if (albums.containsKey(pin.key) &&
          blocks.isNotEmpty &&
          albums.containsKey(blocks.last.last.key)) {
        blocks.last.add(pin);
      } else {
        blocks.add([pin]);
      }
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final wide = constraints.maxWidth >= 800 * scale;
        final columnCount = wide
            ? math.max(
                2,
                ((constraints.maxWidth + 32) / (520 * scale + 32)).floor(),
              )
            : 1;
        Widget preview(List<PinnedCatalog> block) => block.length == 1
            ? PinnedCatalogPreview(
                key: ValueKey(block.first.key),
                pin: block.first,
                wide: wide,
              )
            : HomeAlbumFolderGroup(
                key: ValueKey('album-folders:${block.first.key}'),
                pins: block,
                albums: albums,
                wide: wide,
              );
        bool large(List<PinnedCatalog> block) =>
            block.length == 1 &&
            block.first.preview.adaptive &&
            !block.first.page.folderLayout &&
            block.first.largePreview;
        bool adaptive(List<PinnedCatalog> block) =>
            block.first.preview.adaptive && !block.first.shortcut;
        final children = <Widget>[];
        for (var index = 0; index < blocks.length;) {
          if (blocks[index].first.shortcut) {
            final tiles = <Widget>[];
            do {
              tiles.add(preview(blocks[index++]));
            } while (index < blocks.length && blocks[index].first.shortcut);
            children.add(
              Padding(
                padding: const EdgeInsets.only(bottom: kHomePinGap),
                child: CatalogTileGrid(children: tiles),
              ),
            );
          } else if (wide &&
              index + 1 < blocks.length &&
              adaptive(blocks[index]) &&
              adaptive(blocks[index + 1])) {
            final columns = <List<List<PinnedCatalog>>>[];
            while (columns.length < columnCount &&
                index < blocks.length &&
                adaptive(blocks[index])) {
              columns.add([blocks[index++]]);
            }
            // Stack ordinary previews alongside a taller catalogue. A grouped
            // album row occupies one slot, just like an ordinary preview.
            if (columns.any((column) => large(column.first))) {
              for (final column in columns) {
                if (!large(column.first) &&
                    index < blocks.length &&
                    adaptive(blocks[index]) &&
                    !large(blocks[index])) {
                  column.add(blocks[index++]);
                }
              }
            }
            children.add(
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < columns.length; i++) ...[
                    if (i > 0) const SizedBox(width: 32),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: columns[i].map(preview).toList(),
                      ),
                    ),
                  ],
                ],
              ),
            );
          } else {
            children.add(preview(blocks[index++]));
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );
      },
    );
  }
}

/// Album-folder pins share a compact row, each keeping its own name and link.
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
  const PinnedCatalogPreview({super.key, required this.pin, this.wide = false});

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
    final available =
        modules.value?.any(
          (module) =>
              module.enabled &&
              module.name == source &&
              // An artist opens by id, without the source's catalogs.
              (pin.page.isArtist || module.can(ModuleCapability.catalogs)),
        ) ??
        false;
    final notifier = ref.read(searchSessionProvider.notifier);
    void open() => notifier.openPage(pin.page, filter: pin.filter);
    CatalogSectionRequest requestOf(int limit) {
      // A finished scan may have changed what a library catalog holds.
      final libraryRevision = source == 'localfiles'
          ? ref.watch(indexerStatusProvider.select((s) => s.libraryRevision))
          : 0;
      return (
        id: pin.page.id!,
        filter: pin.filter.encoded(pin.page.filterCapabilities),
        // An artist's preview is read off one probe, whatever it shows.
        limit: pin.page.isArtist ? artistProbe : limit,
        revision: ref.watch(collectionsRevisionProvider) + libraryRevision,
      );
    }

    if (pin.shortcut) {
      if (loadingSources) {
        return const CatalogTileShimmer(hasSubtitle: true);
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
    final heading = LayoutBuilder(
      builder: (context, constraints) {
        final measure = TextPainter(
          text: TextSpan(
            text: title.toUpperCase(),
            style: KalinkaTextStyles.sectionLabel,
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final fits =
            measure.width + MediaQuery.textScalerOf(context).scale(100) + 60 <
            constraints.maxWidth;
        measure.dispose();
        return ShelfHeading(
          title: title.toUpperCase(),
          source: source,
          showDivider: fits,
          subtitle: detail.isEmpty ? null : detail,
          onViewAll: available ? open : null,
        );
      },
    );
    if (!available && !loadingSources) {
      return Padding(
        padding: const EdgeInsets.only(bottom: kHomePinGap),
        child: heading,
      );
    }
    if (pin.preview.adaptive) {
      final capacity = wide
          ? AdaptiveAlbumPreview.capacityFor(width, large: pin.largePreview)
          : 8;
      final request = (
        listing: requestOf(homePreviewFetchLimit(capacity)),
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
                ? PreviewShelfShimmer(
                    preview: Preview(type: PreviewType.tile, itemsCount: 3),
                  )
                : ref
                      .watch(homePinContentProvider(request))
                      .when(
                        skipLoadingOnReload: false,
                        skipLoadingOnRefresh: false,
                        loading: () => PreviewShelfShimmer(
                          preview: Preview(
                            type: PreviewType.tile,
                            itemsCount: 3,
                          ),
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
                          final items =
                              pin.page.isArtist && source == 'localfiles'
                              ? content.listing.items
                                    .where(
                                      (item) =>
                                          item.album != null &&
                                          sourceOfId(item.id) == source,
                                    )
                                    .toList()
                              : content.listing.items;
                          if (items.isEmpty) {
                            return Text(
                              'No items match this catalog.',
                              style: KalinkaTextStyles.trackRowSubtitle,
                            );
                          }
                          final albums = items.every(
                            (item) => item.album != null,
                          );
                          return BrowseNavigationScope(
                            onOpen: notifier.openBrowseItem,
                            child: album != null || albums
                                ? AdaptiveAlbumPreview(
                                    items: album == null ? items : [album],
                                    wide: wide,
                                    single: album != null,
                                    large: pin.largePreview,
                                    storageId: pin.key,
                                    // The album-folder remains a folder destination.
                                    onOpen: album != null
                                        ? (_) => open()
                                        : notifier.openBrowseItem,
                                  )
                                : BrowseItemRows(
                                    items: items.take(3).toList(),
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
    final limit = pin.preview == HomePreviewType.cards ? 8 : 5;
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
    return Padding(
      padding: const EdgeInsets.only(bottom: kHomePinGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading,
          const SizedBox(height: kHomeHeadingGap),
          loadingSources
              ? PreviewShelfShimmer(preview: preview)
              : ref
                    .watch(pinnedPreviewProvider(request))
                    .when(
                      // A pull to refresh reloads in view, not behind
                      // the previous items.
                      skipLoadingOnReload: false,
                      skipLoadingOnRefresh: false,
                      loading: () => PreviewShelfShimmer(preview: preview),
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
                              child: PreviewShelf(
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
