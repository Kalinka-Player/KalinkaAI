import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data_model/data_model.dart';
import 'browse_root.dart';
import 'kalinka_player_api_provider.dart';

/// One shelf plan on the Discover surface — everything needed to render a
/// single row (title, image grid target, role-driven styling) without
/// actually fetching the row items. Items are fetched lazily per shelf
/// via [discoverShelfItemsProvider].
class DiscoverShelf {
  final String id;
  final String title;
  final CatalogRole role;
  final PreviewContentType? contentType;
  final CardSize? cardSize;
  final String moduleTitle;

  const DiscoverShelf({
    required this.id,
    required this.title,
    required this.role,
    required this.moduleTitle,
    this.contentType,
    this.cardSize,
  });
}

// How many index-node grandchildren we surface as shelves.
const int _kMaxIndexChildren = 2;

/// Plans the Discover shelves: walks root → module → catalog, honours
/// [CatalogRole] hints (skips [CatalogRole.hideOnHome], auto-descends one
/// level through [CatalogRole.indexNode]), and returns an ordered list
/// grouped by role (library → featured → discovery).
final discoverShelfPlansProvider =
    FutureProvider<List<DiscoverShelf>>((ref) async {
  final api = ref.watch(kalinkaProxyProvider);

  final roots = await browseAllRoots(api);

  final shelves = <DiscoverShelf>[];
  for (final module in roots) {
    if (!module.canBrowse) continue;
    final moduleTitle = module.name ?? module.catalog?.title ?? '';
    final children = await api.browse(module.id, limit: 20);

    for (final item in children.items) {
      final catalog = item.catalog;
      if (catalog == null) continue;
      final role = catalog.role;

      if (role == CatalogRole.hideOnHome) continue;

      if (role == CatalogRole.indexNode) {
        final grand = await api.browse(item.id, limit: _kMaxIndexChildren);
        for (final sub in grand.items.take(_kMaxIndexChildren)) {
          final subCatalog = sub.catalog;
          if (subCatalog == null) continue;
          if (subCatalog.role == CatalogRole.hideOnHome) continue;
          shelves.add(DiscoverShelf(
            id: sub.id,
            title: sub.name ?? subCatalog.title,
            // Grandchildren inherit the parent's index role as discovery by
            // default; UI treats them as plain shelves.
            role: subCatalog.role ?? CatalogRole.discovery,
            contentType: subCatalog.previewConfig?.contentType,
            cardSize: subCatalog.previewConfig?.cardSize,
            moduleTitle: moduleTitle,
          ));
        }
        continue;
      }

      shelves.add(DiscoverShelf(
        id: item.id,
        title: item.name ?? catalog.title,
        role: role ?? CatalogRole.discovery,
        contentType: catalog.previewConfig?.contentType,
        cardSize: catalog.previewConfig?.cardSize,
        moduleTitle: moduleTitle,
      ));
    }
  }

  // Stable ordering: library first (your stuff), then featured (editorial),
  // then discovery (everything else). Preserves backend insertion order
  // within each bucket.
  int rolePriority(CatalogRole role) {
    switch (role) {
      case CatalogRole.library:
        return 0;
      case CatalogRole.featured:
        return 1;
      case CatalogRole.discovery:
        return 2;
      case CatalogRole.indexNode:
      case CatalogRole.hideOnHome:
        return 3;
    }
  }

  final indexed = shelves
      .asMap()
      .entries
      .map((e) => MapEntry(e.key, e.value))
      .toList();
  indexed.sort((a, b) {
    final pa = rolePriority(a.value.role);
    final pb = rolePriority(b.value.role);
    if (pa != pb) return pa.compareTo(pb);
    return a.key.compareTo(b.key);
  });

  return indexed.map((e) => e.value).toList();
});

/// Lazily loads the row items for a single shelf. Each shelf widget
/// watches its own instance, so the ListView can skip fetches for shelves
/// that never scroll into view.
final discoverShelfItemsProvider =
    FutureProvider.family<BrowseItemsList, String>((ref, id) async {
  final api = ref.read(kalinkaProxyProvider);
  return api.browse(id, limit: 10);
});
