import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/box_control_provider.dart';
import '../data_model/module_icons.dart';
import '../providers/catalog_sources_provider.dart';
import '../providers/collections_provider.dart';
import '../providers/connection_state_provider.dart';
import '../providers/search_session_provider.dart';
import '../providers/server_info_provider.dart';
import '../providers/source_modules_provider.dart' show colorForSourceName;
import '../providers/supervisor_api.dart';
import '../theme/app_theme.dart';
import '../utils/schema_icons.dart';
import 'measure_size.dart';
import 'module_artwork.dart';

enum ShellDestination { home, results, source, collections, configuration }

/// Above and below the destinations.
const _railInset = 4.0;

/// How far each item's highlight keeps in from the sides of the wide rail and
/// of the narrow one, and its corners.
const _itemInset = 6.0;
const _compactItemInset = 4.0;
const _itemRadius = 12.0;

/// The server's own controls, pinned under Configuration.
enum ShellAction { restart, changeServer, powerOff }

typedef _Control = ({
  ShellAction action,
  String label,
  IconData icon,
  String tooltip,
  bool selected,
});

/// Persistent shortcuts beside browsing on larger screens.
class ShellNavigation extends ConsumerStatefulWidget {
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
  ConsumerState<ShellNavigation> createState() => _ShellNavigationState();
}

class _ShellNavigationState extends ConsumerState<ShellNavigation> {
  // What the rail's parts take, to tell how many of the server's controls
  // fit under the rest.
  double _listHeight = 0;
  double _footHeight = 0;
  final _controlHeights = <ShellAction, double>{};
  double _moreHeight = 0;

  void _measuredControl(ShellAction action, double height) =>
      setState(() => _controlHeights[action] = height);

  void _measured({double? list, double? foot, double? more}) => setState(() {
    _listHeight = list ?? _listHeight;
    _footHeight = foot ?? _footHeight;
    _moreHeight = more ?? _moreHeight;
  });

  @override
  Widget build(BuildContext context) {
    final extended = widget.extended;
    final enabled = widget.enabled;
    final connected =
        ref.watch(connectionStateProvider) == ConnectionStatus.connected;
    final session = ref.watch(searchSessionProvider);
    // The destination shown, whatever page in it is: an album opened from
    // Results is still Results.
    final shown = widget.configurationOpen || widget.changeServerOpen
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
      icons: source?.module.icons,
      selected: selected,
      extended: extended,
      onPressed: enabled && available
          ? () => widget.onNavigate(destination, source)
          : null,
    );

    Widget control(
      _Control control, {
      bool extended = false,
      VoidCallback? then,
    }) => _NavigationButton(
      key: ValueKey('navigation-${control.action.name}'),
      label: control.label,
      tooltip: control.tooltip,
      icon: control.icon,
      // In berry: the one of them that leaves the box off.
      iconColor: control.action == ShellAction.powerOff
          ? KalinkaColors.accent
          : null,
      selected: control.selected,
      extended: extended,
      onPressed: enabled
          ? () {
              then?.call();
              widget.onAction(control.action);
            }
          : null,
    );

    const divider = Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Divider(height: 1, color: KalinkaColors.borderSubtle),
    );
    final configuration = ref.watch(pluginCatalogEnabledProvider);
    final List<_Control> controls = [
      if (box?.offers(BoxAction.reboot) ?? false)
        (
          action: ShellAction.restart,
          label: 'Restart',
          icon: Icons.autorenew,
          tooltip: 'Restart the streamer',
          selected: false,
        ),
      // Web is bound to the server that serves it.
      if (!kIsWeb)
        (
          action: ShellAction.changeServer,
          label: 'Change server',
          icon: Icons.language,
          tooltip: 'Connect to a different server',
          selected: widget.changeServerOpen,
        ),
      if (box?.offers(BoxAction.powerOff) ?? false)
        (
          action: ShellAction.powerOff,
          label: 'Power off',
          icon: Icons.power_settings_new,
          tooltip: 'Power off the streamer',
          selected: false,
        ),
    ];
    Widget more({bool open = false, VoidCallback? onPressed}) =>
        _NavigationButton(
          key: const ValueKey('navigation-more'),
          label: 'More',
          tooltip: open ? null : 'More controls',
          icon: Icons.more_horiz,
          selected: open,
          extended: extended,
          onPressed: onPressed,
        );
    // Each measured on its own, out of sight, whether it stands or not.
    final measures = Offstage(
      child: ExcludeFocus(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final c in controls)
              MeasureSize(
                onChange: (size) => _measuredControl(c.action, size.height),
                child: control(c, extended: extended),
              ),
            MeasureSize(
              onChange: (size) => _measured(more: size.height),
              child: more(),
            ),
          ],
        ),
      ),
    );

    return FocusTraversalGroup(
      child: Material(
        color: KalinkaColors.surfaceBase,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // As many as fit stand; the rest go behind More.
              final room =
                  constraints.maxHeight -
                  _listHeight -
                  _footHeight -
                  4 * _railInset;
              double heightOf(Iterable<_Control> some) => some.fold(
                0.0,
                (sum, c) => sum + (_controlHeights[c.action] ?? 0),
              );
              var standing = controls.length;
              if (heightOf(controls) > room) {
                standing = controls.length - 1;
                while (standing > 0 &&
                    heightOf(controls.take(standing)) + _moreHeight > room) {
                  standing--;
                }
              }
              final folded = controls.skip(standing).toList();
              // One scroll on a short window; otherwise the server's controls
              // keep to the foot.
              return CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(vertical: _railInset),
                    sliver: SliverToBoxAdapter(
                      child: MeasureSize(
                        onChange: (size) => _measured(list: size.height),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                                  : 'Search results appear after your first '
                                        'search',
                              selected: shown == BrowseDestination.results,
                              available: session.resultsAvailable,
                            ),
                            divider,
                            for (final source
                                in sources.value ?? <CatalogSource>[])
                              destination(
                                'source-${source.module.name}',
                                source.module.title,
                                iconNamed(source.module.icon) ??
                                    Icons.library_music_outlined,
                                ShellDestination.source,
                                selected:
                                    shown ==
                                    BrowseDestination.source(
                                      source.module.name,
                                    ),
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
                                    ? () =>
                                          ref.invalidate(catalogSourcesProvider)
                                    : null,
                              ),
                            // Apart from the sources: it holds tracks from any
                            // of them.
                            if (collections != null) ...[
                              const SizedBox(height: 8),
                              destination(
                                'collections',
                                'Collections',
                                Icons.queue_music_rounded,
                                ShellDestination.collections,
                                selected:
                                    shown == BrowseDestination.collections,
                                available: connected,
                              ),
                            ],
                          ],
                        ),
                      ),
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
                          MeasureSize(
                            onChange: (size) => _measured(foot: size.height),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (configuration)
                                  destination(
                                    'configuration',
                                    'Configuration',
                                    Icons.settings_outlined,
                                    ShellDestination.configuration,
                                    compactLabel: 'Config',
                                    selected:
                                        widget.configurationOpen &&
                                        !widget.changeServerOpen,
                                  ),
                                if (configuration && controls.isNotEmpty)
                                  divider,
                              ],
                            ),
                          ),
                          for (final c in controls.take(standing))
                            control(c, extended: extended),
                          if (folded.isNotEmpty)
                            _OverflowShelf(
                              enabled: enabled,
                              selected: folded.any((c) => c.selected),
                              button: more,
                              controls: (close) => [
                                for (final c in folded) control(c, then: close),
                              ],
                            ),
                          measures,
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The server's controls that do not fit the rail, behind More; they unfold
/// side by side on a shelf to the rail's right.
class _OverflowShelf extends StatefulWidget {
  final bool enabled;

  /// One of the controls is the destination shown.
  final bool selected;

  /// The More item, highlighted while [open].
  final Widget Function({bool open, VoidCallback? onPressed}) button;

  /// The controls, each closing the shelf through the callback first.
  final List<Widget> Function(VoidCallback close) controls;

  const _OverflowShelf({
    required this.enabled,
    required this.selected,
    required this.button,
    required this.controls,
  });

  @override
  State<_OverflowShelf> createState() => _OverflowShelfState();
}

class _OverflowShelfState extends State<_OverflowShelf>
    with SingleTickerProviderStateMixin {
  final _portal = OverlayPortalController();
  late final _unfold = AnimationController(vsync: this);
  late final _curve = CurvedAnimation(
    parent: _unfold,
    curve: Curves.easeOutCubic,
  );
  bool _open = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _unfold.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
  }

  @override
  void didUpdateWidget(_OverflowShelf oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _close();
  }

  @override
  void dispose() {
    _curve.dispose();
    _unfold.dispose();
    super.dispose();
  }

  void _show() {
    setState(() => _open = true);
    _portal.show();
    _unfold.forward();
  }

  void _close() {
    if (!_open) return;
    setState(() => _open = false);
    _unfold.reverse().whenComplete(() {
      if (mounted && !_open) _portal.hide();
    });
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      groupId: this,
      onTapOutside: (_) => _close(),
      // Placed from where More is, not by following it: a follower above
      // the controls' tooltips, which are overlay children themselves,
      // leaves them no position to lay out from.
      child: OverlayPortal.overlayChildLayoutBuilder(
        controller: _portal,
        overlayChildBuilder: _shelf,
        child: Semantics(
          expanded: _open,
          child: widget.button(
            open: widget.selected || _open,
            onPressed: widget.enabled ? (_open ? _close : _show) : null,
          ),
        ),
      ),
    );
  }

  /// Level with More, from just past the rail's edge.
  Widget _shelf(BuildContext context, OverlayChildLayoutInfo info) {
    // More is out of view.
    if (info.childPaintTransform.determinant() == 0) {
      return const SizedBox.shrink();
    }
    final more = MatrixUtils.transformRect(
      info.childPaintTransform,
      Offset.zero & info.childSize,
    );
    return Positioned(
      left: more.right + 8,
      top: more.center.dy,
      child: FractionalTranslation(
        translation: const Offset(0, -0.5),
        child: TapRegion(
          groupId: this,
          child: FadeTransition(
            opacity: _curve,
            child: SizeTransition(
              sizeFactor: _curve,
              axis: Axis.horizontal,
              alignment: Alignment.centerLeft,
              child: Material(
                color: KalinkaColors.surfaceBase,
                elevation: 8,
                shadowColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: KalinkaColors.borderSubtle),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(_railInset),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final control in widget.controls(_close))
                        SizedBox(width: kKalinkaRailWidth - 1, child: control),
                    ],
                  ),
                ),
              ),
            ),
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
  final ModuleIcons? icons;

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
    this.icons,
    this.iconColor,
    required this.selected,
    required this.extended,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final glyph = ExcludeSemantics(
      child: ModuleArtwork(
        icons: icons,
        size: 24,
        fallback: Icon(
          icon,
          size: 24,
          color: onPressed == null ? null : iconColor,
        ),
      ),
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
            minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
            // Desktop's compact density would take 8dp off top and bottom.
            visualDensity: extended ? null : VisualDensity.standard,
            // Only as tall as the icon and its label, so a short window
            // keeps the whole rail in view.
            padding: WidgetStatePropertyAll(
              extended
                  ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
                  : const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            ),
            alignment: extended ? AlignmentDirectional.centerStart : null,
            shape: const WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(_itemRadius)),
              ),
            ),
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
            // As the player's PLAYING / QUEUE tabs respond. The current
            // destination is no action, so it takes no hover.
            overlayColor: WidgetStateProperty.resolveWith(
              (states) =>
                  states.contains(WidgetState.focused) ||
                      states.contains(WidgetState.pressed)
                  ? KalinkaColors.surfaceOverlay
                  : states.contains(WidgetState.hovered) && !selected
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
      // Half the room between two items' highlights either side.
      padding: EdgeInsets.symmetric(
        horizontal: extended ? _itemInset : _compactItemInset,
        vertical: extended ? 2 : 3,
      ),
      // The current destination on grey: the rail is chrome, on screen all
      // session, which berry would leave meaning nothing in particular.
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: KalinkaColors.surfaceOverlay.withValues(
                  alpha: selected ? 1 : 0,
                ),
                borderRadius: BorderRadius.circular(_itemRadius),
              ),
            ),
          ),
          message == null
              ? button
              : Tooltip(
                  message: message,
                  excludeFromSemantics: true,
                  child: button,
                ),
        ],
      ),
    );
  }
}
