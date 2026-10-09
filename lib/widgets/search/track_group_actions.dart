import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/kalinka_player_api_provider.dart';
import '../../providers/selection_state_provider.dart';
import '../../providers/toast_provider.dart';
import '../../theme/app_theme.dart';
import '../search_cards/action_pill_button.dart';

/// The batch actions a group of tracks carries under its heading: play them
/// all, enqueue them all, or — in multi-select mode — select them all.
///
/// The chips take the whole group's ids, hidden rows included, so the action
/// covers the set the heading names rather than the rows in view.
class TrackGroupActions extends ConsumerWidget {
  final List<String> trackIds;

  const TrackGroupActions({super.key, required this.trackIds});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (trackIds.isEmpty) return const SizedBox.shrink();
    final selectionMode = ref.watch(
      selectionStateProvider.select((s) => s.isActive),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (selectionMode) ...[
          SelectAllButton(trackIds: trackIds),
        ] else ...[
          PlayAllChip(trackIds: trackIds),
          const SizedBox(width: 8),
          AddAllChip(trackIds: trackIds),
        ],
      ],
    );
  }
}

/// Play these ids now: they become the queue, starting from the first. The
/// berry tint marks it as the default action; the additive enqueue chip
/// beside it stays neutral.
///
/// The ids are whatever the caller wants queued — a section's tracks, or the
/// single id of a container the server expands. [trackCount] is how many
/// tracks they stand for, where that is not simply their number.
class PlayAllChip extends ConsumerStatefulWidget {
  final List<String> trackIds;
  final int? trackCount;

  const PlayAllChip({super.key, required this.trackIds, this.trackCount});

  @override
  ConsumerState<PlayAllChip> createState() => _PlayAllChipState();
}

class _PlayAllChipState extends ConsumerState<PlayAllChip> {
  bool _busy = false;

  Future<void> _playAll() async {
    if (_busy) return;
    setState(() => _busy = true);
    final api = ref.read(kalinkaProxyProvider);
    final expected = widget.trackCount ?? widget.trackIds.length;
    await runQueueActivity(
      pending: 'Starting playback…',
      action: () async {
        final added = await api.replace(widget.trackIds);
        await api.play(0);
        return added;
      },
      done: (r) {
        final n = r.count ?? expected;
        return 'Playing $n track${n == 1 ? '' : 's'}';
      },
      failed: (e) => 'Failed to play: $e',
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return ActionPillButton(
      label: 'Play all',
      icon: Icons.play_arrow_rounded,
      accent: true,
      enabled: !_busy,
      onTap: _playAll,
      semanticsLabel: 'Play all tracks in this section',
    );
  }
}

/// Enqueue every track in a section, reporting via the shared activity toast.
/// Idle → busy (request in flight) → added (3s confirmation) → idle.
enum _AddStatus { idle, busy, added }

class AddAllChip extends ConsumerStatefulWidget {
  final List<String> trackIds;
  final int? trackCount;

  /// What was enqueued, where the toast can name it — a container has a name,
  /// a section of results is only "these tracks".
  final String? name;

  const AddAllChip({
    super.key,
    required this.trackIds,
    this.trackCount,
    this.name,
  });

  @override
  ConsumerState<AddAllChip> createState() => _AddAllChipState();
}

class _AddAllChipState extends ConsumerState<AddAllChip> {
  _AddStatus _status = _AddStatus.idle;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _enqueue() async {
    if (_status != _AddStatus.idle) return;
    // Busy (disabled) while the request is in flight — the "Added ✓"
    // confirmation only appears once the add actually succeeds.
    setState(() => _status = _AddStatus.busy);
    final api = ref.read(kalinkaProxyProvider);
    final toast = ref.read(toastProvider.notifier);
    final expected = widget.trackCount ?? widget.trackIds.length;
    toast.beginQueueActivity('Adding to queue…');
    try {
      final added = await api.add(widget.trackIds);
      final n = added.count ?? expected;
      final tracks = '$n track${n == 1 ? '' : 's'}';
      toast.endQueueActivity(
        widget.name == null
            ? '$tracks added to queue'
            : '${widget.name} — $tracks added to queue',
      );
      if (!mounted) return;
      setState(() => _status = _AddStatus.added);
      _resetTimer?.cancel();
      _resetTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _status = _AddStatus.idle);
      });
    } catch (e) {
      // Failed — back to idle so they can retry immediately.
      if (mounted) setState(() => _status = _AddStatus.idle);
      toast.endQueueActivity('Failed to add: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final added = _status == _AddStatus.added;
    return ActionPillButton(
      label: added ? 'Added' : 'Enqueue',
      icon: added ? Icons.check_rounded : Icons.playlist_add_rounded,
      // Enabled only when idle — no re-add while adding or confirming.
      enabled: _status == _AddStatus.idle,
      onTap: _enqueue,
      foregroundOverride: added ? KalinkaColors.gold : null,
      borderOverride: added ? KalinkaColors.gold.withValues(alpha: 0.4) : null,
      semanticsLabel: added
          ? 'Added to queue'
          : _status == _AddStatus.busy
          ? 'Adding to queue'
          : 'Add ${widget.name ?? 'all'} to queue',
    );
  }
}

/// Select / clear all of a card's tracks (including any hidden behind "show
/// more"), surfacing the multi-select toolbar for play now / play next / add.
///
/// Grey while nothing is selected — selecting is one option among the rows'
/// own taps; crimson once the whole group is selected, where clearing it is
/// the action the heading leads with, the slot "Play all" holds otherwise.
class SelectAllButton extends ConsumerWidget {
  final List<String> trackIds;

  const SelectAllButton({super.key, required this.trackIds});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allSelected = ref.watch(
      selectionStateProvider.select(
        (s) => trackIds.every(s.selectedIds.contains),
      ),
    );
    // Same 44px slot as the Play all / Enqueue pills it replaces, so the
    // header height doesn't jump when selection mode toggles.
    return Center(
      child: ActionPillButton(
        label: allSelected ? 'Clear' : 'Select all',
        accent: allSelected,
        onTap: () {
          final notifier = ref.read(selectionStateProvider.notifier);
          if (allSelected) {
            notifier.deselectTracks(trackIds);
          } else {
            notifier.selectTracks(trackIds);
          }
        },
        semanticsLabel: allSelected ? 'Clear selection' : 'Select all tracks',
      ),
    );
  }
}
