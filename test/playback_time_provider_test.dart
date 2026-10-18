import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/monotonic_clock_provider.dart';
import 'package:kalinka/providers/playback_time_provider.dart';

class _Queue extends PlayQueueStateStore {
  @override
  PlayQueueState build() => PlayQueueState.empty;

  void set(PlayQueueState next) => state = next;
}

class _Connection extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;

  void set(ConnectionStatus next) => state = next;
}

class _Resumed extends AppLifecycleNotifier {
  @override
  AppLifecycleState build() => AppLifecycleState.resumed;
}

PlayQueueState _playing({required int positionMs, required int atMs}) =>
    PlayQueueState(
      playbackState: PlaybackState(
        state: PlayerStateType.playing,
        position: positionMs,
        timestampNs: atMs,
      ),
      trackList: const [],
      playbackMode: PlaybackMode.empty,
      seq: 0,
    );

typedef _Harness = ({
  ProviderContainer container,
  _Queue queue,
  _Connection connection,
  Stopwatch clock,
});

_Harness _harness(FakeAsync async) {
  final clock = async.getClock(DateTime(2026, 10, 18)).stopwatch()..start();
  final container = ProviderContainer(
    overrides: [
      monotonicClockProvider.overrideWithValue(clock),
      appLifecycleProvider.overrideWith(_Resumed.new),
      playQueueStateStoreProvider.overrideWith(_Queue.new),
      connectionStateProvider.overrideWith(_Connection.new),
    ],
  );
  addTearDown(container.dispose);
  container.listen(playbackTimeMsProvider, (_, _) {});
  return (
    container: container,
    queue: container.read(playQueueStateStoreProvider.notifier) as _Queue,
    connection: container.read(connectionStateProvider.notifier) as _Connection,
    clock: clock,
  );
}

void main() {
  test('reconnecting holds the position until the server reports again', () {
    fakeAsync((async) {
      final h = _harness(async);
      int time() => h.container.read(playbackTimeMsProvider);

      h.queue.set(_playing(positionMs: 10000, atMs: 0));
      async.elapse(const Duration(seconds: 3));
      expect(time(), 13000);

      h.connection.set(ConnectionStatus.reconnecting);
      // Riverpod refreshes dependents on a zero-length timer.
      async.elapse(Duration.zero);
      expect(time(), 13000);
      expect(async.periodicTimerCount, 0);
      expect(async.nonPeriodicTimerCount, 0);

      async.elapse(const Duration(seconds: 30));
      expect(time(), 13000);
      h.connection.set(ConnectionStatus.offline);
      async.elapse(const Duration(minutes: 1));
      expect(time(), 13000);

      h.connection.set(ConnectionStatus.connected);
      async.elapse(const Duration(seconds: 2));
      expect(time(), 13000);

      h.queue.set(
        _playing(positionMs: 40000, atMs: h.clock.elapsedMilliseconds),
      );
      async.elapse(Duration.zero);
      expect(time(), 40000);
      async.elapse(const Duration(seconds: 1));
      expect(time(), 41000);
    });
  });

  test('a report arriving while still reconnecting is not held', () {
    fakeAsync((async) {
      final h = _harness(async);
      int time() => h.container.read(playbackTimeMsProvider);

      h.queue.set(_playing(positionMs: 10000, atMs: 0));
      async.elapse(Duration.zero);
      h.connection.set(ConnectionStatus.reconnecting);
      async.elapse(const Duration(seconds: 30));
      expect(time(), 10000);

      // The reconnect replay lands before the status flips back.
      h.queue.set(
        _playing(positionMs: 40000, atMs: h.clock.elapsedMilliseconds),
      );
      async.elapse(Duration.zero);
      expect(time(), 40000);

      h.connection.set(ConnectionStatus.connected);
      async.elapse(const Duration(seconds: 2));
      expect(time(), 42000);
    });
  });

  test('dropping again before the server reports keeps the first hold', () {
    fakeAsync((async) {
      final h = _harness(async);
      int time() => h.container.read(playbackTimeMsProvider);

      h.queue.set(_playing(positionMs: 10000, atMs: 0));
      async.elapse(Duration.zero);
      h.connection.set(ConnectionStatus.reconnecting);
      async.elapse(const Duration(seconds: 30));
      h.connection.set(ConnectionStatus.connected);
      async.elapse(Duration.zero);
      h.connection.set(ConnectionStatus.reconnecting);
      async.elapse(const Duration(seconds: 5));
      expect(time(), 10000);
    });
  });
}
