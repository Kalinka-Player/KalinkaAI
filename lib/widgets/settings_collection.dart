import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../data_model/collection_entry.dart';
import '../data_model/presentation_schema.dart';
import '../providers/collection_entry_binding.dart';
import '../theme/app_theme.dart';
import '../utils/click_cursor.dart';
import '../utils/json_equality.dart';
import 'kalinka_bottom_sheet.dart';
import 'kalinka_button.dart';
import 'settings_controls/issue_notes.dart';
import 'settings_controls/settings_binding.dart';
import 'settings_controls/settings_enum_pills.dart';
import 'settings_controls/settings_row.dart';
import 'settings_controls/settings_section.dart';
import 'settings_renderer.dart' show SchemaFieldRenderer, schemaIcon;
import 'tap_highlight.dart';

/// A collection of records as a column of cards, each opening a sheet that
/// edits one entry with the page's own controls.
///
/// Every edit in the sheet stages the whole list at once, so the backend
/// judges it as the user types; closing it stages the list as it was found.
class SchemaCollectionRenderer extends StatefulWidget {
  final CollectionSpec collection;

  const SchemaCollectionRenderer({super.key, required this.collection});

  @override
  State<SchemaCollectionRenderer> createState() =>
      _SchemaCollectionRendererState();
}

enum _Outcome { done, removed }

class _SchemaCollectionRendererState extends State<SchemaCollectionRenderer> {
  // The sheet lives on a route of its own, outside the SettingsScope the page
  // rebuilds, so it follows the page's binding through this.
  ValueNotifier<SettingsBinding>? _binding;

  CollectionSpec get _collection => widget.collection;

  @override
  void dispose() {
    _binding?.dispose();
    super.dispose();
  }

  void _follow(SettingsBinding binding) {
    final current = _binding;
    if (current == null) {
      _binding = ValueNotifier(binding);
      return;
    }
    if (identical(current.value, binding)) return;
    // Not while building: an open sheet would rebuild mid-frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) current.value = binding;
    });
  }

  List<Map<String, dynamic>> _entries() =>
      entriesOf(_binding!.value.effectiveValue(_collection.path));

  List<ConfigIssue> _issuesOf(
    SettingsBinding binding,
    Map<String, dynamic> entry,
  ) {
    final at = _collection.entryPath(entry);
    final variant = _collection.variantOf(entry);
    return [
      ...binding.issuesFor(at),
      if (variant != null)
        for (final field in variant.allFields)
          ...binding.issuesFor('$at.${field.path}'),
    ];
  }

  Future<void> _add() async {
    final variants = _collection.variants;
    if (variants.isEmpty) return;
    final discriminator = _collection.discriminator;
    final entry = <String, dynamic>{
      'id': newRecordId(),
      if (discriminator != null) discriminator: variants.first.key,
    };
    await _open(_entries(), null, entry);
  }

  Future<void> _edit(int index) async {
    final entries = _entries();
    await _open(entries, index, entries[index]);
  }

  /// Opens the sheet on [entry], at [index] in [before] or added after it.
  Future<void> _open(
    List<Map<String, dynamic>> before,
    int? index,
    Map<String, dynamic> entry,
  ) async {
    final binding = _binding!;
    final outcome = await showKalinkaBottomSheet<_Outcome>(
      context: context,
      mayFillScreen: true,
      contentBuilder: (_) => _EntrySheet(
        collection: _collection,
        binding: binding,
        before: before,
        index: index,
        entry: entry,
      ),
    );
    if (outcome == null) binding.value.stage(_collection.path, before);
  }

  @override
  Widget build(BuildContext context) {
    final binding = SettingsScope.of(context);
    _follow(binding);
    final entries = entriesOf(binding.effectiveValue(_collection.path));
    return SettingsRow(
      label: _collection.title,
      sublabel: _collection.help,
      isStaged: binding.isStaged(_collection.path),
      isVertical: true,
      // About the list as a whole; an entry's own go under its card.
      issues: binding.issuesFor(_collection.path),
      action: KalinkaButton(
        label: 'Add',
        variant: KalinkaButtonVariant.neutral,
        size: KalinkaButtonSize.compact,
        leading: const Icon(Icons.add, size: 16, color: KalinkaColors.accent),
        onTap: _add,
      ),
      control: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < entries.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _EntryCard(
                key: ValueKey(entries[i]['id']),
                variant: _collection.variantOf(entries[i]),
                entry: entries[i],
                issues: _issuesOf(binding, entries[i]),
                onTap: () => _edit(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  final VariantSpec? variant;
  final Map<String, dynamic> entry;
  final List<ConfigIssue> issues;
  final VoidCallback onTap;

  const _EntryCard({
    super.key,
    required this.variant,
    required this.entry,
    required this.issues,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final summary = variant?.summaryOf(entry) ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: KalinkaColors.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: issueBorderColor(issues) ?? KalinkaColors.borderDefault,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            mouseCursor: clickCursor(interactive: true),
            overlayColor: kalinkaOverlay,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    schemaIcon(variant?.icon),
                    size: 18,
                    color: KalinkaColors.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          variant?.label ?? '',
                          style: KalinkaTextStyles.trayRowLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (summary.isNotEmpty)
                          Text(
                            summary,
                            style: KalinkaTextStyles.trayRowSublabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: KalinkaColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
        IssueNotes(issues: issues),
      ],
    );
  }
}

// The server rescans the network at most every 10 s, and answers take a few.
const _suggestionsEvery = Duration(seconds: 4);

class _EntrySheet extends StatefulWidget {
  final CollectionSpec collection;
  final ValueListenable<SettingsBinding> binding;
  final List<Map<String, dynamic>> before;

  /// Where the entry sits in [before]; null for one being added.
  final int? index;
  final Map<String, dynamic> entry;

  const _EntrySheet({
    required this.collection,
    required this.binding,
    required this.before,
    required this.index,
    required this.entry,
  });

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  late Map<String, dynamic> _entry = copyEntry(widget.entry);
  late Map<String, dynamic> _opened = copyEntry(widget.entry);

  /// What each shape of a new entry held when the user switched away from
  /// it, so switching back finds it again.
  final Map<Object?, Map<String, dynamic>> _drafts = {};

  Timer? _suggesting;
  ModalRoute<dynamic>? _route;

  CollectionSpec get _collection => widget.collection;

  bool get _isNew => widget.index == null;

  /// False once the sheet pops, however it pops. A field still holding an
  /// edit commits it as it loses focus or is torn down — after a dismissal
  /// has already put the list back.
  bool get _open => _route?.isCurrent ?? true;

  @override
  void initState() {
    super.initState();
    final suggests = _collection.variants.any(
      (v) => v.allFields.any((f) => f.dynamicOptions),
    );
    if (suggests) {
      _refreshSuggestions();
      _suggesting = Timer.periodic(
        _suggestionsEvery,
        (_) => _refreshSuggestions(),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    _suggesting?.cancel();
    super.dispose();
  }

  void _refreshSuggestions() => widget.binding.value.refreshOptions();

  /// Writes an edit into [target], the entry its field was drawn for.
  void _stage(Map<String, dynamic> target, String path, dynamic value) {
    if (!mounted || !_open) return;
    if (entryHasPath(target, path) &&
        jsonEquals(readEntryPath(target, path), value)) {
      return;
    }
    // A field torn down by a rebuild commits from inside the frame.
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      scheduler.addPostFrameCallback((_) => _stage(target, path, value));
      return;
    }
    // A shape switched away from keeps what its fields commit on the way out.
    if (!identical(target, _entry)) {
      writeEntryPath(target, path, value);
      return;
    }
    setState(() => writeEntryPath(_entry, path, value));
    _push();
  }

  /// Stages the list as it was, with this entry as it is now.
  void _push() {
    final entries = [...widget.before];
    final entry = copyEntry(_entry);
    final index = widget.index;
    if (index == null) {
      entries.add(entry);
    } else {
      entries[index] = entry;
    }
    widget.binding.value.stage(_collection.path, entries);
  }

  /// Lets a focused field commit what it holds while it is still the field
  /// it was typed into; the focus change lands in a microtask.
  Future<bool> _settled() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.microtask(() {});
    return mounted && _open;
  }

  /// Makes a new entry another shape, keeping what the one it leaves held.
  Future<void> _switchKind(String key) async {
    final discriminator = _collection.discriminator;
    if (discriminator == null || _entry[discriminator] == key) return;
    if (!await _settled()) return;
    setState(() {
      _drafts[_entry[discriminator]] = _entry;
      _opened = {'id': _entry['id'], discriminator: key};
      _entry = _drafts[key] ?? copyEntry(_opened);
    });
    _push();
  }

  /// Switches a part of the entry to another shape. Back to the shape it had
  /// when the sheet opened, it gets what it held then — a saved password is
  /// kept only while the login it belongs to is sent back as it was.
  void _switch(GroupSpec group, String key) {
    // The pills report the shape already chosen too; that is not a switch.
    if (group.variantOf(_entry)?.key == key) return;
    final discriminator = group.discriminator!;
    final opened = readEntryPath(_opened, group.path);
    final value = opened is Map && opened[discriminator] == key
        ? copyEntry(opened.cast<String, dynamic>())
        : <String, dynamic>{discriminator: key};
    // A new copy, so a field of the shape left commits into the old one as
    // it is torn down rather than into this.
    final next = copyEntry(_entry);
    writeEntryPath(next, group.path, value);
    setState(() => _entry = next);
    _push();
  }

  Future<void> _done() async {
    if (!await _settled()) return;
    _push();
    if (mounted) Navigator.of(context).pop(_Outcome.done);
  }

  void _remove() {
    final entries = [...widget.before]..removeAt(widget.index!);
    widget.binding.value.stage(_collection.path, entries);
    Navigator.of(context).pop(_Outcome.removed);
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    return ValueListenableBuilder<SettingsBinding>(
      valueListenable: widget.binding,
      builder: (context, page, _) {
        final entry = _entry;
        final variant = _collection.variantOf(entry);
        final description = variant?.description;
        return SettingsScope(
          binding: CollectionEntryBinding(
            page: page,
            collection: _collection,
            entry: entry,
            before: _opened,
            onStage: (path, value) => _stage(entry, path, value),
          ),
          child: Padding(
            // Clears the keyboard a field raises.
            padding: EdgeInsets.only(bottom: insets),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetHeader(
                  title: _isNew
                      ? 'ADD TO ${_collection.title.toUpperCase()}'
                      : _collection.title.toUpperCase(),
                  summary: _isNew
                      ? ''
                      : [
                          ?variant?.label,
                          ?variant?.summaryOf(entry),
                        ].where((part) => part.isNotEmpty).join(' · '),
                ),
                if (_isNew && _collection.variants.length > 1)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      kSheetGutter,
                      0,
                      kSheetGutter,
                      8,
                    ),
                    child: SettingsEnumPills(
                      options: [for (final v in _collection.variants) v.label],
                      selected: variant?.label ?? '',
                      onChanged: (label) => _switchKind(
                        _collection.variants
                            .firstWhere((v) => v.label == label)
                            .key,
                      ),
                    ),
                  ),
                if (_isNew && description != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      kSheetGutter,
                      0,
                      kSheetGutter,
                      12,
                    ),
                    child: Text(
                      description,
                      style: KalinkaTextStyles.trayRowSublabel,
                    ),
                  ),
                const SheetDivider(),
                Flexible(
                  child: SingleChildScrollView(
                    child: _EntryForm(
                      key: ValueKey(variant?.key),
                      variant: variant,
                      entry: _entry,
                      // A value the server refuses outright is pinned on the
                      // list, not on the entry being typed into.
                      issues: [
                        ...page.issuesFor(_collection.path),
                        ...page.issuesFor(_collection.entryPath(_entry)),
                      ],
                      onSwitch: _switch,
                    ),
                  ),
                ),
                const SheetDivider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    kSheetGutter,
                    12,
                    kSheetGutter,
                    8,
                  ),
                  child: Row(
                    children: [
                      if (!_isNew) ...[
                        Expanded(
                          child: KalinkaButton(
                            label: 'REMOVE',
                            variant: KalinkaButtonVariant.neutral,
                            fullWidth: true,
                            onTap: _remove,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: KalinkaButton(
                          label: _isNew ? 'ADD' : 'KEEP CHANGES',
                          fullWidth: true,
                          onTap: _done,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// An entry's fields, grouped as its record declares them, with what the
/// backend suggests listed under each field it has suggestions for. Fields
/// the backend ranks expert wait behind "Advanced".
class _EntryForm extends StatelessWidget {
  final VariantSpec? variant;
  final Map<String, dynamic> entry;
  final List<ConfigIssue> issues;
  final void Function(GroupSpec group, String key) onSwitch;

  const _EntryForm({
    super.key,
    required this.variant,
    required this.entry,
    required this.issues,
    required this.onSwitch,
  });

  @override
  Widget build(BuildContext context) {
    final shown = <Widget>[];
    final advanced = <FieldSpec>[];
    final shape = variant;
    if (shape != null) {
      _addFields(shape.fields, shown, advanced);
      for (final group in shape.groups) {
        _addGroup(group, shown, advanced);
      }
    }
    final binding = SettingsScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IssueNotes(
          issues: issues,
          padding: const EdgeInsets.fromLTRB(kSheetGutter, 10, kSheetGutter, 0),
        ),
        ...shown,
        if (advanced.isNotEmpty) ...[
          // Nothing above it but the sheet's own rule otherwise.
          if (shown.isNotEmpty) const SheetDivider(),
          SettingsSection(
            title: 'Advanced',
            showTopBorder: false,
            gutter: kSheetGutter,
            // Opened on what the card complained about.
            initiallyExpanded: advanced.any(
              (field) => binding.issuesFor(field.path).isNotEmpty,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (final field in advanced) _field(field)],
            ),
          ),
        ],
      ],
    );
  }

  Widget _field(FieldSpec field) => SchemaFieldRenderer(
    key: ValueKey(field.path),
    field: field,
    listSuggestions: true,
    gutter: kSheetGutter,
  );

  void _addFields(
    List<FieldSpec> fields,
    List<Widget> shown,
    List<FieldSpec> advanced,
  ) {
    for (final field in fields) {
      if (field.importance == Importance.expert) {
        advanced.add(field);
      } else {
        shown.add(_field(field));
      }
    }
  }

  void _addGroup(
    GroupSpec group,
    List<Widget> shown,
    List<FieldSpec> advanced,
  ) {
    final rows = <Widget>[];
    final chosen = group.variantOf(entry);
    if (chosen != null) {
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(kSheetGutter, 8, kSheetGutter, 4),
          child: SettingsEnumPills(
            options: [for (final v in group.variants) v.label],
            selected: chosen.label,
            onChanged: (label) => onSwitch(
              group,
              group.variants.firstWhere((v) => v.label == label).key,
            ),
          ),
        ),
      );
      _addFields(chosen.fields, rows, advanced);
      for (final nested in chosen.groups) {
        _addGroup(nested, rows, advanced);
      }
    } else {
      _addFields(group.fields, rows, advanced);
      for (final nested in group.groups) {
        _addGroup(nested, rows, advanced);
      }
    }
    if (rows.isEmpty) return;
    shown.add(
      Padding(
        padding: const EdgeInsets.fromLTRB(kSheetGutter, 14, kSheetGutter, 0),
        child: Text(
          group.title.toUpperCase(),
          style: KalinkaTextStyles.sectionHeaderMuted,
        ),
      ),
    );
    shown.addAll(rows);
  }
}
