import 'dart:async' show scheduleMicrotask;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/playqueue_events.dart' show PlaybackEvent;
import 'app_state_provider.dart';
import 'wire_event_provider.dart';

/// What the current renderer reported happening during the track it plays:
/// the latest details of each [PlaybackEvent] kind, keyed by kind.
///
/// Kept apart from the queue state, which the events would churn. They hold
/// for one track on one renderer and go when either changes, a reconnect
/// included, as no replay carries them. The app listens from its start: an
/// event is not sent again once what it reports stops. Every kind is kept as
/// it arrived; a reader takes the kinds it knows.
class PlaybackEventsNotifier
    extends Notifier<Map<String, Map<String, Object?>>> {
  @override
  Map<String, Map<String, Object?>> build() {
    ref.listen(
      playQueueStateStoreProvider.select(
        (s) => (s.playbackState.currentTrack?.id, s.currentRendererId),
      ),
      (_, _) => state = const {},
    );
    ref.listen(playQueueEventBusProvider, (_, next) {
      if (next case AsyncData(
        value: PlaybackEvent(:final kind, :final details),
      )) {
        // Behind the store's own update, so its track is current by then.
        scheduleMicrotask(() {
          if (ref.mounted) state = {...state, kind: details};
        });
      }
    });
    return const {};
  }
}

final playbackEventsProvider =
    NotifierProvider<PlaybackEventsNotifier, Map<String, Map<String, Object?>>>(
      PlaybackEventsNotifier.new,
    );
