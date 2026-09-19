import 'package:flutter/material.dart';
import '../../data_model/presentation_schema.dart' show OptionSpec;
import '../../theme/app_theme.dart';
import '../../utils/click_cursor.dart';
import '../../utils/haptics.dart';
import '../kalinka_bottom_sheet.dart';
import 'option_picker.dart';
import 'settings_text_input.dart';

/// A text field with the values the backend found offered beside it, for
/// settings it can often guess but never bound — a music folder is a drive
/// it can see, a share that answered a broadcast, or a path only the user
/// knows. Picking fills the field in; typing over it is always allowed.
///
/// Browse is shown whenever the field says suggestions exist, not only once
/// some have arrived: a button that appears when a NAS finally answers is a
/// button nobody knows to wait for.
class SettingsComboInput extends StatelessWidget {
  final String value;
  final List<OptionSpec> options;
  final ValueChanged<String> onChanged;
  final String? hintText;
  final bool autofocus;
  final Color? borderColor;

  const SettingsComboInput({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.hintText,
    this.autofocus = false,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsTextInput(
      value: value,
      hintText: hintText,
      autofocus: autofocus,
      borderColor: borderColor,
      onChanged: onChanged,
      trailingBuilder: (context, replace) =>
          _BrowseButton(onTap: () => _browse(context, replace)),
    );
  }

  Future<void> _browse(
    BuildContext context,
    ValueChanged<String> replace,
  ) async {
    KalinkaHaptics.selectionClick();
    final picked = await showKalinkaBottomSheet<String>(
      context: context,
      contentBuilder: (_) => OptionPicker(
        options: options,
        selectedValue: value,
        emptyMessage:
            'Nothing found yet. Type the address, or come back in a moment.',
      ),
    );
    if (picked != null) replace(picked);
  }
}

class _BrowseButton extends StatelessWidget {
  final VoidCallback onTap;

  const _BrowseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Browse',
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: clickCursor(interactive: true),
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: KalinkaColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.travel_explore,
              size: 15,
              color: KalinkaColors.accent,
            ),
          ),
        ),
      ),
    );
  }
}
