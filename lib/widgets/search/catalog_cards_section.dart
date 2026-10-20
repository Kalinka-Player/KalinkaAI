import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/catalog_sources_provider.dart';
import '../../providers/connection_state_provider.dart';
import '../../providers/search_session_provider.dart';
import '../../providers/server_info_provider.dart';
import '../../providers/shell_nav_provider.dart';
import '../../providers/source_modules_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/schema_icons.dart';
import '../home/catalog_tile.dart';
import '../home/home_layout.dart';
import '../shelf_heading.dart';
import '../tap_highlight.dart';

/// Compact source tiles. Catalog selection belongs to the listener, so Home
/// never fetches or promotes arbitrary children of these roots.
class CatalogCardsSection extends ConsumerWidget {
  /// A host can dismiss its onboarding panel after a source opens.
  final VoidCallback? onSourceOpened;

  const CatalogCardsSection({super.key, this.onSourceOpened});

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
              ref,
              CatalogTileGrid(
                fill: true,
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
              ref,
              CatalogTileGrid(
                fill: true,
                children: [
                  for (final source in sources)
                    CatalogTile(
                      key: ValueKey('catalog-source-${source.module.name}'),
                      title: source.module.title,
                      icon:
                          iconNamed(source.module.icon) ??
                          Icons.library_music_outlined,
                      onTap: () {
                        ref
                            .read(searchSessionProvider.notifier)
                            .openPage(
                              CatalogPage.fromItem(
                                source.root,
                                provider: source.module.title,
                              ),
                            );
                        onSourceOpened?.call();
                      },
                    ),
                ],
              ),
            );
          },
        );
  }

  Widget _section(WidgetRef ref, Widget grid) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const Expanded(child: ShelfHeading(title: 'MUSIC SOURCES')),
          if (ref.watch(pluginCatalogEnabledProvider)) ...[
            const SizedBox(width: 8),
            IconButton(
              key: const ValueKey('music-sources-settings-button'),
              tooltip: 'Configure music sources',
              style: kalinkaIconButtonStyle,
              color: KalinkaColors.textSecondary,
              icon: const Icon(Icons.settings_outlined, size: 20),
              onPressed: () =>
                  ref.read(musicSourcesSettingsRequestProvider.notifier).open(),
            ),
          ],
        ],
      ),
      const SizedBox(height: kHomeHeadingGap),
      grid,
      const SizedBox(height: kHomeSectionGap),
    ],
  );
}
