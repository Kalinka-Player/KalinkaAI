import 'dart:async' show scheduleMicrotask;

import 'package:flutter_riverpod/flutter_riverpod.dart'
    show
        AsyncValueExtensions,
        Notifier,
        NotifierProvider,
        Provider,
        ProviderListenableSelect;
import '../data_model/ext_device_events.dart';
import '../data_model/playqueue_events.dart'
    show PlayQueueState, PlayQueueEvent, TrackMovedEvent;
import '../providers/monotonic_clock_provider.dart' show monotonicClockProvider;
import '../providers/wire_event_provider.dart'
    show playQueueEventBusProvider, extDeviceEventBusProvider;
import 'package:logger/logger.dart';

final logger = Logger();

class PlayQueueStateStore extends Notifier<PlayQueueState> {
  /// Tracks moves issued by this client that have not yet been confirmed by
  /// the server.  When the matching `track_moved` event arrives we consume
  /// the pending entry and skip re-applying the move (it was already applied
  /// optimistically), preventing a double-move.
  final List<({int from, int to})> _pendingMoves = [];
  bool _disposed = false;

  @override
  PlayQueueState build() {
    state = PlayQueueState.empty;
    _disposed = false;
    ref.onDispose(() => _disposed = true);

    ref.listen(playQueueEventBusProvider, (prev, next) {
      next.when(
        data: (PlayQueueEvent event) {
          final timestamp = ref
              .read(monotonicClockProvider)
              .elapsedMilliseconds;
          scheduleMicrotask(() {
            if (_disposed) return;
            if (event is TrackMovedEvent) {
              final idx = _pendingMoves.indexWhere(
                (m) => m.from == event.fromIndex && m.to == event.toIndex,
              );
              if (idx != -1) {
                // Our own move — already applied optimistically. Just sync seq.
                _pendingMoves.removeAt(idx);
                state = state.copyWith(seq: event.seq);
                return;
              }
            }
            state = state.apply(event, timestamp);
          });
        },
        loading: () {
          scheduleMicrotask(() {
            if (_disposed) return;
            _pendingMoves.clear();
            state = PlayQueueState.empty;
          });
        },
        error: (Object error, StackTrace stackTrace) {
          logger.e('Error occurred: $error', stackTrace: stackTrace);
          scheduleMicrotask(() {
            if (_disposed) return;
            _pendingMoves.clear();
            state = PlayQueueState.empty;
          });
        },
      );
    });

    return state;
  }

  static int _remapIndex(int idx, int from, int to) {
    if (idx == from) return to;
    if (from < to) {
      if (from < idx && idx <= to) return idx - 1;
    } else {
      if (to <= idx && idx < from) return idx + 1;
    }
    return idx;
  }

  static int _clampPlaybackIndex(int index, int trackCount) {
    if (trackCount <= 0) return 0;
    if (index < 0) return 0;
    final maxIndex = trackCount - 1;
    if (index > maxIndex) return maxIndex;
    return index;
  }

  void optimisticallyReorder(int oldIndex, int newIndex) {
    final list = [...state.trackList];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    _pendingMoves.add((from: oldIndex, to: newIndex));
    final oldPlaybackIndex = state.playbackState.index ?? 0;
    final remappedPlaybackIndex = _remapIndex(
      oldPlaybackIndex,
      oldIndex,
      newIndex,
    );
    final normalizedPlaybackIndex = _clampPlaybackIndex(
      remappedPlaybackIndex,
      list.length,
    );
    final newPlaybackState = normalizedPlaybackIndex != oldPlaybackIndex
        ? state.playbackState.copyWithFields(index: normalizedPlaybackIndex)
        : state.playbackState;
    state = state.copyWith(
      trackList: list,
      playbackState: newPlaybackState,
      seq: state.seq,
    );
  }
}

class ExtDeviceStateStore extends Notifier<ExtDeviceState> {
  bool _disposed = false;

  @override
  ExtDeviceState build() {
    state = ExtDeviceState.empty;
    _disposed = false;
    ref.onDispose(() => _disposed = true);

    ref.listen(extDeviceEventBusProvider, (prev, next) {
      next.when(
        data: (ExtDeviceEvent event) {
          scheduleMicrotask(() {
            if (_disposed) return;
            state = state.apply(event);
          });
        },
        loading: () {
          scheduleMicrotask(() {
            if (_disposed) return;
            state = ExtDeviceState.empty;
          });
        },
        error: (Object error, StackTrace stackTrace) {
          logger.e('Error occurred: $error', stackTrace: stackTrace);
          scheduleMicrotask(() {
            if (_disposed) return;
            state = ExtDeviceState.empty;
          });
        },
      );
    });

    return state;
  }
}

final playQueueStateStoreProvider =
    NotifierProvider<PlayQueueStateStore, PlayQueueState>(
      () => PlayQueueStateStore(),
    );

final extDeviceStateStoreProvider =
    NotifierProvider<ExtDeviceStateStore, ExtDeviceState>(
      () => ExtDeviceStateStore(),
    );

final playerStateProvider = Provider(
  (ref) =>
      ref.watch(playQueueStateStoreProvider.select((s) => s.playbackState)),
);

/// Whether the queue drives the output, or a plugin plays exclusively.
final playbackControlProvider = Provider(
  (ref) =>
      ref.watch(playQueueStateStoreProvider.select((s) => s.playbackControl)),
);

final playQueueProvider = Provider(
  (ref) => ref.watch(playQueueStateStoreProvider.select((s) => s.trackList)),
);

final volumeStateProvider = Provider(
  (ref) => ref.watch(extDeviceStateStoreProvider.select((s) => s.volume)),
);

final playbackModeProvider = Provider(
  (ref) => ref.watch(playQueueStateStoreProvider.select((s) => s.playbackMode)),
);

// Queue expansion state
class QueueExpansionNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
  void expand() => state = true;
  void collapse() => state = false;
}

final queueExpansionProvider = NotifierProvider<QueueExpansionNotifier, bool>(
  QueueExpansionNotifier.new,
);
