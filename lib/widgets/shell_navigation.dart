import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/catalog_sources_provider.dart';
import '../providers/connection_state_provider.dart';
import '../providers/search_session_provider.dart';
import '../providers/server_info_provider.dart';
import '../providers/source_modules_provider.dart';
import '../theme/app_theme.dart';
import '../utils/schema_icons.dart';

enum ShellDestination { home, results, source, configuration }

/// Persistent shortcuts beside browsing on larger screens.
class ShellNavigation extends ConsumerWidget {
  final bool configurationOpen;
  final bool enabled;
  final void Function(ShellDestination destination, CatalogSource? source)
  onNavigate;

  const ShellNavigation({
    super.key,
    this.configurationOpen = false,
    this.enabled = true,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected =
        ref.watch(connectionStateProvider) == ConnectionStatus.connected;
    final session = ref.watch(searchSessionProvider);
    final searching = session.activeView == FindMusicView.results;
    final selectedSource = !configurationOpen && !searching && !session.atHome
        ? sourceOfId(session.shownListing.id ?? '')
        : null;
    final sources = ref.watch(catalogSourcesProvider);

    Widget destination(
      String id,
      String label,
      IconData icon,
      ShellDestination destination, {
      bool selected = false,
      bool available = true,
      String? compactLabel,
      String? tooltip,
      CatalogSource? source,
    }) => _NavigationButton(
      key: ValueKey('navigation-$id'),
      label: label,
      compactLabel: compactLabel,
      tooltip: tooltip,
      icon: icon,
      selected: selected,
      onPressed: enabled && available
          ? () => onNavigate(destination, source)
          : null,
    );

    return FocusTraversalGroup(
      child: Material(
        color: KalinkaColors.surfaceBase,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(6),
                  children: [
                    destination(
                      'home',
                      'Home',
                      Icons.home_outlined,
                      ShellDestination.home,
                      selected:
                          !configurationOpen && !searching && session.atHome,
                    ),
                    destination(
                      'results',
                      'Search results',
                      Icons.manage_search,
                      ShellDestination.results,
                      compactLabel: 'Results',
                      tooltip: session.resultsAvailable
                          ? 'Search results: ${session.searchQuery}'
                          : 'Search results appear after your first search',
                      selected: !configurationOpen && searching,
                      available: session.resultsAvailable,
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      child: Divider(
                        height: 1,
                        color: KalinkaColors.borderSubtle,
                      ),
                    ),
                    for (final source in sources.value ?? <CatalogSource>[])
                      destination(
                        'source-${source.module.name}',
                        source.module.title,
                        iconNamed(source.module.icon) ??
                            Icons.library_music_outlined,
                        ShellDestination.source,
                        selected: selectedSource == source.module.name,
                        available: connected && source.root.canBrowse,
                        source: source,
                      ),
                    if (sources.hasError && connected)
                      _NavigationButton(
                        label: 'Retry sources',
                        icon: Icons.refresh,
                        selected: false,
                        onPressed: enabled
                            ? () => ref.invalidate(catalogSourcesProvider)
                            : null,
                      ),
                  ],
                ),
              ),
              if (ref.watch(pluginCatalogEnabledProvider))
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: destination(
                    'configuration',
                    'Configuration',
                    Icons.settings_outlined,
                    ShellDestination.configuration,
                    compactLabel: 'Config',
                    selected: configurationOpen,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigationButton extends StatelessWidget {
  final String label;
  final String? compactLabel;
  final String? tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback? onPressed;

  const _NavigationButton({
    super.key,
    required this.label,
    this.compactLabel,
    this.tooltip,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final glyph = ExcludeSemantics(child: Icon(icon, size: 24));
    final text = ExcludeSemantics(
      child: Text(
        compactLabel ?? label,
        textAlign: TextAlign.center,
        style: KalinkaFonts.sans(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Tooltip(
        message: tooltip ?? label,
        excludeFromSemantics: true,
        child: MergeSemantics(
          child: Semantics(
            label: label,
            selected: selected,
            child: TextButton(
              onPressed: onPressed,
              style: ButtonStyle(
                minimumSize: const WidgetStatePropertyAll(Size(48, 64)),
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                ),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                foregroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.disabled)
                      ? KalinkaColors.textMuted
                      : selected
                      ? KalinkaColors.accentTint
                      : KalinkaColors.textSecondary,
                ),
                backgroundColor: WidgetStatePropertyAll(
                  selected ? KalinkaColors.accentSubtle : Colors.transparent,
                ),
                side: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.focused)
                      ? const BorderSide(
                          color: KalinkaColors.textPrimary,
                          width: 2,
                        )
                      : BorderSide(
                          color: selected
                              ? KalinkaColors.accentBorder
                              : Colors.transparent,
                        ),
                ),
                overlayColor: const WidgetStatePropertyAll(
                  KalinkaColors.surfaceOverlay,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [glyph, const SizedBox(height: 4), text],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
