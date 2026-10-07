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
import 'package:kalinka/widgets/selection_overlay.dart';

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

/// Takes what the bar sends and remembers it, so a test can tell what was
/// asked for and where it was meant to land.
class _QueueApi implements KalinkaPlayerProxy {
  final List<(List<String>, int?)> added = [];
  int cleared = 0;

  @override
  Future<StatusMessage> add(List<String> items, {int? index}) async {
    added.add((items, index));
    return StatusMessage(count: items.length);
  }

  @override
  Future<StatusMessage> clear() async {
    cleared++;
    return StatusMessage();
  }

  @override
  Future<StatusMessage> play([int? index]) async => StatusMessage();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
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
    KalinkaPlayerProxy api,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
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

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('the bar offers three things to do with a selection', (
    tester,
  ) async {
    await openBar(tester, _QueueApi());

    expect(find.text('2 selected'), findsOneWidget);
    expect(find.text('Play now'), findsOneWidget);
    expect(find.text('Queue…'), findsOneWidget);
    expect(find.text('Collection'), findsOneWidget);
    // Where in the queue is a question the bar has not asked yet.
    expect(find.text('Play next'), findsNothing);
    expect(find.text('Enqueue'), findsNothing);
  });

  testWidgets('queueing asks where before it queues anything', (tester) async {
    final api = _QueueApi();
    await openBar(tester, api);

    await tap(tester, 'Queue…');

    expect(find.text('QUEUE 2 TRACKS'), findsOneWidget);
    expect(find.text('Play next'), findsOneWidget);
    expect(find.text('Enqueue'), findsOneWidget);
    expect(api.added, isEmpty);
  });

  testWidgets('the way back leaves the selection as it was', (tester) async {
    final container = await openBar(tester, _QueueApi());

    await tap(tester, 'Queue…');
    await tester.tap(find.bySemanticsLabel('Back to actions'));
    await tester.pumpAndSettle();

    expect(find.text('Play now'), findsOneWidget);
    expect(find.text('Play next'), findsNothing);
    expect(container.read(selectionStateProvider).count, 2);
  });

  testWidgets('enqueueing sends the selection to the end of the queue', (
    tester,
  ) async {
    final api = _QueueApi();
    final container = await openBar(tester, api);

    await tap(tester, 'Queue…');
    await tap(tester, 'Enqueue');

    expect(api.added.single.$1, unorderedEquals([_t1, _t2]));
    expect(api.added.single.$2, isNull);
    expect(container.read(selectionStateProvider).isActive, isFalse);
    await letToastsGo(tester);
  });

  testWidgets('playing next sends it in after the track playing', (
    tester,
  ) async {
    final api = _QueueApi();
    await openBar(tester, api);

    await tap(tester, 'Queue…');
    await tap(tester, 'Play next');

    expect(api.added.single.$2, 2);
    expect(api.cleared, 0);
    await letToastsGo(tester);
  });

  testWidgets('the collection button opens the destination sheet', (
    tester,
  ) async {
    final container = await openBar(tester, _QueueApi());

    await tap(tester, 'Collection');

    expect(find.text('ADD SELECTION TO COLLECTION'), findsOneWidget);
    expect(find.text('2 items selected'), findsOneWidget);
    // Nothing has landed anywhere, so the selection is still there to save.
    expect(container.read(selectionStateProvider).count, 2);
  });

  testWidgets('a folder is counted as a folder and queued whole', (
    tester,
  ) async {
    const folder = 'kalinka:localfiles:catalog:folder.L211c2lj';
    final api = _QueueApi();
    final container = await openBar(tester, api);
    container.read(selectionStateProvider.notifier).toggleContainer(folder);
    await tester.pumpAndSettle();

    expect(find.text('3 selected'), findsOneWidget);
    expect(find.text('2 tracks · 1 folder'), findsOneWidget);

    await tap(tester, 'Queue…');
    await tap(tester, 'Enqueue');

    expect(api.added.single.$1, unorderedEquals([_t1, _t2, folder]));
    await letToastsGo(tester);
  });
}
