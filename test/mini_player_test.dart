import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/kalinka_ws_api.dart';
import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/kalinka_ws_api_provider.dart';
import 'package:kalinka/providers/bit_perfect_provider.dart';
import 'package:kalinka/providers/playback_time_provider.dart';
import 'package:kalinka/providers/renderer_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/providers/url_resolver.dart';
import 'package:kalinka/widgets/gradient_progress_line.dart';
import 'package:kalinka/widgets/mini_player.dart';

import 'support/haptic_recorder.dart';

// ── Fake notifiers ────────────────────────────────────────────────────────────
// Each extends the real notifier and overrides build() to return a fixed value,
// avoiding any network/timer setup from the real implementations.

class _SettableQueueNotifier extends PlayQueueStateStore {
  _SettableQueueNotifier(this._initialState);
  final PlayQueueState _initialState;

  @override
  PlayQueueState build() => _initialState;

  void emit(PlayQueueState s) => state = s;
}

class _FakeConnectionNotifier extends ConnectionStateNotifier {
  _FakeConnectionNotifier(this._status);
  final ConnectionStatus _status;

  @override
  ConnectionStatus build() => _status;
}

class _FakeSearchSessionNotifier extends SearchSessionNotifier {
  @override
  SearchSessionState build() => const SearchSessionState();
}

class _FakePlaybackTimeNotifier extends PlaybackTimeMsNotifier {
  @override
  int build() => 0;
}

/// No renderers, so the switcher stays hidden and the real notifier's
/// `/renderer/list` fetch (and its connection-settings dependency) is skipped.
class _FakeRendererNotifier extends RendererListNotifier {
  @override
  RendererListState build() => const RendererListState();
}

// ── Helpers ───────────────────────────────────────────────────────────────────

// Return type is intentionally inferred — Riverpod's Override type is sealed
// and its concrete form is resolved by the package internally.
/// Records queue commands instead of hitting the websocket.
class _FakeWsApi extends KalinkaWsApi {
  _FakeWsApi(super.ref);

  final List<QueueCommand> sent = [];
  Object? sendError;

  @override
  Future<void> sendQueueCommand(QueueCommand command) async {
    sent.add(command);
    if (sendError != null) throw sendError!;
  }
}

List<Override> _buildOverrides({
  required PlayQueueState queueState,
  ConnectionStatus connectionStatus = ConnectionStatus.connected,
}) => [
  playQueueStateStoreProvider.overrideWith(
    () => _SettableQueueNotifier(queueState),
  ),
  connectionStateProvider.overrideWith(
    () => _FakeConnectionNotifier(connectionStatus),
  ),
  searchSessionProvider.overrideWith(() => _FakeSearchSessionNotifier()),
  playbackTimeMsProvider.overrideWith(() => _FakePlaybackTimeNotifier()),
  rendererListProvider.overrideWith(() => _FakeRendererNotifier()),
  urlResolverProvider.overrideWithValue(UrlResolver('')),
];

PlayQueueState _queueWithState({PlayerStateType? state, String? message}) =>
    PlayQueueState(
      playbackState: PlaybackState(state: state, message: message),
      trackList: const [],
      playbackMode: PlaybackMode.empty,
      seq: 0,
    );

Future<void> pumpMiniPlayer(
  WidgetTester tester, {
  PlayQueueState? queueState,
  ConnectionStatus connectionStatus = ConnectionStatus.connected,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: _buildOverrides(
        queueState: queueState ?? PlayQueueState.empty,
        connectionStatus: connectionStatus,
      ),
      child: const MaterialApp(home: Scaffold(body: MiniPlayer())),
    ),
  );
  await tester.pump();
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('swipe track changes', () {
    final current = Track(id: 'current', title: 'Current track', duration: 120);
    final next = Track(id: 'next', title: 'Old next track', duration: 180);
    final inserted = Track(
      id: 'inserted',
      title: 'Inserted track',
      duration: 240,
    );

    PlayQueueState initialQueue() => PlayQueueState(
      playbackState: PlaybackState(index: 0, state: PlayerStateType.playing),
      trackList: [current, next],
      playbackMode: PlaybackMode.empty,
      seq: 0,
    );

    Future<ProviderContainer> mount(WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: [
          ..._buildOverrides(queueState: initialQueue()),
          kalinkaWsApiProvider.overrideWith((ref) => _FakeWsApi(ref)),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: Center(child: SizedBox(width: 360, child: MiniPlayer())),
            ),
          ),
        ),
      );
      return container;
    }

    Future<void> swipeNext(WidgetTester tester) async {
      await tester.dragFrom(
        tester.getTopLeft(find.byType(MiniPlayer)) + const Offset(200, 36),
        const Offset(-180, 0),
      );
      await tester.pump();
    }

    for (final duringAnimation in [true, false]) {
      testWidgets(
        'play next ${duringAnimation ? 'during' : 'after'} a swipe cannot leave a stale preview',
        (tester) async {
          final container = await mount(tester);
          final notifier =
              container.read(playQueueStateStoreProvider.notifier)
                  as _SettableQueueNotifier;
          final api = container.read(kalinkaWsApiProvider) as _FakeWsApi;

          await swipeNext(tester);
          if (!duringAnimation) {
            await tester.pump(const Duration(milliseconds: 300));
            expect(find.text('Old next track'), findsOneWidget);
          }
          final added = initialQueue().apply(
            PlayQueueEvent.tracksAdded(tracks: [inserted], index: 1, seq: 1),
            0,
          );
          notifier.emit(added);
          await tester.pumpAndSettle();
          expect(api.sent, [const QueueCommand.next()]);

          notifier.emit(
            added.apply(
              PlayQueueEvent.playbackStateChanged(
                state: PlaybackState(index: 1, state: PlayerStateType.playing),
                seq: 2,
              ),
              0,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Inserted track'), findsOneWidget);
          expect(find.text('Old next track'), findsNothing);

          await swipeNext(tester);
          await tester.pumpAndSettle();
          expect(api.sent, [
            const QueueCommand.next(),
            const QueueCommand.next(),
          ]);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }

    testWidgets('a different server-selected track replaces the prediction', (
      tester,
    ) async {
      final container = await mount(tester);
      final notifier =
          container.read(playQueueStateStoreProvider.notifier)
              as _SettableQueueNotifier;
      final queue = initialQueue().copyWith(
        trackList: [current, next, inserted],
        seq: 1,
      );
      notifier.emit(queue);
      await tester.pump();
      await swipeNext(tester);
      await tester.pumpAndSettle();
      expect(find.text('Old next track'), findsOneWidget);

      notifier.emit(
        queue.apply(
          PlayQueueEvent.playbackStateChanged(
            state: PlaybackState(index: 2, state: PlayerStateType.playing),
            seq: 2,
          ),
          0,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Inserted track'), findsOneWidget);
      expect(find.text('Old next track'), findsNothing);
    });

    testWidgets('an unanswered swipe expires and can be retried', (
      tester,
    ) async {
      final container = await mount(tester);
      final api = container.read(kalinkaWsApiProvider) as _FakeWsApi;
      await swipeNext(tester);
      await tester.pumpAndSettle();
      expect(find.text('Old next track'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Current track'), findsOneWidget);
      await swipeNext(tester);
      await tester.pumpAndSettle();
      expect(api.sent, [const QueueCommand.next(), const QueueCommand.next()]);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a failed command releases the preview and allows retry', (
      tester,
    ) async {
      final container = await mount(tester);
      final api = container.read(kalinkaWsApiProvider) as _FakeWsApi;
      api.sendError = StateError('Socket closed');
      await swipeNext(tester);
      await tester.pumpAndSettle();
      expect(find.text('Current track'), findsOneWidget);
      api.sendError = null;
      await swipeNext(tester);
      await tester.pumpAndSettle();
      expect(api.sent, [const QueueCommand.next(), const QueueCommand.next()]);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('play button icons', () {
    testWidgets('shows pause icon when playing', (tester) async {
      await pumpMiniPlayer(
        tester,
        queueState: _queueWithState(state: PlayerStateType.playing),
      );

      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    });

    testWidgets('shows play icon when paused', (tester) async {
      await pumpMiniPlayer(
        tester,
        queueState: _queueWithState(state: PlayerStateType.paused),
      );

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.byIcon(Icons.pause_rounded), findsNothing);
    });

    testWidgets('shows play icon when stopped', (tester) async {
      await pumpMiniPlayer(
        tester,
        queueState: _queueWithState(state: PlayerStateType.stopped),
      );

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });

    testWidgets('shows CircularProgressIndicator when buffering', (
      tester,
    ) async {
      await pumpMiniPlayer(
        tester,
        queueState: _queueWithState(state: PlayerStateType.buffering),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
      expect(find.byIcon(Icons.pause_rounded), findsNothing);
    });

    // A failed track keeps a plain play button — pressing it retries. Showing
    // a warning there read as "this control is broken".
    testWidgets('shows play icon when the track failed', (tester) async {
      await pumpMiniPlayer(
        tester,
        queueState: _queueWithState(
          state: PlayerStateType.error,
          message: 'Oops',
        ),
      );

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.byIcon(Icons.warning_rounded), findsNothing);
      expect(find.byIcon(Icons.pause_rounded), findsNothing);
    });

    testWidgets('pressing play on a failed track retries it', (tester) async {
      final container = ProviderContainer(
        overrides: [
          ..._buildOverrides(
            queueState: PlayQueueState(
              playbackState: PlaybackState(
                state: PlayerStateType.error,
                message: 'Oops',
              ),
              trackList: [
                Track(
                  id: 't0',
                  title: 'Track',
                  duration: 1000,
                  performer: Artist(id: 'a', name: 'Someone'),
                ),
              ],
              playbackMode: PlaybackMode.empty,
              seq: 0,
            ),
          ),
          kalinkaWsApiProvider.overrideWith((ref) => _FakeWsApi(ref)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: MiniPlayer())),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();

      final api = container.read(kalinkaWsApiProvider) as _FakeWsApi;
      expect(api.sent, [const QueueCommand.play()]);
    });
  });

  group('haptics', () {
    Future<_FakeWsApi> pumpTwoTracks(WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: [
          ..._buildOverrides(
            queueState: PlayQueueState(
              playbackState: PlaybackState(
                state: PlayerStateType.playing,
                index: 0,
              ),
              trackList: [
                Track(id: 't0', title: 'First', duration: 100),
                Track(id: 't1', title: 'Second', duration: 100),
              ],
              playbackMode: PlaybackMode.empty,
              seq: 0,
            ),
          ),
          kalinkaWsApiProvider.overrideWith((ref) => _FakeWsApi(ref)),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: MiniPlayer())),
        ),
      );
      await tester.pump();
      return container.read(kalinkaWsApiProvider) as _FakeWsApi;
    }

    testWidgets('a swipe to the next track ticks once', (tester) async {
      final haptics = HapticRecorder.install();
      final api = await pumpTwoTracks(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('First')),
      );
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(-50, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));

      expect(haptics.calls, ['selectionClick']);
      expect(api.sent, [const QueueCommand.next()]);
    });

    testWidgets('the play button is silent', (tester) async {
      final haptics = HapticRecorder.install();
      final api = await pumpTwoTracks(tester);

      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.pump();

      expect(api.sent, isNotEmpty);
      expect(haptics.calls, isEmpty);
    });
  });

  // Note: the playback-error dialog moved out of MiniPlayer into
  // MusicPlayerScreen (it must show in the tablet layout too, where the mini
  // player isn't mounted). MiniPlayer now only surfaces the error as a warning
  // icon (covered by 'play button icons' above); dialog behaviour is covered
  // in playback_error_dialog_test.dart.

  group('offline dimming', () {
    testWidgets('content is dimmed when reconnecting', (tester) async {
      await pumpMiniPlayer(
        tester,
        connectionStatus: ConnectionStatus.reconnecting,
      );

      final opacities = tester
          .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
          .map((w) => w.opacity)
          .toList();
      expect(opacities.contains(0.45), isTrue);
    });

    testWidgets('content is dimmed when offline', (tester) async {
      await pumpMiniPlayer(tester, connectionStatus: ConnectionStatus.offline);

      final opacities = tester
          .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
          .map((w) => w.opacity)
          .toList();
      expect(opacities.contains(0.45), isTrue);
    });

    testWidgets('content is fully visible when connected', (tester) async {
      await pumpMiniPlayer(
        tester,
        connectionStatus: ConnectionStatus.connected,
      );

      final opacities = tester
          .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
          .map((w) => w.opacity)
          .toList();
      expect(opacities.contains(0.45), isFalse);
    });
  });

  group('empty queue behaviour', () {
    testWidgets('shows "No track" when queue is empty and stopped', (
      tester,
    ) async {
      await pumpMiniPlayer(
        tester,
        queueState: PlayQueueState(
          playbackState: PlaybackState(state: PlayerStateType.stopped),
          trackList: const [],
          playbackMode: PlaybackMode.empty,
          seq: 0,
        ),
      );

      expect(find.text('No track'), findsOneWidget);
      expect(tester.getSize(find.byType(MiniPlayer)).height, greaterThan(0));
    });

    testWidgets(
      'does not show stale track when queue is cleared but playbackState.currentTrack is still set',
      (tester) async {
        // Simulate the server state after a queue clear: trackList is empty but
        // PlaybackState.currentTrack still holds the old track because copyWith
        // never clears fields to null.
        final staleTrack = Track(
          id: 'stale-id',
          title: 'Stale Track',
          duration: 180,
          performer: Artist(id: 'a1', name: 'Stale Artist'),
        );
        await pumpMiniPlayer(
          tester,
          queueState: PlayQueueState(
            playbackState: PlaybackState(
              state: PlayerStateType.stopped,
              currentTrack: staleTrack,
              index: 0,
            ),
            trackList: const [],
            playbackMode: PlaybackMode.empty,
            seq: 1,
          ),
        );

        expect(find.text('Stale Track'), findsNothing);
        expect(find.text('Stale Artist'), findsNothing);
        expect(find.text('No track'), findsOneWidget);
      },
    );

    Future<void> pumpWithVerdict(WidgetTester tester, PlayQueueState state) =>
        tester
            .pumpWidget(
              ProviderScope(
                overrides: [
                  ..._buildOverrides(queueState: state),
                  bitPerfectProvider.overrideWithValue(true),
                ],
                child: const MaterialApp(home: Scaffold(body: MiniPlayer())),
              ),
            )
            .then((_) => tester.pump());

    testWidgets('does not claim bit-perfect playback beside "No track"', (
      tester,
    ) async {
      // audioInfo survives a queue clear the same way currentTrack does, so
      // the verdict can still read true with nothing playing.
      await pumpWithVerdict(
        tester,
        PlayQueueState(
          playbackState: PlaybackState(state: PlayerStateType.stopped),
          trackList: const [],
          playbackMode: PlaybackMode.empty,
          seq: 1,
        ),
      );

      expect(find.text('No track'), findsOneWidget);
      expect(find.text('1:1'), findsNothing);
    });

    testWidgets('shows the bit-perfect chip while a track is playing', (
      tester,
    ) async {
      final track = Track(id: 'tid', title: 'Playing', duration: 200);
      await pumpWithVerdict(
        tester,
        PlayQueueState(
          playbackState: PlaybackState(
            state: PlayerStateType.playing,
            currentTrack: track,
            index: 0,
          ),
          trackList: [track],
          playbackMode: PlaybackMode.empty,
          seq: 1,
        ),
      );

      expect(find.text('1:1'), findsOneWidget);
    });

    testWidgets('shows "No track" after playing track is removed from queue', (
      tester,
    ) async {
      final track = Track(id: 'tid', title: 'Now Playing', duration: 200);
      final container = ProviderContainer(
        overrides: _buildOverrides(
          queueState: PlayQueueState(
            playbackState: PlaybackState(
              state: PlayerStateType.playing,
              currentTrack: track,
              index: 0,
            ),
            trackList: [track],
            playbackMode: PlaybackMode.empty,
            seq: 0,
          ),
        ),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: MiniPlayer())),
        ),
      );
      await tester.pump();

      expect(find.text('Now Playing'), findsOneWidget);

      // Simulate the server clearing the queue: empty trackList + stopped state,
      // stale currentTrack still present in playbackState.
      (container.read(playQueueStateStoreProvider.notifier)
              as _SettableQueueNotifier)
          .emit(
            PlayQueueState(
              playbackState: PlaybackState(
                state: PlayerStateType.stopped,
                currentTrack: track, // stale — never cleared by copyWith
                index: 0,
              ),
              trackList: const [],
              playbackMode: PlaybackMode.empty,
              seq: 1,
            ),
          );
      await tester.pump();

      expect(find.text('Now Playing'), findsNothing);
      expect(find.text('No track'), findsOneWidget);
    });
  });

  group('plugin playback', () {
    const qobuz = PlaybackControl.exclusive(
      pluginId: 'qobuz',
      title: 'Qobuz Connect',
    );
    final connect = Track(
      id: 'kalinka:qobuz:track:111',
      title: 'Connect song',
      duration: 240,
      performer: Artist(id: 'p', name: 'Connect artist'),
    );

    PlayQueueState held(
      PlayerStateType state, {
      List<Track> queue = const [],
    }) => PlayQueueState(
      playbackState: PlaybackState(
        state: state,
        currentTrack: connect,
        index: 0,
      ),
      trackList: queue,
      playbackMode: PlaybackMode.empty,
      seq: 1,
      playbackControl: qobuz,
    );

    ModuleInfo module(String name, String title, {String? icon}) => ModuleInfo(
      name: name,
      title: title,
      enabled: true,
      state: ModuleState.ready,
      icon: icon,
    );

    Future<_FakeWsApi> pumpHeld(
      WidgetTester tester,
      PlayQueueState state, {
      List<ModuleInfo>? modules,
    }) async {
      final container = ProviderContainer(
        overrides: [
          ..._buildOverrides(queueState: state),
          kalinkaWsApiProvider.overrideWith((ref) => _FakeWsApi(ref)),
          sourceModulesProvider.overrideWith(
            (ref) => modules ?? [module('qobuz', 'Qobuz')],
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: MiniPlayer())),
        ),
      );
      await tester.pump();
      return container.read(kalinkaWsApiProvider) as _FakeWsApi;
    }

    testWidgets('shows the plugin\'s track with an empty queue', (
      tester,
    ) async {
      await pumpHeld(tester, held(PlayerStateType.playing));

      expect(find.text('Connect song'), findsOneWidget);
      expect(find.text('Connect artist'), findsOneWidget);
      expect(find.text('No track'), findsNothing);
    });

    testWidgets(
      'badges the track with its source\'s icon, not the plugin\'s title',
      (tester) async {
        await pumpHeld(
          tester,
          held(PlayerStateType.playing),
          modules: [
            module('qobuz', 'Qobuz', icon: 'waves_outlined'),
            module('localfiles', 'My Library'),
          ],
        );

        expect(find.byIcon(Icons.waves_outlined), findsOneWidget);
        expect(find.text('Qobuz Connect'), findsNothing);
      },
    );

    testWidgets('shows the plugin\'s track, not the queue\'s at that index', (
      tester,
    ) async {
      final queued = Track(id: 'q', title: 'Queued song', duration: 100);
      await pumpHeld(tester, held(PlayerStateType.playing, queue: [queued]));

      expect(find.text('Connect song'), findsOneWidget);
      expect(find.text('Queued song'), findsNothing);
    });

    testWidgets('pause and resume go to the plugin', (tester) async {
      final playing = await pumpHeld(tester, held(PlayerStateType.playing));
      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.pump();
      expect(playing.sent, [const QueueCommand.pause(paused: true)]);
    });

    testWidgets('paused, the button resumes rather than playing the queue', (
      tester,
    ) async {
      final api = await pumpHeld(tester, held(PlayerStateType.paused));
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();
      expect(api.sent, [const QueueCommand.pause(paused: false)]);
    });

    testWidgets(
      'stopped, the button would take the output back, so it sends nothing',
      (tester) async {
        final api = await pumpHeld(tester, held(PlayerStateType.stopped));
        await tester.tap(find.byIcon(Icons.play_arrow_rounded));
        await tester.pump();
        expect(api.sent, isEmpty);
      },
    );
  });

  group('progress line mode', () {
    testWidgets('uses normal mode when connected', (tester) async {
      await pumpMiniPlayer(
        tester,
        connectionStatus: ConnectionStatus.connected,
      );

      final line = tester.widget<GradientProgressLine>(
        find.byType(GradientProgressLine),
      );
      expect(line.mode, GradientProgressLineMode.normal);
    });

    testWidgets('uses reconnecting mode when reconnecting', (tester) async {
      await pumpMiniPlayer(
        tester,
        connectionStatus: ConnectionStatus.reconnecting,
      );

      final line = tester.widget<GradientProgressLine>(
        find.byType(GradientProgressLine),
      );
      expect(line.mode, GradientProgressLineMode.reconnecting);
    });

    testWidgets('uses offline mode when offline', (tester) async {
      await pumpMiniPlayer(tester, connectionStatus: ConnectionStatus.offline);

      final line = tester.widget<GradientProgressLine>(
        find.byType(GradientProgressLine),
      );
      expect(line.mode, GradientProgressLineMode.offline);
    });
  });
}
