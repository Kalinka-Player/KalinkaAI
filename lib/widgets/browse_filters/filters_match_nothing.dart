import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../kalinka_button.dart';

/// What stands where a listing's rows would be when its filters left none of
/// them, with the way out. Filters are remembered, so the choice that emptied
/// the listing may be one made long ago.
class FiltersMatchNothing extends StatelessWidget {
  /// Drops the filters.
  final VoidCallback onReset;

  const FiltersMatchNothing({super.key, required this.onReset});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.filter_list_off_rounded,
          size: 40,
          color: KalinkaColors.textSecondary.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 12),
        Text(
          'Nothing matches these filters',
          style: KalinkaTextStyles.cardTitle,
        ),
        const SizedBox(height: 16),
        // Neutral: dropping filters destroys nothing.
        KalinkaButton(
          label: 'Reset filters',
          variant: KalinkaButtonVariant.neutral,
          size: KalinkaButtonSize.compact,
          onTap: onReset,
        ),
      ],
    );
  }
}
