import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The right chevron at a row's end: it opens the same page as the row's
/// title, with a target of its own so it can be aimed at and reached by
/// keyboard.
class OpenChevronButton extends StatelessWidget {
  final VoidCallback onTap;

  /// What the row stands for, so the tooltip says where it leads.
  final String? name;

  const OpenChevronButton({super.key, required this.onTap, this.name});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: name == null ? 'Open' : 'Open $name',
      onPressed: onTap,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      icon: const Icon(
        Icons.chevron_right,
        size: 20,
        color: KalinkaColors.textSecondary,
      ),
    );
  }
}
