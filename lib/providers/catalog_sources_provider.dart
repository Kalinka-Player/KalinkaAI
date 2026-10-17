import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart';
import 'browse_root.dart';
import 'catalog_cards_provider.dart';
import 'kalinka_player_api_provider.dart';
import 'source_modules_provider.dart';

typedef CatalogSource = ({ModuleInfo module, BrowseItem root});

/// Only explicit plugin capabilities decide which sources Home offers.
/// Root IDs come from browse; neither names nor manufactured IDs are used.
final catalogSourcesProvider = FutureProvider<List<CatalogSource>>((ref) async {
  ref.watch(catalogCardsReloadProvider);
  final api = ref.watch(kalinkaProxyProvider);
  final modules = await ref.watch(sourceModulesProvider.future);
  final eligible = {
    for (final module in modules)
      if (module.enabled &&
          !module.builtin &&
          module.can(ModuleCapability.catalogs))
        module.name: module,
  };
  if (eligible.isEmpty) return [];
  final sources = <CatalogSource>[];
  final seen = <String>{};
  final roots = await browseAllRoots(api);
  for (final item in roots) {
    final source = sourceOfId(item.id);
    final module = eligible[source];
    if (module != null && item.canBrowse && seen.add(module.name)) {
      sources.add((module: module, root: item));
    }
  }
  sources.sort(
    (a, b) =>
        a.module.title.toLowerCase().compareTo(b.module.title.toLowerCase()),
  );
  return sources;
});
