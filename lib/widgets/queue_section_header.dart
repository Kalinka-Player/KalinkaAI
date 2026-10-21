import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'queue_columns.dart';

/// Reusable section header for queue sections ("UP NEXT" / "PREVIOUSLY PLAYED").
class QueueSectionHeader extends StatelessWidget {
  static const double horizontalPadding = 20;
  static const double verticalPadding = 8;
  static const double height = 46;

  final String label;
  final int? trackCount;
  final bool showShuffleBadge;
  final Widget? trailing;
  final QueueColumns? columns;
  final bool showColumnLegend;

  /// Optional free-form suffix rendered inline after the label, prefixed by
  /// a "·" separator. Used for "NOW PLAYING · FLAC 24-bit · 96 kHz".
  final String? suffix;

  const QueueSectionHeader({
    super.key,
    required this.label,
    this.trackCount,
    this.showShuffleBadge = false,
    this.trailing,
    this.suffix,
    this.columns,
    this.showColumnLegend = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: columns?.titleHeight ?? height,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            child: Row(
              children: [
                // Left cluster
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        flex: 2,
                        child: Text(
                          label,
                          style: KalinkaTextStyles.sectionHeader,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (trackCount != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          '· $trackCount',
                          style: KalinkaTextStyles.trackCountBadge,
                        ),
                      ],
                      if (suffix != null && suffix!.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '· ${suffix!}',
                            style: KalinkaTextStyles.trackCountBadge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                          ),
                        ),
                      ],
                      if (showShuffleBadge) ...[
                        const SizedBox(width: 8),
                        AnimatedOpacity(
                          opacity: 1.0,
                          duration: const Duration(milliseconds: 200),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.shuffle,
                                size: 12,
                                color: KalinkaColors.gold,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '\u00b7 Shuffled',
                                style: KalinkaTextStyles.shuffleBadgeText,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Right side
                ?trailing,
              ],
            ),
          ),
        ),
        if (showColumnLegend && (columns?.showAlbum ?? false))
          QueueColumnLegend(columns: columns!),
      ],
    );
  }
}
