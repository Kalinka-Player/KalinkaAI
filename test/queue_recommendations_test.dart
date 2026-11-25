import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/playback_time_provider.dart';
import 'package:kalinka/providers/queue_features_provider.dart';
import 'package:kalinka/providers/server_refusal.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/providers/toast_provider.dart';
import 'package:kalinka/providers/url_resolver.dart';
import 'package:kalinka/widgets/queue_actions.dart';
import 'package:kalinka/widgets/queue_management_tray.dart';
import 'package:kalinka/widgets/queue_zone.dart';
import 'package:kalinka/widgets/up_next_preview.dart';

import 'support/home_shell.dart';
import 'support/queue_server.dart';

/// Says what `/server/version` would, how many similar tracks came, and how
/// many turning Keep playing on added, or holds that answer for [held].
class _QueueApi implements KalinkaPlayerProxy {
  _QueueApi({
    this.version = const {},
    this.similar = 0,
    this.kept = 0,
    this.refusal,
    this.held,
  });

  final Map<String, dynamic> version;
  final int similar;
  final int kept;
  final Exception? refusal;
  final Completer<int>? held;
  int versionAsked = 0;
  int similarAsked = 0;
  final List<bool> keepPlayingSet = [];

  @override
  Future<Map<String, dynamic>> getServerVersion() async {
    versionAsked++;
    return version;
  }

  @override
  Future<int> addSimilarTracks() async {
    similarAsked++;
    if (refusal != null) throw refusal!;
    return similar;
  }

  @override
  Future<int> setKeepPlaying(bool enabled) async {
    keepPlayingSet.add(enabled);
    if (refusal != null) throw refusal!;
    return held?.future ?? (enabled ? kept : 0);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

const _queueBlock = {
  'server_version': '9.9.9',
  'queue': {'keep_playing': false, 'similar': true, 'dislike': true},
};

/// A track from each of [sources] in turn, the one at [index] in [state].
PlayQueueState _queueFrom(
  List<String> sources, {
  int index = 0,
  PlayerStateType state = PlayerStateType.playing,
  bool? keepPlaying,
}) => PlayQueueState(
  playbackState: PlaybackState(index: index, state: state),
  trackList: [
    for (final (i, source) in sources.indexed)
      Track(id: 'kalinka:$source:track:t$i', title: 'Night drive', duration: 1),
  ],
  playbackMode: PlaybackMode.empty,
  seq: 1,
  keepPlaying: keepPlaying,
);

/// Two tracks, the last one playing, with Keep playing off.
final _runOut = _queueFrom(
  ['localfiles', 'localfiles'],
  index: 1,
  keepPlaying: false,
);

class _StillClock extends PlaybackTimeMsNotifier {
  @override
  int build() => 0;
}

ModuleInfo _module(String name, {bool continuation = true}) => ModuleInfo(
  name: name,
  title: name,
  enabled: true,
  state: ModuleState.ready,
  capabilities: [if (continuation) ModuleCapability.continuation],
);

/// [child] in a connected app whose server is [api] and whose queue is
/// [queue], with [modules] as its sources (by default a library that
/// continues) and [more] overrides.
Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget child, {
  required _QueueApi api,
  required PlayQueueState queue,
  List<ModuleInfo>? modules,
  List<Override> more = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      kalinkaProxyProvider.overrideWithValue(api),
      connectionStateProvider.overrideWith(SettableConnection.new),
      playQueueStateStoreProvider.overrideWith(() => SettableQueue(queue)),
      sourceModulesProvider.overrideWith(
        (ref) => modules ?? [_module('localfiles')],
      ),
      ...more,
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );
  return container;
}

/// The queue menu over [queue], acting on its choices as the app does unless
/// [onAction] takes them.
Future<ProviderContainer> _pumpTray(
  WidgetTester tester, {
  Map<String, dynamic> version = _queueBlock,
  PlayQueueState? queue,
  List<ModuleInfo>? modules,
  ValueChanged<TrayAction>? onAction,
  _QueueApi? api,
}) async {
  final container = await _pump(
    tester,
    SingleChildScrollView(
      child: Consumer(
        builder: (context, ref, _) => QueueManagementTrayContent(
          onAction:
              onAction ?? (action) => runQueueTrayAction(context, ref, action),
        ),
      ),
    ),
    api: api ?? _QueueApi(version: version),
    queue: queue ?? _queueFrom(['localfiles']),
    modules: modules,
  );
  await tester.pumpAndSettle();
  return container;
}

const _upNextHeight = 560.0;

/// Where Up next comes to an end: under Now Playing, and in the queue.
enum _UpNext { nowPlaying, queue }

/// [place] over [queue], [width] wide with text at [textScale]. Now Playing's
/// preview fits the room left under [above] where that is set, as the player
/// fits it; otherwise it shows below the fold, as on the phone's sheet.
Future<ProviderContainer> _pumpUpNext(
  WidgetTester tester,
  _UpNext place, {
  required PlayQueueState queue,
  List<ModuleInfo>? modules,
  _QueueApi? api,
  double width = 400,
  double textScale = 1,
  double? above,
}) async {
  final container = await _pump(
    tester,
    Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: SizedBox(
          width: width,
          height: _upNextHeight,
          child: switch (place) {
            _UpNext.nowPlaying => CustomScrollView(
              slivers: [
                if (above != null)
                  SliverToBoxAdapter(child: SizedBox(height: above)),
                SliverUpNextPreview(
                  canOpenQueue: false,
                  fitToSpace: above != null,
                ),
              ],
            ),
            _UpNext.queue => const QueueZone(),
          },
        ),
      ),
    ),
    api: api ?? _QueueApi(),
    queue: queue,
    modules: modules,
    more: [
      playbackTimeMsProvider.overrideWith(_StillClock.new),
      sourceCountProvider.overrideWithValue(1),
      urlResolverProvider.overrideWithValue(UrlResolver('')),
    ],
  );
  await tester.pump();
  return container;
}

void _setQueue(ProviderContainer container, PlayQueueState queue) =>
    (container.read(playQueueStateStoreProvider.notifier) as SettableQueue).set(
      queue,
    );

ServerRefusalException _demoRefusal() => ServerRefusalException(
  DioException(requestOptions: RequestOptions()),
  'demo_read_only',
  'This is a read-only demo server.',
);

void main() {
  group('the queue routes', () {
    test('a dislike is one bare request', () async {
      final server = QueueServer(200, {
        'message': 'Ok',
      }, route: '/queue/dislike');

      expect(await server.api().dislikeCurrent(), isTrue);
      expect(server.requests, ['POST /queue/dislike']);
      expect(server.bodies['POST /queue/dislike'], isNull);
    });

    test('nothing playing to dislike is not an error', () async {
      final server = QueueServer(409, {
        'detail': 'Nothing is playing',
      }, route: '/queue/dislike');

      expect(await server.api().dislikeCurrent(), isFalse);
    });

    test('a refused dislike is told in the server\'s words', () async {
      final server = QueueServer(409, {
        'detail': {'code': 'demo_read_only', 'message': 'Not in the demo.'},
      }, route: '/queue/dislike');

      await expectLater(
        server.api().dislikeCurrent(),
        throwsA(
          isA<ServerRefusalException>().having(
            (e) => '$e',
            'text',
            'Not in the demo.',
          ),
        ),
      );
    });

    test('a server still starting its queue fails the dislike', () async {
      final server = QueueServer(503, {
        'detail': 'The queue is starting',
      }, route: '/queue/dislike');

      await expectLater(
        server.api().dislikeCurrent(),
        throwsA(isA<DioException>()),
      );
    });

    test('similar tracks are asked for without a count', () async {
      for (final added in [3, 0]) {
        final server = QueueServer(200, {
          'message': 'Similar tracks added',
          'count': added,
        }, route: '/queue/similar');

        expect(await server.api().addSimilarTracks(), added);
        expect(server.requests, ['POST /queue/similar']);
        expect(server.queries['POST /queue/similar'], isEmpty);
        expect(server.bodies['POST /queue/similar'], isNull);
      }
    });
  });

  group('what the server says its queue does', () {
    test('the queue block names each feature', () {
      final features = QueueFeatures.fromVersion(_queueBlock);
      expect(features.similar, isTrue);
      expect(features.dislike, isTrue);
      final partial = QueueFeatures.fromVersion({
        'queue': {'similar': true},
      });
      expect(partial.similar, isTrue);
      expect(partial.dislike, isFalse);
    });

    test('a server without the block offers neither', () {
      final older = QueueFeatures.fromVersion({
        'server_version': '5.0.0',
        'api_version': '0.26',
      });
      expect(older.similar, isFalse);
      expect(older.dislike, isFalse);
    });

    test('it is asked only once connected', () async {
      SharedPreferences.setMockInitialValues({});
      final api = _QueueApi(version: _queueBlock);
      final connection = SettableConnection();
      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          kalinkaProxyProvider.overrideWithValue(api),
          connectionStateProvider.overrideWith(() => connection),
        ],
      );
      addTearDown(container.dispose);
      container.read(connectionStateProvider);
      connection.set(ConnectionStatus.connecting);
      final listened = container.listen(queueFeaturesProvider, (_, _) {});

      expect(
        (await container.read(queueFeaturesProvider.future)).dislike,
        isFalse,
      );
      expect(api.versionAsked, 0);
      connection.set(ConnectionStatus.connected);

      expect(
        (await container.read(queueFeaturesProvider.future)).dislike,
        isTrue,
      );
      expect(api.versionAsked, 1);
      // An interruption keeps what the server said until it answers again.
      connection.set(ConnectionStatus.reconnecting);
      await container.pump();
      expect(listened.read().value?.dislike, isTrue);
      expect(api.versionAsked, 1);
    });
  });

  group('Add similar tracks', () {
    final row = find.text('Add similar tracks');

    testWidgets('is offered where the playing track\'s source continues', (
      tester,
    ) async {
      TrayAction? taken;
      await _pumpTray(
        tester,
        version: _queueBlock,
        onAction: (action) => taken = action,
      );

      expect(row, findsOneWidget);
      await tester.tap(row);
      await tester.pump();
      expect(taken, TrayAction.addSimilar);
    });

    testWidgets('is not offered by a server without the queue block', (
      tester,
    ) async {
      await _pumpTray(tester, version: const {'server_version': '5.0.0'});
      expect(row, findsNothing);
    });

    testWidgets('is not offered where the server turns it off', (tester) async {
      await _pumpTray(
        tester,
        version: const {
          'queue': {'similar': false, 'dislike': true},
        },
      );
      expect(row, findsNothing);
    });

    testWidgets('is not offered for a source that suggests nothing', (
      tester,
    ) async {
      await _pumpTray(
        tester,
        version: _queueBlock,
        queue: _queueFrom(['radio']),
        modules: [_module('localfiles'), _module('radio', continuation: false)],
      );
      expect(row, findsNothing);
    });

    for (final (added, said) in [
      (3, 'Added 3 similar tracks'),
      (1, 'Added 1 similar track'),
      (0, 'No similar tracks found'),
    ]) {
      testWidgets('says what came: $said', (tester) async {
        final api = _QueueApi(version: _queueBlock, similar: added);
        final container = await _pumpTray(
          tester,
          version: _queueBlock,
          api: api,
        );

        await tester.tap(row);
        await tester.pump();

        expect(api.similarAsked, 1);
        final toast = container.read(toastProvider).single;
        expect(toast.message, said);
        expect(toast.isError, isFalse);
        await tester.pump(const Duration(seconds: 30));
      });
    }

    for (final (failure, said) in [
      (
        ServerRefusalException(
          DioException(requestOptions: RequestOptions()),
          'queue_full',
          'The queue is full.',
        ),
        'The queue is full.',
      ),
      (Exception('connection reset'), 'Could not add similar tracks'),
    ]) {
      testWidgets('a failure is said as an error: $said', (tester) async {
        final api = _QueueApi(version: _queueBlock, refusal: failure);
        final container = await _pumpTray(
          tester,
          version: _queueBlock,
          api: api,
        );

        await tester.tap(row);
        await tester.pump();

        final toast = container.read(toastProvider).single;
        expect(toast.message, said);
        expect(toast.isError, isTrue);
        await tester.pump(const Duration(seconds: 30));
      });
    }
  });
  group('the Keep playing route', () {
    test('saves the setting and says how many tracks came', () async {
      for (final (enabled, added) in [(true, 4), (true, 0), (false, 0)]) {
        final server = QueueServer(200, {
          'enabled': enabled,
          'count': added,
        }, route: '/queue/keep_playing');

        expect(await server.api().setKeepPlaying(enabled), added);
        expect(server.requests, ['PUT /queue/keep_playing']);
        expect(server.bodies['PUT /queue/keep_playing'], {'enabled': enabled});
      }
    });

    test('a demo server\'s refusal is told in its words', () async {
      final server = QueueServer(403, {
        'detail': {'code': 'demo_read_only', 'message': 'Not in the demo.'},
      }, route: '/queue/keep_playing');

      await expectLater(
        server.api().setKeepPlaying(true),
        throwsA(
          isA<ServerRefusalException>().having(
            (e) => '$e',
            'text',
            'Not in the demo.',
          ),
        ),
      );
    });

    test('a server without the route fails it', () async {
      final server = QueueServer(404, {
        'detail': 'Not Found',
      }, route: '/queue/keep_playing');

      await expectLater(
        server.api().setKeepPlaying(true),
        throwsA(
          isA<DioException>().having(
            (e) => e is ServerRefusalException,
            'a refusal',
            isFalse,
          ),
        ),
      );
    });
  });

  group('what turning Keep playing on would do', () {
    Future<bool> offered(
      PlayQueueState queue, {
      List<ModuleInfo>? modules,
    }) async {
      final container = ProviderContainer(
        overrides: [
          playQueueStateStoreProvider.overrideWith(() => SettableQueue(queue)),
          sourceModulesProvider.overrideWith(
            (ref) => modules ?? [_module('localfiles')],
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sourceModulesProvider.future);
      return container.read(keepPlayingOfferedProvider);
    }

    test(
      'the queue at its last track, playing or played out, goes on',
      () async {
        expect(await offered(_runOut), isTrue);
        expect(
          await offered(
            _queueFrom(
              ['localfiles', 'localfiles'],
              index: 1,
              state: PlayerStateType.stopped,
              keepPlaying: false,
            ),
          ),
          isTrue,
        );
      },
    );

    test('nothing while tracks still follow', () async {
      expect(
        await offered(
          _queueFrom(['localfiles', 'localfiles'], keepPlaying: false),
        ),
        isFalse,
      );
    });

    test(
      'nothing while Keep playing is on, or on a server without it',
      () async {
        for (final keepPlaying in [true, null]) {
          expect(
            await offered(
              _queueFrom(
                ['localfiles', 'localfiles'],
                index: 1,
                keepPlaying: keepPlaying,
              ),
            ),
            isFalse,
          );
        }
      },
    );

    test('one queued source that continues is enough', () async {
      final mixed = _queueFrom(
        ['localfiles', 'radio'],
        index: 1,
        keepPlaying: false,
      );
      expect(
        await offered(
          mixed,
          modules: [
            _module('localfiles'),
            _module('radio', continuation: false),
          ],
        ),
        isTrue,
      );
      expect(
        await offered(
          mixed,
          modules: [
            _module('localfiles', continuation: false),
            _module('radio', continuation: false),
          ],
        ),
        isFalse,
      );
    });

    test('nothing for an empty queue', () async {
      expect(await offered(_queueFrom([], keepPlaying: false)), isFalse);
    });
  });

  group('the Keep playing switch', () {
    final label = find.text('Keep playing');
    Finder switchedOn(bool on) => find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label == 'Keep playing' &&
          widget.properties.toggled == on,
    );

    testWidgets('is not there for a server without the setting', (
      tester,
    ) async {
      await _pumpTray(tester);
      expect(label, findsNothing);
    });

    testWidgets('shows the server\'s setting and follows it', (tester) async {
      final container = await _pumpTray(
        tester,
        queue: _queueFrom(['localfiles'], keepPlaying: true),
      );
      expect(switchedOn(true), findsOneWidget);
      expect(
        find.text('On \u2014 adds tracks like these at the end'),
        findsOneWidget,
      );

      _setQueue(container, _queueFrom(['localfiles'], keepPlaying: false));
      await tester.pumpAndSettle();
      expect(switchedOn(false), findsOneWidget);
      expect(
        find.text('Off \u2014 stops after the last track'),
        findsOneWidget,
      );
    });

    testWidgets('is there where similar tracks are not', (tester) async {
      await _pumpTray(
        tester,
        version: const {'server_version': '5.0.0'},
        queue: _queueFrom(['localfiles'], keepPlaying: false),
      );
      expect(find.text('Add similar tracks'), findsNothing);
      expect(switchedOn(false), findsOneWidget);
    });

    for (final on in [true, false]) {
      testWidgets(
        'turns it ${on ? 'off' : 'on'}, saying nothing where no tracks came',
        (tester) async {
          final api = _QueueApi(version: _queueBlock);
          final container = await _pumpTray(
            tester,
            api: api,
            queue: _queueFrom(['localfiles', 'localfiles'], keepPlaying: on),
          );

          await tester.tap(switchedOn(on));
          await tester.pump();

          expect(api.keepPlayingSet, [!on]);
          expect(container.read(toastProvider), isEmpty);
        },
      );
    }

    for (final (added, said) in [
      (3, 'Keep playing added 3 tracks'),
      (1, 'Keep playing added 1 track'),
      (0, 'No tracks to recommend'),
    ]) {
      testWidgets('turned on where the queue ran out, says what came: $said', (
        tester,
      ) async {
        final api = _QueueApi(version: _queueBlock, kept: added);
        final container = await _pumpTray(tester, api: api, queue: _runOut);

        await tester.tap(switchedOn(false));
        await tester.pump();

        expect(api.keepPlayingSet, [true]);
        final toast = container.read(toastProvider).single;
        expect(toast.message, said);
        expect(toast.isError, isFalse);
        await tester.pump(const Duration(seconds: 30));
      });
    }

    testWidgets('a tap while the last is answered saves nothing more', (
      tester,
    ) async {
      final held = Completer<int>();
      final api = _QueueApi(version: _queueBlock, held: held);
      await _pumpTray(tester, api: api, queue: _runOut);

      await tester.tap(switchedOn(false));
      await tester.pump();
      await tester.tap(switchedOn(false));
      await tester.pump();
      expect(api.keepPlayingSet, [true]);

      held.complete(0);
      await tester.pump();
      await tester.tap(switchedOn(false));
      await tester.pump();
      expect(api.keepPlayingSet, [true, true]);
      await tester.pump(const Duration(seconds: 30));
    });

    testWidgets('a refusal is said in the server\'s words', (tester) async {
      final api = _QueueApi(version: _queueBlock, refusal: _demoRefusal());
      final container = await _pumpTray(tester, api: api, queue: _runOut);

      await tester.tap(switchedOn(false));
      await tester.pump();

      final toast = container.read(toastProvider).single;
      expect(toast.message, 'This is a read-only demo server.');
      expect(toast.isError, isTrue);
      await tester.pump(const Duration(seconds: 30));
    });
  });

  group('where the queue has run out', () {
    final offer = find.text('Turn on Keep playing');
    final message = find.text(
      'No more tracks in the queue. Continue with something similar?',
    );
    final empty = find.text('Queue is empty');

    for (final place in _UpNext.values) {
      testWidgets('${place.name}: offers Keep playing at the last track', (
        tester,
      ) async {
        await _pumpUpNext(tester, place, queue: _runOut);

        expect(message, findsOneWidget);
        expect(offer, findsOneWidget);
        expect(empty, findsNothing);
        expect(
          tester.getCenter(offer).dy,
          greaterThan(tester.getRect(message).bottom),
        );
        expect(
          tester.getCenter(offer).dx,
          closeTo(tester.getCenter(message).dx, 0.5),
        );
        expect(find.byIcon(Icons.all_inclusive_rounded), findsNothing);
      });

      testWidgets(
        '${place.name}: only the button takes the tap, and lights only itself',
        (tester) async {
          final api = _QueueApi();
          await _pumpUpNext(tester, place, queue: _runOut, api: api);

          final inks = find.ancestor(of: offer, matching: find.byType(InkWell));
          expect(inks, findsOneWidget);
          expect(
            tester.widget<InkWell>(inks).customBorder,
            isA<StadiumBorder>(),
          );
          final ink = tester.getRect(inks);
          expect(ink.height, lessThanOrEqualTo(48));
          expect(ink.top, greaterThan(tester.getRect(message).bottom));
          expect(
            find.ancestor(of: message, matching: find.byType(InkWell)),
            findsNothing,
          );
          expect(
            find.ancestor(of: message, matching: find.byType(GestureDetector)),
            findsNothing,
          );

          await tester.tap(message, warnIfMissed: false);
          await tester.pump();
          expect(api.keepPlayingSet, isEmpty);
        },
      );

      testWidgets('${place.name}: offers it once the queue has played out', (
        tester,
      ) async {
        await _pumpUpNext(
          tester,
          place,
          queue: _queueFrom(
            ['localfiles', 'localfiles'],
            index: 1,
            state: PlayerStateType.stopped,
            keepPlaying: false,
          ),
        );

        expect(offer, findsOneWidget);
        expect(empty, findsNothing);
      });

      testWidgets('${place.name}: one tap turns it on once, and plays on', (
        tester,
      ) async {
        final held = Completer<int>();
        final api = _QueueApi(held: held);
        final container = await _pumpUpNext(
          tester,
          place,
          queue: _runOut,
          api: api,
        );

        final button = find.ancestor(of: offer, matching: find.byType(InkWell));
        final before = tester.getRect(button);
        await tester.tap(offer);
        await tester.pump();
        expect(
          find.descendant(
            of: button,
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget,
        );
        expect(tester.getRect(button), before);
        await tester.tap(offer, warnIfMissed: false);
        await tester.pump();
        expect(api.keepPlayingSet, [true]);

        // The server says it is on before it answers; the offer waits for it.
        _setQueue(
          container,
          _queueFrom(['localfiles', 'localfiles'], index: 1, keepPlaying: true),
        );
        await tester.pump();
        expect(offer, findsOneWidget);
        expect(empty, findsNothing);

        held.complete(2);
        await tester.pump();
        final toast = container.read(toastProvider).single;
        expect(toast.message, 'Keep playing added 2 tracks');
        expect(toast.isError, isFalse);
        expect(toast.inPanel, isTrue);
        expect(offer, findsNothing);
        expect(api.keepPlayingSet, [true]);
        await tester.pump(const Duration(seconds: 30));
      });

      testWidgets('${place.name}: says so where nothing could be recommended', (
        tester,
      ) async {
        final api = _QueueApi();
        final container = await _pumpUpNext(
          tester,
          place,
          queue: _runOut,
          api: api,
        );

        await tester.tap(offer);
        await tester.pump();

        expect(api.keepPlayingSet, [true]);
        final toast = container.read(toastProvider).single;
        expect(toast.message, 'No tracks to recommend');
        expect(toast.isError, isFalse);
        await tester.pump(const Duration(seconds: 30));
      });

      testWidgets('${place.name}: goes once Keep playing is on', (
        tester,
      ) async {
        final container = await _pumpUpNext(tester, place, queue: _runOut);
        expect(offer, findsOneWidget);

        _setQueue(
          container,
          _queueFrom(['localfiles', 'localfiles'], index: 1, keepPlaying: true),
        );
        await tester.pump();

        expect(offer, findsNothing);
        expect(empty, findsOneWidget);
      });

      for (final (why, queue, modules) in [
        (
          'Keep playing is on',
          _queueFrom(['localfiles', 'localfiles'], index: 1, keepPlaying: true),
          null,
        ),
        (
          'the server has no Keep playing',
          _queueFrom(['localfiles', 'localfiles'], index: 1),
          null,
        ),
        (
          'no queued source continues',
          _runOut,
          [_module('localfiles', continuation: false)],
        ),
      ]) {
        testWidgets('${place.name}: the queue is empty where $why', (
          tester,
        ) async {
          final api = _QueueApi();
          await _pumpUpNext(
            tester,
            place,
            queue: queue,
            modules: modules,
            api: api,
          );

          expect(empty, findsOneWidget);
          expect(offer, findsNothing);
          await tester.tap(empty);
          await tester.pump();
          expect(api.keepPlayingSet, isEmpty);
        });
      }
    }

    testWidgets('nothing is asked while the server is away', (tester) async {
      final api = _QueueApi();
      final container = await _pumpUpNext(
        tester,
        _UpNext.nowPlaying,
        queue: _runOut,
        api: api,
      );
      (container.read(connectionStateProvider.notifier) as SettableConnection)
          .set(ConnectionStatus.offline);
      await tester.pump();

      await tester.tap(offer, warnIfMissed: false);
      await tester.pump();

      expect(api.keepPlayingSet, isEmpty);
    });

    testWidgets('a refusal is said in the server\'s words', (tester) async {
      final api = _QueueApi(refusal: _demoRefusal());
      final container = await _pumpUpNext(
        tester,
        _UpNext.nowPlaying,
        queue: _runOut,
        api: api,
      );

      await tester.tap(offer);
      await tester.pump();

      final toast = container.read(toastProvider).single;
      expect(toast.message, 'This is a read-only demo server.');
      expect(toast.isError, isTrue);
      expect(toast.inPanel, isTrue);
      expect(offer, findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
    });

    group('in Now Playing\'s preview', () {
      testWidgets('takes the height it needs where the player has room', (
        tester,
      ) async {
        await _pumpUpNext(tester, _UpNext.nowPlaying, queue: _runOut, above: 0);

        expect(offer.hitTestable(), findsOneWidget);
        expect(
          tester
              .getRect(find.byKey(const ValueKey('now-playing-up-next')))
              .bottom,
          lessThanOrEqualTo(_upNextHeight),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('is left out where only a row would fit', (tester) async {
        const tight = _upNextHeight - 48 - 16 - 80;
        await _pumpUpNext(
          tester,
          _UpNext.nowPlaying,
          queue: _runOut,
          above: tight,
        );
        expect(find.byKey(const ValueKey('now-playing-up-next')), findsNothing);

        await _pumpUpNext(
          tester,
          _UpNext.nowPlaying,
          queue: _queueFrom(
            ['localfiles', 'localfiles'],
            index: 1,
            keepPlaying: true,
          ),
          above: tight,
        );
        expect(empty, findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    for (final place in _UpNext.values) {
      for (final (width, textScale) in [
        (320.0, 2.0),
        (320.0, 1.0),
        (400.0, 2.0),
      ]) {
        testWidgets(
          '${place.name}: wraps whole and fits at $width wide, text $textScale',
          (tester) async {
            await _pumpUpNext(
              tester,
              place,
              queue: _runOut,
              width: width,
              textScale: textScale,
              above: place == _UpNext.nowPlaying ? 0 : null,
            );

            expect(tester.takeException(), isNull);
            expect(offer.hitTestable(), findsOneWidget);
            final text = tester.widget<Text>(message);
            expect(text.maxLines, isNull);
            expect(text.overflow, isNull);
            final lines = tester
                .renderObject<RenderParagraph>(message)
                .didExceedMaxLines;
            expect(lines, isFalse);
            final button = tester.getRect(
              find.ancestor(of: offer, matching: find.byType(InkWell)),
            );
            expect(button.left, greaterThanOrEqualTo(0));
            expect(button.right, lessThanOrEqualTo(width));
            expect(button.bottom, lessThanOrEqualTo(_upNextHeight));
          },
        );
      }
    }
  });
}
