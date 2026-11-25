import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/now_playing_favorite_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';

import 'support/home_shell.dart';
import 'support/queue_server.dart';

/// Lists each source's favourite tracks from [favorites], or holds the answer
/// for [held] where that is set.
class _FavoritesApi implements KalinkaPlayerProxy {
  _FavoritesApi(this.favorites);

  final Map<String, Set<String>> favorites;
  Completer<void>? held;
  final List<String?> asked = [];

  @override
  Future<FavoriteIds> getFavoriteIds({String? source}) async {
    asked.add(source);
    await held?.future;
    return FavoriteIds(
      albums: [],
      tracks: [...?favorites[source]],
      artists: [],
      playlists: [],
    );
  }

  @override
  Future<StatusMessage> addFavorite(String id) async =>
      throw Exception('connection reset');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

ModuleInfo _module(String name, {bool favorites = true}) => ModuleInfo(
  name: name,
  title: name,
  enabled: true,
  state: ModuleState.ready,
  capabilities: [if (favorites) ModuleCapability.favorites],
);

PlayQueueState _playing(String id, {bool exclusive = false}) => PlayQueueState(
  playbackState: PlaybackState(index: 0, state: PlayerStateType.playing),
  trackList: [Track(id: id, title: 'Night drive', duration: 1)],
  playbackMode: PlaybackMode.empty,
  playbackControl: exclusive
      ? const PlaybackControl.exclusive(pluginId: 'connect', title: 'Connect')
      : const PlaybackControl.queue(),
  seq: 1,
);

const _qobuzTrack = 'kalinka:qobuz:track:1';
const _tidalTrack = 'kalinka:tidal:track:7';

Future<ProviderContainer> _container(
  PlayQueueState queue, {
  _FavoritesApi? api,
  List<ModuleInfo>? modules,
}) async {
  final container = ProviderContainer(
    overrides: [
      kalinkaProxyProvider.overrideWithValue(api ?? _FavoritesApi({})),
      connectionStateProvider.overrideWith(SettableConnection.new),
      playQueueStateStoreProvider.overrideWith(() => SettableQueue(queue)),
      sourceModulesProvider.overrideWith(
        (ref) => modules ?? [_module('qobuz'), _module('tidal')],
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
          'albums': ['kalinka:qobuz:album:2'],
          'artists': [],
          'tracks': [_qobuzTrack, 'kalinka:qobuz:track:3'],
          'playlists': [],
        }, route: '/favorite/ids');

        final ids = await server.api().getFavoriteIds(source: 'qobuz');

        expect(server.requests, ['GET /favorite/ids']);
        expect(server.queries['GET /favorite/ids'], {'source': 'qobuz'});
        expect(ids.tracks, [_qobuzTrack, 'kalinka:qobuz:track:3']);
        expect(ids.albums, ['kalinka:qobuz:album:2']);
        expect(ids.artists, isEmpty);
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

  group('whether the playing track can be marked', () {
    test('where its own source keeps favourites', () async {
      final container = await _container(_playing(_qobuzTrack));
      expect(container.read(favoriteAvailableProvider), isTrue);
      expect(container.read(favoriteSourceProvider), 'qobuz');
    });

    test('not where only another source keeps them', () async {
      final container = await _container(
        _playing(_qobuzTrack),
        modules: [_module('qobuz', favorites: false), _module('tidal')],
      );
      expect(container.read(favoriteAvailableProvider), isFalse);
    });

    test('not while a plugin plays, nor with nothing playing', () async {
      for (final queue in [
        _playing(_qobuzTrack, exclusive: true),
        PlayQueueState.empty,
        _playing('track-without-a-source'),
      ]) {
        final container = await _container(queue);
        expect(container.read(favoriteAvailableProvider), isFalse);
      }
    });
  });

  group('the playing source\'s favourites', () {
    test('are asked for that source alone', () async {
      final api = _FavoritesApi({
        'qobuz': {_qobuzTrack},
      });
      final container = await _container(_playing(_qobuzTrack), api: api);
      container.listen(favoriteTracksProvider, (_, _) {});

      expect(await container.read(favoriteTracksProvider.future), {
        _qobuzTrack,
      });
      expect(api.asked, ['qobuz']);
    });

    test('are asked again for a new source, the last kept meanwhile', () async {
      final api = _FavoritesApi({
        'qobuz': {_qobuzTrack},
        'tidal': {_tidalTrack},
      });
      final container = await _container(_playing(_qobuzTrack), api: api);
      final listened = container.listen(favoriteTracksProvider, (_, _) {});
      await container.read(favoriteTracksProvider.future);

      api.held = Completer<void>();
      (container.read(playQueueStateStoreProvider.notifier) as SettableQueue)
          .set(_playing(_tidalTrack));
      await container.pump();
      expect(api.asked, ['qobuz', 'tidal']);
      expect(listened.read().value, {_qobuzTrack});

      api.held!.complete();
      expect(await container.read(favoriteTracksProvider.future), {
        _tidalTrack,
      });
    });

    test('are not asked again for another track of the same source', () async {
      final api = _FavoritesApi({});
      final container = await _container(_playing(_qobuzTrack), api: api);
      container.listen(favoriteTracksProvider, (_, _) {});
      await container.read(favoriteTracksProvider.future);

      (container.read(playQueueStateStoreProvider.notifier) as SettableQueue)
          .set(_playing('kalinka:qobuz:track:2'));
      await container.pump();

      expect(api.asked, ['qobuz']);
    });

    test('are asked again on reconnect', () async {
      final api = _FavoritesApi({
        'qobuz': {_qobuzTrack},
      });
      final container = await _container(_playing(_qobuzTrack), api: api);
      final listened = container.listen(favoriteTracksProvider, (_, _) {});
      await container.read(favoriteTracksProvider.future);
      final connection = container.read(
        connectionStateProvider.notifier,
      ) as SettableConnection;

      connection.set(ConnectionStatus.reconnecting);
      await container.pump();
      expect(api.asked, ['qobuz']);
      api.held = Completer<void>();
      connection.set(ConnectionStatus.connected);
      await container.pump();

      expect(api.asked, ['qobuz', 'qobuz']);
      expect(listened.read().value, {_qobuzTrack});
      api.held!.complete();
    });

    test('a failed mark takes back only itself', () async {
      final api = _FavoritesApi({
        'qobuz': {'kalinka:qobuz:track:9'},
      });
      final container = await _container(_playing(_qobuzTrack), api: api);
      container.listen(favoriteTracksProvider, (_, _) {});
      await container.read(favoriteTracksProvider.future);

      await expectLater(
        container.read(favoriteTracksProvider.notifier).toggle(_qobuzTrack),
        throwsException,
      );

      expect(container.read(favoriteTracksProvider).value, {
        'kalinka:qobuz:track:9',
      });
    });
  });
}
