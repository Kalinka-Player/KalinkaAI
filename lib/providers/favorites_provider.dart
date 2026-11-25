import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart';
import '../data_model/playqueue_events.dart';
import 'connection_state_provider.dart';
import 'kalinka_player_api_provider.dart';
import 'source_modules_provider.dart';
import 'wire_event_provider.dart';

/// The sources that keep favourites, as their capabilities say (`favorites`):
/// none while the sources load, or on a server whose sources list none. Told
/// again only when a source joins or leaves them.
class FavoriteSourcesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    final modules = ref.watch(sourceModulesProvider.select((m) => m.value));
    return {
      for (final module in modules ?? const <ModuleInfo>[])
        if (module.can(ModuleCapability.favorites)) module.name,
    };
  }

  @override
  bool updateShouldNotify(Set<String> previous, Set<String> next) =>
      !setEquals(previous, next);
}

final favoriteSourcesProvider =
    NotifierProvider<FavoriteSourcesNotifier, Set<String>>(
      FavoriteSourcesNotifier.new,
    );

/// The source [id] can be marked a favourite of: its own, where it names a
/// track, an album, an artist or a playlist and is one of [keeping], the
/// sources that keep favourites. Null for what cannot be marked.
String? favoriteSourceOf(String id, Set<String> keeping) {
  if (keeping.isEmpty) return null;
  try {
    final entity = EntityId.fromString(id);
    return switch (entity.type) {
      EntityType.track ||
      EntityType.album ||
      EntityType.artist ||
      EntityType.playlist when keeping.contains(entity.source) => entity.source,
      _ => null,
    };
  } catch (_) {
    return null;
  }
}

/// What one source holds as favourites, tracks, albums, artists and
/// playlists alike, by entity id, as `/favorite/ids?sources=` lists them:
/// one source a request, so a source that cannot answer costs only its own
/// hearts.
///
/// Asked when first watched and on each reconnect, the last answer staying
/// meanwhile, and kept current by the queue socket's `favorite_changed`.
/// [toggle] shows a change at once and takes it back if the server does not
/// make it.
class FavoritesNotifier extends AsyncNotifier<Set<String>> {
  FavoritesNotifier(this.source);

  final String source;

  /// The changes made while a read is out, laid over its answer, which may
  /// have been written before them.
  Map<String, bool>? _sinceAsked;

  @override
  Future<Set<String>> build() async {
    refetchOnReconnect(ref);
    ref.listen(playQueueEventBusProvider, (_, next) {
      if (next
          case AsyncData(
            value: FavoriteChangedEvent(:final id, :final favorite),
          )
          when sourceOfId(id) == source) {
        _mark(id, favorite);
      }
    });
    final sinceAsked = _sinceAsked = {};
    final FavoriteIds listed;
    try {
      listed = await ref
          .read(kalinkaProxyProvider)
          .getFavoriteIds(source: source);
    } finally {
      if (identical(_sinceAsked, sinceAsked)) _sinceAsked = null;
    }
    final ids = {
      ...listed.tracks,
      ...listed.albums,
      ...listed.artists,
      ...listed.playlists,
    };
    sinceAsked.forEach(
      (id, favorite) => favorite ? ids.add(id) : ids.remove(id),
    );
    return ids;
  }

  /// Marks [id] a favourite, or no longer one where it is. A change the
  /// server does not make is undone and rethrown for the caller to tell, and
  /// the source's favourites are read again: after a timeout the server may
  /// have made it all the same.
  Future<void> toggle(String id) async {
    final adding = !(state.value?.contains(id) ?? false);
    final api = ref.read(kalinkaProxyProvider);
    _mark(id, adding);
    try {
      await (adding ? api.addFavorite(id) : api.removeFavorite(id));
    } catch (_) {
      if (ref.mounted) {
        _mark(id, !adding);
        ref.invalidateSelf();
      }
      rethrow;
    }
  }

  void _mark(String id, bool favorite) {
    _sinceAsked?[id] = favorite;
    final known = state.value;
    if (known == null || known.contains(id) == favorite) return;
    state = AsyncData(favorite ? {...known, id} : ({...known}..remove(id)));
  }
}

final favoritesProvider =
    AsyncNotifierProvider.family<FavoritesNotifier, Set<String>, String>(
      FavoritesNotifier.new,
      retry: favoritesRetry,
    );

/// After a failed read, when a source's favourites are asked for again: a
/// few times, further apart each time, so one that was briefly away does not
/// leave its hearts inert until the next reconnect.
Duration? favoritesRetry(int count, Object _) =>
    count < 4 ? Duration(seconds: 1 << count) : null;
