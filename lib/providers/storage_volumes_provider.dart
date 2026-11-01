import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/playqueue_events.dart';
import '../data_model/storage.dart';
import 'connection_settings_provider.dart';
import 'connection_state_provider.dart';
import 'kalinka_player_api_provider.dart';
import 'wire_event_provider.dart';

/// The server's volumes: its music folder, the drives it mounted and the
/// shares and disks it reads (API 0.21).
///
/// Fetched on connect and kept current by the queue socket's
/// `volumes_changed`. An older server lists none.
class StorageVolumesNotifier extends AsyncNotifier<List<StorageVolume>> {
  List<StorageVolume>? _pushed;

  @override
  Future<List<StorageVolume>> build() async {
    ref.watch(connectionSettingsProvider.select((s) => s.address));
    refetchOnReconnect(ref);
    _pushed = null;
    if (!ref.read(connectionSettingsProvider).isSet) return const [];
    ref.listen(playQueueEventBusProvider, (_, next) {
      if (next case AsyncData(value: VolumesChangedEvent(:final volumes))) {
        _pushed = volumes;
        state = AsyncData(volumes);
      }
    });
    final List<StorageVolume> fetched;
    try {
      fetched = await ref.read(kalinkaProxyProvider).listStorageVolumes();
    } catch (_) {
      if (_pushed case final pushed?) return pushed;
      rethrow;
    }
    return _pushed ?? fetched;
  }
}

final storageVolumesProvider =
    AsyncNotifierProvider<StorageVolumesNotifier, List<StorageVolume>>(
      StorageVolumesNotifier.new,
    );

/// Removable drives in [after] that were not mounted in [before].
List<StorageVolume> newlyPlugged(
  List<StorageVolume> before,
  List<StorageVolume> after,
) {
  final mounted = {
    for (final v in before)
      if (v.isMounted) v.id,
  };
  return [
    for (final v in after)
      if (v.isRemovable && v.isMounted && !mounted.contains(v.id)) v,
  ];
}

/// The volumes mounted in [volumes], by id.
Set<String> mountedVolumeIds(List<StorageVolume> volumes) => {
  for (final v in volumes)
    if (v.isMounted) v.id,
};
