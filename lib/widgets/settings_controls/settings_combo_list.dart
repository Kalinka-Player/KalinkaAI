import 'package:flutter/material.dart';
import '../../data_model/presentation_schema.dart' show OptionSpec;
import '../../theme/app_theme.dart';
import 'option_picker.dart';
import 'settings_text_input.dart';

/// A text field with the values the backend found listed right under it, for
/// a form with the room to show them: tap one to take it, or type your own.
/// Once the user types, the list narrows to what the text could still become.
class SettingsComboList extends StatelessWidget {
  final String value;
  final List<OptionSpec> options;
  final ValueChanged<String> onChanged;
  final String? hintText;
  final Color? borderColor;

  const SettingsComboList({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.hintText,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsTextInput(
      value: value,
      hintText: hintText,
      borderColor: borderColor,
      onChanged: onChanged,
      // Part of the field for a click: one that unfocused it would commit the
      // text first, and the list would change under the pointer.
      belowBuilder: (context, typed, replace) => TextFieldTapRegion(
        child: _Suggestions(
          matching: _matching(typed),
          anyFound: options.isNotEmpty,
          typed: typed.trim(),
          onPick: replace,
        ),
      ),
    );
  }

  /// The options [typed] could still become: one that holds it, or one it
  /// goes on inside — a folder typed under a disk that was offered.
  List<OptionSpec> _matching(String typed) {
    final needle = typed.trim().toLowerCase();
    if (needle.isEmpty || typed.trim() == value.trim()) return options;
    return [
      for (final option in options)
        if (option.value.toLowerCase().contains(needle) ||
            option.label.toLowerCase().contains(needle) ||
            needle.startsWith(option.value.toLowerCase()))
          option,
    ];
  }
}

class _Suggestions extends StatelessWidget {
  final List<OptionSpec> matching;

  /// Whether the backend offered anything at all, which tells a search that
  /// is still going apart from a value the user is typing for themselves.
  final bool anyFound;
  final String typed;
  final ValueChanged<String> onPick;

  const _Suggestions({
    required this.matching,
    required this.anyFound,
    required this.typed,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    if (!anyFound) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Nothing found yet. Type it in, or wait a moment.',
          style: KalinkaTextStyles.trayRowSublabel,
        ),
      );
    }
    if (matching.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'FOUND · ${matching.length}',
            style: KalinkaTextStyles.traySectionLabel,
          ),
          const SizedBox(height: 2),
          for (final option in matching)
            OptionRow(
              option: option,
              selected: option.value == typed,
              onTap: () => onPick(option.value),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            ),
        ],
      ),
    );
  }
}
