import 'dart:async' show Timer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart';
import '../data_model/playqueue_events.dart' show DspMetersChangedEvent;
import 'app_state_provider.dart';
import 'wire_event_provider.dart';

/// The DSP meters of the track playing now, or null when none are live.
///
/// Kept apart from the queue state, which they would churn twice a second.
/// They count from the start of one track on one renderer, so they go when
/// either changes or the signal path ends, and after [staleAfter] without a
/// report, as none come while paused.
class DspMetersNotifier extends Notifier<DspMeters?> {
  static const staleAfter = Duration(seconds: 3);

  @override
  DspMeters? build() {
    ref.watch(playerStateProvider.select((s) => s.currentTrack?.id));
    ref.watch(playQueueStateStoreProvider.select((s) => s.currentRendererId));
    final processed = ref.watch(
      playerStateProvider.select(
        (s) => s.audioInfo?.output?.signalPath != null,
      ),
    );
    if (!processed) return null;

    Timer? stale;
    ref.onDispose(() => stale?.cancel());
    ref.listen(playQueueEventBusProvider, (_, next) {
      if (next case AsyncData(value: DspMetersChangedEvent(:final meters))) {
        stale?.cancel();
        stale = Timer(staleAfter, () => state = null);
        state = meters;
      }
    });
    return null;
  }
}

final dspMetersProvider =
    NotifierProvider.autoDispose<DspMetersNotifier, DspMeters?>(
      DspMetersNotifier.new,
    );
