import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'hover_text_action.dart';
import 'source_badge.dart';

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

  /// The source the shelf comes from, whose tile stands before the title.
  final String? source;
  final bool showDivider;

  final VoidCallback? onViewAll;
  final String viewAllLabel;

  const ShelfHeading({
    super.key,
    required this.title,
    this.titleColor = KalinkaColors.textPrimary,
    this.count,
    this.subtitle,
    this.source,
    this.showDivider = true,
    this.onViewAll,
    this.viewAllLabel = 'View All',
  });

  static const _tileSize = 20.0;
  static const _tileGap = 10.0;

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
            if (source != null) ...[
              SourceTile(source: source!, size: _tileSize),
              const SizedBox(width: _tileGap),
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
          // Under the title, past the tile before it.
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: source == null ? 0 : _tileSize + _tileGap,
            ),
            child: Text(
              subtitle!,
              style: KalinkaTextStyles.trackRowSubtitle.copyWith(
                color: KalinkaColors.textMuted,
              ),
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

/// The action that opens a shelf or a group in full: a small, neutral link
/// that lights up under the pointer, so it never competes with the heading.
/// The chevron marks it as a link.
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
      color: KalinkaColors.textSecondary,
      hoverColor: KalinkaColors.textPrimary,
      trailingIcon: Icons.chevron_right_rounded,
      mono: false,
      // Room beside the small words, not above them: the title's row stays
      // its own height, so the subtitle sits close under it.
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
    );
  }
}
