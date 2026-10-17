import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Expand/collapse chevron button with 44px tap target and 28px visual.
/// Used in album and playlist search result rows.
class ExpandChevronButton extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onTap;
  final bool canExpand;

  const ExpandChevronButton({
    super.key,
    required this.isExpanded,
    required this.onTap,
    this.canExpand = true,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      expanded: canExpand ? isExpanded : null,
      child: IconButton(
        tooltip: canExpand ? (isExpanded ? 'Collapse' : 'Expand') : 'Open',
        onPressed: onTap,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: AnimatedRotation(
          turns: canExpand && isExpanded ? 0.5 : 0,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 200),
          child: Icon(
            canExpand ? Icons.expand_more : Icons.chevron_right,
            size: 20,
            color: KalinkaColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
