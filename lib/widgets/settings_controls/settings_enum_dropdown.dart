import 'package:flutter/material.dart';
import '../../data_model/presentation_schema.dart' show OptionSpec;
import '../../theme/app_theme.dart';
import '../../utils/haptics.dart';
import '../kalinka_bottom_sheet.dart';
import 'option_picker.dart';

/// Dropdown control for enum-like settings whose option set is too
/// long or too variable for a chip group.
///
/// Tapping the trigger row opens a modal bottom sheet listing every
/// option. Chosen by UX rationale: ALSA device labels are typically
/// 30–60 chars and the count drifts with hot-plug. Chips would wrap
/// awkwardly and shuffle visually on every refresh; a bottom sheet
/// gives stable rows with comfortable touch targets and a clear
/// dismiss gesture.
///
/// The current selection is shown in the trigger as its *label* (what
/// the user sees), while the underlying *value* (e.g. an opaque
/// `hw:CARD=…,DEV=…` handle) is what flows back through [onChanged].
/// Values not present in [options] fall back to displaying the raw
/// value so a hot-unplugged device doesn't render as blank.
class SettingsEnumDropdown extends StatelessWidget {
  final List<OptionSpec> options;
  final String selectedValue;
  final ValueChanged<String> onChanged;
  final String? placeholder;

  const SettingsEnumDropdown({
    super.key,
    required this.options,
    required this.selectedValue,
    required this.onChanged,
    this.placeholder,
  });

  String _labelForSelected() {
    for (final o in options) {
      if (o.value == selectedValue) return o.label;
    }
    // Selection isn't in the option set — show the raw value so the
    // user can see what's currently saved (e.g. a device that was
    // unplugged between renders).
    if (selectedValue.isNotEmpty) return selectedValue;
    return placeholder ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final label = _labelForSelected();
    return Material(
      color: KalinkaColors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: KalinkaColors.borderDefault),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openPicker(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KalinkaTextStyles.textFieldInput.copyWith(
                    color: label.isEmpty
                        ? KalinkaColors.textSecondary
                        : KalinkaColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.keyboard_arrow_down,
                size: 18,
                color: KalinkaColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    KalinkaHaptics.selectionClick();
    final picked = await showKalinkaBottomSheet<String>(
      context: context,
      contentBuilder: (_) =>
          OptionPicker(options: options, selectedValue: selectedValue),
    );
    if (picked != null && picked != selectedValue) onChanged(picked);
  }
}
