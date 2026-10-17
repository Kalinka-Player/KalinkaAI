import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/catalog_section_provider.dart';
import '../../providers/catalog_sources_provider.dart';
import '../../providers/collections_provider.dart';
import '../../providers/indexer_status_provider.dart';
import '../../providers/pinned_catalogs_provider.dart';
import '../../providers/search_session_provider.dart';
import '../../providers/source_modules_provider.dart';
import '../../theme/app_theme.dart';
import '../search_cards/browse_navigation_scope.dart';
import '../shelf_heading.dart';
import 'catalog_tile.dart';
import 'catalog_artwork.dart';
import 'home_layout.dart';
import 'preview_shelf.dart';

/// Only adjacent compact pins share a row, preserving the user's mixed order.
class PinnedCatalogsSection extends StatelessWidget {
  final List<PinnedCatalog> pins;

  const PinnedCatalogsSection({super.key, required this.pins});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var index = 0; index < pins.length;) {
      if (pins[index].preview == HomePreviewType.compact) {
        final tiles = <Widget>[];
        do {
          final pin = pins[index++];
          tiles.add(PinnedCatalogPreview(key: ValueKey(pin.key), pin: pin));
        } while (index < pins.length &&
            pins[index].preview == HomePreviewType.compact);
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: kHomeSectionGap),
            child: CatalogTileGrid(children: tiles),
          ),
        );
      } else {
        final pin = pins[index++];
        children.add(PinnedCatalogPreview(key: ValueKey(pin.key), pin: pin));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// Home without pins: says what pinning is, until dismissed. Absent until a
/// source offers catalogs to pin.
class PinnedCatalogsEmptyCard extends ConsumerWidget {
  const PinnedCatalogsEmptyCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(pinHintDismissedProvider)) return const SizedBox.shrink();
    final sources = ref.watch(catalogSourcesProvider).value;
    if (sources == null || sources.isEmpty) return const SizedBox.shrink();
    return Container(
      // The close button's own padding makes up the top and end.
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 4, 16),
      decoration: BoxDecoration(
        color: KalinkaColors.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KalinkaColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                CupertinoIcons.pin,
                size: 18,
                color: KalinkaColors.accentTint,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Pin catalogs to Home',
                  style: KalinkaTextStyles.trackRowTitle,
                ),
              ),
              IconButton(
                tooltip: 'Dismiss',
                iconSize: 20,
                color: KalinkaColors.textMuted,
                onPressed: () =>
                    ref.read(pinHintDismissedProvider.notifier).dismiss(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'Open a source above, find a catalog and tap ',
                  ),
                  const WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(
                      CupertinoIcons.pin,
                      size: 14,
                      color: KalinkaColors.textSecondary,
                      semanticLabel: 'the pin',
                    ),
                  ),
                  const TextSpan(text: ' to keep it here.'),
                ],
              ),
              style: KalinkaTextStyles.trackRowSubtitle,
            ),
          ),
        ],
      ),
    );
  }
}

class PinnedCatalogPreview extends ConsumerWidget {
  final PinnedCatalog pin;
  const PinnedCatalogPreview({super.key, required this.pin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              module.can(ModuleCapability.catalogs),
        ) ??
        false;
    final notifier = ref.read(searchSessionProvider.notifier);
    void open() => notifier.openPage(pin.page, filter: pin.filter);
    final sourceDescription = [
      sourceTitle,
      if (pin.filterDescription.isNotEmpty) pin.filterDescription,
      if (!available) 'Unavailable',
    ].join(' · ');
    if (pin.preview == HomePreviewType.compact) {
      if (loadingSources) {
        return const CatalogTileShimmer(hasSubtitle: true);
      }
      return CatalogTile(
        title: pin.page.title ?? 'Catalog',
        subtitle: sourceDescription,
        icon: info?.icon ?? Icons.library_music_outlined,
        tint: info?.color ?? colorForSourceName(source),
        onTap: available ? open : null,
      );
    }
    final title = pin.page.title ?? 'Catalog';
    final description = pin.page.description?.trim() ?? '';
    final about =
        description.isEmpty ||
            description.toLowerCase() == title.trim().toLowerCase()
        ? null
        : description;
    final subtitle = !available && !loadingSources ? 'Unavailable' : about;
    if (pin.preview == HomePreviewType.artwork) {
      return Padding(
        padding: const EdgeInsets.only(bottom: kHomeSectionGap),
        child: CatalogArtwork(
          page: pin.page,
          description: subtitle,
          sourceIcon: info?.icon ?? Icons.library_music_outlined,
          sourceColor: info?.color ?? colorForSourceName(source),
          onOpen: available ? open : null,
        ),
      );
    }
    // The pin marks it as one of yours; the subtitle says where it's from.
    final heading = ShelfHeading(
      showDivider: false,
      title: title.toUpperCase(),
      icon: CupertinoIcons.pin,
      iconColor: info?.color ?? colorForSourceName(source),
      subtitle: [
        sourceTitle,
        if (pin.filterDescription.isNotEmpty) pin.filterDescription,
        if (!available && !loadingSources) 'Unavailable',
        ?about,
      ].join(' · '),
      onViewAll: available ? open : null,
    );
    if (!available && !loadingSources) {
      return Padding(
        padding: const EdgeInsets.only(bottom: kHomeSectionGap),
        child: heading,
      );
    }
    // A finished scan may have changed what a library catalog holds.
    final libraryRevision = sourceOfId(pin.page.id!) == 'localfiles'
        ? ref.watch(indexerStatusProvider.select((s) => s.libraryRevision))
        : 0;
    final request = (
      id: pin.page.id!,
      filter: pin.filter.encoded(pin.page.filterCapabilities),
      limit: pin.preview == HomePreviewType.cards ? 8 : 5,
      revision: ref.watch(collectionsRevisionProvider) + libraryRevision,
    );
    final preview = Preview(
      type: pin.preview == HomePreviewType.cards
          ? PreviewType.imageText
          : PreviewType.tile,
      itemsCount: request.limit,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: kHomeSectionGap),
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
                                items: list.items.take(request.limit).toList(),
                                preview: preview,
                                storageId: pin.key,
                                onOpenItem: notifier.openBrowseItem,
                              ),
                            ),
                    ),
        ],
      ),
    );
  }
}
