import 'dart:async' show Completer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/catalog_cards_provider.dart';
import 'package:kalinka/providers/collections_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/indexer_status_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/onboarding_provider.dart';
import 'package:kalinka/providers/playback_time_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/providers/url_resolver.dart';
import 'package:kalinka/providers/websocket_provider.dart';
import 'package:kalinka/screens/music_player_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// The queue, set from the test.
class SettableQueue extends PlayQueueStateStore {
  SettableQueue(this._initial);
  final PlayQueueState _initial;

  @override
  PlayQueueState build() => _initial;

  void set(PlayQueueState next) => state = next;
}

/// The connection, connected until set otherwise from the test.
class SettableConnection extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;

  void set(ConnectionStatus next) => state = next;
}

class _StillClock extends PlaybackTimeMsNotifier {
  @override
  int build() => 0;
}

/// The real notifier polls `/indexer/status` on a repeating timer.
class _IdleIndexer extends IndexerStatusNotifier {
  @override
  IndexerStatusState build() => const IndexerStatusState();

  @override
  void acquire() {}

  @override
  void release() {}
}

/// Answers what Home asks for at rest with nothing, and fails anything else.
class HomeApi implements KalinkaPlayerProxy {
  int favouriteCalls = 0;
  int suggestionCalls = 0;

  @override
  Future<BrowseItemsList> getFavorite(
    SearchType queryType, {
    int offset = 0,
    int limit = 10,
    String filter = '',
  }) async {
    favouriteCalls++;
    return BrowseItemsList(0, 0, 0, const []);
  }

  @override
  Future<SearchSuggestionList> searchSuggestions({
    int count = 4,
    int? tzOffsetMin,
  }) async {
    suggestionCalls++;
    return const SearchSuggestionList(suggestions: []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Track homeTrack(String id) => Track(
  id: id,
  title: 'Track $id',
  duration: 200,
  performer: Artist(id: 'a', name: 'Someone'),
);

/// [count] tracks, the one at [index] playing.
PlayQueueState queueOf(int count, {int index = 0}) => PlayQueueState(
  playbackState: PlaybackState(
    state: count == 0 ? PlayerStateType.stopped : PlayerStateType.playing,
    index: count == 0 ? null : index,
  ),
  trackList: [for (var i = 0; i < count; i++) homeTrack('t$i')],
  playbackMode: PlaybackMode.empty,
  seq: 0,
);

/// The main screen, connected, with the queue as [queue] and Home's sections
/// quiet. The window is [size]; [overrides] go after the harness's own.
Future<ProviderContainer> pumpHomeShell(
  WidgetTester tester, {
  required SettableQueue queue,
  HomeApi? api,
  Size size = const Size(400, 800),
  bool coachMarksShown = true,
  List<Override> overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues({
    'Kalinka.host': 'localhost',
    'Kalinka.port': 8080,
    'Kalinka.name': 'Test',
    OnboardingStatusNotifier.sharedPrefOobeComplete: true,
    OnboardingStatusNotifier.sharedPrefCoachMarksShown: coachMarksShown,
  });
  final prefs = await SharedPreferences.getInstance();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      kalinkaProxyProvider.overrideWithValue(api ?? HomeApi()),
      playQueueStateStoreProvider.overrideWith(() => queue),
      connectionStateProvider.overrideWith(SettableConnection.new),
      playbackTimeMsProvider.overrideWith(_StillClock.new),
      indexerStatusProvider.overrideWith(_IdleIndexer.new),
      sourceModulesProvider.overrideWith((ref) => <ModuleInfo>[]),
      sourceCountProvider.overrideWithValue(1),
      catalogCardGroupsProvider.overrideWith(
        (ref) async => const <CatalogCardGroup>[],
      ),
      collectionsShelfProvider.overrideWith((ref) async => null),
      // The real family dials a socket and arms a 5s connect timeout that
      // outlives the test; a never-completing future keeps it inert.
      webSocketProvider.overrideWith(
        (ref, path) => Completer<WebSocketChannel>().future,
      ),
      urlResolverProvider.overrideWithValue(UrlResolver('')),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: MusicPlayerScreen()),
    ),
  );
  if (coachMarksShown) {
    await tester.pumpAndSettle();
  } else {
    // The tour's spotlight never stops moving.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }
  return container;
}
