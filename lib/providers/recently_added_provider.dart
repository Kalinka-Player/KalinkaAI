import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart';
import 'catalog_cards_provider.dart';
import 'indexer_status_provider.dart';
import 'kalinka_player_api_provider.dart';

/// Home's Recently added shelf: its first items, and the catalog VIEW ALL
/// opens.
class RecentlyAddedShelf {
  final CatalogCardPlan plan;

  /// The source's name, as the page's subtitle.
  final String provider;
  final List<BrowseItem> items;

  const RecentlyAddedShelf({
    required this.plan,
    required this.provider,
    required this.items,
  });
}

/// When the catalog does not say how many to preview.
const _kDefaultCount = 10;

/// The catalog behind the shelf, found by what it says it is rather than by
/// which plugin offers it: a library catalog marked `recent`.
({CatalogCardPlan plan, String provider})? recentCatalogIn(
  List<CatalogCardGroup> groups,
) {
  for (final group in groups) {
    for (final plan in group.cards) {
      if (plan.role == CatalogRole.library && plan.icon == 'recent') {
        return (plan: plan, provider: group.sourceTitle);
      }
    }
  }
  return null;
}

/// Only the metadata that affects the shelf, so generated catalog artwork
/// can refresh without refetching its items. Keep the plan with the key to
/// avoid reading a different server's plan after awaiting the selection.
class _RecentCatalog {
  final CatalogCardPlan plan;
  final String provider;
  final List<(String, Preview?)> sections;

  _RecentCatalog(this.plan, this.provider)
    : sections = [
        for (final section in plan.sections)
          if (section.canBrowse && section.catalog != null)
            (section.id, section.catalog!.previewConfig),
      ];

  @override
  bool operator ==(Object other) =>
      other is _RecentCatalog &&
      plan.id == other.plan.id &&
      plan.title == other.plan.title &&
      plan.sourceName == other.plan.sourceName &&
      plan.preview == other.plan.preview &&
      provider == other.provider &&
      listEquals(sections, other.sections);

  @override
  int get hashCode => Object.hash(
    plan.id,
    plan.title,
    plan.sourceName,
    plan.preview,
    provider,
    Object.hashAll(sections),
  );
}

/// As many newest items as the preview asks for, with the entity kinds
/// interleaved when the catalog offers separate shelves. Null when no source
/// has one or it is empty.
final recentlyAddedProvider = FutureProvider<RecentlyAddedShelf?>((ref) async {
  // Watch and capture the client before awaiting catalogs. Identical catalog
  // metadata on two servers must still fetch separate items and artwork.
  final api = ref.watch(kalinkaProxyProvider);
  ref.watch(catalogCardsReloadProvider);
  // A finished index may have added to it.
  ref.watch(indexerStatusProvider.select((s) => s.libraryRevision));
  // Keyed on what the shelf uses, so the cards' art polls don't refetch it.
  final recent = await ref.watch(
    catalogCardGroupsProvider.selectAsync((groups) {
      final r = recentCatalogIn(groups);
      return r == null ? null : _RecentCatalog(r.plan, r.provider);
    }),
  );
  if (!ref.mounted || recent == null) return null;
  final items = await _previewItems(api, recent.plan);
  if (items.isEmpty) return null;
  return RecentlyAddedShelf(
    plan: recent.plan,
    provider: recent.provider,
    items: items,
  );
});

Future<List<BrowseItem>> _previewItems(
  KalinkaPlayerProxy api,
  CatalogCardPlan plan,
) async {
  final limit = plan.preview?.itemsCount ?? _kDefaultCount;
  var sections = plan.sections
      .where((item) => item.canBrowse && item.catalog != null)
      .toList();
  if (sections.isEmpty) {
    final list = await api.browse(plan.id, limit: limit);
    // Older servers return the items directly. Other servers advertise the
    // sub-catalogs here instead of in the parent catalog's sections metadata.
    if (list.items.isEmpty ||
        list.items.any((item) => !item.canBrowse || item.catalog == null)) {
      return list.items;
    }
    sections = list.items;
  }

  final lists = await Future.wait([
    for (final section in sections)
      api.browse(
        section.id,
        limit: (section.catalog!.previewConfig?.itemsCount ?? limit).clamp(
          0,
          limit,
        ),
      ),
  ]);
  final items = <BrowseItem>[];
  for (var index = 0; items.length < limit; index++) {
    var added = false;
    for (final list in lists) {
      if (index >= list.items.length) continue;
      items.add(list.items[index]);
      added = true;
      if (items.length == limit) break;
    }
    if (!added) break;
  }
  return items;
}
