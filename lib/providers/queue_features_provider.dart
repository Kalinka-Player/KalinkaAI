import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart' show ModuleCapability;
import 'app_state_provider.dart';
import 'connection_state_provider.dart';
import 'kalinka_player_api_provider.dart';
import 'now_playing_provider.dart';
import 'source_modules_provider.dart';

/// What the server's queue does beyond playing what it holds (API 0.27), as
/// the `queue` block of `/server/version` declares it. A server without the
/// block offers none of it.
class QueueFeatures {
  /// Queues tracks like the playing one right after it, from its own source.
  final bool similar;

  /// Turns the playing track down for the queue's session and skips it.
  final bool dislike;

  const QueueFeatures({this.similar = false, this.dislike = false});

  static const none = QueueFeatures();

  factory QueueFeatures.fromVersion(Map<String, dynamic> version) {
    final queue = version['queue'];
    bool offers(String feature) => queue is Map && queue[feature] == true;
    return QueueFeatures(
      similar: offers('similar'),
      dislike: offers('dislike'),
    );
  }
}

/// The connected server's [QueueFeatures], asked again on each reconnect and
/// kept meanwhile. Asked on its own rather than through `serverInfoProvider`,
/// whose round trip is timed for whoever opens the server menu.
final queueFeaturesProvider = FutureProvider<QueueFeatures>((ref) async {
  final api = ref.watch(kalinkaProxyProvider);
  refetchOnReconnect(ref);
  if (ref.read(connectionStateProvider) != ConnectionStatus.connected) {
    return QueueFeatures.none;
  }
  return QueueFeatures.fromVersion(await api.getServerVersion());
}, retry: (_, _) => null);

/// Whether the track Now Playing shows can be turned down: the server takes a
/// dislike, and the track is the queue's rather than a plugin's stream.
final dislikeAvailableProvider = Provider<bool>(
  (ref) =>
      ref.watch(
        queueFeaturesProvider.select((f) => f.value?.dislike ?? false),
      ) &&
      !ref.watch(playbackControlProvider.select((c) => c.isExclusive)) &&
      ref.watch(nowPlayingTrackProvider.select((track) => track != null)),
);

/// Whether tracks like the playing one can be asked for: the server queues
/// them, and the playing track's own source can suggest them.
final similarTracksAvailableProvider = Provider<bool>((ref) {
  if (!ref.watch(
    queueFeaturesProvider.select((f) => f.value?.similar ?? false),
  )) {
    return false;
  }
  final source = ref.watch(
    nowPlayingTrackProvider.select(
      (track) => track == null ? null : sourceOfId(track.id),
    ),
  );
  if (source == null) return false;
  return ref.watch(
    sourceModulesProvider.select(
      (modules) =>
          modules.value?.any(
            (module) =>
                module.name == source &&
                module.can(ModuleCapability.continuation),
          ) ??
          false,
    ),
  );
});
