import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart' show ModuleInfo;
import '../../providers/catalog_sources_provider.dart';
import '../../providers/connection_state_provider.dart';
import '../../providers/server_info_provider.dart';
import '../../providers/shell_nav_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/schema_icons.dart';
import '../edge_fading_rail.dart';
import '../module_artwork.dart';
import '../search/search_zero_state.dart' show kHomeSideInset;
import '../tap_highlight.dart' show kalinkaIconButtonStyle;

/// Home's music sources as icons and names, ending with the gear that
/// configures them: centred while it fits, else scrolled and faded at its
/// edges as the search prompts are. A name opens its source — for a new
/// listener, the way into the music.
class HomeSourceList extends ConsumerWidget {
  final ValueChanged<CatalogSource> onOpen;

  const HomeSourceList({super.key, required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(connectionStateProvider, (prev, next) {
      if (next == ConnectionStatus.connected && prev != next) {
        ref.invalidate(catalogSourcesProvider);
      }
    });
    final configurable = ref.watch(pluginCatalogEnabledProvider);
    return ref
        .watch(catalogSourcesProvider)
        .when(
          skipLoadingOnReload: false,
          // Holds the line's place, so what follows does not jump.
          loading: () => const SizedBox(height: 48),
          error: (_, _) => Center(
            child: TextButton.icon(
              onPressed: () => ref.invalidate(catalogSourcesProvider),
              icon: const Icon(Icons.refresh),
              label: const Text('Could not load sources. Retry'),
            ),
          ),
          data: (sources) {
            if (sources.isEmpty && !configurable) {
              return const SizedBox.shrink();
            }
            return EdgeFadingRail(
              storageId: 'home-sources',
              gutter: kHomeSideInset,
              spacing: 4,
              children: [
                for (final source in sources)
                  _SourceName(
                    key: ValueKey('home-source-${source.module.name}'),
                    module: source.module,
                    onTap: () => onOpen(source),
                  ),
                if (configurable)
                  IconButton(
                    key: const ValueKey('music-sources-settings-button'),
                    tooltip: 'Configure music sources',
                    style: kalinkaIconButtonStyle,
                    color: KalinkaColors.textSecondary,
                    icon: const Icon(Icons.settings_outlined, size: 20),
                    onPressed: () => ref
                        .read(musicSourcesSettingsRequestProvider.notifier)
                        .open(),
                  ),
              ],
            );
          },
        );
  }
}

/// A source's icon and name, lit under the pointer or focus.
class _SourceName extends StatelessWidget {
  final ModuleInfo module;
  final VoidCallback onTap;

  const _SourceName({super.key, required this.module, required this.onTap});

  @override
  Widget build(BuildContext context) {
    bool lit(Set<WidgetState> states) =>
        states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.focused) ||
        states.contains(WidgetState.pressed);
    return TextButton.icon(
      onPressed: onTap,
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 18),
        ),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        textStyle: WidgetStatePropertyAll(
          KalinkaFonts.sans(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => lit(states)
              ? KalinkaColors.textPrimary
              : KalinkaColors.textSecondary,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              lit(states) ? KalinkaColors.surfaceOverlay : Colors.transparent,
        ),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      icon: ModuleArtwork(
        icons: module.icons,
        small: true,
        size: MediaQuery.textScalerOf(context).scale(20),
        fallback: Icon(
          iconNamed(module.icon) ?? Icons.library_music_outlined,
          size: 20,
          applyTextScaling: true,
        ),
      ),
      label: Text(module.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
