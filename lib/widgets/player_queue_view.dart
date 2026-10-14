import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_state_provider.dart';
import '../providers/connection_state_provider.dart';
import '../theme/app_theme.dart';
import 'queue_actions.dart';
import 'queue_zone.dart';
import 'search_cards/track_row_support.dart' show formatTotalDuration;

/// The player's queue view: how much is left to play and the queue's
/// actions, over the queue itself.
class PlayerQueueView extends ConsumerWidget {
  /// Offered by the empty queue; see [QueueZone.onFindMusic].
  final VoidCallback? onFindMusic;
  final bool isTablet;

  const PlayerQueueView({super.key, this.onFindMusic, this.isTablet = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        const _QueueSummary(),
        Expanded(
          child: QueueZone(
            bottomPadding: 16,
            isTablet: isTablet,
            onOpenManagementTray: () => showQueueManagementTray(context, ref),
            showMenuButton: false,
            onFindMusic: onFindMusic,
          ),
        ),
      ],
    );
  }
}

class _QueueSummary extends ConsumerWidget {
  const _QueueSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(
      playQueueStateStoreProvider.select(
        (s) => (tracks: s.trackList, index: s.playbackState.index ?? 0),
      ),
    );
    // The saved queue under a plugin's playback heads itself, count included.
    final exclusive = ref.watch(
      playbackControlProvider.select((c) => c.isExclusive),
    );
    final connection = ref.watch(connectionStateProvider);
    // As the queue's own menu: nothing to act on while the server is away.
    final offline =
        connection == ConnectionStatus.reconnecting ||
        connection == ConnectionStatus.offline ||
        connection == ConnectionStatus.none;

    final tracks = queue.tracks;
    final remaining = tracks.sublist(queue.index.clamp(0, tracks.length));
    final seconds = remaining.fold<int>(0, (sum, t) => sum + t.duration);
    final count = switch (remaining.length) {
      0 => tracks.isEmpty ? 'Empty' : 'Nothing left to play',
      1 => '1 track',
      final n => '$n tracks',
    };
    final summary = seconds > 0
        ? '$count · ${formatTotalDuration(seconds)}'
        : count;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: exclusive
                ? const SizedBox.shrink()
                : Text(
                    summary,
                    style: KalinkaTextStyles.trackCountBadge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
          if (!offline) ...[
            if (tracks.isNotEmpty)
              IconButton(
                tooltip: 'Save as collection',
                onPressed: () => saveQueueToCollection(context, ref),
                icon: const Icon(
                  Icons.playlist_add_rounded,
                  size: 22,
                  color: KalinkaColors.textSecondary,
                ),
              ),
            IconButton(
              tooltip: 'Queue options',
              onPressed: () => showQueueManagementTray(context, ref),
              icon: const Icon(
                Icons.more_vert,
                size: 20,
                color: KalinkaColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
