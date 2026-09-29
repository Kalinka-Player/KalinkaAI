import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart';
import '../utils/playback_utils.dart';
import 'app_state_provider.dart';

/// The track the output is on: the queue's current entry, or the plugin's own
/// while one plays exclusively (its track is not in the queue). Null once the
/// queue is emptied — the state's currentTrack is sticky, the queue is not.
final nowPlayingTrackProvider = Provider<Track?>((ref) {
  final queue = ref.watch(playQueueStateStoreProvider);
  final current = queue.playbackState.currentTrack;
  if (queue.playbackControl.isExclusive) return current;
  final index = queue.playbackState.index ?? 0;
  if (index >= 0 && index < queue.trackList.length) {
    return queue.trackList[index];
  }
  return queue.trackList.isNotEmpty ? current : null;
});

/// Length of what is playing. A plugin's stream reports its own, which the
/// track it describes may not carry.
final nowPlayingDurationMsProvider = Provider<int>((ref) {
  final exclusive = ref.watch(
    playbackControlProvider.select((c) => c.isExclusive),
  );
  final streamMs = ref.watch(
    playerStateProvider.select((s) => s.audioInfo?.durationMs ?? 0),
  );
  if (exclusive && streamMs > 0) return streamMs;
  return (ref.watch(nowPlayingTrackProvider.select((t) => t?.duration)) ?? 0) *
      1000;
});

/// What the transport buttons may do right now.
typedef TransportState = ({
  PlayerStateType? playerState,
  bool exclusive,
  bool hasTrack,
  bool canPrev,
  bool canNext,
  bool playPauseDisabled,
});

final transportStateProvider = Provider<TransportState>((ref) {
  final playerState = ref.watch(playerStateProvider.select((s) => s.state));
  final mode = ref.watch(playbackModeProvider);
  final position = ref.watch(
    playQueueStateStoreProvider.select(
      (s) => (length: s.trackList.length, index: s.playbackState.index ?? 0),
    ),
  );
  // A plugin's playback carries its own queue: its controls go to it, and
  // only it knows where its ends are.
  final exclusive = ref.watch(
    playbackControlProvider.select((c) => c.isExclusive),
  );
  final hasTrack = exclusive || position.length > 0;

  // Gate prev/next at the queue ends, but only for plain sequential
  // playback: repeat-all wraps around and shuffle decouples list order from
  // play order, so in those modes either end stays meaningful.
  final bounded = !exclusive && !mode.shuffle && !mode.repeatAll;
  return (
    playerState: playerState,
    exclusive: exclusive,
    hasTrack: hasTrack,
    canPrev: hasTrack && (!bounded || position.index > 0),
    canNext: hasTrack && (!bounded || position.index < position.length - 1),
    playPauseDisabled:
        !hasTrack || isPlayPauseDisabled(playerState, exclusive: exclusive),
  );
});
