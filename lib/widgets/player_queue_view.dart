import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'queue_actions.dart';
import 'queue_zone.dart';

/// The player's queue view: the queue itself, its menu opening as a sheet
/// over the player.
class PlayerQueueView extends ConsumerWidget {
  /// Offered by the empty queue; see [QueueZone.onFindMusic].
  final VoidCallback? onFindMusic;
  final bool isTablet;

  const PlayerQueueView({super.key, this.onFindMusic, this.isTablet = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return QueueZone(
      bottomPadding: 16,
      isTablet: isTablet,
      onOpenManagementTray: () => showQueueManagementTray(context, ref),
      onFindMusic: onFindMusic,
    );
  }
}
