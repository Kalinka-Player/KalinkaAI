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
import 'package:kalinka/providers/toast_provider.dart';
import 'package:kalinka/providers/wire_event_provider.dart'
    show playQueueEventBusProvider;
import 'package:kalinka/widgets/kalinka_button.dart';
import 'package:kalinka/widgets/queue_management_tray.dart';
import 'package:kalinka/widgets/search/add_to_collection_sheet.dart';

const _c1 = 'kalinka:collections:playlist:c1';
const _c2 = 'kalinka:collections:playlist:c2';
const _made = 'kalinka:collections:playlist:new';

BrowseItem _collection(String id, String name, int tracks) => BrowseItem(
  id: id,
  name: name,
  canBrowse: true,
  canAdd: true,
  canEdit: true,
  playlist: Playlist(id: id, name: name, trackCount: tracks),
  catalog: Catalog(id: id, title: name, sources: const ['localfiles']),
);

/// A queue that stands still, so the tray can be built without a socket
/// behind it.
class _StillQueue extends PlayQueueStateStore {
  _StillQueue(this.tracks);

  final int tracks;

  @override
  PlayQueueState build() => PlayQueueState(
    playbackState: PlaybackState.empty,
    trackList: [
      for (var i = 0; i < tracks; i++)
        Track(
          id: 'kalinka:localfiles:track:t$i',
          title: 'Track $i',
          duration: 100,
        ),
    ],
    playbackMode: PlaybackMode.empty,
    seq: 0,
  );
}

/// Takes what it is given and says how it went. Records both, so a test can
/// tell what the sheet asked the server for.
class _AddApi implements KalinkaPlayerProxy {
  final List<(String, List<String>, bool)> added = [];
  final List<(String, List<String>, bool)> replaced = [];
  final List<String> created = [];
  final int alreadyThere;

  _AddApi({this.alreadyThere = 0});

  @override
  Future<({int added, int dropped})> replaceCollection(
    String id,
    List<String> itemIds, {
    bool keepDuplicates = false,
  }) async {
    replaced.add((id, itemIds, keepDuplicates));
    return (added: itemIds.length, dropped: 18);
  }

  @override
  Future<({int added, int alreadyThere})> addToCollection(
    String id,
    List<String> itemIds, {
    bool keepDuplicates = false,
  }) async {
    added.add((id, itemIds, keepDuplicates));
    return (added: itemIds.length - alreadyThere, alreadyThere: alreadyThere);
  }

  @override
  Future<String> createCollection(
    String name, {
    String description = '',
  }) async {
    created.add(name);
    return _made;
  }

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

  Future<ProviderContainer> openSheet(
    WidgetTester tester,
    KalinkaPlayerProxy api, {
    List<BrowseItem> choices = const [],
  }) async {
    // A phone-sized surface: the sheet gives its list whatever the header,
    // the switch and the actions leave, and the default 600px test window
    // leaves room for one row.
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        kalinkaProxyProvider.overrideWithValue(api),
        collectionChoicesProvider.overrideWith((ref) => Future.value(choices)),
        playQueueEventBusProvider.overrideWith(
          (ref) => const Stream<PlayQueueEvent>.empty(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAddToCollectionSheet(
                  context,
                  CollectionAddition.queue(const ['t1', 't2']),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return container;
  }

  /// Turns on keeping what the collection already holds.
  Future<void> keepDuplicates(WidgetTester tester) async {
    await tester.tap(find.text('Keep duplicates'));
    await tester.pump();
  }

  /// A toast retires itself on a timer the container outlives; left pending,
  /// it fails the test after the tree is gone.
  Future<void> letToastsGo(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 30));

  final twoCollections = [
    _collection(_c1, 'Late Night Signals', 18),
    _collection(_c2, 'Sunday Morning', 12),
  ];

  testWidgets('both ways out wait until a collection is chosen', (
    tester,
  ) async {
    await openSheet(tester, _AddApi(), choices: twoCollections);

    KalinkaButton action(String label) =>
        tester.widget<KalinkaButton>(find.widgetWithText(KalinkaButton, label));
    expect(action('APPEND').enabled, isFalse);
    expect(action('REPLACE').enabled, isFalse);

    await tester.tap(find.text('Sunday Morning'));
    await tester.pump();

    expect(action('APPEND').enabled, isTrue);
    expect(action('REPLACE').enabled, isTrue);
  });

  testWidgets('adding sends the queue to the one that was chosen', (
    tester,
  ) async {
    final api = _AddApi();
    await openSheet(tester, api, choices: twoCollections);

    await tester.tap(find.text('Sunday Morning'));
    await tester.pump();
    await tester.tap(find.text('APPEND'));
    await tester.pumpAndSettle();

    expect(api.added.single.$1, _c2);
    expect(api.added.single.$2, ['t1', 't2']);
    expect(api.added.single.$3, isFalse);
    expect(find.text('APPEND'), findsNothing);
    await letToastsGo(tester);
  });

  testWidgets('typing narrows the collections offered', (tester) async {
    await openSheet(tester, _AddApi(), choices: twoCollections);

    await tester.enterText(
      find.widgetWithText(TextField, 'Find a collection'),
      'sunday',
    );
    await tester.pump();

    expect(find.text('Sunday Morning'), findsOneWidget);
    expect(find.text('Late Night Signals'), findsNothing);
    expect(find.text('YOUR COLLECTIONS · 1'), findsOneWidget);
  });

  testWidgets('creating one from the sheet adds to what it made', (
    tester,
  ) async {
    final api = _AddApi();
    await openSheet(tester, api, choices: twoCollections);

    await tester.tap(find.text('Create new collection'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Name it'),
      'For the Train',
    );
    await tester.pump();
    await tester.tap(find.text('CREATE'));
    await tester.pumpAndSettle();

    expect(api.created, ['For the Train']);
    expect(api.added.single.$1, _made);
    expect(api.added.single.$2, ['t1', 't2']);
    expect(find.text('APPEND'), findsNothing);
    await letToastsGo(tester);
  });

  testWidgets('what the collection already held is said, not added twice', (
    tester,
  ) async {
    final container = await openSheet(
      tester,
      _AddApi(alreadyThere: 1),
      choices: twoCollections,
    );

    await tester.tap(find.text('Late Night Signals'));
    await tester.pump();
    await tester.tap(find.text('APPEND'));
    await tester.pumpAndSettle();

    expect(
      container.read(toastProvider).single.message,
      'Added 1 track to Late Night Signals · 1 already there',
    );
    await letToastsGo(tester);
  });

  testWidgets('with nothing to choose from, the sheet says where to start', (
    tester,
  ) async {
    await openSheet(tester, _AddApi());

    expect(
      find.text('No collections yet — make the first one above'),
      findsOneWidget,
    );
  });

  testWidgets('replacing a collection with tracks in it asks first', (
    tester,
  ) async {
    final api = _AddApi();
    await openSheet(tester, api, choices: twoCollections);

    await tester.tap(find.text('Late Night Signals'));
    await tester.pump();
    await tester.tap(find.text('REPLACE'));
    await tester.pumpAndSettle();

    expect(find.text('Replace Late Night Signals?'), findsOneWidget);
    expect(api.replaced, isEmpty);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(api.replaced, isEmpty);
    expect(find.text('REPLACE'), findsOneWidget);
  });

  testWidgets('confirming the replace sends the queue in place of it', (
    tester,
  ) async {
    final api = _AddApi();
    await openSheet(tester, api, choices: twoCollections);

    await tester.tap(find.text('Late Night Signals'));
    await tester.pump();
    await tester.tap(find.text('REPLACE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();

    expect(api.replaced.single.$1, _c1);
    expect(api.replaced.single.$2, ['t1', 't2']);
    expect(api.added, isEmpty);
    expect(find.text('REPLACE'), findsNothing);
    await letToastsGo(tester);
  });

  testWidgets('an empty collection is replaced without being asked about', (
    tester,
  ) async {
    final api = _AddApi();
    await openSheet(
      tester,
      api,
      choices: [_collection(_c1, 'Late Night Signals', 0)],
    );

    await tester.tap(find.text('Late Night Signals'));
    await tester.pump();
    await tester.tap(find.text('REPLACE'));
    await tester.pumpAndSettle();

    expect(api.replaced.single.$1, _c1);
    await letToastsGo(tester);
  });

  testWidgets('the switch starts off, so what is already there is skipped', (
    tester,
  ) async {
    await openSheet(tester, _AddApi(), choices: twoCollections);

    expect(
      find.text('Tracks the collection already holds are skipped.'),
      findsOneWidget,
    );

    await keepDuplicates(tester);

    expect(
      find.text('The same track may land more than once.'),
      findsOneWidget,
    );
  });

  testWidgets('the switch travels with the append', (tester) async {
    final api = _AddApi();
    await openSheet(tester, api, choices: twoCollections);
    await keepDuplicates(tester);

    await tester.tap(find.text('Sunday Morning'));
    await tester.pump();
    await tester.tap(find.text('APPEND'));
    await tester.pumpAndSettle();

    expect(api.added.single.$3, isTrue);
    await letToastsGo(tester);
  });

  testWidgets('the switch travels with the replace too', (tester) async {
    final api = _AddApi();
    await openSheet(
      tester,
      api,
      choices: [_collection(_c1, 'Late Night Signals', 0)],
    );
    await keepDuplicates(tester);

    await tester.tap(find.text('Late Night Signals'));
    await tester.pump();
    await tester.tap(find.text('REPLACE'));
    await tester.pumpAndSettle();

    expect(api.replaced.single.$3, isTrue);
    await letToastsGo(tester);
  });

  testWidgets('a collection made here is filled, never replaced', (
    tester,
  ) async {
    final api = _AddApi();
    await openSheet(tester, api, choices: twoCollections);

    await tester.tap(find.text('Create new collection'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Name it'),
      'For the Train',
    );
    await tester.pump();
    await tester.tap(find.text('CREATE'));
    await tester.pumpAndSettle();

    expect(api.replaced, isEmpty);
    expect(api.added.single.$1, _made);
    await letToastsGo(tester);
  });

  testWidgets('the queue tray leads with saving what is queued', (
    tester,
  ) async {
    TrayAction? taken;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          playQueueStateStoreProvider.overrideWith(() => _StillQueue(3)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: QueueManagementTrayContent(
                onAction: (action) => taken = action,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('3 TRACKS'), findsOneWidget);

    await tester.tap(find.text('Save this queue'));
    await tester.pump();

    expect(taken, TrayAction.saveToCollection);
  });

  testWidgets('with nothing queued there is nothing to save', (tester) async {
    TrayAction? taken;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          playQueueStateStoreProvider.overrideWith(() => _StillQueue(0)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: QueueManagementTrayContent(
                onAction: (action) => taken = action,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Save this queue'));
    await tester.pump();

    expect(taken, isNull);
    expect(find.text('Nothing queued to save yet'), findsOneWidget);
  });
}
