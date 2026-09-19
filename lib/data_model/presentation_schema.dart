// Dart mirror of `presentation_schema.py` on the backend.
//
// The backend describes the entire settings UI declaratively (pages → sections
// → fields, or pages → modules → sections → fields). The frontend only has
// to render what it receives — no re-mapping, no name-based heuristics, no
// hard-coded labels or banners.

/// Two-tier UI prominence, matching the backend.
///
/// * [simple] — appears on the structured settings page (the user-facing
///   default tabs). Reserved for mandatory or frequently changed fields.
/// * [expert] — only reachable through the about:config-style search
///   screen. The backend already prunes the page tree to SIMPLE before
///   sending; the [expert] case is mainly carried so the about:config
///   list can badge entries by tier.
///
/// Legacy values `"normal"` and `"advanced"` map to [simple] and
/// [expert] respectively, so older server builds keep working without
/// a coordinated upgrade.
enum Importance {
  simple,
  expert;

  static Importance fromName(String? s) => switch (s) {
    'expert' || 'advanced' => Importance.expert,
    _ => Importance.simple,
  };
}

/// Whether a field belongs in first-run setup, per the server's tag.
///
/// `required` means the owning module cannot work until the user supplies a
/// value — the server guarantees such a field defaults to its type's empty
/// value, so "still empty" *is* "not answered yet". `prompt` has a working
/// default but is worth asking about during setup. Everything else (and any
/// unknown or missing tag, including whole schemas from older servers) is
/// `hidden` and never appears in the wizard. Independent of [Importance]:
/// a `prompt` field may be expert-tier.
enum Setup {
  required,
  prompt,
  hidden;

  static Setup fromName(String? s) => switch (s) {
    'required' => Setup.required,
    'prompt' => Setup.prompt,
    _ => Setup.hidden,
  };
}

enum Severity {
  info,
  warning,
  danger;

  static Severity fromName(String? s) => switch (s) {
    'warning' => Severity.warning,
    'danger' => Severity.danger,
    _ => Severity.info,
  };
}

enum WidgetKind {
  text,
  richText,
  password,
  path,
  url,
  toggle,
  numberInput,
  numberSlider,
  enumPills,
  enumDropdown,
  listEditor,
  folderList;

  static WidgetKind fromName(String? s) => switch (s) {
    'rich_text' => WidgetKind.richText,
    'password' => WidgetKind.password,
    'path' => WidgetKind.path,
    'url' => WidgetKind.url,
    'toggle' => WidgetKind.toggle,
    'number_input' => WidgetKind.numberInput,
    'number_slider' => WidgetKind.numberSlider,
    'enum_pills' => WidgetKind.enumPills,
    'enum_dropdown' => WidgetKind.enumDropdown,
    'list_editor' => WidgetKind.listEditor,
    'folder_list' => WidgetKind.folderList,
    _ => WidgetKind.text,
  };
}

/// One choice in a dynamic-options enum field.
///
/// The backend ships these in the values envelope under
/// ``enum_options[path]`` for fields whose option list depends on
/// live system state (e.g. ALSA devices). [value] is what gets PUT
/// back to the server (a stable identifier — `hw:CARD=…,DEV=…` for
/// ALSA); [label] is what the user sees in the dropdown.
///
/// [description] is an optional dim second line shown under [label]
/// when the dropdown opens its bottom sheet — used for the ALSA PCM
/// mode (e.g. "HDMI Audio Output") and tags like "auto-convert" or
/// "not connected". The collapsed trigger row never shows it, so the
/// rest-state row stays uncluttered.
class OptionSpec {
  final String value;
  final String label;
  final String? description;

  const OptionSpec({
    required this.value,
    required this.label,
    this.description,
  });

  factory OptionSpec.fromJson(Map<String, dynamic> j) => OptionSpec(
    value: j['value'] as String,
    label: j['label'] as String,
    description: j['description'] as String?,
  );
}

/// An error blocks Apply; a warning is shown beside the field and saved anyway.
enum IssueSeverity {
  error,
  warning;

  static IssueSeverity fromName(String? raw) =>
      raw == 'warning' ? IssueSeverity.warning : IssueSeverity.error;
}

/// Something the backend found wrong with a staged value. [path] is the
/// dotted field path; [index] narrows it to one item of a list field.
class ConfigIssue {
  final String path;
  final String message;
  final IssueSeverity severity;
  final int? index;

  const ConfigIssue({
    required this.path,
    required this.message,
    this.severity = IssueSeverity.error,
    this.index,
  });

  bool get isBlocking => severity == IssueSeverity.error;

  factory ConfigIssue.fromJson(Map<String, dynamic> j) => ConfigIssue(
    path: j['path'] as String? ?? '',
    message: j['message'] as String? ?? '',
    severity: IssueSeverity.fromName(j['severity'] as String?),
    index: j['index'] as int?,
  );
}

class BannerSpec {
  final String text;
  final Severity severity;
  final String? title;

  const BannerSpec({required this.text, required this.severity, this.title});

  factory BannerSpec.fromJson(Map<String, dynamic> j) => BannerSpec(
    text: j['text'] as String? ?? '',
    severity: Severity.fromName(j['severity'] as String?),
    title: j['title'] as String?,
  );
}

class Constraints {
  final double? ge;
  final double? le;
  final int? minLength;
  final int? maxLength;
  final double? step;
  final String? pattern;
  final String? unit;
  final double? sliderMin;
  final double? sliderMax;

  const Constraints({
    this.ge,
    this.le,
    this.minLength,
    this.maxLength,
    this.step,
    this.pattern,
    this.unit,
    this.sliderMin,
    this.sliderMax,
  });

  factory Constraints.fromJson(Map<String, dynamic> j) => Constraints(
    ge: (j['ge'] as num?)?.toDouble(),
    le: (j['le'] as num?)?.toDouble(),
    minLength: j['min_length'] as int?,
    maxLength: j['max_length'] as int?,
    step: (j['step'] as num?)?.toDouble(),
    pattern: j['pattern'] as String?,
    unit: j['unit'] as String?,
    sliderMin: (j['slider_min'] as num?)?.toDouble(),
    sliderMax: (j['slider_max'] as num?)?.toDouble(),
  );
}

class FieldSpec {
  final String path;
  final String label;
  final WidgetKind widget;
  final String type;
  final String? help;
  final dynamic defaultValue;
  final bool readonly;
  // True when the value is resolved by the owning plugin at request time
  // (e.g. sub-feature status views). Implies readonly. Distinct so the
  // UI can choose to poll for changes vs. assume stability.
  final bool dynamic_;
  // The backend may have values to suggest for this open field. Flagged
  // rather than inferred from the resolved options: an empty result must
  // still show the browse control, or it would come and go.
  final bool dynamicOptions;
  final Importance importance;
  final Setup setup;
  final List<String>? enumValues;
  final Constraints? constraints;

  const FieldSpec({
    required this.path,
    required this.label,
    required this.widget,
    required this.type,
    this.help,
    this.defaultValue,
    this.readonly = false,
    this.dynamic_ = false,
    this.dynamicOptions = false,
    this.importance = Importance.simple,
    this.setup = Setup.hidden,
    this.enumValues,
    this.constraints,
  });

  factory FieldSpec.fromJson(Map<String, dynamic> j) => FieldSpec(
    path: j['path'] as String,
    label: j['label'] as String,
    widget: WidgetKind.fromName(j['widget'] as String?),
    type: j['type'] as String,
    help: j['help'] as String?,
    defaultValue: j['default'],
    readonly: j['readonly'] as bool? ?? false,
    dynamic_: j['dynamic'] as bool? ?? false,
    dynamicOptions: j['dynamic_options'] as bool? ?? false,
    importance: Importance.fromName(j['importance'] as String?),
    setup: Setup.fromName(j['setup'] as String?),
    enumValues: (j['enum_values'] as List?)?.map((e) => e.toString()).toList(),
    constraints: j['constraints'] is Map
        ? Constraints.fromJson(
            (j['constraints'] as Map).cast<String, dynamic>(),
          )
        : null,
  );
}

class SectionSpec {
  final String id;
  final String title;
  final String? icon;
  final Importance importance;
  final List<BannerSpec> banners;
  final List<FieldSpec> fields;
  final List<SectionSpec> sections;

  const SectionSpec({
    required this.id,
    required this.title,
    this.icon,
    this.importance = Importance.simple,
    this.banners = const [],
    this.fields = const [],
    this.sections = const [],
  });

  factory SectionSpec.fromJson(Map<String, dynamic> j) => SectionSpec(
    id: j['id'] as String,
    title: j['title'] as String,
    icon: j['icon'] as String?,
    importance: Importance.fromName(j['importance'] as String?),
    banners: ((j['banners'] as List?) ?? [])
        .map((e) => BannerSpec.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
    fields: ((j['fields'] as List?) ?? [])
        .map((e) => FieldSpec.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
    sections: ((j['sections'] as List?) ?? [])
        .map((e) => SectionSpec.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
  );
}

class ModuleSpec {
  final String id;
  final String kind; // "input_module" | "device"
  final String title;
  final String? icon;
  final String? iconColor;
  final List<String> previewFields;
  final List<BannerSpec> banners;
  // Top-level scalar fields of the module's config. Backend hoists these
  // out of an auto-generated "General" section so the client renders
  // them flat under the module header rather than inside a foldable.
  final List<FieldSpec> fields;
  final List<SectionSpec> sections;

  const ModuleSpec({
    required this.id,
    required this.kind,
    required this.title,
    this.icon,
    this.iconColor,
    this.previewFields = const [],
    this.banners = const [],
    this.fields = const [],
    this.sections = const [],
  });

  factory ModuleSpec.fromJson(Map<String, dynamic> j) => ModuleSpec(
    id: j['id'] as String,
    kind: j['kind'] as String,
    title: j['title'] as String,
    icon: j['icon'] as String?,
    iconColor: j['icon_color'] as String?,
    previewFields: ((j['preview_fields'] as List?) ?? [])
        .map((e) => e.toString())
        .toList(),
    banners: ((j['banners'] as List?) ?? [])
        .map((e) => BannerSpec.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
    fields: ((j['fields'] as List?) ?? [])
        .map((e) => FieldSpec.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
    sections: ((j['sections'] as List?) ?? [])
        .map((e) => SectionSpec.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
  );
}

class PageSpec {
  final String id;
  final String title;
  final String? icon;
  final List<BannerSpec> banners;
  final List<SectionSpec> sections;
  final List<ModuleSpec> modules;

  const PageSpec({
    required this.id,
    required this.title,
    this.icon,
    this.banners = const [],
    this.sections = const [],
    this.modules = const [],
  });

  factory PageSpec.fromJson(Map<String, dynamic> j) => PageSpec(
    id: j['id'] as String,
    title: j['title'] as String,
    icon: j['icon'] as String?,
    banners: ((j['banners'] as List?) ?? [])
        .map((e) => BannerSpec.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
    sections: ((j['sections'] as List?) ?? [])
        .map((e) => SectionSpec.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
    modules: ((j['modules'] as List?) ?? [])
        .map((e) => ModuleSpec.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
  );
}

class PresentationSchema {
  final String schemaVersion;
  // Hierarchical SIMPLE view: pages → modules → sections → fields. The
  // backend has already pruned EXPERT-tier content from this tree.
  final List<PageSpec> pages;
  // Flat list of every settable field across the whole config tree,
  // sorted by dotted path. Backs the about:config-style search screen
  // and includes both tiers so a single search surfaces everything.
  final List<FieldSpec> expertFields;

  const PresentationSchema({
    required this.schemaVersion,
    required this.pages,
    this.expertFields = const [],
  });

  factory PresentationSchema.fromJson(Map<String, dynamic> j) =>
      PresentationSchema(
        schemaVersion: j['schema_version'] as String,
        pages: ((j['pages'] as List?) ?? [])
            .map((e) => PageSpec.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        expertFields: ((j['expert_fields'] as List?) ?? [])
            .map((e) => FieldSpec.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}
