import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart';
import 'browse_root.dart';
import 'catalog_cards_provider.dart';
import 'kalinka_player_api_provider.dart';
import 'source_modules_provider.dart';

/// How many collections the shelf shows before View All, where the server
/// did not say.
const _kDefaultPreviewCount = 3;

/// Bumped whenever a write lands, so everything showing collections — the
/// Discover shelf and the open Collections screen — refetches. Held apart
/// from the shelf itself because the screen reloads off it too.
class CollectionsRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final collectionsRevisionProvider = NotifierProvider<CollectionsRevision, int>(
  CollectionsRevision.new,
);

/// The collections shelf as the Discover root shows it: the first few, how
/// many there are in all, and the catalog View All opens.
class CollectionsShelf {
  final CatalogCardPlan plan;
  final List<BrowseItem> items;
  final int total;

  const CollectionsShelf({
    required this.plan,
    required this.items,
    required this.total,
  });

  bool get isEmpty => total == 0;
}

/// Finds the collections shelf among the server's own sources — the one
/// listing playlists — and takes its first page. Null when the server has no
/// such source, in which case the Discover root shows no section at all.
///
/// Reloads with the catalog cards, so both halves of the root refresh
/// together; the section itself re-fetches on reconnect.
final collectionsShelfProvider = FutureProvider<CollectionsShelf?>((ref) async {
  ref.watch(catalogCardsReloadProvider);
  ref.watch(collectionsRevisionProvider);
  final builtin = ref.watch(builtinSourcesProvider);
  if (builtin.isEmpty) return null;

  final api = ref.watch(kalinkaProxyProvider);
  final roots = await browseAllRoots(api);
  for (final module in roots) {
    if (!module.canBrowse) continue;
    final sourceName = sourceOfId(module.id);
    if (sourceName == null || !builtin.contains(sourceName)) continue;

    final shelves = await api.browse(module.id, limit: 20);
    for (final shelf in shelves.items) {
      final catalog = shelf.catalog;
      if (catalog == null || !shelf.canBrowse) continue;
      if (catalog.previewConfig?.contentType != PreviewContentType.playlist) {
        continue;
      }

      final page = await api.browse(
        shelf.id,
        limit: catalog.previewConfig?.itemsCount ?? _kDefaultPreviewCount,
      );
      return CollectionsShelf(
        plan: CatalogCardPlan(
          id: shelf.id,
          title: shelf.name ?? catalog.title,
          description: catalog.description,
          sourceName: sourceName,
          contentType: catalog.previewConfig?.contentType,
          icon: catalog.previewConfig?.icon,
          artPath: artPathOf(shelf),
          filters: catalog.filters,
          sections: shelf.sections ?? const [],
          canEdit: shelf.canEdit,
        ),
        items: page.items,
        total: page.total,
      );
    }
  }
  return null;
});

/// How many collections a picker offers at once. Well past what one person
/// makes, and a longer list is narrowed by typing rather than paged.
const _kChoicesLimit = 200;

/// Every collection something can be added to, most recently changed first.
/// Empty on a server that has no collections source at all.
///
/// Follows the shelf, so it is refetched by the same write that refetches
/// everything else showing collections.
final collectionChoicesProvider = FutureProvider<List<BrowseItem>>((ref) async {
  final shelf = await ref.watch(collectionsShelfProvider.future);
  if (shelf == null) return const [];
  final page = await ref
      .read(kalinkaProxyProvider)
      .browse(shelf.plan.id, limit: _kChoicesLimit);
  return page.items;
});
