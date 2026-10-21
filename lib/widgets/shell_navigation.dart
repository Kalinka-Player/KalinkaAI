import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/box_control_provider.dart';
import '../providers/catalog_sources_provider.dart';
import '../providers/collections_provider.dart';
import '../providers/connection_state_provider.dart';
import '../providers/search_session_provider.dart';
import '../providers/server_info_provider.dart';
import '../providers/source_modules_provider.dart' show colorForSourceName;
import '../providers/supervisor_api.dart';
import '../theme/app_theme.dart';
import '../utils/schema_icons.dart';

enum ShellDestination { home, results, source, collections, configuration }

/// Above and below the destinations, which span the rail edge to edge.
const _railInset = 6.0;

/// The server's own controls, pinned under Configuration.
enum ShellAction { restart, changeServer, powerOff }

/// Persistent shortcuts beside browsing on larger screens.
class ShellNavigation extends ConsumerWidget {
  final bool configurationOpen;

  /// The server picker shows: Change server is then the destination shown,
  /// over whatever it covers.
  final bool changeServerOpen;
  final bool enabled;

  /// Icons beside full names, rather than over short labels.
  final bool extended;
  final void Function(ShellDestination destination, CatalogSource? source)
  onNavigate;
  final void Function(ShellAction action) onAction;

  const ShellNavigation({
    super.key,
    this.configurationOpen = false,
    this.changeServerOpen = false,
    this.enabled = true,
    this.extended = false,
    required this.onNavigate,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected =
        ref.watch(connectionStateProvider) == ConnectionStatus.connected;
    final session = ref.watch(searchSessionProvider);
    // The destination shown, whatever page in it is: an album opened from
    // Results is still Results.
    final shown = configurationOpen || changeServerOpen
        ? null
        : session.destination;
    final sources = ref.watch(catalogSourcesProvider);
    // Only where the server keeps collections.
    final collections = ref.watch(collectionsShelfProvider).value?.plan;
    final box = ref.watch(boxControlProvider).value;

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
      // A source's icon in its own colour, as its badges are.
      iconColor: source == null ? null : colorForSourceName(source.module.name),
      selected: selected,
      extended: extended,
      onPressed: enabled && available
          ? () => onNavigate(destination, source)
          : null,
    );

    Widget action(
      ShellAction action,
      String label,
      IconData icon,
      String tooltip, {
      bool selected = false,
    }) => _NavigationButton(
      key: ValueKey('navigation-${action.name}'),
      label: label,
      tooltip: tooltip,
      icon: icon,
      selected: selected,
      extended: extended,
      onPressed: enabled ? () => onAction(action) : null,
    );

    const divider = Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Divider(height: 1, color: KalinkaColors.borderSubtle),
    );
    final configuration = ref.watch(pluginCatalogEnabledProvider);
    final actions = [
      if (box?.offers(BoxAction.reboot) ?? false)
        action(
          ShellAction.restart,
          'Restart',
          Icons.autorenew,
          'Restart the streamer',
        ),
      // Web is bound to the server that serves it.
      if (!kIsWeb)
        action(
          ShellAction.changeServer,
          'Change server',
          Icons.language,
          'Connect to a different server',
          selected: changeServerOpen,
        ),
      if (box?.offers(BoxAction.powerOff) ?? false)
        action(
          ShellAction.powerOff,
          'Power off',
          Icons.power_settings_new,
          'Power off the streamer',
        ),
    ];

    return FocusTraversalGroup(
      child: Material(
        color: KalinkaColors.surfaceBase,
        child: SafeArea(
          // One scroll on a short window; otherwise the server's controls
          // keep to the foot.
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.symmetric(vertical: _railInset),
                sliver: SliverList.list(
                  children: [
                    destination(
                      'home',
                      'Home',
                      Icons.home_outlined,
                      ShellDestination.home,
                      selected: shown == BrowseDestination.home,
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
                      selected: shown == BrowseDestination.results,
                      available: session.resultsAvailable,
                    ),
                    divider,
                    for (final source in sources.value ?? <CatalogSource>[])
                      destination(
                        'source-${source.module.name}',
                        source.module.title,
                        iconNamed(source.module.icon) ??
                            Icons.library_music_outlined,
                        ShellDestination.source,
                        selected:
                            shown ==
                            BrowseDestination.source(source.module.name),
                        available: connected && source.root.canBrowse,
                        source: source,
                      ),
                    if (sources.hasError && connected)
                      _NavigationButton(
                        label: 'Retry sources',
                        icon: Icons.refresh,
                        selected: false,
                        extended: extended,
                        onPressed: enabled
                            ? () => ref.invalidate(catalogSourcesProvider)
                            : null,
                      ),
                    // Apart from the sources: it holds tracks from any of
                    // them.
                    if (collections != null) ...[
                      const SizedBox(height: 16),
                      destination(
                        'collections',
                        'Collections',
                        Icons.queue_music_rounded,
                        ShellDestination.collections,
                        selected: shown == BrowseDestination.collections,
                        available: connected,
                      ),
                    ],
                  ],
                ),
              ),
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: _railInset),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (configuration)
                        destination(
                          'configuration',
                          'Configuration',
                          Icons.settings_outlined,
                          ShellDestination.configuration,
                          compactLabel: 'Config',
                          selected: configurationOpen && !changeServerOpen,
                        ),
                      if (configuration && actions.isNotEmpty) divider,
                      ...actions,
                    ],
                  ),
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

  /// The icon's own colour while it can be followed; null takes the label's.
  final Color? iconColor;
  final bool selected;
  final bool extended;
  final VoidCallback? onPressed;

  const _NavigationButton({
    super.key,
    required this.label,
    this.compactLabel,
    this.tooltip,
    required this.icon,
    this.iconColor,
    required this.selected,
    required this.extended,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final glyph = ExcludeSemantics(
      child: Icon(icon, size: 24, color: onPressed == null ? null : iconColor),
    );
    final text = ExcludeSemantics(
      child: Text(
        extended ? label : compactLabel ?? label,
        textAlign: extended ? TextAlign.start : TextAlign.center,
        style: KalinkaFonts.sans(
          fontSize: extended ? 16 : 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
    // The full name is on show beside the icon, so only an addition to it
    // makes a tooltip.
    final message = extended ? tooltip : tooltip ?? label;
    final button = MergeSemantics(
      child: Semantics(
        label: label,
        selected: selected,
        child: TextButton(
          onPressed: onPressed,
          style: ButtonStyle(
            minimumSize: WidgetStatePropertyAll(
              extended ? const Size(48, 48) : const Size(48, 64),
            ),
            padding: WidgetStatePropertyAll(
              extended
                  ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
                  : const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            alignment: extended ? AlignmentDirectional.centerStart : null,
            // A plain block from edge to edge, as the rule beside it.
            shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? KalinkaColors.textMuted
                  : selected
                  ? KalinkaColors.textPrimary
                  : KalinkaColors.textSecondary,
            ),
            side: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.focused)
                  ? const BorderSide(color: KalinkaColors.textPrimary, width: 2)
                  : BorderSide.none,
            ),
            // As the player's PLAYING / QUEUE tabs respond.
            overlayColor: WidgetStateProperty.resolveWith(
              (states) =>
                  states.contains(WidgetState.focused) ||
                      states.contains(WidgetState.pressed)
                  ? KalinkaColors.surfaceOverlay
                  : states.contains(WidgetState.hovered)
                  ? KalinkaColors.surfaceInput
                  : null,
            ),
            // The destination shown is no action.
            mouseCursor: WidgetStateProperty.resolveWith(
              (states) => selected || states.contains(WidgetState.disabled)
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.click,
            ),
          ),
          child: extended
              ? Row(
                  children: [
                    glyph,
                    const SizedBox(width: 12),
                    Expanded(child: text),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [glyph, const SizedBox(height: 4), text],
                ),
        ),
      ),
    );
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      // Marked as the player's PLAYING / QUEUE tabs are: a berry rule as
      // long as what it marks, here upright on the rail's edge beside the
      // pane it shows, the item's full height, and no fill.
      child: Stack(
        // The button keeps the rail's full width.
        fit: StackFit.passthrough,
        children: [
          message == null
              ? button
              : Tooltip(
                  message: message,
                  excludeFromSemantics: true,
                  child: button,
                ),
          PositionedDirectional(
            top: 0,
            bottom: 0,
            end: 0,
            width: 2,
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOutCubic,
              color: selected ? KalinkaColors.accent : Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }
}
