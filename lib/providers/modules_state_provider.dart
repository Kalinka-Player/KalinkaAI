import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data_model/data_model.dart';
import 'connection_settings_provider.dart';
import 'connection_state_provider.dart';
import 'kalinka_player_api_provider.dart';

/// Full snapshot of `/server/modules` — every loaded input module and
/// output device with its live state (READY / WARNING / ERROR /
/// DISABLED), human-readable message, and the list of optional pip
/// packages the module currently needs but cannot import.
///
/// This is the live counterpart to the static presentation schema:
/// the schema describes the layout, this provider describes the
/// current state. They're decoupled so transient state changes don't
/// invalidate the cached schema version.
final modulesStateProvider = FutureProvider<ModulesAndDevices>((ref) async {
  // A server-side rename refreshes the name; only the address matters here.
  ref.watch(connectionSettingsProvider.select((s) => s.address));
  refetchOnReconnect(ref);
  final settings = ref.read(connectionSettingsProvider);
  if (!settings.isSet) {
    return ModulesAndDevices(inputModules: const [], devices: const []);
  }
  final api = ref.read(kalinkaProxyProvider);
  return api.listModules();
});

/// Look up live state for one module by id and kind.
ModuleInfo? lookupModule(
  ModulesAndDevices snapshot,
  String id,
  String kind,
) {
  final list = kind == 'device' ? snapshot.devices : snapshot.inputModules;
  for (final m in list) {
    if (m.name == id) return m;
  }
  return null;
}
