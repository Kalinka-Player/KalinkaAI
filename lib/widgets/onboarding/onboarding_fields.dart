import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data_model/collection_entry.dart';
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
bool schemaHasSetupTags(PresentationSchema? schema) => schema == null
    ? false
    : _hasSetupTags[schema] ??= schema.expertFields.any(
        (f) => f.setup != Setup.hidden,
      );

// A schema never changes once read, and the wizard asks these of it on every
// keystroke typed into a sheet.
final _hasSetupTags = Expando<bool>();
final _setupFields = Expando<Map<String, List<FieldSpec>>>();

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
  final cache = _setupFields[schema] ??= {};
  return cache[moduleRoot(m)] ??= _setupFieldsOf(schema, m);
}

List<FieldSpec> _setupFieldsOf(PresentationSchema schema, ModuleSpec m) {
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

/// Whether something was typed into [entry]: a non-blank text in one of its
/// shape's fields. Adding it, picking a shape or a sign-in, or flipping a
/// switch writes values too, none of them typed.
bool _entryFilled(CollectionSpec c, Map<String, dynamic> entry) =>
    (c.variantOf(entry)?.allFields ?? const <FieldSpec>[]).any((f) {
      final value = readEntryPath(entry, f.path);
      return value is String && value.trim().isNotEmpty;
    });

/// The required questions keeping an enabled module from being ready,
/// by label. Prompt fields never gate. A collection asked in a required
/// field's place is answered once an entry holds something.
List<String> moduleMissingFields(SettingsState state, ModuleSpec m) {
  final missing = <String>{};
  for (final f in setupModuleFields(state.schema, m)) {
    if (f.setup != Setup.required) continue;
    final collection = m.collectionReplacing(f.path);
    if (collection == null) {
      if (!_answered(state, f)) missing.add(f.label);
    } else if (!entriesOf(
      state.getEffective(collection.path),
    ).any((e) => _entryFilled(collection, e))) {
      missing.add(collection.title);
    }
  }
  return missing.toList();
}

/// Whether the server refuses something staged under [m]. The wizard saves
/// everything at once and a refused batch is refused whole, so one such
/// value would cost the final restart.
bool moduleRefused(SettingsState state, ModuleSpec m) =>
    state.issues.entries.any(
      (e) =>
          e.key.startsWith(moduleRoot(m)) && e.value.any((i) => i.isBlocking),
    );

/// A source counts once it is on, every required question is answered and
/// the server takes what was entered for it.
bool moduleConfigured(SettingsState state, ModuleSpec m) =>
    inputModuleEnabled(state, m) &&
    moduleMissingFields(state, m).isEmpty &&
    !moduleRefused(state, m);

/// The source-setup gate: at least one source ready to feed the library.
bool anySourceConfigured(SettingsState state) => schemaModulesOfKind(
  state.schema,
  'input_module',
).any((m) => moduleConfigured(state, m));

/// Whether an enabled source holds something the server refuses. The step
/// that sets sources up waits for it, beside [anySourceConfigured].
bool anySourceRefused(SettingsState state) => schemaModulesOfKind(
  state.schema,
  'input_module',
).any((m) => inputModuleEnabled(state, m) && moduleRefused(state, m));

/// Whether the step that sets sources up may be left: a source is ready and
/// none holds what the server refuses. Not enforced until the schema is up,
/// so a load failure can't strand the step.
bool setupStepReady(SettingsState state) =>
    state.schema == null ||
    (anySourceConfigured(state) && !anySourceRefused(state));

/// Each thing the server refuses in the staged setup, named by the module it
/// belongs to and, inside a collection, the entry.
List<String> refusedNotes(SettingsState state) {
  final modules = [
    ...schemaModulesOfKind(state.schema, 'input_module'),
    ...schemaModulesOfKind(state.schema, 'device'),
  ];
  final notes = <String>{};
  for (final MapEntry(key: path, value: issues) in state.issues.entries) {
    final owner = _ownerOf(state, modules, path);
    for (final issue in issues) {
      if (!issue.isBlocking) continue;
      notes.add(owner == null ? issue.message : '$owner: ${issue.message}');
    }
  }
  return notes.toList();
}

/// What [path] belongs to, for a note with no field to sit under: its
/// module, and the entry of a collection it points into, so two entries
/// refused alike read as two.
String? _ownerOf(SettingsState state, List<ModuleSpec> modules, String path) {
  final module = modules
      .where((m) => path.startsWith(moduleRoot(m)))
      .firstOrNull;
  if (module == null) return null;
  for (final c in module.allCollections) {
    if (!path.startsWith('${c.path}.')) continue;
    final id = path.substring(c.path.length + 1).split('.').first;
    final entry = entriesOf(
      state.getEffective(c.path),
    ).where((e) => e['id'] == id).firstOrNull;
    final summary = entry == null
        ? ''
        : c.variantOf(entry)?.summaryOf(entry) ?? '';
    if (summary.isNotEmpty) return '${module.title}, $summary';
  }
  return module.title;
}

/// What the server refuses of [m] that the source-setup step has no field
/// or card to show under, so a held-up Continue still says why. The step
/// shows each question it asks, and a collection's list, entries and their
/// fields.
List<String> unshownRefusals(SettingsState state, ModuleSpec m) {
  final shown = <String>{};
  for (final f in setupModuleFields(state.schema, m)) {
    final c = m.collectionReplacing(f.path);
    if (c == null) {
      shown.add(f.path);
      continue;
    }
    shown.add(c.path);
    for (final entry in entriesOf(state.getEffective(c.path))) {
      final at = c.entryPath(entry);
      shown.add(at);
      for (final field in c.variantOf(entry)?.allFields ?? <FieldSpec>[]) {
        shown.add('$at.${field.path}');
      }
    }
  }
  return {
    for (final MapEntry(key: path, value: issues) in state.issues.entries)
      if (path.startsWith(moduleRoot(m)) && !shown.contains(path))
        for (final issue in issues)
          if (issue.isBlocking) issue.message,
  }.toList();
}

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
