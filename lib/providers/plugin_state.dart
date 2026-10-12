import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart'
    show ModuleInfo, ModuleState, ModulesAndDevices;
import '../data_model/plugin_catalog.dart';
import '../data_model/presentation_schema.dart';
import 'modules_state_provider.dart';
import 'plugin_catalog_provider.dart';
import 'settings_provider.dart';

/// Where a catalog plugin stands on the connected server: whether it is
/// installed, switched on, working, and what its settings are.
class PluginState {
  /// Its live entry in `/server/modules`; null while it is not installed.
  final ModuleInfo? live;

  /// Its settings, where the server's settings schema carries them.
  final ModuleSpec? module;

  /// Config path of its on/off switch, where the schema has one.
  final String? enabledPath;

  /// On or off as the server has it saved.
  final bool savedEnabled;

  /// On or off with staged edits applied.
  final bool enabled;
  final bool hasPendingChanges;

  final PluginUpdate? update;
  final PluginOperation? operation;

  /// The last install, removal or update that failed, until put away.
  final PluginFailure? failure;

  const PluginState({
    this.live,
    this.module,
    this.enabledPath,
    this.savedEnabled = false,
    this.enabled = false,
    this.hasPendingChanges = false,
    this.update,
    this.operation,
    this.failure,
  });

  factory PluginState.of(
    CatalogPlugin plugin, {
    required ModulesAndDevices? modules,
    required SettingsState settings,
    PluginUpdate? update,
    PluginOperation? operation,
    PluginFailure? failure,
  }) {
    final live = modules == null
        ? null
        : lookupModule(modules, plugin.id, plugin.moduleKind);
    ModuleSpec? module;
    for (final page in settings.schema?.pages ?? const <PageSpec>[]) {
      for (final m in page.modules) {
        if (m.id == plugin.id && m.kind == plugin.moduleKind) module = m;
      }
    }
    final field = module?.enabledField;
    bool read(dynamic value) =>
        (value ?? field?.defaultValue ?? live?.enabled ?? false) == true;
    final root =
        '${plugin.isDevice ? 'devices' : 'input_modules'}.${plugin.id}.';
    final staged = settings.stagedChanges.keys;
    final paths = staged.isEmpty ? null : module?.settingPaths.toSet();
    return PluginState(
      live: live,
      module: module,
      enabledPath: field?.path,
      savedEnabled: read(field == null ? null : settings.values[field.path]),
      enabled: read(field == null ? null : settings.getEffective(field.path)),
      hasPendingChanges: staged.any(
        (path) => path.startsWith(root) || paths?.contains(path) == true,
      ),
      update: live == null ? null : update,
      operation: operation,
      failure: failure,
    );
  }

  bool get installed => live != null;

  /// An on/off edit waits for the restart that applies it.
  bool get staged => installed && enabled != savedEnabled;

  /// Something to show on its settings page besides the on/off switch.
  bool get hasSettings {
    final module = this.module;
    if (module == null) return false;
    return module.fields.any((f) => f.path != enabledPath) ||
        module.collections.isNotEmpty ||
        module.sections.isNotEmpty ||
        module.banners.isNotEmpty;
  }

  /// What there is to say beside its status badge: the module's own
  /// summary, a restart it waits on, a newer release.
  String? get detail {
    final live = this.live;
    if (operation != null || live == null) return null;
    if (staged) {
      return enabled ? 'Turns on after restart' : 'Turns off after restart';
    }
    if (hasPendingChanges) return 'Changes pending';
    if (update case final update?) {
      return 'Update available · ${update.version}';
    }
    if (!enabled) return null;
    return live.state == ModuleState.ready ? live.summary : null;
  }
}

/// How one plugin stands, for a page about it alone.
final pluginStateProvider = Provider.autoDispose
    .family<PluginState, CatalogPlugin>(
      (ref, plugin) => PluginState.of(
        plugin,
        modules: ref.watch(modulesStateProvider).value,
        settings: ref.watch(settingsProvider),
        update: ref.watch(pluginUpdatesProvider).value?[plugin.id],
        operation: ref.watch(pluginOperationsProvider)[plugin.id],
        failure: ref.watch(pluginFailuresProvider)[plugin.id],
      ),
    );
