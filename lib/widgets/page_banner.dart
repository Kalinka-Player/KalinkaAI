import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'fitted_title.dart';

/// A display heading for music browsing pages: a Playfair title over one line
/// that says what the page holds. Type scales gently with width.
/// Settings use SettingsTopBar and SettingsPageIntro instead.
class PageBanner extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? titleLeading;

  /// Drawn before [subtitle] — a source badge, a status dot.
  final Widget? subtitleLeading;

  final EdgeInsetsGeometry padding;

  /// The lines the title may take before it is set smaller.
  final int titleLines;

  /// The lines the subtitle may take before it is cut short.
  final int? subtitleLines;

  /// The share of the width the text may take.
  final double widthFactor;

  /// The subtitle moves under [subtitleLeading] where the two do not fit
  /// side by side, rather than being cut short beside it.
  final bool subtitleWraps;

  const PageBanner({
    super.key,
    required this.title,
    this.subtitle = '',
    this.titleLeading,
    this.subtitleLeading,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 24),
    this.titleLines = 2,
    this.subtitleLines = 1,
    this.widthFactor = 0.82,
    this.subtitleWraps = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = (constraints.maxWidth / 420).clamp(1.0, 1.25);
        final text = Text(
          subtitle,
          style: KalinkaTextStyles.trackRowSubtitle
              .copyWith(color: KalinkaColors.textSecondary)
              .apply(fontSizeFactor: scale),
          maxLines: subtitleLines,
          softWrap: true,
          overflow: subtitleLines == null
              ? TextOverflow.clip
              : TextOverflow.ellipsis,
        );
        final heading = Semantics(
          headingLevel: 1,
          child: FittedTitle(
            title,
            style: KalinkaFonts.display(
              fontSize: (KalinkaTypography.baseSize + 21) * scale,
              fontWeight: FontWeight.w600,
              color: KalinkaColors.textPrimary,
            ),
            minFontSize: (KalinkaTypography.baseSize + 7) * scale,
            lines: titleLines,
          ),
        );
        // The text block is content-sized — no zone to be centred in, so the
        // padding is the whole vertical spacing and nothing drifts with width.
        return Padding(
          padding: padding,
          child: FractionallySizedBox(
            // Wide enough that ordinary names stay on one line; longer ones
            // still wrap rather than shrink.
            widthFactor: widthFactor,
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (titleLeading == null)
                  heading
                else
                  Row(
                    children: [
                      titleLeading!,
                      const SizedBox(width: 14),
                      Expanded(child: heading),
                    ],
                  ),
                if (subtitle.isNotEmpty || subtitleLeading != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: subtitleWraps
                        ? Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              ?subtitleLeading,
                              if (subtitle.isNotEmpty) text,
                            ],
                          )
                        : Row(
                            children: [
                              ?subtitleLeading,
                              if (subtitle.isNotEmpty) Flexible(child: text),
                            ],
                          ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
