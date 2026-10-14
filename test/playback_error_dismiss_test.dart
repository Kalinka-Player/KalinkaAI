import 'dart:async' show Completer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/onboarding_provider.dart';
import 'package:kalinka/providers/playback_time_provider.dart';
import 'package:kalinka/providers/shell_nav_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/providers/url_resolver.dart';
import 'package:kalinka/providers/websocket_provider.dart';
import 'package:kalinka/screens/music_player_screen.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// How a failed track surfaces, driven end to end from server state.
//
// The dialog is raised from server state, so it has to be retired from server
// state too: if another client skips the failing track, the error the dialog
// describes is gone and the dialog must go with it. The queue's own signals —
// the CAN'T PLAY header and the per-row marker — are covered here too, since
// they are what remains once the dialog is gone.

class _SettableQueueNotifier extends PlayQueueStateStore {
  _SettableQueueNotifier(this._initial);
  final PlayQueueState _initial;
  @override
  PlayQueueState build() => _initial;
  void set(PlayQueueState s) => state = s;
}

class _FakeConnectionNotifier extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

class _FakePlaybackTimeNotifier extends PlaybackTimeMsNotifier {
  @override
  int build() => 0;
}

class _FakeApi implements KalinkaPlayerProxy {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Track _track(String id) => Track(
  id: id,
  title: 'Track $id',
  duration: 200000,
  performer: Artist(id: 'a', name: 'Someone'),
);

PlayQueueState _queue({
  required PlayerStateType state,
  required int index,
  String? message,
  required int seq,
}) => PlayQueueState(
  playbackState: PlaybackState(
    state: state,
    index: index,
    currentTrack: _track('t$index'),
    message: message,
  ),
  trackList: [_track('t0'), _track('t1'), _track('t2')],
  playbackMode: PlaybackMode.empty,
  seq: seq,
);

Future<_SettableQueueNotifier> _pumpScreen(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'Kalinka.host': 'localhost',
    'Kalinka.port': 8080,
    'Kalinka.name': 'Test',
    OnboardingStatusNotifier.sharedPrefOobeComplete: true,
    OnboardingStatusNotifier.sharedPrefCoachMarksShown: true,
  });
  final prefs = await SharedPreferences.getInstance();
  final queueNotifier = _SettableQueueNotifier(
    _queue(state: PlayerStateType.playing, index: 0, seq: 0),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        kalinkaProxyProvider.overrideWithValue(_FakeApi()),
        playQueueStateStoreProvider.overrideWith(() => queueNotifier),
        connectionStateProvider.overrideWith(() => _FakeConnectionNotifier()),
        playbackTimeMsProvider.overrideWith(() => _FakePlaybackTimeNotifier()),
        sourceModulesProvider.overrideWith((ref) => <ModuleInfo>[]),
        // The real family dials a socket and arms a 5s connect timeout that
        // outlives the test; a never-completing future keeps it inert.
        webSocketProvider.overrideWith(
          (ref, path) => Completer<WebSocketChannel>().future,
        ),
        sourceCountProvider.overrideWithValue(1),
        urlResolverProvider.overrideWithValue(UrlResolver('')),
      ],
      child: const MaterialApp(home: MusicPlayerScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return queueNotifier;
}

void main() {
  testWidgets('a track change from the server closes the error dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final queue = await _pumpScreen(tester);

    queue.set(
      _queue(
        state: PlayerStateType.error,
        index: 0,
        message: 'Unsupported codec',
        seq: 1,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unsupported codec'), findsOneWidget);

    // Another client hits "next": the server pushes the new track, playing.
    queue.set(_queue(state: PlayerStateType.playing, index: 1, seq: 2));
    await tester.pumpAndSettle();

    expect(find.text('Unsupported codec'), findsNothing);
    expect(find.text('Playback error'), findsNothing);
  });

  testWidgets('recovering on the same track closes the error dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final queue = await _pumpScreen(tester);

    queue.set(
      _queue(
        state: PlayerStateType.error,
        index: 0,
        message: 'Network down',
        seq: 1,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Playback error'), findsOneWidget);

    queue.set(_queue(state: PlayerStateType.playing, index: 0, seq: 2));
    await tester.pumpAndSettle();

    expect(find.text('Playback error'), findsNothing);
  });

  testWidgets('the queue reports the failure in its header and on the row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final queue = await _pumpScreen(tester);
    ProviderScope.containerOf(
      tester.element(find.byType(MusicPlayerScreen)),
    ).read(queuePageProvider.notifier).open();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.error_outline), findsNothing);

    queue.set(
      _queue(
        state: PlayerStateType.error,
        index: 0,
        message: 'Unsupported codec',
        seq: 1,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("CAN'T PLAY"), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsWidgets);

    // The marker outlives the dialog: another client skips on, the row the
    // user just watched fail stays flagged.
    queue.set(_queue(state: PlayerStateType.playing, index: 1, seq: 2));
    await tester.pumpAndSettle();

    expect(find.text('Playback error'), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsWidgets);
  });

  testWidgets('a second error on a new track replaces the dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final queue = await _pumpScreen(tester);

    queue.set(
      _queue(
        state: PlayerStateType.error,
        index: 0,
        message: 'Unsupported codec',
        seq: 1,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unsupported codec'), findsOneWidget);

    queue.set(
      _queue(
        state: PlayerStateType.error,
        index: 1,
        message: 'File not found',
        seq: 2,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unsupported codec'), findsNothing);
    expect(find.text('File not found'), findsOneWidget);
    expect(find.text('Playback error'), findsOneWidget);
  });
}
