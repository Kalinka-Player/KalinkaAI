import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Section header for search result chunks.
///
/// Renders an optional leading [icon], the uppercase [label] (with an optional
/// [subtitle] line beneath it), and the item [count] on the right. When
/// [onOnlyTap] is provided, shows an "Only {label} >" link instead of the bare
/// count. A divider is drawn above unless [showDivider] is false.
///
/// Presentation (icon / label / subtitle) is supplied by the caller from the
/// backend's section config — this widget makes no assumptions about content.
class SectionHeader extends StatelessWidget {
  final String label;
  final int count;
  final bool showDivider;
  final VoidCallback? onOnlyTap;
  final IconData? icon;

  /// Icon tint. Defaults to [KalinkaColors.accent] when null.
  final Color? iconColor;
  final String? subtitle;

  const SectionHeader({
    super.key,
    required this.label,
    required this.count,
    this.showDivider = true,
    this.onOnlyTap,
    this.icon,
    this.iconColor,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (showDivider)
          const Divider(
            color: KalinkaColors.borderSubtle,
            thickness: 1,
            height: 24,
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: iconColor ?? KalinkaColors.accent),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      onOnlyTap != null
                          ? '${label.toUpperCase()} ($count)'
                          : label.toUpperCase(),
                      style: KalinkaTextStyles.sectionLabel,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: KalinkaTextStyles.trackRowSubtitle,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (onOnlyTap != null)
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: onOnlyTap,
                    behavior: HitTestBehavior.opaque,
                    child: Text(
                      'Only $label ›',
                      style: KalinkaTextStyles.trackRowSubtitle.copyWith(
                        color: KalinkaColors.accent,
                      ),
                    ),
                  ),
                )
              else
                Text('$count', style: KalinkaTextStyles.sectionLabel),
            ],
          ),
        ),
      ],
    );
  }
}
