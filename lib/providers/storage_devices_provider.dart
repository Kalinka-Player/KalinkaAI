import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/playqueue_events.dart';
import '../data_model/storage.dart';
import 'connection_settings_provider.dart';
import 'kalinka_player_api_provider.dart';
import 'wire_event_provider.dart';

/// How often Drives & shares asks again while it is open, which is also what
/// keeps the server looking for shares.
const storageDevicesPollInterval = Duration(seconds: 2);

/// What Drives & shares lists (API 0.22), while the screen is open.
///
/// Fetched again as volumes change, and by the screen as it polls; a failed
/// fetch keeps the last list, as the next will likely answer.
class StorageDevicesNotifier extends AsyncNotifier<StorageDeviceList> {
  Future<void>? _asking;

  @override
  Future<StorageDeviceList> build() async {
    ref.watch(connectionSettingsProvider.select((s) => s.address));
    ref.listen(playQueueEventBusProvider, (_, next) {
      if (next case AsyncData(value: VolumesChangedEvent())) refresh();
    });
    return ref.read(kalinkaProxyProvider).listStorageDevices();
  }

  /// Asks again now, as an action does once the server has taken it; joins
  /// a question already out rather than asking twice.
  Future<void> refresh() =>
      _asking ??= _ask().whenComplete(() => _asking = null);

  Future<void> _ask() async {
    try {
      final devices = await ref.read(kalinkaProxyProvider).listStorageDevices();
      if (ref.mounted) state = AsyncData(devices);
    } catch (e, stack) {
      if (ref.mounted && !state.hasValue) state = AsyncError(e, stack);
    }
  }
}

final storageDevicesProvider =
    AsyncNotifierProvider.autoDispose<
      StorageDevicesNotifier,
      StorageDeviceList
    >(StorageDevicesNotifier.new);
