import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/catalog_sources_provider.dart';
import '../../providers/connection_state_provider.dart';
import '../../providers/server_info_provider.dart';
import '../../providers/shell_nav_provider.dart';
import '../../theme/app_theme.dart';
import '../tap_highlight.dart' show kalinkaIconButtonStyle;

/// Home's music sources as a centred line of names, ending with the gear that
/// configures them. A name opens its source.
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
            return Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final source in sources)
                  _SourceName(
                    key: ValueKey('home-source-${source.module.name}'),
                    title: source.module.title,
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

/// A source's name, lit under the pointer or focus.
class _SourceName extends StatelessWidget {
  final String title;
  final VoidCallback onTap;

  const _SourceName({super.key, required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    bool lit(Set<WidgetState> states) =>
        states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.focused) ||
        states.contains(WidgetState.pressed);
    return TextButton(
      onPressed: onTap,
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 18),
        ),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        textStyle: WidgetStatePropertyAll(
          KalinkaFonts.sans(fontSize: 14, fontWeight: FontWeight.w500),
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
      child: Text(title),
    );
  }
}
