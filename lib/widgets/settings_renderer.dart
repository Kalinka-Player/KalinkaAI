import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/collection_entry.dart';
import '../data_model/data_model.dart' show ModuleInfo, ModuleState;
import '../data_model/presentation_schema.dart';
import '../providers/connection_settings_provider.dart';
import '../providers/modules_state_provider.dart';
import '../providers/server_info_provider.dart';
import '../theme/app_theme.dart';
import '../utils/schema_icons.dart';
import 'server_update_banner.dart';
import 'configuration_appearance.dart';
import 'settings_controls/footer_note.dart';
import 'settings_controls/inline_markdown.dart';
import 'settings_controls/issue_notes.dart';
import 'settings_controls/settings_binding.dart';
import 'settings_controls/module_header_row.dart';
import 'settings_controls/settings_card.dart';
import 'settings_controls/settings_combo_input.dart';
import 'settings_controls/settings_combo_list.dart';
import 'settings_controls/settings_enum_dropdown.dart';
import 'settings_controls/settings_enum_pills.dart';
import 'settings_controls/settings_list_editor.dart';
import 'settings_controls/settings_numeric_input.dart';
import 'settings_controls/settings_password_input.dart';
import 'settings_controls/settings_readonly_card.dart';
import 'settings_controls/settings_row.dart';
import 'settings_controls/settings_section.dart';
import 'settings_controls/settings_slider.dart';
import 'settings_controls/settings_text_input.dart';
import 'settings_controls/settings_toggle.dart';
import 'settings_controls/settings_toggleable_section.dart';
import 'settings_controls/warning_note.dart';
import 'modules_empty_state.dart';
import 'settings_collection.dart';

// ---------------------------------------------------------------------------
// Icons
// ---------------------------------------------------------------------------

/// The icon for a backend material icon name, a plugin piece where this app
/// has none by that name.
IconData schemaIcon(String? name) =>
    iconNamed(name) ?? Icons.extension_outlined;

Color _colorFromHex(String? hex, Color fallback) {
  if (hex == null || !hex.startsWith('#')) return fallback;
  final value = int.tryParse(hex.substring(1), radix: 16);
  if (value == null) return fallback;
  return Color(0xFF000000 | value);
}

// ---------------------------------------------------------------------------
// Banner
// ---------------------------------------------------------------------------

class SchemaBanner extends StatelessWidget {
  final BannerSpec banner;
  const SchemaBanner({super.key, required this.banner});

  @override
  Widget build(BuildContext context) {
    switch (banner.severity) {
      case Severity.warning:
      case Severity.danger:
        return WarningNote(message: banner.text);
      case Severity.info:
        final hasTitle = banner.title != null && banner.title!.isNotEmpty;
        final hasBody = banner.text.isNotEmpty;
        // Text-only info banner → muted footer style.
        if (!hasTitle && hasBody) {
          return FooterNote(text: banner.text);
        }
        // Title present (possibly with body) → prominent hero-style row.
        final inset = ConfigurationAppearance.sideInset(context);
        return Padding(
          padding: EdgeInsets.fromLTRB(inset, 4, inset, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasTitle)
                Text(
                  banner.title!,
                  style: KalinkaTextStyles.trayRowLabel.copyWith(
                    fontSize: KalinkaTypography.baseSize + 6,
                    color: KalinkaColors.textPrimary,
                  ),
                ),
              if (hasTitle && hasBody) const SizedBox(height: 2),
              if (hasBody)
                Text(
                  banner.text,
                  style: KalinkaTextStyles.trayRowSublabel.copyWith(
                    fontSize: KalinkaTypography.baseSize + 1,
                  ),
                ),
            ],
          ),
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Field renderer: FieldSpec → SettingsRow+control
// ---------------------------------------------------------------------------

class SchemaFieldRenderer extends StatelessWidget {
  final FieldSpec field;

  /// Lists what the backend suggests under the field instead of behind a
  /// Browse button, where the form has the room for it.
  final bool listSuggestions;

  /// As [SettingsRow.gutter].
  final double gutter;

  /// A read-only field reporting on this one, shown under its help.
  final FieldSpec? statusField;

  const SchemaFieldRenderer({
    super.key,
    required this.field,
    this.listSuggestions = false,
    this.gutter = kSettingsGutter,
    this.statusField,
  });

  @override
  Widget build(BuildContext context) {
    final binding = SettingsScope.of(context);
    final configuration = ConfigurationAppearance.active(context);
    final label = field.label;
    final help = field.help;
    final isStaged = binding.isStaged(field.path);
    final value = binding.effectiveValue(field.path) ?? field.defaultValue;
    final status = switch (statusField) {
      final status? => binding.effectiveValue(status.path)?.toString().trim(),
      null => null,
    };

    // Plain read-only values are metadata, with no input border or fill.
    // Rich status messages retain their card and markdown presentation.
    if (field.readonly) {
      if (field.widget == WidgetKind.text) {
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(label, style: KalinkaTextStyles.trayRowSublabel),
                  Text(
                    (value ?? '').toString(),
                    style: KalinkaTextStyles.trayRowSublabel.copyWith(
                      color: KalinkaColors.textSecondary,
                    ),
                  ),
                ],
              ),
              if (help != null) ...[
                const SizedBox(height: 2),
                InlineMarkdown(
                  text: help,
                  style: KalinkaTextStyles.trayRowSublabel,
                ),
              ],
            ],
          ),
        );
      }
      return SettingsRow(
        label: label,
        sublabel: help,
        isVertical: true,
        gutter: gutter,
        control: SettingsReadonlyCard(text: (value ?? '').toString()),
      );
    }

    // Sliders carry their own label + value readout + range labels, so we
    // render them bare (no SettingsRow wrapper — that would duplicate the
    // label).
    if (field.widget == WidgetKind.numberSlider) {
      if (configuration) {
        return SettingsRow(
          label: label,
          sublabel: help,
          isStaged: isStaged,
          isVertical: true,
          gutter: gutter,
          issues: binding.issuesFor(field.path),
          control: buildSliderControl(
            field: field,
            value: value,
            onChanged: (v) => binding.stage(field.path, v),
            dense: true,
          ),
        );
      }
      return buildSliderControl(
        field: field,
        value: value,
        onChanged: (v) => binding.stage(field.path, v),
        dense: false,
      );
    }

    // Pills, list editors, text inputs, and multi-line controls need the full
    // row width — they render stacked below the label rather than inline.
    final vertical =
        field.widget == WidgetKind.listEditor ||
        field.widget == WidgetKind.folderList ||
        field.widget == WidgetKind.enumPills ||
        field.widget == WidgetKind.enumDropdown ||
        field.widget == WidgetKind.text ||
        field.widget == WidgetKind.password ||
        field.widget == WidgetKind.path ||
        field.widget == WidgetKind.url;

    // A list field places issues per item itself; everything else shows
    // them under the control.
    final issues = binding.issuesFor(field.path);
    final isList =
        field.widget == WidgetKind.listEditor ||
        field.widget == WidgetKind.folderList;

    return SettingsRow(
      label: label,
      sublabel: help,
      status: status == null || status.isEmpty ? null : status,
      isStaged: isStaged,
      isVertical: vertical,
      gutter: gutter,
      issues: isList ? const [] : issues,
      control: buildFieldControl(
        field: field,
        value: value,
        options: binding,
        issues: issues,
        secretHidden: binding.hasHiddenSecret(field.path),
        listSuggestions: listSuggestions,
        onChanged: (v) => binding.stage(field.path, v),
      ),
    );
  }
}

/// Slider for a bounded numeric field, built the same way wherever it appears.
///
/// [dense] is the expert row, which prints the label itself and gives the
/// control the full row width; the simple page passes false and lets the
/// slider carry its own label.
Widget buildSliderControl({
  required FieldSpec field,
  required dynamic value,
  required ValueChanged<dynamic> onChanged,
  required bool dense,
}) {
  final c = field.constraints;
  final min = c?.sliderMin ?? c?.ge ?? 0;
  final max = c?.sliderMax ?? c?.le ?? 100;
  final unit = c?.unit ?? '';
  String fmt(num n) => '${n.toInt()}${unit.isEmpty ? '' : ' $unit'}';
  return SettingsSlider(
    label: dense ? '' : field.label,
    value: (value as num? ?? 0).toDouble().clamp(min, max),
    min: min,
    max: max,
    step: c?.step,
    minLabel: fmt(min),
    maxLabel: fmt(max),
    formatValue: fmt,
    dense: dense,
    onChanged: (nv) => onChanged(nv.round()),
  );
}

/// Dispatch a [FieldSpec] to the right editable widget, given the
/// current value, a source of live enum options, and a callback that
/// stages the change.
///
/// Exposed at module level so the expert/about:config screen can
/// reuse exactly the same control widgets the simple page uses —
/// the rows there look different (mono path, dense layout), but
/// every input behaves identically and shares the staging flow.
///
/// Takes [EnumOptionSource] rather than a whole settings store: the
/// dispatcher reads options and nothing else, so anything that can
/// answer that one question can drive these controls.
///
/// [compact] is false on the expert screen, where every control
/// occupies a dedicated row beneath the path — narrow defaults like
/// the 80px numeric input look stranded in that space, so we let
/// them stretch. The simple page passes [compact]=true to keep the
/// established right-aligned layout next to a label.
///
/// [secretHidden] is [SettingsBinding.hasHiddenSecret] for the field: the
/// store holds a credential there that [value] cannot carry.
///
/// [listSuggestions] lists a field's suggestions under it rather than behind
/// a Browse button.
Widget buildFieldControl({
  required FieldSpec field,
  required dynamic value,
  required EnumOptionSource options,
  required ValueChanged<dynamic> onChanged,
  List<ConfigIssue> issues = const [],
  bool compact = true,
  bool secretHidden = false,
  bool listSuggestions = false,
}) {
  switch (field.widget) {
    case WidgetKind.toggle:
      return compact
          ? SettingsToggle(value: value == true, onChanged: onChanged)
          // Left-align a toggle in a full-width slot so it doesn't
          // sit alone in the middle of the row.
          : Align(
              alignment: Alignment.centerLeft,
              child: SettingsToggle(value: value == true, onChanged: onChanged),
            );
    case WidgetKind.numberInput:
      return SettingsNumericInput(
        value: value is num ? value : 0,
        onChanged: onChanged,
        unit: field.constraints?.unit,
        min: field.constraints?.ge,
        max: field.constraints?.le,
        // Match the surrounding controls (text, dropdown) when the
        // row gives us its full width.
        width: compact ? 80 : double.infinity,
      );
    case WidgetKind.numberSlider:
      // SchemaFieldRenderer renders sliders with the field label before
      // reaching here; the expert/onboarding rows route through this dispatch
      // and already show the label above, so the dense form drops it.
      return buildSliderControl(
        field: field,
        value: value,
        onChanged: onChanged,
        dense: true,
      );
    case WidgetKind.enumDropdown:
      // Dropdown — used for enums whose options are long, numerous,
      // or resolved live (e.g. ALSA devices). Live options ship in
      // the values envelope as enum_options[path]; if missing, fall
      // back to the schema's static enum_values shaped as
      // (value = label) pairs.
      final liveOptions = options.optionsFor(field.path);
      final enumOptions =
          liveOptions ??
          (field.enumValues ?? const [])
              .map((v) => OptionSpec(value: v, label: v))
              .toList();
      return SettingsEnumDropdown(
        options: enumOptions,
        selectedValue: (value ?? '').toString(),
        onChanged: onChanged,
      );
    case WidgetKind.enumPills:
      return SettingsEnumPills(
        options: field.enumValues ?? const [],
        selected: (value ?? '').toString(),
        onChanged: onChanged,
      );
    case WidgetKind.listEditor:
    case WidgetKind.folderList:
      final items =
          (value as List?)?.map((e) => e.toString()).toList() ?? const [];
      return SettingsListEditor(
        items: items,
        addLabel: field.widget == WidgetKind.folderList
            ? 'Add folder'
            : 'Add item',
        suggestions: field.dynamicOptions
            ? (options.optionsFor(field.path) ?? const [])
            : null,
        issues: issues,
        onChanged: onChanged,
      );
    case WidgetKind.password:
      return SettingsPasswordInput(
        value: (value ?? '').toString(),
        hidden: secretHidden,
        onChanged: onChanged,
      );
    case WidgetKind.text:
    case WidgetKind.path:
    case WidgetKind.url:
      if (field.dynamicOptions) {
        final suggestions = options.optionsFor(field.path) ?? const [];
        return listSuggestions
            ? SettingsComboList(
                value: (value ?? '').toString(),
                options: suggestions,
                borderColor: issueBorderColor(issues),
                onChanged: onChanged,
              )
            : SettingsComboInput(
                value: (value ?? '').toString(),
                options: suggestions,
                borderColor: issueBorderColor(issues),
                onChanged: onChanged,
              );
      }
      return SettingsTextInput(
        value: (value ?? '').toString(),
        borderColor: issueBorderColor(issues),
        onChanged: onChanged,
      );
    case WidgetKind.richText:
      // Rich text is always display-only; if a backend marks a field
      // rich_text without readonly we still refuse to expose an editor.
      return SettingsReadonlyCard(text: (value ?? '').toString());
  }
}

// ---------------------------------------------------------------------------
// Rows: fields with the collections and sections placed among them
// ---------------------------------------------------------------------------

/// One thing a module or section lays out.
sealed class _Placed {
  const _Placed();
}

class _Field extends _Placed {
  final FieldSpec spec;
  const _Field(this.spec);
}

class _Collection extends _Placed {
  final CollectionSpec spec;
  const _Collection(this.spec);
}

class _Section extends _Placed {
  final SectionSpec spec;
  const _Section(this.spec);
}

/// The [fields] shown, each of [collections] right after the field it
/// follows and each of [sections] right before the one it precedes — hidden
/// or not, so neither moves when that field goes into a header, or is one a
/// collection stands in for.
///
/// [replaced] is every path a collection of the module shows in its own
/// way, wherever in the module that collection sits.
List<_Placed> _laidOut(
  List<FieldSpec> fields,
  List<CollectionSpec> collections,
  List<SectionSpec> sections, {
  Set<FieldSpec> hidden = const {},
  Set<String> replaced = const {},
}) {
  final placed = {null, ...fields.map((f) => f.path)};
  final gone = {...replaced, ..._shownByCollections(collections)};
  return [
    for (final c in collections)
      if (c.after == null) _Collection(c),
    for (final field in fields) ...[
      for (final s in sections)
        if (s.before == field.path) _Section(s),
      if (!hidden.contains(field) && !gone.contains(field.path)) _Field(field),
      for (final c in collections)
        if (c.after == field.path) _Collection(c),
    ],
    // One placed by a field the page does not have still belongs on it.
    for (final c in collections)
      if (!placed.contains(c.after)) _Collection(c),
    for (final s in sections)
      if (s.before == null || !placed.contains(s.before)) _Section(s),
  ];
}

/// Fields [collections] show in their own way: the older ones they replace
/// and the status they carry.
Set<String> _shownByCollections(Iterable<CollectionSpec> collections) => {
  for (final c in collections) ...[...c.replaces, ?c.status],
};

List<Widget> _rowsOf(
  List<_Placed> items, {
  Set<String> replaced = const {},
  bool showServerUpdate = true,
}) => [
  for (final item in items)
    switch (item) {
      _Field(:final spec) => SchemaFieldRenderer(
        key: ValueKey(spec.path),
        field: spec,
      ),
      _Collection(:final spec) => SchemaCollectionRenderer(
        key: ValueKey(spec.path),
        collection: spec,
      ),
      _Section(:final spec) => SchemaSectionRenderer(
        key: ValueKey(spec.id),
        section: spec,
        replaced: replaced,
        showServerUpdate: showServerUpdate,
      ),
    },
];

const _rowDivider = Divider(
  height: 1,
  thickness: 1,
  color: KalinkaColors.borderSubtle,
);

Widget _separated(List<Widget> rows) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    for (var i = 0; i < rows.length; i++) ...[if (i > 0) _rowDivider, rows[i]],
  ],
);

// ---------------------------------------------------------------------------
// Section renderer
// ---------------------------------------------------------------------------

class SchemaSectionRenderer extends StatelessWidget {
  final SectionSpec section;
  final bool isTopLevel;
  final bool showServerUpdate;

  /// Metadata line under a top-level section's label, e.g. the renderer
  /// page's host + version badge.
  final Widget? subtitle;

  /// Paths a collection elsewhere in the module stands in for.
  final Set<String> replaced;

  const SchemaSectionRenderer({
    super.key,
    required this.section,
    this.isTopLevel = false,
    this.showServerUpdate = true,
    this.subtitle,
    this.replaced = const {},
  });

  @override
  Widget build(BuildContext context) {
    // The backend prunes EXPERT-tier content out of the simple page
    // tree before sending, so the renderer no longer filters by
    // importance — every field/section it receives is meant to be
    // visible. Expert configuration lives behind the dedicated
    // about:config screen, not as an in-place reveal here.

    // A nested section with an `.enabled` field is a "sub-feature":
    // render its header with an integrated toggle and pull the optional
    // `.status_view` dynamic field's value into the header subtitle.
    // Both fields are then hidden from the regular field list — they
    // belong in the header, not the body.
    final enabledField = isTopLevel
        ? null
        : _firstFieldWithPathSuffix(section.fields, '.enabled');
    final statusField = enabledField == null
        ? null
        : _firstFieldWithPathSuffix(section.fields, '.status_view');

    final rows = _rowsOf(
      _laidOut(
        section.fields,
        section.collections,
        section.sections,
        hidden: {?enabledField, ?statusField},
        replaced: replaced,
      ),
      replaced: replaced,
      showServerUpdate: showServerUpdate,
    );

    // Toggleable sub-feature section: route through the dedicated header
    // widget with the body unchanged.
    if (enabledField != null) {
      return _buildToggleableSection(
        SettingsScope.of(context),
        enabledField,
        statusField,
        rows,
      );
    }

    if (rows.isEmpty) {
      return Column(
        children: [
          for (final banner in section.banners) SchemaBanner(banner: banner),
        ],
      );
    }
    final body = _separated(rows);

    // Top-level section: label + card. (The legacy "advanced" branch
    // was dropped together with the three-tier importance model — the
    // simple page is now a flat list of named sections, with anything
    // power-user-tuned routed to the expert about:config screen.)
    if (isTopLevel) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionLabel(
            context,
            section.title,
            subtitle:
                section.id == 'base_config.server' &&
                    !ConfigurationAppearance.active(context)
                ? const _ServerAddressBadge()
                : subtitle,
          ),
          // "New version available ›" banner between the SERVER label
          // and the settings fields; hidden when there's no update.
          if (showServerUpdate && section.id == 'base_config.server')
            const ServerUpdateBanner(),
          ...section.banners.map((b) => SchemaBanner(banner: b)),
          SettingsCard(children: [body]),
        ],
      );
    }

    // Nested section: inline collapsible, expanded by default since
    // every simple-tier section is meant to be visible at a glance.
    return SettingsSection(
      title: section.title,
      showTopBorder: false,
      initiallyExpanded: true,
      child: body,
    );
  }

  static FieldSpec? _firstFieldWithPathSuffix(
    List<FieldSpec> fields,
    String suffix,
  ) {
    for (final f in fields) {
      if (f.path.endsWith(suffix)) return f;
    }
    return null;
  }

  Widget _buildToggleableSection(
    SettingsBinding binding,
    FieldSpec enabledField,
    FieldSpec? statusField,
    List<Widget> rows,
  ) {
    final enabledValue =
        (binding.effectiveValue(enabledField.path) ??
                enabledField.defaultValue ??
                false)
            as bool;
    final isStaged = binding.isStaged(enabledField.path);

    // Status text is whichever value the values blob currently carries
    // for the dynamic status_view field — resolved server-side by the
    // owning plugin.
    String? statusMarkdown;
    if (statusField != null) {
      final raw = binding.effectiveValue(statusField.path);
      if (raw != null && raw.toString().trim().isNotEmpty) {
        statusMarkdown = raw.toString();
      }
    }

    return SettingsToggleableSection(
      title: section.title,
      enabled: enabledValue,
      onToggle: (v) => binding.stage(enabledField.path, v),
      statusMarkdown: statusMarkdown,
      body: rows.isEmpty ? null : _separated(rows),
      // Simple-tier sub-features expand by default — anything users
      // shouldn't need to see lives behind the expert search now.
      initiallyExpanded: true,
      isStaged: isStaged,
    );
  }

  static Widget _sectionLabel(
    BuildContext context,
    String label, {
    Widget? subtitle,
  }) {
    return Padding(
      padding: ConfigurationAppearance.sectionPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: KalinkaTextStyles.sectionHeaderMuted,
          ),
          if (subtitle != null) ...[const SizedBox(height: 4), subtitle],
        ],
      ),
    );
  }
}

/// Shows the address and `v<version>` on the metadata line under the Server
/// section title. Version is shown in full; the Text ellipsises if it
/// overflows the available width.
class _ServerAddressBadge extends ConsumerWidget {
  const _ServerAddressBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(connectionSettingsProvider);
    final serverInfo = ref.watch(serverInfoProvider);
    final version = serverInfo.whenOrNull(data: (i) => i.version);

    final parts = <String>[
      if (settings.host.isNotEmpty) settings.displayAddress,
      if (version != null && version != 'Unknown') 'v$version',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(
      parts.join(' · '),
      style: KalinkaTextStyles.trayRowSublabel.copyWith(
        fontSize: KalinkaTypography.baseSize + 1,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

// ---------------------------------------------------------------------------
// Module card renderer
// ---------------------------------------------------------------------------

class SchemaModuleCard extends ConsumerStatefulWidget {
  final ModuleSpec module;
  final bool initiallyExpanded;
  const SchemaModuleCard({
    super.key,
    required this.module,
    this.initiallyExpanded = false,
  });

  @override
  ConsumerState<SchemaModuleCard> createState() => _SchemaModuleCardState();
}

class _SchemaModuleCardState extends ConsumerState<SchemaModuleCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.module;
    // Modules only ever appear on the server's own settings page, but they read
    // values through the same binding as everything else — nothing here needs
    // to know which store is behind it.
    final binding = SettingsScope.of(context);

    // Live module state lives at /server/modules — the schema deliberately
    // doesn't carry it so schema_version doesn't churn on plugin hiccups.
    final liveSnapshot = ref.watch(modulesStateProvider).value;
    final ModuleInfo? live = liveSnapshot == null
        ? null
        : lookupModule(liveSnapshot, m.id, m.kind);
    final status = live == null ? null : _moduleStatusFor(live.state);
    final message = live?.message;

    // Preview subtitle from backend-declared preview_fields.
    final subtitle = _subtitleFor(m, binding);
    final icon = schemaIcon(m.icon);
    final color = _colorFromHex(m.iconColor, KalinkaColors.textSecondary);

    // Hoist a module-level `.enabled` field into the header switch, mirroring
    // the toggleable-section pattern used for nested sub-features.
    final enabledField = m.enabledField;
    final bool? enabledValue = enabledField == null
        ? null
        : (binding.effectiveValue(enabledField.path) ??
                  enabledField.defaultValue ??
                  false)
              as bool;

    final hasBody =
        (message != null && message.isNotEmpty) ||
        m.banners.isNotEmpty ||
        SchemaModuleBody.rowsOf(m).isNotEmpty;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: KalinkaColors.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: KalinkaColors.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ModuleHeaderRow(
            title: m.title,
            subtitle: subtitle,
            icon: icon,
            iconColor: color,
            status: status,
            expanded: _expanded,
            onToggle: () => setState(() => _expanded = !_expanded),
            hasBody: hasBody,
            enabled: enabledValue,
            onEnabledChanged: enabledField == null
                ? null
                : (v) => binding.stage(enabledField.path, v),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 340),
            curve: const Cubic(0.4, 0, 0.2, 1),
            alignment: Alignment.topCenter,
            child: _expanded
                ? SchemaModuleBody(module: m)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  ModuleStatus _moduleStatusFor(ModuleState state) => switch (state) {
    ModuleState.ready => ModuleStatus.ready,
    ModuleState.warning => ModuleStatus.warning,
    ModuleState.error => ModuleStatus.error,
    ModuleState.disabled => ModuleStatus.disabled,
  };

  /// Build the subtitle by reading `module.previewFields` from the staged/server values.
  String _subtitleFor(ModuleSpec m, SettingsBinding binding) {
    final parts = <String>[];
    final prefix = m.kind == 'device'
        ? 'devices.${m.id}'
        : 'input_modules.${m.id}';
    for (final name in m.previewFields) {
      final path = '$prefix.$name';
      final collection = m.collectionReplacing(path);
      if (collection != null) {
        final preview = collection.previewOf(
          entriesOf(binding.effectiveValue(collection.path)),
        );
        if (preview.isNotEmpty) parts.add(preview);
        continue;
      }
      final v = binding.effectiveValue(path);
      if (v == null) continue;
      if (v is List) {
        if (v.isNotEmpty) {
          parts.add(v.length == 1 ? v.first.toString() : '${v.length} items');
        }
      } else if (v is num) {
        if (v > 0) parts.add(v.toString());
      } else {
        final s = v.toString();
        if (s.isNotEmpty) parts.add(s);
      }
    }
    if (parts.isEmpty) {
      return m.kind == 'device' ? 'Output device' : 'Input module';
    }
    return parts.join(' \u00b7 ');
  }
}

/// What a module configures, below its header in [SchemaModuleCard]: its live
/// message, banners and rows, dimmed while the module is switched off.
class SchemaModuleBody extends ConsumerWidget {
  final ModuleSpec module;

  const SchemaModuleBody({super.key, required this.module});

  /// Backend prunes EXPERT content out of the simple page tree, so the only
  /// filter here is "drop the .enabled field the header shows".
  static List<Widget> rowsOf(ModuleSpec module) {
    final replaced = _shownByCollections(module.allCollections);
    return _rowsOf(
      _laidOut(
        module.fields,
        module.collections,
        module.sections,
        hidden: {?module.enabledField},
        replaced: replaced,
      ),
      replaced: replaced,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final binding = SettingsScope.of(context);
    final liveSnapshot = ref.watch(modulesStateProvider).value;
    final ModuleInfo? live = liveSnapshot == null
        ? null
        : lookupModule(liveSnapshot, module.id, module.kind);
    final message = live?.message;
    final enabledField = module.enabledField;
    final dimmed =
        enabledField != null &&
        (binding.effectiveValue(enabledField.path) ??
                enabledField.defaultValue ??
                false) ==
            false;

    return Opacity(
      opacity: dimmed ? 0.45 : 1.0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (message != null && message.isNotEmpty)
            WarningNote(
              message: message,
              severity: live?.state == ModuleState.error
                  ? WarningNoteSeverity.error
                  : WarningNoteSeverity.warning,
            ),
          for (final b in module.banners) SchemaBanner(banner: b),
          // A divider above each row, so it reads as continuous content under
          // the header rather than floating.
          for (final row in rowsOf(module)) ...[_rowDivider, row],
        ],
      ),
    );
  }
}

/// A plugin's settings page: what the module configures as labelled cards —
/// one for each collection, each section, and each run of fields a heading
/// opens — with nothing folded away. Sections inside a card open in place,
/// and a status field reads as the live state of the field before it.
class SchemaModuleGroups extends StatelessWidget {
  final ModuleSpec module;
  final double gutter;

  const SchemaModuleGroups({
    super.key,
    required this.module,
    required this.gutter,
  });

  @override
  Widget build(BuildContext context) {
    final binding = SettingsScope.of(context);
    final replaced = _shownByCollections(module.allCollections);
    final groups = <_Group>[];
    _Group? run;
    for (final item in _laidOut(
      module.fields,
      module.collections,
      module.sections,
      hidden: {?module.enabledField},
      replaced: replaced,
    )) {
      switch (item) {
        case _Field(:final spec):
          if (run == null || spec.heading != null) {
            run = _Group(spec.heading);
            groups.add(run);
          }
          run.items.add(item);
        case _Collection(:final spec):
          run = null;
          groups.add(
            _Group(spec.title, caption: spec.help)
              ..rows.add(
                SchemaCollectionRenderer(
                  key: ValueKey(spec.path),
                  collection: spec,
                  showTitle: false,
                ),
              ),
          );
        case _Section(:final spec):
          run = null;
          groups.add(
            _Group(spec.title)
              ..rows.addAll(_cardRows(binding, spec, replaced, titled: false)),
          );
      }
    }
    for (final group in groups) {
      group.rows.addAll(_flatRows(binding, group.items, replaced));
    }
    final shown = groups.where((g) => g.rows.isNotEmpty).toList();
    final enabledField = module.enabledField;
    final off = enabledField != null && !_isOn(binding, enabledField);
    return Opacity(
      opacity: off ? 0.45 : 1.0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final b in module.banners) SchemaBanner(banner: b),
          for (final (i, group) in shown.indexed) ...[
            if (group.label case final label?)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  gutter,
                  i == 0 ? 6 : 20,
                  gutter,
                  10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: KalinkaTextStyles.sectionHeaderMuted,
                    ),
                    if (group.caption case final caption?) ...[
                      const SizedBox(height: 4),
                      InlineMarkdown(
                        text: caption,
                        style: KalinkaTextStyles.trayRowSublabel,
                      ),
                    ],
                  ],
                ),
              )
            else if (i > 0)
              const SizedBox(height: 8),
            SettingsCard(gutter: gutter, children: [_separated(group.rows)]),
          ],
        ],
      ),
    );
  }

  static bool _isOn(SettingsBinding binding, FieldSpec field) =>
      (binding.effectiveValue(field.path) ?? field.defaultValue) == true;

  /// A section's settings as rows of the card it sits in. A section with a
  /// switch of its own leads with it and dims the rest while it is off.
  static List<Widget> _cardRows(
    SettingsBinding binding,
    SectionSpec section,
    Set<String> replaced, {
    required bool titled,
  }) {
    // Its own, not one of a model laid out inline within it.
    final enabled = section.fields
        .where((f) => f.path == '${section.id}.enabled')
        .firstOrNull;
    final items = _laidOut(
      section.fields,
      section.collections,
      section.sections,
      replaced: replaced,
    );
    return [
      // One that only groups other sections has nothing of its own to head.
      if (titled && enabled == null && section.fields.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            kSettingsGutter,
            14,
            kSettingsGutter,
            0,
          ),
          child: Text(
            section.title.toUpperCase(),
            style: KalinkaTextStyles.sectionHeaderMuted,
          ),
        ),
      ..._flatRows(
        binding,
        items,
        replaced,
        lead: enabled,
        leadOff: enabled != null && !_isOn(binding, enabled),
      ),
    ];
  }

  /// [items] as rows, a status field joining the row of the field before it.
  /// While [leadOff], every row but [lead]'s is dimmed.
  static List<Widget> _flatRows(
    SettingsBinding binding,
    List<_Placed> items,
    Set<String> replaced, {
    FieldSpec? lead,
    bool leadOff = false,
  }) {
    bool isStatus(_Placed? item) =>
        item is _Field &&
        item.spec.readonly &&
        item.spec.path.endsWith('.status_view');
    // Only a row SchemaFieldRenderer ends in a SettingsRow has room for it.
    bool takesStatus(FieldSpec spec) =>
        !spec.readonly && spec.widget != WidgetKind.numberSlider;
    final rows = <Widget>[];
    // Always wrapped, so toggling the lead keeps the rows' state.
    void add(Widget row, {bool isLead = false}) =>
        rows.add(Opacity(opacity: leadOff && !isLead ? 0.45 : 1.0, child: row));
    for (var i = 0; i < items.length; i++) {
      switch (items[i]) {
        case _Field(:final spec):
          final next = i + 1 < items.length ? items[i + 1] : null;
          final status = takesStatus(spec) && isStatus(next)
              ? (next! as _Field).spec
              : null;
          if (status != null) i++;
          add(
            SchemaFieldRenderer(
              key: ValueKey(spec.path),
              field: spec,
              statusField: status,
            ),
            isLead: spec == lead,
          );
        case _Collection(:final spec):
          add(
            SchemaCollectionRenderer(
              key: ValueKey(spec.path),
              collection: spec,
            ),
          );
        case _Section(:final spec):
          for (final row in _cardRows(binding, spec, replaced, titled: true)) {
            add(row);
          }
      }
    }
    return rows;
  }
}

/// One card of [SchemaModuleGroups], under [label] where it has one.
class _Group {
  final String? label;
  final String? caption;

  /// Fields of a run, turned into [rows] once the run ends.
  final List<_Placed> items = [];
  final List<Widget> rows = [];

  _Group(this.label, {this.caption});
}

// ---------------------------------------------------------------------------
// Page renderer
// ---------------------------------------------------------------------------

class SchemaPageRenderer extends ConsumerWidget {
  final PageSpec page;

  /// Drawn after the page's own sections — what the app adds to a page the
  /// server describes.
  final Widget? footer;

  const SchemaPageRenderer({super.key, required this.page, this.footer});

  /// True for the output-devices page. Page ids mirror the config paths
  /// (`devices.*`), so a `device` substring identifies it.
  bool get _isDevicePage =>
      page.id.toLowerCase().contains('device') ||
      page.title.toLowerCase().contains('device');

  /// True for either plugin-backed page (input modules or output devices) —
  /// the pages whose body is a list of installed plugins.
  bool get _isPluginPage =>
      _isDevicePage ||
      page.id.toLowerCase().contains('module') ||
      page.title.toLowerCase().contains('module');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A modules/devices page with nothing to show means the server has no
    // plugins of that kind installed. Surface a dedicated empty state telling
    // the user to install plugins rather than rendering a blank list. The
    // General page (base_config) always carries sections, so it never trips
    // this branch.
    if (_isPluginPage && page.modules.isEmpty && page.sections.isEmpty) {
      return ModulesEmptyState(isDevice: _isDevicePage);
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        for (final b in page.banners) SchemaBanner(banner: b),
        for (final s in page.sections)
          SchemaSectionRenderer(
            key: ValueKey(s.id),
            section: s,
            isTopLevel: true,
          ),
        if (page.modules.isNotEmpty) ...[
          for (int i = 0; i < page.modules.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 8 : 0),
              child: SchemaModuleCard(
                key: ValueKey(page.modules[i].id),
                module: page.modules[i],
                initiallyExpanded: i == 0,
              ),
            ),
        ],
        ?footer,
      ],
    );
  }
}
