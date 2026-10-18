import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'box_control_provider.dart';
import 'connection_settings_provider.dart';
import 'network_setup_api.dart';

/// The query the hotspot setup page adds to the player link it opens, naming
/// the server whose box it just put on the network.
const networkedQuery = 'networked';

/// Servers whose box this app put on a network this session, by Bluetooth or
/// the hotspot, so setup does not offer Network again. On web the page
/// itself was opened by that setup, which says so in its link.
class NetworkedBoxesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {
    if (kIsWeb) ?Uri.base.queryParameters[networkedQuery],
  };

  void add(String? serverId) {
    if (serverId == null || serverId.isEmpty || state.contains(serverId)) {
      return;
    }
    state = {...state, serverId};
  }
}

final networkedBoxesProvider =
    NotifierProvider<NetworkedBoxesNotifier, Set<String>>(
      NetworkedBoxesNotifier.new,
    );

/// Whether setup should offer Network for the connected server: always over
/// the box's own hotspot, never right after this app gave it its network.
Future<bool> offerNetworkSetup(WidgetRef ref) async {
  if (ref.read(connectionSettingsProvider).host == hotspotAddress) return true;
  final networked = ref.read(networkedBoxesProvider);
  if (networked.isEmpty) return true;
  final id = await ref.read(serverIdentityProvider.future);
  return id == null || !networked.contains(id);
}
