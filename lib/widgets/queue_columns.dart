import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'column_separator.dart';

/// Shared widths for queue rows and their pinned column labels.
class QueueColumns {
  final double width;
  final double textScale;
  final bool hasAlbums;

  const QueueColumns({
    required this.width,
    required this.textScale,
    required this.hasAlbums,
  });

  bool get showAlbum => hasAlbums && width >= 600 * textScale;
  double get albumWidth =>
      (width * 0.27).clamp(160 * textScale, 280 * textScale);
  double get timeWidth => 72 * textScale;
  static const handleWidth = 55.0;
  double get trailingWidth => timeWidth + handleWidth;
  double get titleHeight => (18 * textScale + 16).clamp(46.0, double.infinity);
  double get legendHeight => 14 * textScale + 8;
  double get headerHeight => titleHeight + (showAlbum ? legendHeight : 0);

  @override
  bool operator ==(Object other) =>
      other is QueueColumns &&
      width == other.width &&
      textScale == other.textScale &&
      hasAlbums == other.hasAlbums;

  @override
  int get hashCode => Object.hash(width, textScale, hasAlbums);
}

/// Part of the Up Next heading, sharing its rows' artwork and action gutters.
class QueueColumnLegend extends StatelessWidget {
  final QueueColumns columns;

  /// Where the rows' words begin.
  final double start;

  /// Whether the rows end in a drag handle.
  final bool handle;

  const QueueColumnLegend({
    super.key,
    required this.columns,
    this.start = 76,
    this.handle = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget label(String value) => Text(
      value,
      style: KalinkaTextStyles.sectionLabel.copyWith(
        fontSize: 10,
        height: 1.4,
        letterSpacing: 1.2,
        color: KalinkaColors.textMuted,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    return SizedBox(
      height: columns.legendHeight,
      child: Padding(
        padding: EdgeInsets.only(left: start, right: 12, bottom: 8),
        child: Row(
          children: [
            Expanded(child: label('TRACK / ARTIST')),
            const ColumnSeparator(height: 14),
            SizedBox(width: columns.albumWidth, child: label('ALBUM')),
            const SizedBox(width: 8),
            SizedBox(
              width: columns.timeWidth,
              child: Align(
                alignment: Alignment.centerRight,
                child: label('TIME'),
              ),
            ),
            if (handle) const SizedBox(width: QueueColumns.handleWidth),
          ],
        ),
      ),
    );
  }
}
