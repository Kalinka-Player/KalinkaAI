import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../kalinka_button.dart';

/// Empty state for a listing whose filters matched nothing, with a reset.
class FiltersMatchNothing extends StatelessWidget {
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
