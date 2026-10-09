import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data_model/data_model.dart';
import '../providers/browse_detail_provider.dart';
import '../providers/selection_state_provider.dart';
import '../providers/kalinka_player_api_provider.dart';
import '../providers/toast_provider.dart';
import '../theme/app_theme.dart';
import '../utils/play_next.dart';
import 'search/add_to_collection_sheet.dart';
import 'search_cards/action_icon_chip.dart';

/// Bottom batch bar shown during multi-select mode. One row, in two stages:
/// what to do with the selection — play it now, queue it, keep it — and,
/// behind `Queue…`, where in the queue it goes. Splitting the queueing in two
/// is what leaves room for a third action; both stages stand the same height,
/// so stepping between them moves nothing above the bar.
class MultiSelectBottomBar extends ConsumerStatefulWidget {
  const MultiSelectBottomBar({super.key});

  @override
  ConsumerState<MultiSelectBottomBar> createState() =>
      _MultiSelectBottomBarState();
}

class _MultiSelectBottomBarState extends ConsumerState<MultiSelectBottomBar> {
  /// Whether the bar is asking where in the queue the selection lands. The bar
  /// leaves the tree with the selection, so every selection starts over.
  bool _placing = false;

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(selectionStateProvider);
    final tally = _trackTally(selection);

    return AnimatedSlide(
      offset: selection.isActive ? Offset.zero : const Offset(0, 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutQuart,
      child: AnimatedOpacity(
        opacity: selection.isActive ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
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
            child: _placing
                ? _placementRow(selection, tally)
                : _actionsRow(selection, tally),
          ),
        ),
      ),
    );
  }

  /// What can be done with the selection, and what it comes to.
  Widget _actionsRow(SelectionState selection, String tally) {
    final ready = selection.count > 0;
    return Row(
      children: [
        ActionIconChip(
          icon: Icons.close,
          semanticsLabel: 'Cancel selection',
          onTap: () {
            ref.read(selectionStateProvider.notifier).exitSelectionMode();
          },
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _BarLabel(
            title: '${selection.count} selected',
            subtitle: tally,
          ),
        ),
        const SizedBox(width: 8),
        const _BarRule(),
        const SizedBox(width: 8),
        _BatchActionButton(
          icon: Icons.play_arrow_rounded,
          label: 'Play now',
          look: _BatchLook.filled,
          onTap: ready
              ? () {
                  _playNow(selection);
                }
              : null,
        ),
        const SizedBox(width: 8),
        _BatchActionButton(
          icon: Icons.playlist_add_rounded,
          label: 'Queue…',
          onTap: ready
              ? () {
                  setState(() => _placing = true);
                }
              : null,
        ),
        const SizedBox(width: 8),
        _BatchActionButton(
          icon: Icons.library_add_rounded,
          label: 'Collection',
          onTap: ready ? _saveToCollection : null,
        ),
      ],
    );
  }

  /// Where in the queue the selection lands. Wider buttons than the stage
  /// before it: there are two of them, and nothing else to fit.
  Widget _placementRow(SelectionState selection, String tally) {
    return Row(
      children: [
        ActionIconChip(
          icon: Icons.chevron_left_rounded,
          semanticsLabel: 'Back to actions',
          onTap: () {
            setState(() => _placing = false);
          },
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 3,
          child: _BarLabel(
            title: 'QUEUE ${tally.toUpperCase()}',
            titleStyle: KalinkaTextStyles.sectionLabel,
            subtitle: 'Choose placement',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: _BatchActionButton(
            icon: Icons.arrow_upward_rounded,
            label: 'Play next',
            look: _BatchLook.outlined,
            width: null,
            onTap: () {
              _playNext(selection);
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: _BatchActionButton(
            icon: Icons.playlist_add_rounded,
            label: 'Enqueue',
            width: null,
            onTap: () {
              _appendToQueue(selection);
            },
          ),
        ),
      ],
    );
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

/// InkWell overlay for the batch bar: subtle wash on hover, accent on press
/// (matches KalinkaButton).
WidgetStateProperty<Color?> _batchOverlay() =>
    WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) {
        return KalinkaColors.accent.withValues(alpha: 0.20);
      }
      if (states.contains(WidgetState.hovered)) {
        return Colors.white.withValues(alpha: 0.07);
      }
      return null;
    });

/// Overlay for the accent-filled button, where an accent wash would vanish.
WidgetStateProperty<Color?> _accentOverlay() =>
    WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) {
        return Colors.white.withValues(alpha: 0.15);
      }
      if (states.contains(WidgetState.hovered)) {
        return Colors.white.withValues(alpha: 0.07);
      }
      return null;
    });

/// How a batch action is drawn: [filled] for the one that takes the queue
/// over, [outlined] for the one a stage of two leads with, [plain] for the
/// rest.
enum _BatchLook { filled, outlined, plain }

/// One batch action: an icon over its label. [width] fixes the footprint so a
/// row of them reads as a set, leaving the spare width to the label beside
/// them; a null one fills whatever it is given instead. A null [onTap]
/// renders it disabled.
class _BatchActionButton extends StatelessWidget {
  // Wide enough for the longest label of the set ("Collection").
  static const double _defaultWidth = 72;

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final _BatchLook look;
  final double? width;

  const _BatchActionButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.look = _BatchLook.plain,
    this.width = _defaultWidth,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final Color fg = switch (look) {
      _BatchLook.outlined => KalinkaColors.accentTint,
      _BatchLook.filled => KalinkaColors.textPrimary,
      _BatchLook.plain =>
        enabled ? KalinkaColors.textPrimary : KalinkaColors.textMuted,
    };
    final Color background = switch (look) {
      _BatchLook.filled => KalinkaColors.accent,
      _BatchLook.outlined => KalinkaColors.accentSubtle,
      _BatchLook.plain => KalinkaColors.surfaceElevated,
    };
    final Color border = look == _BatchLook.plain
        ? KalinkaColors.borderDefault
        : KalinkaColors.accent;
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          // On the crimson fill an accent wash would vanish — use white.
          overlayColor: look == _BatchLook.filled
              ? _accentOverlay()
              : _batchOverlay(),
          child: SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 24, color: fg),
                  const SizedBox(height: 1),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KalinkaFonts.sans(
                      fontSize: KalinkaTypography.baseSize - 1,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The upright rule that keeps the batch actions off the label beside them.
class _BarRule extends StatelessWidget {
  const _BarRule();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 30, color: KalinkaColors.borderDefault);
}

/// What the bar is about, over a line saying what it amounts to: the count of
/// items taken over the tracks they come to, or the stage's own name over what
/// it wants decided.
class _BarLabel extends StatelessWidget {
  final String title;
  final String subtitle;

  /// Overrides the plain title where a stage names itself the way a section
  /// header does.
  final TextStyle? titleStyle;

  const _BarLabel({
    required this.title,
    required this.subtitle,
    this.titleStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              titleStyle ??
              KalinkaFonts.sans(
                fontSize: KalinkaTypography.baseSize + 1,
                fontWeight: FontWeight.w700,
                color: KalinkaColors.textPrimary,
              ),
        ),
        const SizedBox(height: 1),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: KalinkaFonts.sans(
            fontSize: KalinkaTypography.baseSize - 1,
            fontWeight: FontWeight.w500,
            color: KalinkaColors.textMuted,
          ),
        ),
      ],
    );
  }
}
