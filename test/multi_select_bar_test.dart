import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/collections_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/selection_state_provider.dart';
import 'package:kalinka/providers/toast_provider.dart';
import 'package:kalinka/widgets/selection_overlay.dart';

import 'support/queue_api.dart';
import 'support/queue_server.dart';

const _t1 = 'kalinka:localfiles:track:t1';
const _t2 = 'kalinka:localfiles:track:t2';

/// A queue standing at [index], so what plays next has a place to go.
class _StillQueue extends PlayQueueStateStore {
  _StillQueue(this.index);

  final int index;

  @override
  PlayQueueState build() => PlayQueueState(
    playbackState: PlaybackState(index: index),
    trackList: const [],
    playbackMode: PlaybackMode.empty,
    seq: 0,
  );
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'Kalinka.host': 'localhost',
      'Kalinka.port': 8080,
      'Kalinka.name': 'Test',
    });
    prefs = await SharedPreferences.getInstance();
  });

  /// The bar over a selection of two tracks, as a listing would raise it.
  Future<ProviderContainer> openBar(
    WidgetTester tester,
    KalinkaPlayerProxy api, {
    double width = 1000,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        kalinkaProxyProvider.overrideWithValue(api),
        playQueueStateStoreProvider.overrideWith(() => _StillQueue(1)),
        collectionChoicesProvider.overrideWith(
          (ref) => Future.value(const <BrowseItem>[]),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(selectionStateProvider.notifier).selectTracks([_t1, _t2]);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: MultiSelectBottomBar(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  /// A toast retires itself on a timer the container outlives; left pending,
  /// it fails the test after the tree is gone.
  Future<void> letToastsGo(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 30));

  Future<void> tap(WidgetTester tester, String action) async {
    await tester.tap(find.text(action));
    await tester.pumpAndSettle();
  }

  const actions = ['Play all', 'Enqueue', 'Play next', 'Add to collection'];

  testWidgets('the bar offers four things to do with a selection', (
    tester,
  ) async {
    await openBar(tester, QueueApi());

    expect(find.textContaining('2 selected'), findsOneWidget);
    for (final action in actions) {
      expect(find.text(action), findsOneWidget, reason: action);
    }
    expect(find.byTooltip('More actions'), findsNothing);
  });

  testWidgets('short of room, a floating bar sets Play next and then Add to '
      'collection behind the chevron', (tester) async {
    await openBar(tester, QueueApi(), width: 760);
    expect(find.text('Play next'), findsNothing);
    expect(find.text('Add to collection'), findsOneWidget);

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    expect(find.text('Play all'), findsNothing);
    expect(find.text('Play next'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Play all'), findsOneWidget);
    expect(find.text('Play next'), findsNothing);
  });

  testWidgets('a docked bar scrolls its actions sideways', (tester) async {
    await openBar(tester, QueueApi(), width: 400);
    expect(find.byTooltip('More actions'), findsNothing);
    for (final action in actions) {
      expect(find.text(action), findsOneWidget, reason: action);
    }
    expect(find.text('Add to collection').hitTestable(), findsNothing);

    await tester.drag(find.text('Enqueue'), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.text('Add to collection').hitTestable(), findsOneWidget);
  });

  testWidgets('the cross drops the selection', (tester) async {
    final container = await openBar(tester, QueueApi());

    await tester.tap(find.byTooltip('Cancel selection'));
    await tester.pumpAndSettle();

    expect(container.read(selectionStateProvider).isActive, isFalse);
  });

  testWidgets('enqueueing sends the selection to the end of the queue', (
    tester,
  ) async {
    final api = QueueApi();
    final container = await openBar(tester, api);

    await tap(tester, 'Enqueue');

    expect(api.added.single.$1, unorderedEquals([_t1, _t2]));
    expect(api.added.single.$2, isNull);
    expect(container.read(selectionStateProvider).isActive, isFalse);
    await letToastsGo(tester);
  });

  testWidgets('playing next sends it in after the track playing', (
    tester,
  ) async {
    final api = QueueApi();
    await openBar(tester, api);

    await tap(tester, 'Play next');

    expect(api.added.single.$2, 2);
    expect(api.cleared, 0);
    await letToastsGo(tester);
  });

  testWidgets('playing now replaces the queue in one request', (tester) async {
    final api = QueueApi();
    final container = await openBar(tester, api);

    await tap(tester, 'Play all');

    expect(api.replaced.single, unorderedEquals([_t1, _t2]));
    expect(api.cleared, 0);
    expect(api.added, isEmpty);
    expect(api.played, [0]);
    expect(container.read(selectionStateProvider).isActive, isFalse);
    await letToastsGo(tester);
  });

  testWidgets('a refused play neither clears the queue nor plays', (
    tester,
  ) async {
    final api = QueueApi(refusal: Exception('The queue is full.'));
    final container = await openBar(tester, api);

    await tap(tester, 'Play all');

    expect(api.cleared, 0);
    expect(api.added, isEmpty);
    expect(api.played, isEmpty);
    final toast = container.read(toastProvider).single;
    expect(toast.isError, isTrue);
    expect(toast.message, contains('The queue is full.'));
    await letToastsGo(tester);
  });

  for (final (status, body, kind) in olderServers) {
    testWidgets('playing now on an older server $kind clears then adds', (
      tester,
    ) async {
      final server = QueueServer(status, body);
      await openBar(tester, server.api());

      await tap(tester, 'Play all');

      expect(server.requests, [
        'POST /queue/replace',
        'PUT /queue/clear',
        'POST /queue/add',
        'PUT /queue/play',
      ]);
      await letToastsGo(tester);
    });
  }

  testWidgets('Add to collection opens the collection destination sheet', (
    tester,
  ) async {
    final container = await openBar(tester, QueueApi());

    await tap(tester, 'Add to collection');

    expect(find.text('ADD SELECTION TO COLLECTION'), findsOneWidget);
    expect(find.text('2 items selected'), findsOneWidget);
    // Nothing has landed anywhere, so the selection is still there to save.
    expect(container.read(selectionStateProvider).count, 2);
  });

  testWidgets('a folder is counted as a folder and queued whole', (
    tester,
  ) async {
    const folder = 'kalinka:localfiles:catalog:folder.L211c2lj';
    final api = QueueApi();
    final container = await openBar(tester, api);
    container.read(selectionStateProvider.notifier).toggleContainer(folder);
    await tester.pumpAndSettle();

    expect(find.textContaining('3 selected'), findsOneWidget);
    expect(find.textContaining('2 tracks · 1 folder'), findsOneWidget);

    await tap(tester, 'Enqueue');

    expect(api.added.single.$1, unorderedEquals([_t1, _t2, folder]));
    await letToastsGo(tester);
  });
}
