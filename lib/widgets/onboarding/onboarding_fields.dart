import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data_model/presentation_schema.dart';
import '../../providers/settings_provider.dart';
import '../settings_controls/settings_row.dart';
import '../settings_renderer.dart' show buildFieldControl;

/// All modules of [kind] (`input_module` / `device`) across every page.
List<ModuleSpec> schemaModulesOfKind(PresentationSchema? schema, String kind) {
  if (schema == null) return const [];
  return [
    for (final page in schema.pages)
      for (final m in page.modules)
        if (m.kind == kind) m,
  ];
}

/// The server's built-in renderer volume module. Never offered as a choice
/// and never toggled by the wizard: disabling it drops volume control for
/// every output.
const kRendererVolumeModuleId = 'kalinka-renderer';

/// What "no external amplifier" is called wherever the wizard names it.
///
/// Not the module's own title: the output list one step earlier names
/// renderers `Kalinka Renderer on <host>`, so calling this choice "Kalinka
/// Renderer default" read as another output rather than a volume-control
/// choice. Named once here because it appears on the amplifier step twice
/// and again in the review.
const kDefaultVolumeControlLabel = 'Default volume control';

/// Device plugins the wizard offers as amplifier control: every device
/// module the server loaded, bar the built-in renderer volume module —
/// that one *is* the default choice, and offering it twice would let the
/// user disable the thing that carries volume for every output.
///
/// Everything else the server has loaded belongs here even if it looks like
/// a stub: hiding a module the wizard still writes `enabled` around left it
/// switched on server-side while the step claimed nothing was controlling
/// volume.
List<ModuleSpec> setupDeviceModules(PresentationSchema? schema) => [
  for (final m in schemaModulesOfKind(schema, 'device'))
    if (m.id != kRendererVolumeModuleId) m,
];

/// Boolean field paths that mean "download a model and analyse". The setup
/// tag says *when to ask*, not what saying yes costs, so this suffix set
/// stays the one app-side convention — it hangs a resource warning off the
/// toggle on the source-setup step.
const kSmartSearchFieldSuffixes = ['.ai_search_enabled', '.embedder.enabled'];

/// The module's `enabled` field, if it has one.
FieldSpec? moduleEnabledField(ModuleSpec m) {
  for (final f in m.fields) {
    if (f.path.endsWith('.enabled')) return f;
  }
  return null;
}

/// Whether the module is on. Local Library has no meaningful off state — the
/// server's library backend is built in — so it always reads enabled.
bool inputModuleEnabled(SettingsState state, ModuleSpec m) {
  if (m.id == 'localfiles') return true;
  final f = moduleEnabledField(m);
  if (f == null) return false;
  return (state.getEffective(f.path) ?? f.defaultValue ?? false) == true;
}

/// Whether the connected server tags fields for setup at all. Older servers
/// don't — every field parses as hidden — and the wizard falls back to its
/// old tier-based rules rather than asking nothing.
bool schemaHasSetupTags(PresentationSchema? schema) =>
    schema?.expertFields.any((f) => f.setup != Setup.hidden) ?? false;

/// The dotted-path root that names a module's config subtree.
String moduleRoot(ModuleSpec m) =>
    '${m.kind == 'device' ? 'devices' : 'input_modules'}.${m.id}.';

/// Required questions first, then prompts; path order within each group
/// (expertFields comes sorted by path).
List<FieldSpec> _setupOrdered(Iterable<FieldSpec> fields) {
  final list = fields.toList();
  return [
    for (final f in list)
      if (f.setup == Setup.required) f,
    for (final f in list)
      if (f.setup != Setup.required) f,
  ];
}

/// The wizard's questions for one module: every field the server tagged for
/// setup under the module's root — both tiers, `expertFields` is the index —
/// minus the module's own enable flag, required first. On an untagged
/// (older) schema, the module's top-level simple fields, as before.
List<FieldSpec> setupModuleFields(PresentationSchema? schema, ModuleSpec m) {
  if (schema == null) return const [];
  if (!schemaHasSetupTags(schema)) {
    return [
      for (final f in m.fields)
        if (!f.readonly && !f.path.endsWith('.enabled')) f,
    ];
  }
  final root = moduleRoot(m);
  return _setupOrdered([
    for (final f in schema.expertFields)
      if (f.setup != Setup.hidden &&
          !f.readonly &&
          f.path.startsWith(root) &&
          f.path != '${root}enabled')
        f,
  ]);
}

// The server's own `base_config` setup tags are deliberately not asked here:
// every one of them has a working default (the service name today), and a
// whole wizard step for renaming a server that already named itself read as
// setup work the user had to do. They live in Settings.

/// A required answer exists: a credential the server holds, a non-blank
/// string, or a list with at least one non-blank entry. The server
/// guarantees a required field defaults to its type's empty value, so
/// "still empty" is "not answered yet".
bool _answered(SettingsState state, FieldSpec f) {
  if (state.hasHiddenSecret(f.path)) return true;
  final value = state.getEffective(f.path);
  if (value == null) return false;
  if (value is String) return value.trim().isNotEmpty;
  if (value is List) return value.any((e) => e.toString().trim().isNotEmpty);
  return true;
}

/// The required questions keeping an enabled module from being ready,
/// by label. Prompt fields never gate.
List<String> moduleMissingFields(SettingsState state, ModuleSpec m) => [
  for (final f in setupModuleFields(state.schema, m))
    if (f.setup == Setup.required && !_answered(state, f)) f.label,
];

/// A source counts once it is on and every required question is answered.
bool moduleConfigured(SettingsState state, ModuleSpec m) =>
    inputModuleEnabled(state, m) && moduleMissingFields(state, m).isEmpty;

/// The source-setup gate: at least one source ready to feed the library.
bool anySourceConfigured(SettingsState state) => schemaModulesOfKind(
  state.schema,
  'input_module',
).any((m) => moduleConfigured(state, m));

/// Renders a single backend config field inside the setup wizard, bound to
/// the shared settings staging flow ([SettingsNotifier.stageChange]).
///
/// Unlike [SchemaFieldRenderer] this allows overriding the backend's label
/// and help text with wizard-specific copy, and silently renders nothing
/// when the connected server's schema doesn't carry the field (older
/// server or plugin not installed).
class OnboardingFieldRow extends ConsumerWidget {
  final String path;
  final String? label;
  final String? help;

  const OnboardingFieldRow({
    super.key,
    required this.path,
    this.label,
    this.help,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final field = state.schema?.field(path);
    if (field == null || field.readonly) return const SizedBox.shrink();

    final value = state.getEffective(path) ?? field.defaultValue;

    // Same full-width rules as the settings screen's field renderer.
    final vertical =
        field.widget == WidgetKind.listEditor ||
        field.widget == WidgetKind.folderList ||
        field.widget == WidgetKind.enumPills ||
        field.widget == WidgetKind.enumDropdown ||
        field.widget == WidgetKind.text ||
        field.widget == WidgetKind.password ||
        field.widget == WidgetKind.path ||
        field.widget == WidgetKind.url;

    return SettingsRow(
      label: label ?? field.label,
      sublabel: help ?? field.help,
      isStaged: state.isStaged(path),
      isVertical: vertical,
      control: buildFieldControl(
        field: field,
        value: value,
        options: ServerSettingsBinding(state, notifier),
        issues: state.issuesFor(path),
        secretHidden: state.hasHiddenSecret(path),
        onChanged: (v) => notifier.stageChange(path, v),
      ),
    );
  }
}
