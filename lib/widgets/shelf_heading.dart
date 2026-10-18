import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'hover_text_action.dart';

/// A shelf's heading: its name, how many it holds, a rule, and the action
/// that opens it in full. One shape for a library shelf and a results block,
/// so the two read as the same thing.
class ShelfHeading extends StatelessWidget {
  /// Already in the case it should show in.
  final String title;
  final Color titleColor;
  final int? count;

  /// One line under the title, saying what the shelf is made of.
  final String? subtitle;

  /// A glyph before the title, where the shelf has a mark of its own.
  final IconData? icon;
  final Color? iconColor;
  final bool showDivider;

  final VoidCallback? onViewAll;
  final String viewAllLabel;

  const ShelfHeading({
    super.key,
    required this.title,
    this.titleColor = KalinkaColors.textPrimary,
    this.count,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.showDivider = true,
    this.onViewAll,
    this.viewAllLabel = 'VIEW ALL',
  });

  @override
  Widget build(BuildContext context) {
    // Large type leaves no room for the rule; the title takes it, wrapping.
    final roomy = !hasLargeType(context);
    final heading = Text(
      title,
      style: KalinkaTextStyles.sectionLabel.copyWith(color: titleColor),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: iconColor),
              const SizedBox(width: 8),
            ],
            if (roomy && showDivider) heading else Expanded(child: heading),
            if (count != null) ...[
              const SizedBox(width: 8),
              ShelfTally(count!),
            ],
            if (roomy && showDivider) ...[
              const SizedBox(width: 12),
              const Expanded(
                child: Divider(
                  color: KalinkaColors.borderSubtle,
                  thickness: 1,
                  height: 1,
                ),
              ),
            ],
            if (onViewAll != null) ...[
              const SizedBox(width: 12),
              ViewAllAction(label: viewAllLabel, onTap: onViewAll!),
            ],
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: KalinkaTextStyles.trackRowSubtitle.copyWith(
              color: KalinkaColors.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}

/// Text scaled past one and a half times, where a heading's rule no longer
/// fits beside it.
bool hasLargeType(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(18) > 27;

/// How many a shelf or a group holds, after its name: muted, so the name
/// stays the heading.
class ShelfTally extends StatelessWidget {
  final int count;

  const ShelfTally(this.count, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      '· $count',
      style: KalinkaTextStyles.sectionLabel.copyWith(
        color: KalinkaColors.textMuted,
      ),
    );
  }
}

/// The action that opens a shelf or a group in full. Mono and unfilled like
/// RESET ALL, so it reads as the heading's action rather than a control of
/// its own. The arrow marks it as a link.
class ViewAllAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const ViewAllAction({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return HoverTextAction(
      label: label,
      semanticsLabel: 'View all',
      onTap: onTap,
      color: KalinkaColors.accentTint,
      hoverColor: KalinkaColors.textPrimary,
      trailingIcon: Icons.arrow_forward_rounded,
    );
  }
}
