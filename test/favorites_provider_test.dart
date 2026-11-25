import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/favorites_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/now_playing_provider.dart';
import 'package:kalinka/providers/server_refusal.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/providers/wire_event_provider.dart'
    show playQueueEventBusProvider;

import 'support/favorites_server.dart';
import 'support/home_shell.dart';
import 'support/queue_api.dart';
import 'support/queue_server.dart';

class _FavoritesApi extends QueueApi with FavoritesServer {
  _FavoritesApi([Iterable<String> favorites = const []]) {
    this.favorites.addAll(favorites);
  }
}

PlayQueueState _playing(String id, {bool exclusive = false}) => PlayQueueState(
  playbackState: PlaybackState(index: 0, state: PlayerStateType.playing),
  trackList: [Track(id: id, title: 'Night drive', duration: 1)],
  playbackMode: PlaybackMode.empty,
  playbackControl: exclusive
      ? const PlaybackControl.exclusive(pluginId: 'connect', title: 'Connect')
      : const PlaybackControl.queue(),
  seq: 1,
);

PlayQueueEvent _changed(String id, bool favorite) =>
    PlayQueueEvent.favoriteChanged(id: id, favorite: favorite, seq: 1);

const _qobuzTrack = 'kalinka:qobuz:track:1';
const _qobuzAlbum = 'kalinka:qobuz:album:2';
const _qobuzArtist = 'kalinka:qobuz:artist:3';
const _qobuzPlaylist = 'kalinka:qobuz:playlist:4';
const _tidalTrack = 'kalinka:tidal:track:7';

Future<ProviderContainer> _container({
  PlayQueueState? queue,
  _FavoritesApi? api,
  List<ModuleInfo>? modules,
  StreamController<PlayQueueEvent>? events,
}) async {
  final container = ProviderContainer(
    overrides: [
      kalinkaProxyProvider.overrideWithValue(api ?? _FavoritesApi()),
      connectionStateProvider.overrideWith(SettableConnection.new),
      playQueueStateStoreProvider.overrideWith(
        () => SettableQueue(queue ?? PlayQueueState.empty),
      ),
      sourceModulesProvider.overrideWith(
        (ref) =>
            modules ?? [favoritesSource('qobuz'), favoritesSource('tidal')],
      ),
      playQueueEventBusProvider.overrideWith(
        (ref) => events?.stream ?? const Stream.empty(),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sourceModulesProvider.future);
  return container;
}

void main() {
  group('the favourite ids route', () {
    test(
      'asks for one source\'s, and reads them as the server lists them',
      () async {
        final server = QueueServer(200, {
          'albums': [_qobuzAlbum],
          'artists': [],
          'tracks': [_qobuzTrack, 'kalinka:qobuz:track:3'],
          'playlists': [_qobuzPlaylist],
        }, route: '/favorite/ids');

        final ids = await server.api().getFavoriteIds(source: 'qobuz');

        expect(server.requests, ['GET /favorite/ids']);
        expect(server.queries['GET /favorite/ids'], {'sources': 'qobuz'});
        expect(ids.tracks, [_qobuzTrack, 'kalinka:qobuz:track:3']);
        expect(ids.albums, [_qobuzAlbum]);
        expect(ids.artists, isEmpty);
        expect(ids.playlists, [_qobuzPlaylist]);
      },
    );

    test('asks for every source\'s without one', () async {
      final server = QueueServer(200, {
        'tracks': [_qobuzTrack],
      }, route: '/favorite/ids');

      final ids = await server.api().getFavoriteIds();

      expect(server.queries['GET /favorite/ids'], isEmpty);
      expect(ids.tracks, [_qobuzTrack]);
      expect(ids.playlists, isEmpty);
    });
  });

  group('a favourite\'s change', () {
    const own = 'kalinka:tidal:playlist:9';

    test('is put and deleted by id', () async {
      final server = QueueServer(200, {});

      await server.api().addFavorite(_qobuzAlbum);
      await server.api().removeFavorite(_qobuzAlbum);

      expect(server.requests, [
        'PUT /favorite/add/$_qobuzAlbum',
        'DELETE /favorite/remove/$_qobuzAlbum',
      ]);
    });

    for (final (name, route, change) in [
      (
        'an add',
        '/favorite/add/$own',
        (KalinkaPlayerProxy api) => api.addFavorite(own),
      ),
      (
        'a removal',
        '/favorite/remove/$own',
        (KalinkaPlayerProxy api) => api.removeFavorite(own),
      ),
    ]) {
      test('$name the server will not keep says why in its words', () async {
        final server = QueueServer(422, {
          'detail': {
            'field': 'id',
            'reason': 'A playlist of your own cannot be a favourite.',
          },
        }, route: route);

        await expectLater(
          change(server.api()),
          throwsA(
            isA<ServerRefusalException>()
                .having((e) => e.code, 'code', favoriteRefused)
                .having(
                  (e) => '$e',
                  'words',
                  'A playlist of your own cannot be a favourite.',
                ),
          ),
        );
      });
    }

    test('a change its source could not make says why in its words', () async {
      final server = QueueServer(503, {
        'detail': {'source': 'tidal', 'reason': 'TIDAL sign-in expired.'},
      }, route: '/favorite/add/$own');

      await expectLater(
        server.api().addFavorite(own),
        throwsA(
          isA<ServerRefusalException>()
              .having((e) => e.code, 'code', favoriteUnavailable)
              .having((e) => e.reason, 'reason', 'TIDAL sign-in expired.'),
        ),
      );
    });

    for (final (status, detail) in [
      (409, {'source': 'tidal', 'reason': 'tidal keeps no favourites'}),
      (422, {'field': 'id'}),
      (503, {'source': 'tidal'}),
      (504, {'source': 'tidal', 'reason': 'tidal did not answer'}),
    ]) {
      test('a $status without words for the user is no refusal', () async {
        final server = QueueServer(status, {
          'detail': detail,
        }, route: '/favorite/add/$own');

        await expectLater(
          server.api().addFavorite(own),
          throwsA(
            isA<DioException>()
                .having(
                  (e) => e,
                  'refusal',
                  isNot(isA<ServerRefusalException>()),
                )
                .having((e) => e.response?.statusCode, 'status', status),
          ),
        );
      });
    }

    test('a demo server\'s refusal stays its own', () async {
      final server = QueueServer(403, {
        'detail': {'code': 'demo_read_only', 'message': 'A read-only demo.'},
      }, route: '/favorite/add/$own');

      await expectLater(
        server.api().addFavorite(own),
        throwsA(
          isA<ServerRefusalException>()
              .having((e) => e.code, 'code', 'demo_read_only')
              .having((e) => e.reason, 'reason', 'A read-only demo.'),
        ),
      );
    });
  });

  group('the favourite_changed event', () {
    test('is read from the queue socket', () {
      final event = PlayQueueEvent.fromJson({
        'event_type': 'favorite_changed',
        'id': 'kalinka:tidal:track:11',
        'favorite': true,
      });

      expect(
        event,
        isA<FavoriteChangedEvent>()
            .having((e) => e.id, 'id', 'kalinka:tidal:track:11')
            .having((e) => e.favorite, 'favorite', isTrue),
      );
    });

    test('leaves the queue as it was', () {
      final queue = _playing(_qobuzTrack);
      expect(queue.apply(_changed(_qobuzTrack, true), 0), same(queue));
    });
  });

  group('what can be marked', () {
    String? sourceOf(ProviderContainer container, String id) =>
        favoriteSourceOf(id, container.read(favoriteSourcesProvider));

    test('is a track, album, artist or playlist of a source that keeps '
        'favourites', () async {
      final container = await _container();
      for (final id in [
        _qobuzTrack,
        _qobuzAlbum,
        _qobuzArtist,
        _qobuzPlaylist,
      ]) {
        expect(sourceOf(container, id), 'qobuz');
      }
      expect(sourceOf(container, _tidalTrack), 'tidal');
    });

    test('is nothing of another kind, nor without a source', () async {
      final container = await _container();
      for (final id in [
        'kalinka:qobuz:catalog:new',
        'kalinka:qobuz:genre:jazz',
        'track-without-a-source',
        '',
      ]) {
        expect(sourceOf(container, id), isNull);
      }
    });

    test('is nothing of a source that keeps none', () async {
      final container = await _container(
        modules: [
          favoritesSource('qobuz', favorites: false),
          favoritesSource('tidal'),
        ],
      );
      expect(container.read(favoriteSourcesProvider), {'tidal'});
      expect(sourceOf(container, _qobuzTrack), isNull);
      expect(sourceOf(container, _tidalTrack), 'tidal');
    });

    test('is nothing on a server whose sources list no favourites', () async {
      final container = await _container(
        modules: [favoritesSource('qobuz', favorites: false)],
      );
      expect(container.read(favoriteSourcesProvider), isEmpty);
      expect(sourceOf(container, _qobuzTrack), isNull);
    });

    test('is told again only when a source joins or leaves', () async {
      var modules = [
        favoritesSource('qobuz'),
        favoritesSource('tidal', favorites: false),
      ];
      final container = ProviderContainer(
        overrides: [sourceModulesProvider.overrideWith((ref) => modules)],
      );
      addTearDown(container.dispose);
      final told = <Set<String>>[];
      final listened = container.listen(
        favoriteSourcesProvider,
        (_, next) => told.add(next),
      );
      await container.read(sourceModulesProvider.future);
      await container.pump();
      expect(listened.read(), {'qobuz'});
      told.clear();

      modules = [
        favoritesSource('qobuz'),
        favoritesSource('tidal', favorites: false),
      ];
      container.invalidate(sourceModulesProvider);
      await container.read(sourceModulesProvider.future);
      await container.pump();
      expect(told, isEmpty);

      modules = [favoritesSource('qobuz'), favoritesSource('tidal')];
      container.invalidate(sourceModulesProvider);
      await container.read(sourceModulesProvider.future);
      await container.pump();
      expect(told, [
        {'qobuz', 'tidal'},
      ]);
    });
  });

  group('whether the playing track can be marked', () {
    test('where its own source keeps favourites', () async {
      final container = await _container(queue: _playing(_qobuzTrack));
      expect(container.read(nowPlayingFavoriteProvider), _qobuzTrack);
    });

    test('not where only another source keeps them', () async {
      final container = await _container(
        queue: _playing(_qobuzTrack),
        modules: [
          favoritesSource('qobuz', favorites: false),
          favoritesSource('tidal'),
        ],
      );
      expect(container.read(nowPlayingFavoriteProvider), isNull);
    });

    test('not while a plugin plays, nor with nothing playing', () async {
      for (final queue in [
        _playing(_qobuzTrack, exclusive: true),
        PlayQueueState.empty,
        _playing('track-without-a-source'),
      ]) {
        final container = await _container(queue: queue);
        expect(container.read(nowPlayingFavoriteProvider), isNull);
      }
    });
  });

  group('a source\'s favourites', () {
    test('are asked for that source alone, every kind in one set', () async {
      final api = _FavoritesApi([
        _qobuzTrack,
        _qobuzAlbum,
        _qobuzArtist,
        _qobuzPlaylist,
        _tidalTrack,
      ]);
      final container = await _container(api: api);

      expect(await container.read(favoritesProvider('qobuz').future), {
        _qobuzTrack,
        _qobuzAlbum,
        _qobuzArtist,
        _qobuzPlaylist,
      });
      expect(api.asked, ['qobuz']);
    });

    test('a source that cannot answer costs only its own', () async {
      final api = _FavoritesApi([_tidalTrack])..away.add('qobuz');
      final container = await _container(api: api);
      container.listen(favoritesProvider('qobuz'), (_, _) {});
      container.listen(favoritesProvider('tidal'), (_, _) {});
      await container.pump();
      await container.pump();

      expect(api.asked, unorderedEquals(['qobuz', 'tidal']));
      expect(container.read(favoritesProvider('qobuz')).hasValue, isFalse);
      expect(container.read(favoritesProvider('tidal')).value, {_tidalTrack});
    });

    test('a source briefly away is asked again until it answers', () {
      fakeAsync((async) {
        final api = _FavoritesApi([_qobuzTrack])..away.add('qobuz');
        late ProviderContainer container;
        _container(api: api).then((value) => container = value);
        async.flushMicrotasks();
        container.listen(favoritesProvider('qobuz'), (_, _) {});
        async.flushMicrotasks();
        expect(api.asked, ['qobuz']);
        expect(container.read(favoritesProvider('qobuz')).hasValue, isFalse);

        async.elapse(const Duration(seconds: 1));
        expect(api.asked, ['qobuz', 'qobuz']);
        api.away.clear();
        async.elapse(const Duration(seconds: 2));

        expect(api.asked, ['qobuz', 'qobuz', 'qobuz']);
        expect(container.read(favoritesProvider('qobuz')).value, {_qobuzTrack});
        container.dispose();
      });
    });

    test('a source that stays away is asked only a few times', () {
      expect(
        [for (var count = 0; count < 5; count++) favoritesRetry(count, 'away')],
        [
          const Duration(seconds: 1),
          const Duration(seconds: 2),
          const Duration(seconds: 4),
          const Duration(seconds: 8),
          null,
        ],
      );
    });

    test('are asked again on reconnect, the last kept meanwhile', () async {
      final api = _FavoritesApi([_qobuzTrack]);
      final container = await _container(api: api);
      final listened = container.listen(favoritesProvider('qobuz'), (_, _) {});
      await container.read(favoritesProvider('qobuz').future);
      final connection = container.read(
        connectionStateProvider.notifier,
      ) as SettableConnection;

      connection.set(ConnectionStatus.reconnecting);
      await container.pump();
      expect(api.asked, ['qobuz']);
      api.favorites.add(_qobuzAlbum);
      api.readHeld = Completer<void>();
      connection.set(ConnectionStatus.connected);
      await container.pump();

      expect(api.asked, ['qobuz', 'qobuz']);
      expect(listened.read().value, {_qobuzTrack});
      api.readHeld!.complete();
      expect(await container.read(favoritesProvider('qobuz').future), {
        _qobuzTrack,
        _qobuzAlbum,
      });
    });

    test('a mark shows at once and is sent', () async {
      final api = _FavoritesApi()..held = Completer<void>();
      final container = await _container(api: api);
      final listened = container.listen(favoritesProvider('qobuz'), (_, _) {});
      await container.read(favoritesProvider('qobuz').future);

      final marking = container
          .read(favoritesProvider('qobuz').notifier)
          .toggle(_qobuzAlbum);
      expect(listened.read().value, {_qobuzAlbum});
      api.held!.complete();
      await marking;

      expect(api.marked, [_qobuzAlbum]);
      expect(listened.read().value, {_qobuzAlbum});
      expect(api.asked, ['qobuz']);

      await container
          .read(favoritesProvider('qobuz').notifier)
          .toggle(_qobuzAlbum);
      expect(api.unmarked, [_qobuzAlbum]);
      expect(listened.read().value, isEmpty);
    });

    test('a failed mark takes back only itself and reads again', () async {
      final api = _FavoritesApi(['kalinka:qobuz:track:9'])
        ..failure = Exception('connection reset');
      final container = await _container(api: api);
      final listened = container.listen(favoritesProvider('qobuz'), (_, _) {});
      await container.read(favoritesProvider('qobuz').future);

      await expectLater(
        container.read(favoritesProvider('qobuz').notifier).toggle(_qobuzTrack),
        throwsException,
      );

      expect(listened.read().value, {'kalinka:qobuz:track:9'});
      await container.pump();
      expect(api.asked, ['qobuz', 'qobuz']);
      expect(await container.read(favoritesProvider('qobuz').future), {
        'kalinka:qobuz:track:9',
      });
    });

    test('a change that timed out is read as the server left it', () async {
      final api = _FavoritesApi()
        ..failure = Exception('504')
        ..madeAnyway = true;
      final container = await _container(api: api);
      final listened = container.listen(favoritesProvider('qobuz'), (_, _) {});
      await container.read(favoritesProvider('qobuz').future);

      await expectLater(
        container.read(favoritesProvider('qobuz').notifier).toggle(_qobuzTrack),
        throwsException,
      );
      expect(listened.read().value, isEmpty);

      expect(await container.read(favoritesProvider('qobuz').future), {
        _qobuzTrack,
      });
    });

    test('follow a change made anywhere through the server', () async {
      final events = StreamController<PlayQueueEvent>();
      addTearDown(events.close);
      final api = _FavoritesApi([_qobuzTrack]);
      final container = await _container(api: api, events: events);
      final listened = container.listen(favoritesProvider('qobuz'), (_, _) {});
      await container.read(favoritesProvider('qobuz').future);

      events.add(_changed(_qobuzAlbum, true));
      await container.pump();
      expect(listened.read().value, {_qobuzTrack, _qobuzAlbum});

      events.add(_changed(_qobuzTrack, false));
      await container.pump();
      expect(listened.read().value, {_qobuzAlbum});
      expect(api.asked, ['qobuz']);
    });

    test('ignore a change in a source nothing shows', () async {
      final events = StreamController<PlayQueueEvent>();
      addTearDown(events.close);
      final api = _FavoritesApi([_qobuzTrack]);
      final container = await _container(api: api, events: events);
      final listened = container.listen(favoritesProvider('qobuz'), (_, _) {});
      await container.read(favoritesProvider('qobuz').future);

      events.add(_changed(_tidalTrack, true));
      await container.pump();

      expect(listened.read().value, {_qobuzTrack});
      expect(api.asked, ['qobuz']);
      expect(container.read(favoritesProvider('tidal').exists), isFalse);
    });

    test('lay a change told while they are read over the answer', () async {
      final events = StreamController<PlayQueueEvent>();
      addTearDown(events.close);
      final api = _FavoritesApi([_qobuzTrack])..readHeld = Completer<void>();
      final container = await _container(api: api, events: events);
      final listened = container.listen(favoritesProvider('qobuz'), (_, _) {});
      await container.pump();
      expect(api.asked, ['qobuz']);

      events
        ..add(_changed(_qobuzAlbum, true))
        ..add(_changed(_qobuzTrack, false));
      await container.pump();
      // Not known from the changes alone.
      expect(listened.read().hasValue, isFalse);

      api.readHeld!.complete();
      expect(await container.read(favoritesProvider('qobuz').future), {
        _qobuzAlbum,
      });
    });
  });
}
