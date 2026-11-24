import 'package:dio/dio.dart';
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
import 'package:kalinka/providers/queue_features_provider.dart';
import 'package:kalinka/providers/server_refusal.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/providers/toast_provider.dart';
import 'package:kalinka/widgets/queue_actions.dart';
import 'package:kalinka/widgets/queue_management_tray.dart';

import 'support/home_shell.dart';
import 'support/queue_server.dart';

/// Says what `/server/version` would, and how many similar tracks came.
class _QueueApi implements KalinkaPlayerProxy {
  _QueueApi({this.version = const {}, this.similar = 0, this.refusal});

  final Map<String, dynamic> version;
  final int similar;
  final Exception? refusal;
  int versionAsked = 0;
  int similarAsked = 0;

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
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

const _queueBlock = {
  'server_version': '9.9.9',
  'queue': {'autoplay': true, 'similar': true, 'dislike': true},
};

class _Queue extends PlayQueueStateStore {
  _Queue(this.source);

  final String source;

  @override
  PlayQueueState build() => PlayQueueState(
    playbackState: PlaybackState(index: 0, state: PlayerStateType.playing),
    trackList: [
      Track(id: 'kalinka:$source:track:t0', title: 'Night drive', duration: 1),
    ],
    playbackMode: PlaybackMode.empty,
    seq: 1,
  );
}

ModuleInfo _module(String name, {bool continuation = true}) => ModuleInfo(
  name: name,
  title: name,
  enabled: true,
  state: ModuleState.ready,
  capabilities: [if (continuation) ModuleCapability.continuation],
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
    late SharedPreferences prefs;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    Future<ProviderContainer> pumpTray(
      WidgetTester tester, {
      required Map<String, dynamic> version,
      String playing = 'localfiles',
      List<ModuleInfo>? modules,
      ValueChanged<TrayAction>? onAction,
      _QueueApi? api,
    }) async {
      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          kalinkaProxyProvider.overrideWithValue(
            api ?? _QueueApi(version: version),
          ),
          connectionStateProvider.overrideWith(SettableConnection.new),
          playQueueStateStoreProvider.overrideWith(() => _Queue(playing)),
          sourceModulesProvider.overrideWith(
            (ref) => modules ?? [_module('localfiles')],
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Consumer(
                  builder: (context, ref, _) => QueueManagementTrayContent(
                    onAction:
                        onAction ??
                        (action) => runQueueTrayAction(context, ref, action),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    final row = find.text('Add similar tracks');

    testWidgets('is offered where the playing track\'s source continues', (
      tester,
    ) async {
      TrayAction? taken;
      await pumpTray(
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
      await pumpTray(tester, version: const {'server_version': '5.0.0'});
      expect(row, findsNothing);
    });

    testWidgets('is not offered where the server turns it off', (tester) async {
      await pumpTray(
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
      await pumpTray(
        tester,
        version: _queueBlock,
        playing: 'radio',
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
        final container = await pumpTray(
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
        final container = await pumpTray(
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
}
