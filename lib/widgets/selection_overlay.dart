import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart';
import '../providers/browse_detail_provider.dart';
import '../providers/selection_state_provider.dart';
import '../providers/kalinka_player_api_provider.dart';
import '../providers/toast_provider.dart';
import '../theme/app_theme.dart';
import '../utils/play_next.dart';
import 'scroll_edge_fade.dart';
import 'search/add_to_collection_sheet.dart';
import 'search_cards/action_pill_button.dart';

/// What the batch bar offers, in its order.
enum _Action {
  playAll('Play all', Icons.play_arrow_rounded),
  enqueue('Enqueue', Icons.playlist_add_rounded),
  playNext('Play next', Icons.playlist_play_rounded),
  collect('Add to collection', Icons.library_add_rounded);

  const _Action(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Short of room on a floating bar, these give way behind the chevron, first
/// to last.
const _setAside = [_Action.playNext, _Action.collect];

/// Bottom batch bar shown during multi-select mode: what the selection comes
/// to, with the cross that drops it, beside or over what can be done with it.
/// Across a narrow pane it is docked under the page, so the page's end stays
/// in reach, and its actions scroll sideways where they do not all fit; on a
/// wide one it is a card over the page's bottom right, as wide as it needs.
class MultiSelectBottomBar extends ConsumerStatefulWidget {
  const MultiSelectBottomBar({super.key});

  /// From this pane width the bar floats as a card over the page.
  static const floatFrom = 600.0;

  /// Whether the bar floats over a pane [width] wide, rather than docks.
  static bool floatsIn(double width) => width >= floatFrom;

  @override
  ConsumerState<MultiSelectBottomBar> createState() =>
      _MultiSelectBottomBarState();
}

class _MultiSelectBottomBarState extends ConsumerState<MultiSelectBottomBar>
    with SingleTickerProviderStateMixin {
  static const _margin = 16.0;
  static const _gap = 8.0;
  static const _padding = EdgeInsets.fromLTRB(14, 4, 4, 4);

  /// Kept after the actions where they have a line of their own.
  static const _actionsEnd = 10.0;

  /// A compact [IconButton]'s, and an icon-only pill's, width.
  static const _iconWidth = 40.0;
  static const _swap = Duration(milliseconds: 200);

  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  )..forward();
  late final _revealCurve = CurvedAnimation(
    parent: _reveal,
    curve: Curves.easeOutCubic,
  );

  /// Whether the row shows the actions set aside rather than the rest.
  bool _more = false;

  @override
  void dispose() {
    _revealCurve.dispose();
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(selectionStateProvider);
    final ready = selection.count > 0;
    final summary = TextSpan(
      style: KalinkaFonts.sans(
        fontSize: KalinkaTypography.baseSize + 1,
        fontWeight: FontWeight.w700,
        color: KalinkaColors.textPrimary,
      ),
      children: [
        TextSpan(text: '${selection.count} selected'),
        TextSpan(
          text: '   ${_trackTally(selection)}',
          style: KalinkaFonts.sans(
            fontSize: KalinkaTypography.baseSize - 1,
            fontWeight: FontWeight.w500,
            color: KalinkaColors.textMuted,
          ),
        ),
      ],
    );

    Widget button(_Action action) => ActionPillButton(
      key: ValueKey(action),
      label: action.label,
      icon: action.icon,
      accent: action == _Action.playAll,
      enabled: ready,
      onTap: switch (action) {
        _Action.playAll => () => _playNow(selection),
        _Action.enqueue => () => _appendToQueue(selection),
        _Action.playNext => () => _playNext(selection),
        _Action.collect => _saveToCollection,
      },
    );

    final close = IconButton(
      tooltip: 'Cancel selection',
      onPressed: () =>
          ref.read(selectionStateProvider.notifier).exitSelectionMode(),
      icon: const Icon(Icons.close_rounded, size: 22),
      color: KalinkaColors.textSecondary,
      visualDensity: VisualDensity.compact,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final floating = MultiSelectBottomBar.floatsIn(constraints.maxWidth);
        final full =
            constraints.maxWidth -
            (floating ? 2 * _margin : 0) -
            _padding.horizontal;
        final room = full - _actionsEnd;

        final pillWidths = {
          for (final action in _Action.values)
            action: ActionPillButton.widthOf(context, action.label),
        };
        double rowWidth(List<_Action> actions, {required bool chevron}) {
          var width = (actions.length - 1) * _gap;
          for (final action in actions) {
            width += pillWidths[action]!;
          }
          return chevron ? width + _gap + _iconWidth : width;
        }

        final title = Text.rich(
          summary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
        if (!floating) {
          return _revealed(
            _docked(
              title: title,
              close: close,
              actions: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: _gap,
                children: [for (final action in _Action.values) button(action)],
              ),
              inline:
                  _widthOf(context, summary) +
                      2 * _gap +
                      rowWidth(_Action.values, chevron: false) +
                      _iconWidth <=
                  full,
            ),
          );
        }

        final shown = [..._Action.values];
        for (final action in _setAside) {
          final chevron = shown.length < _Action.values.length;
          if (rowWidth(shown, chevron: chevron) <= room) break;
          shown.remove(action);
        }
        final aside = [
          for (final action in _Action.values)
            if (!shown.contains(action)) action,
        ];
        final more = _more && aside.isNotEmpty;
        // Either row may be up, so the line takes the wider.
        final widest = aside.isEmpty
            ? rowWidth(shown, chevron: false)
            : math.max(
                rowWidth(shown, chevron: true),
                rowWidth(aside, chevron: true),
              );
        final inline =
            _widthOf(context, summary) + 2 * _gap + widest + _iconWidth <= full;

        final actions = AnimatedSwitcher(
          duration: _swap,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.centerLeft,
            children: [...previous, ?current],
          ),
          child: Row(
            key: ValueKey(more),
            mainAxisSize: MainAxisSize.min,
            spacing: _gap,
            children: [
              for (final action in more ? aside : shown) button(action),
              if (aside.isNotEmpty)
                Tooltip(
                  message: more ? 'Back' : 'More actions',
                  excludeFromSemantics: true,
                  child: ActionPillButton(
                    icon: more
                        ? Icons.chevron_left_rounded
                        : Icons.chevron_right_rounded,
                    semanticsLabel: more ? 'Back' : 'More actions',
                    onTap: () => setState(() => _more = !more),
                  ),
                ),
            ],
          ),
        );
        final Widget content = inline
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: title),
                  const SizedBox(width: 2 * _gap),
                  actions,
                  const SizedBox(width: _gap / 2),
                  close,
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: title),
                      close,
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: _actionsEnd),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      // The set-aside actions may still be too wide for a
                      // phone; they shrink a little rather than overflow.
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: actions,
                      ),
                    ),
                  ),
                ],
              );

        return _revealed(
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(_margin, 0, _margin, _margin),
              child: Align(
                alignment: Alignment.bottomRight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: KalinkaColors.surfaceInput,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: KalinkaColors.borderDefault),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: AnimatedSize(
                    duration: _swap,
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: _padding,
                      child: IntrinsicWidth(child: content),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Grows into place, and fades in, when the bar first shows.
  Widget _revealed(Widget bar) => SizeTransition(
    sizeFactor: _revealCurve,
    alignment: Alignment.topCenter,
    child: FadeTransition(opacity: _revealCurve, child: bar),
  );

  /// Across the pane's foot: on one line with the summary when [inline],
  /// otherwise under it, scrolling sideways out to the bar's edges.
  Widget _docked({
    required Widget title,
    required Widget close,
    required Widget actions,
    required bool inline,
  }) => DecoratedBox(
    decoration: BoxDecoration(
      color: KalinkaColors.surfaceInput,
      border: const Border(
        top: BorderSide(color: KalinkaColors.borderDefault, width: 1),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.3),
          blurRadius: 8,
          offset: const Offset(0, -2),
        ),
      ],
    ),
    child: SafeArea(
      top: false,
      child: inline
          ? Padding(
              padding: _padding,
              child: Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 2 * _gap),
                  actions,
                  const SizedBox(width: _gap / 2),
                  close,
                ],
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: _padding.copyWith(bottom: 0),
                  child: Row(
                    children: [
                      Expanded(child: title),
                      close,
                    ],
                  ),
                ),
                ScrollEdgeFade(
                  axis: Axis.horizontal,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.fromLTRB(
                      _padding.left,
                      0,
                      _actionsEnd,
                      _padding.bottom,
                    ),
                    child: actions,
                  ),
                ),
              ],
            ),
    ),
  );

  /// How wide [span] sets on one line here.
  static double _widthOf(BuildContext context, InlineSpan span) {
    final painter = TextPainter(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: [span],
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width.ceilToDouble();
  }

  /// How many tracks the selection comes to, in words. A container counts
  /// through what it holds, so one still loading leaves the total open. A
  /// folder adds everything below it, which its listing does not show, so
  /// folders are counted as folders.
  String _trackTally(SelectionState selection) {
    int tracks = selection.selectedIds.length;
    int unresolved = 0;
    int folders = 0;
    for (final containerId in selection.selectedContainerIds) {
      if (_isFolder(containerId)) {
        folders++;
        continue;
      }
      final items = ref.watch(browseDetailProvider(containerId)).value?.items;
      if (items == null) {
        unresolved++;
        continue;
      }
      final trackCount = items.where((i) => i.track != null).length;
      final excluded = selection.containerExclusions[containerId]?.length ?? 0;
      tracks += (trackCount - excluded).clamp(0, trackCount);
    }
    final trackPart = unresolved > 0
        ? (tracks > 0 ? '$tracks+ tracks' : '…')
        : '$tracks ${tracks == 1 ? 'track' : 'tracks'}';
    if (folders == 0) return trackPart;
    final folderPart = '$folders ${folders == 1 ? 'folder' : 'folders'}';
    return tracks == 0 && unresolved == 0
        ? folderPart
        : '$trackPart · $folderPart';
  }

  /// The only catalogs a selection takes whole are folders.
  static bool _isFolder(String containerId) {
    try {
      return EntityId.fromString(containerId).type == EntityType.catalog;
    } catch (_) {
      return false;
    }
  }

  // Each queue action dismisses the panel immediately and reports progress via
  // the shared spinner. `selection` is a tap-time snapshot, so its count stays
  // valid after exitSelectionMode() as a fallback.

  Future<void> _appendToQueue(SelectionState selection) async {
    final api = ref.read(kalinkaProxyProvider);
    final toast = ref.read(toastProvider.notifier);
    final selectionNotifier = ref.read(selectionStateProvider.notifier);
    final ids = selectionNotifier.resolveIdsForApi();
    selectionNotifier.exitSelectionMode();
    toast.beginQueueActivity('Adding to queue…');
    try {
      // Use the server's expanded count, not selection.count (album = 1 item).
      final added = await api.add(ids);
      final n = added.count ?? selection.count;
      toast.endQueueActivity(
        '$n ${n == 1 ? 'track' : 'tracks'} added to queue',
      );
    } catch (e) {
      toast.endQueueActivity('Failed to add to queue: $e', isError: true);
    }
  }

  Future<void> _playNow(SelectionState selection) async {
    final api = ref.read(kalinkaProxyProvider);
    final toast = ref.read(toastProvider.notifier);
    final selectionNotifier = ref.read(selectionStateProvider.notifier);
    final ids = selectionNotifier.resolveIdsForApi();
    selectionNotifier.exitSelectionMode();
    toast.beginQueueActivity('Starting playback…');
    try {
      final added = await api.replace(ids);
      // Explicit index 0: avoids a backend race where a stale FINISHED from the
      // cleared stream advances current_track_id, making play() skip track 0.
      await api.play(0);
      final n = added.count ?? selection.count;
      toast.endQueueActivity('Playing $n ${n == 1 ? 'track' : 'tracks'}');
    } catch (e) {
      toast.endQueueActivity('Failed to play: $e', isError: true);
    }
  }

  Future<void> _playNext(SelectionState selection) async {
    final api = ref.read(kalinkaProxyProvider);
    final toast = ref.read(toastProvider.notifier);
    final selectionNotifier = ref.read(selectionStateProvider.notifier);
    final ids = selectionNotifier.resolveIdsForApi();
    final insertIndex = playNextInsertIndex(ref);
    selectionNotifier.exitSelectionMode();
    toast.beginQueueActivity('Queueing next…');
    try {
      final added = await api.add(ids, index: insertIndex);
      final n = added.count ?? selection.count;
      toast.endQueueActivity('$n ${n == 1 ? 'track' : 'tracks'} playing next');
    } catch (e) {
      toast.endQueueActivity('Failed to add: $e', isError: true);
    }
  }

  /// Hands the selection to the destination sheet, which is where the
  /// collection it joins and the terms it joins on are settled.
  Future<void> _saveToCollection() async {
    final selectionNotifier = ref.read(selectionStateProvider.notifier);
    final landed = await showAddToCollectionSheet(
      context,
      CollectionAddition.selection(selectionNotifier.resolveIdsForApi()),
    );
    // A sheet closed without saving leaves the selection to try again.
    if (landed) selectionNotifier.exitSelectionMode();
  }
}
