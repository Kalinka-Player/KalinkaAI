import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data_model/data_model.dart';
import '../data_model/playqueue_events.dart';
import 'connection_settings_provider.dart';
import 'connection_state_provider.dart';
import 'kalinka_player_api_provider.dart';
import 'wire_event_provider.dart';

/// Full snapshot of `/server/modules` — every loaded input module and
/// output device with its live state (READY / WARNING / ERROR /
/// DISABLED), human-readable message, and the list of optional pip
/// packages the module currently needs but cannot import.
///
/// This is the live counterpart to the static presentation schema:
/// the schema describes the layout, this provider describes the
/// current state. They're decoupled so transient state changes don't
/// invalidate the cached schema version.
///
/// From API 0.19 the queue socket's replay and modules_changed events keep
/// it current. The GET stays the source on older servers, on connect and
/// when invalidated.
class ModulesStateNotifier extends AsyncNotifier<ModulesAndDevices> {
  ModulesAndDevices? _pushed;

  @override
  Future<ModulesAndDevices> build() async {
    // A server-side rename refreshes the name; only the address matters here.
    ref.watch(connectionSettingsProvider.select((s) => s.address));
    refetchOnReconnect(ref);
    _pushed = null;
    final settings = ref.read(connectionSettingsProvider);
    if (!settings.isSet) {
      return ModulesAndDevices(inputModules: const [], devices: const []);
    }
    ref.listen(playQueueEventBusProvider, (_, next) {
      if (next case AsyncData(:final value)) _onEvent(value);
    });
    final ModulesAndDevices fetched;
    try {
      fetched = await ref.read(kalinkaProxyProvider).listModules();
    } catch (_) {
      // The socket already told us; a failed GET is no reason to drop that.
      if (_pushed case final pushed?) return pushed;
      rethrow;
    }
    // A listing pushed while the request was out is the newer one.
    return _pushed ?? fetched;
  }

  void _onEvent(PlayQueueEvent event) {
    final modules = switch (event) {
      ModulesChangedEvent(:final modules) => modules,
      // Null from a server before 0.19, which leaves the GET's answer.
      ReplayPlayQueueEvent(:final state) => state.modules,
      _ => null,
    };
    if (modules == null) return;
    _pushed = modules;
    state = AsyncData(modules);
  }
}

final modulesStateProvider =
    AsyncNotifierProvider<ModulesStateNotifier, ModulesAndDevices>(
      ModulesStateNotifier.new,
    );

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
