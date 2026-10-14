import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/shell_nav_provider.dart';
import 'mini_player.dart';
import 'queue_zone.dart';

/// The player's queue view: the queue itself. Its menu is in the player's
/// header and its mini-player lies over its foot ([QueueMiniPlayer]).
class PlayerQueueView extends ConsumerWidget {
  /// Offered by the empty queue; see [QueueZone.onFindMusic].
  final VoidCallback? onFindMusic;
  final bool isTablet;

  /// Room left under the list for what lies over its foot.
  final double bottomPadding;

  const PlayerQueueView({
    super.key,
    this.onFindMusic,
    this.isTablet = false,
    this.bottomPadding = 16,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return QueueZone(
      bottomPadding: bottomPadding,
      isTablet: isTablet,
      onFindMusic: onFindMusic,
    );
  }
}

/// The mini-player over the foot of the player's queue: in with the queue,
/// out with the track. Its host keeps it outside whatever slides, so it stays
/// put when the phone sheet closes. A tap turns back to the track.
class QueueMiniPlayer extends ConsumerStatefulWidget {
  /// See [MiniPlayer.outputSwitcherKey]; held only while the queue shows.
  final Key? outputSwitcherKey;

  const QueueMiniPlayer({super.key, this.outputSwitcherKey});

  @override
  ConsumerState<QueueMiniPlayer> createState() => _QueueMiniPlayerState();
}

class _QueueMiniPlayerState extends ConsumerState<QueueMiniPlayer> {
  /// Not built once slid out, so a hidden bar costs nothing.
  bool _gone = true;

  @override
  Widget build(BuildContext context) {
    final showing = ref.watch(playerViewProvider) == PlayerView.queue;
    if (showing) _gone = false;
    return IgnorePointer(
      ignoring: !showing,
      child: ExcludeSemantics(
        excluding: !showing,
        child: AnimatedSlide(
          offset: showing ? Offset.zero : const Offset(0, 1),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : kMiniPlayerHideDuration,
          curve: Curves.easeOutCubic,
          onEnd: () {
            if (mounted && ref.read(playerViewProvider) != PlayerView.queue) {
              setState(() => _gone = true);
            }
          },
          child: _gone
              ? const SizedBox.shrink()
              : MiniPlayer(
                  onTap: () => ref
                      .read(playerViewProvider.notifier)
                      .show(PlayerView.nowPlaying),
                  outputSwitcherKey: showing ? widget.outputSwitcherKey : null,
                ),
        ),
      ),
    );
  }
}
