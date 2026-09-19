import 'package:flutter/material.dart';
import '../../data_model/presentation_schema.dart' show ConfigIssue, OptionSpec;
import '../../theme/app_theme.dart';
import '../../utils/click_cursor.dart';
import 'issue_notes.dart';
import 'settings_combo_input.dart';
import 'settings_text_input.dart';

/// List editor for array settings, one row per item.
///
/// Rows commit like every other settings input — on blur, submit and dispose,
/// not per keystroke — so a half-typed path is not staged and judged while it
/// is still being written.
///
/// [suggestions] turns the rows into combos; [issues] are the backend's
/// verdicts, each landing under the item it is about.
class SettingsListEditor extends StatefulWidget {
  final List<String> items;
  final ValueChanged<List<String>> onChanged;
  final String addLabel;
  final List<OptionSpec>? suggestions;
  final List<ConfigIssue> issues;

  const SettingsListEditor({
    super.key,
    required this.items,
    required this.onChanged,
    this.addLabel = 'Add item',
    this.suggestions,
    this.issues = const [],
  });

  @override
  State<SettingsListEditor> createState() => _SettingsListEditorState();
}

class _SettingsListEditorState extends State<SettingsListEditor> {
  // The row added last, focused once built so it can be typed into.
  int _focusOnBuild = -1;

  void _removeItem(int index) {
    widget.onChanged(List<String>.from(widget.items)..removeAt(index));
  }

  void _addItem() {
    setState(() => _focusOnBuild = widget.items.length);
    widget.onChanged(List<String>.from(widget.items)..add(''));
  }

  void _setItem(int index, String value) {
    if (index >= widget.items.length || widget.items[index] == value) return;
    final updated = List<String>.from(widget.items);
    updated[index] = value;
    widget.onChanged(updated);
  }

  List<ConfigIssue> _issuesFor(int index) =>
      widget.issues.where((issue) => issue.index == index).toList();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...List.generate(widget.items.length, (i) {
          final issues = _issuesFor(i);
          return Padding(
            padding: EdgeInsets.only(
              bottom: i < widget.items.length - 1 ? 6 : 0,
            ),
            child: _Row(
              // Keyed by position: the rows hold in-progress text, and
              // without a key removing one leaves its text on the next.
              key: ValueKey('item-$i-${widget.items.length}'),
              value: widget.items[i],
              suggestions: widget.suggestions,
              issues: issues,
              autofocus: i == _focusOnBuild,
              onChanged: (value) => _setItem(i, value),
              onRemove: () => _removeItem(i),
            ),
          );
        }),
        if (widget.items.isNotEmpty) const SizedBox(height: 6),
        _AddRow(label: widget.addLabel, onTap: _addItem),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String value;
  final List<OptionSpec>? suggestions;
  final List<ConfigIssue> issues;
  final bool autofocus;
  final ValueChanged<String> onChanged;
  final VoidCallback onRemove;

  const _Row({
    super.key,
    required this.value,
    required this.suggestions,
    required this.issues,
    required this.autofocus,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = issueBorderColor(issues);
    final input = suggestions == null
        ? SettingsTextInput(
            value: value,
            autofocus: autofocus,
            borderColor: borderColor,
            onChanged: onChanged,
          )
        : SettingsComboInput(
            value: value,
            options: suggestions!,
            autofocus: autofocus,
            borderColor: borderColor,
            onChanged: onChanged,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: input),
            const SizedBox(width: 7),
            _RemoveButton(onTap: onRemove),
          ],
        ),
        IssueNotes(issues: issues),
      ],
    );
  }
}

class _RemoveButton extends StatelessWidget {
  final VoidCallback onTap;

  const _RemoveButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Remove',
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: clickCursor(interactive: true),
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: KalinkaColors.statusOffline.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(5),
            ),
            child: const Icon(
              Icons.close,
              size: 10,
              color: KalinkaColors.statusOffline,
            ),
          ),
        ),
      ),
    );
  }
}

class _AddRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _AddRow({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: clickCursor(interactive: true),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add, size: 13, color: KalinkaColors.accent),
              const SizedBox(width: 4),
              Text(
                label,
                style: KalinkaTextStyles.trayRowLabel.copyWith(
                  fontSize: KalinkaTypography.baseSize + 2,
                  color: KalinkaColors.accent,
                  letterSpacing: 0.03,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
