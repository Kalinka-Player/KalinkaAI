import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/kalinka_ws_api.dart';
import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/indexer_status_provider.dart';
import 'package:kalinka/providers/kalinka_ws_api_provider.dart';
import 'package:kalinka/providers/playback_time_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/providers/url_resolver.dart';
import 'package:kalinka/widgets/queue_zone.dart';
import 'package:kalinka/widgets/search_cards/action_pill_button.dart';

// While a plugin plays exclusively, the queue screen says whose queue plays
// now, lists Kalinka's own queue whole as not playing, and offers to play it.

class _SettableQueueNotifier extends PlayQueueStateStore {
  _SettableQueueNotifier(this._initial);
  final PlayQueueState _initial;

  @override
  PlayQueueState build() => _initial;

  void emit(PlayQueueState next) => state = next;
}

class _Connected extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

class _Time extends PlaybackTimeMsNotifier {
  @override
  int build() => 0;
}

class _IdleIndexer extends IndexerStatusNotifier {
  @override
  IndexerStatusState build() => const IndexerStatusState();

  @override
  void acquire() {}

  @override
  void release() {}
}

class _Api extends KalinkaWsApi {
  _Api(super.ref);
  final List<QueueCommand> sent = [];

  @override
  Future<void> sendQueueCommand(QueueCommand command) async {
    sent.add(command);
  }
}

const _qobuz = PlaybackControl.exclusive(
  pluginId: 'qobuz',
  title: 'Qobuz Connect',
);

Track _track(String id) => Track(id: id, title: 'Track $id', duration: 200);

PlayQueueState _state(List<Track> tracks, {PlaybackControl control = _qobuz}) =>
    PlayQueueState(
      playbackState: PlaybackState(
        state: PlayerStateType.playing,
        index: tracks.isEmpty ? null : 1,
      ),
      trackList: tracks,
      playbackMode: PlaybackMode.empty,
      seq: 0,
      playbackControl: control,
    );

typedef _Pumped = ({_Api api, _SettableQueueNotifier queue});

Future<_Pumped> _pump(WidgetTester tester, PlayQueueState state) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        playQueueStateStoreProvider.overrideWith(
          () => _SettableQueueNotifier(state),
        ),
        connectionStateProvider.overrideWith(() => _Connected()),
        playbackTimeMsProvider.overrideWith(() => _Time()),
        indexerStatusProvider.overrideWith(_IdleIndexer.new),
        kalinkaWsApiProvider.overrideWith((ref) => _Api(ref)),
        sourceCountProvider.overrideWithValue(1),
        sourceModulesProvider.overrideWith(
          (ref) => [
            ModuleInfo(
              name: 'qobuz',
              title: 'Qobuz',
              enabled: true,
              state: ModuleState.ready,
            ),
          ],
        ),
        urlResolverProvider.overrideWithValue(UrlResolver('')),
      ],
      // Disposed with the tree, so the providers' timers go with it.
      child: const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 400, height: 700, child: QueueZone()),
        ),
      ),
    ),
  );
  await tester.pump();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(QueueZone)),
  );
  return (
    api: container.read(kalinkaWsApiProvider) as _Api,
    queue:
        container.read(playQueueStateStoreProvider.notifier)
            as _SettableQueueNotifier,
  );
}

bool _dimmed(WidgetTester tester, Finder finder) => tester
    .widgetList<Opacity>(
      find.ancestor(of: finder, matching: find.byType(Opacity)),
    )
    .any((o) => o.opacity < 1);

void main() {
  testWidgets('says which app manages the queue that plays now', (
    tester,
  ) async {
    await _pump(tester, _state([_track('a')]));

    expect(find.text('Playback queue is managed by Qobuz'), findsOneWidget);
  });

  testWidgets('lists the saved queue whole, as not playing', (tester) async {
    await _pump(tester, _state([_track('a'), _track('b'), _track('c')]));

    expect(find.text('SAVED KALINKA QUEUE'), findsOneWidget);
    expect(find.text('3 tracks · Not playing'), findsOneWidget);
    expect(find.text('Track a'), findsOneWidget);
    expect(find.text('Track b'), findsOneWidget);
    expect(find.text('Track c'), findsOneWidget);
    expect(find.text('NOW PLAYING'), findsNothing);
    expect(find.text('UP NEXT'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the saved queue is set back, its Play queue is not', (
    tester,
  ) async {
    await _pump(tester, _state([_track('a')]));

    expect(_dimmed(tester, find.text('Track a')), isTrue);
    expect(_dimmed(tester, find.text('Play queue')), isFalse);
  });

  testWidgets('Play queue plays the queue again', (tester) async {
    final pumped = await _pump(tester, _state([_track('a'), _track('b')]));

    await tester.tap(find.text('Play queue'));
    await tester.pump();

    expect(pumped.api.sent, [const QueueCommand.play()]);
  });

  testWidgets('Play queue is the accent pill Play all is', (tester) async {
    await _pump(tester, _state([_track('a')]));

    final pill = tester.widget<ActionPillButton>(
      find.widgetWithText(ActionPillButton, 'Play queue'),
    );
    expect(pill.accent, isTrue);
  });

  testWidgets('an empty queue offers nothing to play', (tester) async {
    await _pump(tester, _state(const []));

    expect(find.text('Playback queue is managed by Qobuz'), findsOneWidget);
    expect(find.text('No tracks · Not playing'), findsOneWidget);
    expect(find.text('Play queue'), findsNothing);
    expect(find.text('Nothing Queued'), findsOneWidget);
  });

  testWidgets('with the queue back in control, it is grouped as before', (
    tester,
  ) async {
    final pumped = await _pump(tester, _state([_track('a'), _track('b')]));

    pumped.queue.emit(
      _state([
        _track('a'),
        _track('b'),
      ], control: const PlaybackControl.queue()),
    );
    await tester.pump();

    expect(find.text('SAVED KALINKA QUEUE'), findsNothing);
    expect(find.text('Playback queue is managed by Qobuz'), findsNothing);
    expect(find.text('UP NEXT'), findsOneWidget);
    expect(_dimmed(tester, find.text('Track b')), isFalse);
  });
}
