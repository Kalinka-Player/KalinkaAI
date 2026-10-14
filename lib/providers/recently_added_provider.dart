import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart';
import 'catalog_cards_provider.dart';
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

/// As many of its newest items as its preview asks for, every kind together:
/// browsing the catalog itself is what its source offers a home shelf. Null
/// when no source has one or it is empty.
final recentlyAddedProvider = FutureProvider<RecentlyAddedShelf?>((ref) async {
  final recent = recentCatalogIn(
    await ref.watch(catalogCardGroupsProvider.future),
  );
  if (recent == null) return null;
  final list = await ref
      .read(kalinkaProxyProvider)
      .browse(
        recent.plan.id,
        limit: recent.plan.preview?.itemsCount ?? _kDefaultCount,
      );
  if (list.items.isEmpty) return null;
  return RecentlyAddedShelf(
    plan: recent.plan,
    provider: recent.provider,
    items: list.items,
  );
});
