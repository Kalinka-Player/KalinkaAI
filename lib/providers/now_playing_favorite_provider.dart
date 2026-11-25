import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart' show ModuleCapability;
import 'app_state_provider.dart';
import 'connection_state_provider.dart';
import 'kalinka_player_api_provider.dart';
import 'now_playing_provider.dart';
import 'source_modules_provider.dart';

/// The source of the track Now Playing shows, where that track can be marked
/// a favourite: it is the queue's rather than a plugin's stream, and its own
/// source keeps favourites. Null otherwise.
final favoriteSourceProvider = Provider<String?>((ref) {
  if (ref.watch(playbackControlProvider.select((c) => c.isExclusive))) {
    return null;
  }
  final source = ref.watch(
    nowPlayingTrackProvider.select(
      (track) => track == null ? null : sourceOfId(track.id),
    ),
  );
  return source != null &&
          watchSourcesCan(ref, {source}, ModuleCapability.favorites)
      ? source
      : null;
});

/// Whether the track Now Playing shows can be marked a favourite.
final favoriteAvailableProvider = Provider<bool>(
  (ref) => ref.watch(favoriteSourceProvider) != null,
);

/// The favourite tracks of the source [favoriteSourceProvider] names, as
/// `/favorite/ids?source=` lists them.
///
/// Asked again when that source changes and on each reconnect; the last answer
/// stays meanwhile. [toggle] shows a change at once and takes it back if the
/// server does not make it.
class FavoriteTracksNotifier extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    final source = ref.watch(favoriteSourceProvider);
    refetchOnReconnect(ref);
    if (source == null) return const {};
    final ids = await ref
        .read(kalinkaProxyProvider)
        .getFavoriteIds(source: source);
    return ids.tracks.toSet();
  }

  /// Marks [trackId] a favourite, or no longer one where it is. A failure is
  /// undone and rethrown for the caller to tell.
  Future<void> toggle(String trackId) async {
    final adding = !(state.value?.contains(trackId) ?? false);
    final api = ref.read(kalinkaProxyProvider);
    _mark(trackId, adding);
    try {
      await (adding ? api.addFavorite(trackId) : api.removeFavorite(trackId));
    } catch (_) {
      if (ref.mounted) _mark(trackId, !adding);
      rethrow;
    }
  }

  void _mark(String trackId, bool favorite) {
    final ids = {...?state.value};
    favorite ? ids.add(trackId) : ids.remove(trackId);
    state = AsyncData(ids);
  }
}

final favoriteTracksProvider =
    AsyncNotifierProvider<FavoriteTracksNotifier, Set<String>>(
      FavoriteTracksNotifier.new,
      retry: (_, _) => null,
    );
