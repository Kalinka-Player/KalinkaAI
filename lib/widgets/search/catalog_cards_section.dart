import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/catalog_sources_provider.dart';
import '../../providers/connection_state_provider.dart';
import '../../providers/search_session_provider.dart';
import '../../providers/source_modules_provider.dart';
import '../../utils/schema_icons.dart';
import '../home/catalog_tile.dart';
import '../home/home_layout.dart';
import '../shelf_heading.dart';

/// Compact source tiles. Catalog selection belongs to the listener, so Home
/// never fetches or promotes arbitrary children of these roots.
class CatalogCardsSection extends ConsumerWidget {
  const CatalogCardsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(connectionStateProvider, (prev, next) {
      if (next == ConnectionStatus.connected && prev != next) {
        ref.invalidate(catalogSourcesProvider);
      }
    });
    return ref
        .watch(catalogSourcesProvider)
        .when(
          skipLoadingOnReload: false,
          loading: () {
            final modules = ref.watch(sourceModulesProvider).value;
            final count = modules
                ?.where(
                  (module) =>
                      module.enabled &&
                      !module.builtin &&
                      module.can(ModuleCapability.catalogs),
                )
                .length;
            if (count == 0) return const SizedBox.shrink();
            return _section(
              CatalogTileGrid(
                children: List.generate(
                  count ?? 3,
                  (_) => const CatalogTileShimmer(),
                ),
              ),
            );
          },
          error: (_, _) => TextButton.icon(
            onPressed: () => ref.invalidate(catalogSourcesProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Could not load sources. Retry'),
          ),
          data: (sources) {
            if (sources.isEmpty) {
              return const SizedBox.shrink();
            }
            return _section(
              CatalogTileGrid(
                children: [
                  for (final source in sources)
                    CatalogTile(
                      key: ValueKey('catalog-source-${source.module.name}'),
                      title: source.module.title,
                      icon:
                          iconNamed(source.module.icon) ??
                          Icons.library_music_outlined,
                      onTap: () => ref
                          .read(searchSessionProvider.notifier)
                          .openPage(
                            CatalogPage.fromItem(
                              source.root,
                              provider: source.module.title,
                            ),
                          ),
                    ),
                ],
              ),
            );
          },
        );
  }

  Widget _section(Widget grid) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const ShelfHeading(title: 'BROWSE SOURCES'),
      const SizedBox(height: kHomeHeadingGap),
      grid,
      const SizedBox(height: kHomeSectionGap),
    ],
  );
}
