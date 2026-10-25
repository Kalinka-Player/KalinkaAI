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
import 'package:kalinka/widgets/clear_all_confirm_dialog.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'support/server_answer.dart';

// Full-screen repro for the clear-all crash with semantics enabled (TalkBack):
// 'identical(childRenderObject, parentRenderObject)' assertion in
// _SemanticsGeometry.computeChildGeometry during flushSemantics.

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
  _FakeApi(this.onClear);
  final void Function() onClear;

  @override
  Future<void> clear() async => onClear();

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

PlayQueueState _queueWithTracks() => PlayQueueState(
  playbackState: PlaybackState(state: PlayerStateType.playing, index: 2),
  trackList: [_track('a'), _track('b'), _track('c'), _track('d'), _track('e')],
  playbackMode: PlaybackMode.empty,
  seq: 0,
);

PlayQueueState _emptyQueue() => PlayQueueState(
  playbackState: PlaybackState(state: PlayerStateType.stopped, index: null),
  trackList: const [],
  playbackMode: PlaybackMode.empty,
  seq: 1,
);

void main() {
  testWidgets('clear all from the tray with semantics enabled does not throw', (
    tester,
  ) async {
    // Tablet/desktop layout (>= 900px wide) — matches the Linux desktop
    // window where the crash was reported.
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    SharedPreferences.setMockInitialValues({
      'Kalinka.host': 'localhost',
      'Kalinka.port': 8080,
      'Kalinka.name': 'Test',
      OnboardingStatusNotifier.sharedPrefOobeComplete: true,
      OnboardingStatusNotifier.sharedPrefCoachMarksShown: true,
    });
    final prefs = await SharedPreferences.getInstance();
    final queueNotifier = _SettableQueueNotifier(_queueWithTracks());
    final api = _FakeApi(() => queueNotifier.set(_emptyQueue()));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          kalinkaProxyProvider.overrideWithValue(api),
          playQueueStateStoreProvider.overrideWith(() => queueNotifier),
          connectionStateProvider.overrideWith(() => _FakeConnectionNotifier()),
          serverAnswering('box-1'),
          playbackTimeMsProvider.overrideWith(
            () => _FakePlaybackTimeNotifier(),
          ),
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
    ProviderScope.containerOf(
      tester.element(find.byType(MusicPlayerScreen)),
    ).read(playerViewProvider.notifier).show(PlayerView.queue);
    await tester.pumpAndSettle();

    // Open the queue management tray.
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    expect(find.text('Clear queue'), findsOneWidget);

    // Pick "Clear queue" → tray closes, 160ms delay, confirm dialog opens.
    await tester.tap(find.text('Clear queue'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('Clear entire queue?'), findsOneWidget);

    // Confirm — the queue empties behind the dialog as it pops, which is the
    // frame that used to assert.
    await tester.tap(
      find.descendant(
        of: find.byType(ClearAllConfirmDialog),
        matching: find.text('Clear queue'),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);

    expect(find.text('Clear entire queue?'), findsNothing);
    expect(find.text('Nothing Queued'), findsOneWidget);

    // Let the toast expire so no timers outlive the test.
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    semantics.dispose();
  });
}
