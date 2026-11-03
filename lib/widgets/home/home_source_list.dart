import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart' show ModuleInfo;
import '../../providers/catalog_sources_provider.dart';
import '../../providers/connection_state_provider.dart';
import '../../providers/receiver_provider.dart';
import '../../providers/server_info_provider.dart';
import '../../providers/shell_nav_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/schema_icons.dart';
import '../edge_fading_rail.dart';
import '../module_artwork.dart';
import '../receiver_panel.dart';
import '../search/search_zero_state.dart' show kHomeSideInset;
import '../tap_highlight.dart' show kalinkaIconButtonStyle;
import 'source_button_style.dart';

/// Home's music sources as icons and names, ending with the gear that
/// configures them: centred while it fits, else scrolled and faded at its
/// edges as the search prompts are. A name opens its source — for a new
/// listener, the way into the music.
class HomeSourceList extends ConsumerWidget {
  final ValueChanged<CatalogSource> onOpen;
  final bool showConnect;

  const HomeSourceList({
    super.key,
    required this.onOpen,
    this.showConnect = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(connectionStateProvider, (prev, next) {
      if (next == ConnectionStatus.connected && prev != next) {
        ref.invalidate(catalogSourcesProvider);
      }
    });
    final configurable = ref.watch(pluginCatalogEnabledProvider);
    final receivers = showConnect ? ref.watch(enabledReceiversProvider) : [];
    final sources = ref.watch(catalogSourcesProvider);
    if (sources.isLoading && receivers.isEmpty) {
      return const SizedBox(height: 48);
    }
    if ((sources.value?.isEmpty ?? true) &&
        !configurable &&
        receivers.isEmpty &&
        !sources.hasError) {
      return const SizedBox.shrink();
    }
    return EdgeFadingRail(
      storageId: 'home-sources',
      gutter: kHomeSideInset,
      spacing: 4,
      children: [
        if (receivers.isNotEmpty) const ConnectSourceButton(),
        for (final source in sources.value ?? <CatalogSource>[])
          _SourceName(
            key: ValueKey('home-source-${source.module.name}'),
            module: source.module,
            onTap: () => onOpen(source),
          ),
        if (sources.hasError)
          TextButton.icon(
            onPressed: () => ref.invalidate(catalogSourcesProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Could not load sources. Retry'),
          ),
        if (configurable)
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
    return TextButton.icon(
      onPressed: onTap,
      style: homeSourceButtonStyle,
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
