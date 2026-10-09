import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/widgets/search/track_group_actions.dart';
import 'package:kalinka/widgets/search_cards/search_track_row.dart';

import 'support/queue_server.dart';

const _a = 'kalinka:x:track:a';
const _b = 'kalinka:x:track:b';
const _c = 'kalinka:x:track:c';

BrowseItem _track(String id) => BrowseItem(
  id: id,
  name: 'Track $id',
  canBrowse: false,
  canAdd: true,
  track: Track(id: id, title: 'Track $id', duration: 100),
);

class _EmptyQueue extends PlayQueueStateStore {
  @override
  PlayQueueState build() => PlayQueueState(
    playbackState: PlaybackState(),
    trackList: const [],
    playbackMode: PlaybackMode.empty,
    seq: 0,
  );
}

class _QueueApi implements KalinkaPlayerProxy {
  final List<List<String>> replaced = [];
  final List<int?> played = [];
  int cleared = 0;
  int added = 0;

  @override
  Future<StatusMessage> replace(List<String> items) async {
    replaced.add(items);
    return StatusMessage(count: items.length);
  }

  @override
  Future<StatusMessage> add(List<String> items, {int? index}) async {
    added++;
    return StatusMessage(count: items.length);
  }

  @override
  Future<void> clear() async => cleared++;

  @override
  Future<StatusMessage> play([int? index]) async {
    played.add(index);
    return StatusMessage();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<void> tapIn(
    WidgetTester tester,
    KalinkaPlayerProxy api,
    Widget child,
    Finder target,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          kalinkaProxyProvider.overrideWithValue(api),
          playQueueStateStoreProvider.overrideWith(_EmptyQueue.new),
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
    await tester.pump();
    await tester.tap(target);
    await tester.pumpAndSettle();
    // The result toast retires on a timer the tree must outlive.
    await tester.pump(const Duration(seconds: 30));
  }

  testWidgets('a search track plays its section as the new queue', (
    tester,
  ) async {
    final api = _QueueApi();

    await tapIn(
      tester,
      api,
      SearchTrackRow(item: _track(_b), queueContextIds: const [_a, _b, _c]),
      find.text('Track $_b'),
    );

    expect(api.replaced, [
      [_a, _b, _c],
    ]);
    expect(api.played, [1]);
    expect(api.cleared, 0);
    expect(api.added, 0);
  });

  testWidgets('a search track on its own replaces the queue with itself', (
    tester,
  ) async {
    final api = _QueueApi();

    await tapIn(
      tester,
      api,
      SearchTrackRow(item: _track(_a)),
      find.text('Track $_a'),
    );

    expect(api.replaced, [
      [_a],
    ]);
    expect(api.played, [0]);
    expect(api.cleared, 0);
  });

  testWidgets('play all replaces the queue with the section', (tester) async {
    final api = _QueueApi();

    await tapIn(
      tester,
      api,
      const PlayAllChip(trackIds: [_a, _b]),
      find.text('Play all'),
    );

    expect(api.replaced, [
      [_a, _b],
    ]);
    expect(api.played, [0]);
    expect(api.cleared, 0);
  });

  for (final (status, body, kind) in olderServers) {
    testWidgets('a search track on an older server $kind clears then adds', (
      tester,
    ) async {
      final server = QueueServer(status, body);

      await tapIn(
        tester,
        server.api(),
        SearchTrackRow(item: _track(_b), queueContextIds: const [_a, _b, _c]),
        find.text('Track $_b'),
      );

      expect(server.requests, [
        'POST /queue/replace',
        'PUT /queue/clear',
        'POST /queue/add',
        'PUT /queue/play',
      ]);
      expect(server.bodies['POST /queue/add'], [_a, _b, _c]);
    });
  }
}
