import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Connected segmented control for enum-like settings.
///
/// Outer track holds equal-width segments; the active one fills with accent
/// and flips text to primary contrast.
class SettingsEnumPills extends StatelessWidget {
  final List<String> options;
  final String selected;
  final ValueChanged<String> onChanged;

  const SettingsEnumPills({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KalinkaColors.surfaceInput,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: KalinkaColors.borderDefault),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: _Segment(
                label: options[i],
                isActive: options[i] == selected,
                onTap: () {
                  onChanged(options[i]);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _Segment({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isActive ? KalinkaColors.accent : Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return Colors.white.withValues(alpha: 0.08);
          }
          return null;
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: KalinkaFonts.sans(
              fontSize: KalinkaTypography.baseSize + 2,
              fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
              color: isActive
                  ? KalinkaColors.textPrimary
                  : KalinkaColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
