// Translates a renderer's own config vocabulary into the presentation schema
// the settings widgets already speak, so `settings_renderer.dart` draws a
// renderer's page with no knowledge that renderers exist.
//
// Everything renderer-specific stops here: the widgets downstream see only
// [SectionSpec]/[FieldSpec], a path→value map, and a path→options map — the
// same three things the server's own settings page hands them.

import 'presentation_schema.dart';
import 'renderer_config.dart';

/// A renderer config snapshot expressed the way the settings widgets want it.
class RendererSchemaView {
  /// The simple page: sections holding only the fields the renderer marked
  /// simple. A section whose fields are all expert is left out entirely.
  final List<SectionSpec> sections;

  /// Every settable field, both tiers, sorted by path — what the expert list
  /// searches. Mirrors [PresentationSchema.expertFields] for the server's own
  /// settings, so the same about:config screen renders either.
  final List<FieldSpec> expertFields;

  /// Path → typed value (bool/int/String), ready for the controls.
  final Map<String, dynamic> values;

  /// Path → live option list for enum fields. The renderer resolves these per
  /// request (the device list is whatever ALSA reports right now), so they are
  /// always "live options" rather than static schema enums.
  final Map<String, List<OptionSpec>> options;

  /// Path → what applying that field costs, so the page can warn before saving.
  final Map<String, RendererApplyCost> applyCosts;

  const RendererSchemaView({
    this.sections = const [],
    this.expertFields = const [],
    this.values = const {},
    this.options = const {},
    this.applyCosts = const {},
  });
}

/// One-way conversion, snapshot → [RendererSchemaView].
///
/// Trigger fields are dropped: the renderer declares none today, and a
/// write-only action has no control in the shared schema. Give [WidgetKind] a
/// trigger case the day one appears — until then, rendering it as some other
/// widget would be worse than not showing it.
///
/// Expert fields are kept out of [RendererSchemaView.sections] but stay in
/// every other map: their values and options are what the expert list edits.
/// The server prunes its own tree before sending; a renderer sends both tiers
/// in one snapshot, so the split happens here instead.
RendererSchemaView adaptRendererConfig(RendererConfigSnapshot snapshot) {
  final sections = <SectionSpec>[];
  final expertFields = <FieldSpec>[];
  final values = <String, dynamic>{};
  final options = <String, List<OptionSpec>>{};
  final applyCosts = <String, RendererApplyCost>{};

  for (final section in snapshot.sections) {
    final simpleFields = <FieldSpec>[];
    for (final field in section.fields) {
      if (field.type == RendererFieldType.trigger) continue;
      final spec = _toFieldSpec(field);
      expertFields.add(spec);
      if (spec.importance == Importance.simple) simpleFields.add(spec);
      values[field.path] = decodeRendererValue(field.type, field.value);
      applyCosts[field.path] = field.apply;
      if (field.options.isNotEmpty) {
        options[field.path] = [for (final o in field.options) _toOptionSpec(o)];
      }
    }
    if (simpleFields.isEmpty) continue;
    sections.add(
      SectionSpec(
        id: section.path,
        title: section.title.isEmpty ? section.path : section.title,
        fields: simpleFields,
        help: section.description.trim().isEmpty ? null : section.description,
      ),
    );
  }

  expertFields.sort((a, b) => a.path.compareTo(b.path));

  return RendererSchemaView(
    sections: sections,
    expertFields: expertFields,
    values: values,
    options: options,
    applyCosts: applyCosts,
  );
}

/// Separator the renderer puts between an option's name and its detail.
const _optionDetailSeparator = ' · ';

/// Split an option's detail out of its label so the picker can dim it onto a
/// second line.
///
/// The server's own device dropdown ships `label` and `description` apart, and
/// the picker shows the description as a smaller second line under the name —
/// the collapsed trigger row stays clean because it renders the label alone.
/// The renderer packs both into one label (`"Card, Device · Direct hardware
/// device without any conversions"`), which would otherwise render as a single
/// long line. Splitting here makes the two dropdowns read the same.
///
/// A `description` the renderer did send always wins; a label with no
/// separator is left whole.
OptionSpec _toOptionSpec(RendererConfigOption option) {
  final label = option.label.isEmpty ? option.value : option.label;
  if (option.description.isNotEmpty) {
    return OptionSpec(
      value: option.value,
      label: label,
      description: option.description,
    );
  }
  // First separator, not last: the detail itself may contain one.
  final split = label.indexOf(_optionDetailSeparator);
  if (split <= 0) {
    return OptionSpec(value: option.value, label: label);
  }
  final detail = label.substring(split + _optionDetailSeparator.length).trim();
  return OptionSpec(
    value: option.value,
    label: label.substring(0, split).trim(),
    description: detail.isEmpty ? null : detail,
  );
}

FieldSpec _toFieldSpec(RendererConfigField field) => FieldSpec(
  path: field.path,
  label: field.title.isEmpty ? field.path : field.title,
  widget: _widgetFor(field),
  type: _typeNameFor(field.type),
  help: field.description.isEmpty ? null : field.description,
  helpDetails: field.helpDetails,
  defaultValue: decodeRendererValue(field.type, field.defaultValue),
  readonly: field.readOnly,
  importance: switch (field.importance) {
    RendererFieldImportance.expert => Importance.expert,
    RendererFieldImportance.simple => Importance.simple,
  },
  constraints: _constraintsFor(field),
);

WidgetKind _widgetFor(RendererConfigField field) => switch (field.type) {
  RendererFieldType.boolean => WidgetKind.toggle,
  // A slider only where the renderer asked for one and said what it accepts:
  // its byte counts are bounded too, and dragging one across a 32 MB range
  // would never land on a number anybody wanted.
  RendererFieldType.integer =>
    field.widget == RendererFieldWidget.slider && field.range != null
        ? WidgetKind.numberSlider
        : WidgetKind.numberInput,
  // Always a dropdown, never pills: the option that matters here is the ALSA
  // device list, whose labels run 30–60 characters and whose length changes
  // with hot-plug — exactly what the dropdown exists for.
  RendererFieldType.enumeration => WidgetKind.enumDropdown,
  _ => WidgetKind.text,
};

/// The renderer's limits as the shared controls read them. `ge`/`le` bound what
/// can be typed, `sliderMin`/`sliderMax` the drag; they are the same numbers
/// because a renderer names one range and enforces it on every write.
Constraints? _constraintsFor(RendererConfigField field) {
  final range = field.range;
  if (range == null) {
    return field.unit.isEmpty ? null : Constraints(unit: field.unit);
  }
  return Constraints(
    ge: range.min.toDouble(),
    le: range.max.toDouble(),
    step: range.step > 0 ? range.step.toDouble() : null,
    unit: field.unit.isEmpty ? null : field.unit,
    sliderMin: range.min.toDouble(),
    sliderMax: range.max.toDouble(),
  );
}

String _typeNameFor(RendererFieldType type) => switch (type) {
  RendererFieldType.boolean => 'boolean',
  RendererFieldType.integer => 'integer',
  _ => 'string',
};

/// Wire text → the typed value the controls edit.
dynamic decodeRendererValue(RendererFieldType type, String raw) =>
    switch (type) {
      RendererFieldType.boolean => raw == 'true' || raw == '1',
      RendererFieldType.integer => int.tryParse(raw) ?? 0,
      _ => raw,
    };

/// The typed value a control produced → wire text.
///
/// The inverse of [decodeRendererValue]; booleans go back as the `true`/`false`
/// the renderer's native config parses, not as `1`/`0`.
String encodeRendererValue(dynamic value) => switch (value) {
  bool b => b ? 'true' : 'false',
  null => '',
  _ => value.toString(),
};
