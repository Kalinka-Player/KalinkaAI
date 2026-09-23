import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data_model/data_model.dart' show ModuleInfo, ModuleState;
import '../data_model/presentation_schema.dart';
import '../providers/connection_settings_provider.dart';
import '../providers/modules_state_provider.dart';
import '../providers/server_info_provider.dart';
import '../theme/app_theme.dart';
import 'server_update_banner.dart';
import 'settings_controls/footer_note.dart';
import 'settings_controls/issue_notes.dart';
import 'settings_controls/settings_binding.dart';
import 'settings_controls/module_header_row.dart';
import 'settings_controls/settings_card.dart';
import 'settings_controls/settings_combo_input.dart';
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

// ---------------------------------------------------------------------------
// Icons
// ---------------------------------------------------------------------------

/// Map a backend material icon name to a Flutter IconData. Only icons the
/// backend actually emits need entries here.
IconData _iconFromName(String? name) {
  switch (name) {
    case 'folder_outlined':
      return Icons.folder_outlined;
    case 'music_note_outlined':
      return Icons.music_note_outlined;
    case 'speaker_outlined':
      return Icons.speaker_outlined;
    case 'waves_outlined':
      return Icons.waves_outlined;
    case 'extension_outlined':
    default:
      return Icons.extension_outlined;
  }
}

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
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
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
  const SchemaFieldRenderer({super.key, required this.field});

  @override
  Widget build(BuildContext context) {
    final binding = SettingsScope.of(context);
    final isStaged = binding.isStaged(field.path);
    final value = binding.effectiveValue(field.path) ?? field.defaultValue;

    // Read-only fields (including dynamic plugin-resolved status views)
    // never get an editable control. Render as a labeled elevated card
    // so users see the value as content, not as a disabled input.
    if (field.readonly) {
      return SettingsRow(
        label: field.label,
        sublabel: field.help,
        isVertical: true,
        control: SettingsReadonlyCard(text: (value ?? '').toString()),
      );
    }

    // Sliders carry their own label + value readout + range labels, so we
    // render them bare (no SettingsRow wrapper — that would duplicate the
    // label).
    if (field.widget == WidgetKind.numberSlider) {
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
      label: field.label,
      sublabel: field.help,
      isStaged: isStaged,
      isVertical: vertical,
      issues: isList ? const [] : issues,
      control: buildFieldControl(
        field: field,
        value: value,
        options: binding,
        issues: issues,
        secretHidden: binding.hasHiddenSecret(field.path),
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
Widget buildFieldControl({
  required FieldSpec field,
  required dynamic value,
  required EnumOptionSource options,
  required ValueChanged<dynamic> onChanged,
  List<ConfigIssue> issues = const [],
  bool compact = true,
  bool secretHidden = false,
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
        return SettingsComboInput(
          value: (value ?? '').toString(),
          options: options.optionsFor(field.path) ?? const [],
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
// Section renderer
// ---------------------------------------------------------------------------

class SchemaSectionRenderer extends StatelessWidget {
  final SectionSpec section;
  final bool isTopLevel;

  /// Metadata line under a top-level section's label, e.g. the renderer
  /// page's host + version badge.
  final Widget? subtitle;

  const SchemaSectionRenderer({
    super.key,
    required this.section,
    this.isTopLevel = false,
    this.subtitle,
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

    final visibleFields = section.fields
        .where((f) => f != enabledField && f != statusField)
        .toList();
    final visibleSubSections = section.sections;

    // Toggleable sub-feature section: route through the dedicated header
    // widget with the body unchanged.
    if (enabledField != null) {
      return _buildToggleableSection(
        SettingsScope.of(context),
        enabledField,
        statusField,
        visibleFields,
        visibleSubSections,
      );
    }

    if (visibleFields.isEmpty && visibleSubSections.isEmpty) {
      return const SizedBox.shrink();
    }

    final rows = <Widget>[
      for (final f in visibleFields)
        SchemaFieldRenderer(key: ValueKey(f.path), field: f),
      for (final s in visibleSubSections)
        SchemaSectionRenderer(key: ValueKey(s.id), section: s),
    ];
    final separated = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        separated.add(
          const Divider(
            height: 1,
            thickness: 1,
            color: KalinkaColors.borderSubtle,
          ),
        );
      }
      separated.add(rows[i]);
    }
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: separated,
    );

    // Top-level section: label + card. (The legacy "advanced" branch
    // was dropped together with the three-tier importance model — the
    // simple page is now a flat list of named sections, with anything
    // power-user-tuned routed to the expert about:config screen.)
    if (isTopLevel) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionLabel(
            section.title,
            subtitle: section.id == 'base_config.server'
                ? const _ServerAddressBadge()
                : subtitle,
          ),
          // "New version available ›" banner between the SERVER label
          // and the settings fields; hidden when there's no update.
          if (section.id == 'base_config.server') const ServerUpdateBanner(),
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
    List<FieldSpec> bodyFields,
    List<SectionSpec> bodySubSections,
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

    Widget? body;
    if (bodyFields.isNotEmpty || bodySubSections.isNotEmpty) {
      final rows = <Widget>[
        for (final f in bodyFields)
          SchemaFieldRenderer(key: ValueKey(f.path), field: f),
        for (final s in bodySubSections)
          SchemaSectionRenderer(key: ValueKey(s.id), section: s),
      ];
      final separated = <Widget>[];
      for (var i = 0; i < rows.length; i++) {
        if (i > 0) {
          separated.add(
            const Divider(
              height: 1,
              thickness: 1,
              color: KalinkaColors.borderSubtle,
            ),
          );
        }
        separated.add(rows[i]);
      }
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: separated,
      );
    }

    return SettingsToggleableSection(
      title: section.title,
      enabled: enabledValue,
      onToggle: (v) => binding.stage(enabledField.path, v),
      statusMarkdown: statusMarkdown,
      body: body,
      // Simple-tier sub-features expand by default — anything users
      // shouldn't need to see lives behind the expert search now.
      initiallyExpanded: true,
      isStaged: isStaged,
    );
  }

  static Widget _sectionLabel(String label, {Widget? subtitle}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 10),
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

/// Shows `host:port · v<version>` on the metadata line under the Server
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
      if (settings.host.isNotEmpty) '${settings.host}:${settings.port}',
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
    final isError = live?.state == ModuleState.error;

    // Preview subtitle from backend-declared preview_fields.
    final subtitle = _subtitleFor(m, binding);
    final icon = _iconFromName(m.icon);
    final color = _colorFromHex(m.iconColor, KalinkaColors.textSecondary);

    // Hoist a module-level `.enabled` field into the header switch, mirroring
    // the toggleable-section pattern used for nested sub-features.
    final enabledField = _firstFieldWithPathSuffix(m.fields, '.enabled');
    final bool? enabledValue = enabledField == null
        ? null
        : (binding.effectiveValue(enabledField.path) ??
                  enabledField.defaultValue ??
                  false)
              as bool;

    // Backend prunes EXPERT content out of the simple page tree, so
    // the only filter here is "drop the .enabled field we already
    // hoisted into the header".
    final visibleSections = m.sections;
    final visibleModuleFields = m.fields
        .where((f) => f != enabledField)
        .toList();

    final bodyDimmed = enabledField != null && enabledValue == false;
    final hasBody =
        (message != null && message.isNotEmpty) ||
        m.banners.isNotEmpty ||
        visibleModuleFields.isNotEmpty ||
        visibleSections.isNotEmpty;

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
                ? Opacity(
                    opacity: bodyDimmed ? 0.45 : 1.0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (message != null && message.isNotEmpty)
                          WarningNote(
                            message: message,
                            severity: isError
                                ? WarningNoteSeverity.error
                                : WarningNoteSeverity.warning,
                          ),
                        for (final b in m.banners) SchemaBanner(banner: b),
                        // Module-level scalar fields render flat, with a
                        // divider above them so they read as continuous
                        // content under the header rather than floating.
                        for (
                          var i = 0;
                          i < visibleModuleFields.length;
                          i++
                        ) ...[
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: KalinkaColors.borderSubtle,
                          ),
                          SchemaFieldRenderer(
                            key: ValueKey(visibleModuleFields[i].path),
                            field: visibleModuleFields[i],
                          ),
                        ],
                        for (final s in visibleSections) ...[
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: KalinkaColors.borderSubtle,
                          ),
                          SchemaSectionRenderer(
                            key: ValueKey(s.id),
                            section: s,
                          ),
                        ],
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
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
      final v = binding.effectiveValue('$prefix.$name');
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
