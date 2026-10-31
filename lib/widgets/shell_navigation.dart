import 'dart:math' as math;

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
import 'measure_size.dart';

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

  /// Called as More unfolds its shelf, over what is beside the rail.
  final VoidCallback? onMore;

  const ShellNavigation({
    super.key,
    this.configurationOpen = false,
    this.changeServerOpen = false,
    this.enabled = true,
    this.extended = false,
    required this.onNavigate,
    required this.onAction,
    this.onMore,
  });

  @override
  ConsumerState<ShellNavigation> createState() => _ShellNavigationState();
}

/// One of the rail's items: as it stands in the rail, with what sets it off
/// from its neighbours, and as it is on More's shelf, folding the shelf first.
typedef _Item = ({
  String id,
  bool selected,
  Widget standing,
  Widget Function(VoidCallback close) folded,
});

class _ShellNavigationState extends ConsumerState<ShellNavigation> {
  // What each of the rail's items takes, by id, to tell how many fit.
  final _heights = <String, double>{};

  void _measured(String id, double height) =>
      setState(() => _heights[id] = height);

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

    _Item item(
      String id,
      Widget Function({bool extended, VoidCallback? then}) build, {
      bool selected = false,
      Widget? above,
      Widget? below,
    }) {
      final button = build(extended: extended);
      return (
        id: id,
        selected: selected,
        standing: above == null && below == null
            ? button
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [?above, button, ?below],
              ),
        folded: (close) => build(then: close),
      );
    }

    _Item destination(
      String id,
      String label,
      IconData icon,
      ShellDestination destination, {
      bool selected = false,
      bool available = true,
      String? compactLabel,
      String? tooltip,
      CatalogSource? source,
      Widget? above,
      Widget? below,
    }) => item(
      id,
      selected: selected,
      above: above,
      below: below,
      ({extended = false, then}) => _NavigationButton(
        key: ValueKey('navigation-$id'),
        label: label,
        compactLabel: compactLabel,
        tooltip: tooltip,
        icon: icon,
        // A source's icon in its own colour, as its badges are.
        iconColor: source == null
            ? null
            : colorForSourceName(source.module.name),
        selected: selected,
        extended: extended,
        onPressed: enabled && available
            ? () {
                then?.call();
                widget.onNavigate(destination, source);
              }
            : null,
      ),
    );

    _Item control(_Control control) => item(
      control.action.name,
      selected: control.selected,
      ({extended = false, then}) => _NavigationButton(
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
      ),
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
    final home = destination(
      'home',
      'Home',
      Icons.home_outlined,
      ShellDestination.home,
      selected: shown == BrowseDestination.home,
    );
    // Under Home, from the top.
    final top = <_Item>[
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
        below: divider,
      ),
      for (final source in sources.value ?? <CatalogSource>[])
        destination(
          'source-${source.module.name}',
          source.module.title,
          iconNamed(source.module.icon) ?? Icons.library_music_outlined,
          ShellDestination.source,
          selected: shown == BrowseDestination.source(source.module.name),
          available: connected && source.root.canBrowse,
          source: source,
        ),
      if (sources.hasError && connected)
        item(
          'retry-sources',
          ({extended = false, then}) => _NavigationButton(
            key: const ValueKey('navigation-retry-sources'),
            label: 'Retry sources',
            icon: Icons.refresh,
            selected: false,
            extended: extended,
            onPressed: enabled
                ? () {
                    then?.call();
                    ref.invalidate(catalogSourcesProvider);
                  }
                : null,
          ),
        ),
      // Apart from the sources: it holds tracks from any of them.
      if (collections != null)
        destination(
          'collections',
          'Collections',
          Icons.queue_music_rounded,
          ShellDestination.collections,
          selected: shown == BrowseDestination.collections,
          available: connected,
          above: const SizedBox(height: 8),
        ),
    ];
    // At the rail's foot.
    final foot = <_Item>[
      if (configuration)
        destination(
          'configuration',
          'Configuration',
          Icons.settings_outlined,
          ShellDestination.configuration,
          compactLabel: 'Config',
          selected: widget.configurationOpen && !widget.changeServerOpen,
          below: controls.isEmpty ? null : divider,
        ),
      for (final c in controls) control(c),
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
    // Each measured on its own, out of sight, whether it stands or not; by
    // id, as a measure reports only a change, and sources arrive in between.
    final measures = Offstage(
      child: ExcludeFocus(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final i in [home, ...top, ...foot])
              MeasureSize(
                key: ValueKey(i.id),
                onChange: (size) => _measured(i.id, size.height),
                child: i.standing,
              ),
            MeasureSize(
              key: const ValueKey('more'),
              onChange: (size) => _measured('more', size.height),
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
              // As many as fit stand, from the top, and the rest go behind
              // More, so the rail does not scroll: the server's controls go
              // first, then Configuration, then the destinations from the
              // bottom up. Home always stands.
              final all = [...top, ...foot];
              final room =
                  constraints.maxHeight -
                  4 * _railInset -
                  (_heights[home.id] ?? 0);
              final moreHeight = _heights['more'] ?? 0;
              double heightOf(Iterable<_Item> some) =>
                  some.fold(0.0, (sum, i) => sum + (_heights[i.id] ?? 0));
              var standing = all.length;
              if (heightOf(all) > room) {
                standing = all.length - 1;
                while (standing > 0 &&
                    heightOf(all.take(standing)) + moreHeight > room) {
                  standing--;
                }
              }
              final folded = all.skip(standing).toList();
              // Only a window too short for Home and More alone scrolls.
              final scrolls =
                  heightOf(all.take(standing)) +
                      (folded.isEmpty ? 0 : moreHeight) >
                  room;
              return CustomScrollView(
                physics: scrolls ? null : const NeverScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(vertical: _railInset),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          home.standing,
                          for (final i in all.take(standing).take(top.length))
                            i.standing,
                        ],
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
                          for (final i in all.take(standing).skip(top.length))
                            i.standing,
                          if (folded.isNotEmpty)
                            _OverflowShelf(
                              enabled: enabled,
                              selected: folded.any((i) => i.selected),
                              onOpen: widget.onMore,
                              button: more,
                              items: (close) => [
                                for (final i in folded) i.folded(close),
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

/// The rail's items that do not fit it, behind More; they unfold side by side
/// on a shelf to the rail's right.
class _OverflowShelf extends StatefulWidget {
  final bool enabled;

  /// One of the items is the destination shown.
  final bool selected;

  /// Called as the shelf unfolds.
  final VoidCallback? onOpen;

  /// The More item, highlighted while [open].
  final Widget Function({bool open, VoidCallback? onPressed}) button;

  /// The items, each closing the shelf through the callback first.
  final List<Widget> Function(VoidCallback close) items;

  const _OverflowShelf({
    required this.enabled,
    required this.selected,
    this.onOpen,
    required this.button,
    required this.items,
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
    widget.onOpen?.call();
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
      // the items' tooltips, which are overlay children themselves,
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

  Widget _shelf(BuildContext context, OverlayChildLayoutInfo info) {
    // More is out of view.
    if (info.childPaintTransform.determinant() == 0) {
      return const SizedBox.shrink();
    }
    final more = MatrixUtils.transformRect(
      info.childPaintTransform,
      Offset.zero & info.childSize,
    );
    return Positioned.fill(
      child: CustomSingleChildLayout(
        delegate: _ShelfLayout(more),
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
                  child: Wrap(
                    children: [
                      for (final item in widget.items(_close))
                        SizedBox(width: kKalinkaRailWidth - 1, child: item),
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

/// Level with More, from just past the rail's edge, and kept in the window:
/// where it is too narrow for the shelf, the items run on in more rows.
class _ShelfLayout extends SingleChildLayoutDelegate {
  final Rect more;

  const _ShelfLayout(this.more);

  /// From the rail's edge, and from the window's.
  static const _gap = 8.0;

  // Unbounded in height: the unfolding is an Align, which would fill it.
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.max(0, constraints.maxWidth - more.right - 2 * _gap),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    more.right + _gap,
    (more.center.dy - childSize.height / 2).clamp(
      _gap,
      math.max(_gap, size.height - childSize.height - _gap),
    ),
  );

  @override
  bool shouldRelayout(_ShelfLayout oldDelegate) => oldDelegate.more != more;
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
