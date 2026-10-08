import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Toggle switch control for settings.
///
/// 42x24, accent-colored when on, white knob when on.
class SettingsToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const SettingsToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        onChanged(!value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 42,
        height: 24,
        decoration: BoxDecoration(
          color: value ? KalinkaColors.accent : KalinkaColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value ? KalinkaColors.accent : KalinkaColors.borderDefault,
          ),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 220),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 16,
            height: 16,
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: value ? Colors.white : KalinkaColors.textSecondary,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}
