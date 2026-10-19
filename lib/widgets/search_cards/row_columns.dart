import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/source_modules_provider.dart';
import '../../theme/app_theme.dart';
import '../column_separator.dart';
import '../source_badge.dart';

/// The columns a listing row adds as it widens, each taking over what the
/// row's second line said: the details first — a track's album, an album's
/// year and size, what a folder or playlist holds — then the artist, then the
/// source. Every width here comes from the row's own width and the columns
/// end a fixed [gutter] from its right edge, so rows of one listing —
/// whatever they list — draw their separators on the same lines.
class RowColumns {
  /// The row's full width, edge to edge.
  final double width;

  const RowColumns(this.width);

  static const none = RowColumns(0);

  /// What a row keeps right of its columns for its own controls: a play
  /// button and a chevron.
  static const double gutter = 92;

  bool get detail => width >= 600;
  bool get artist => width >= 800;
  bool get source => width >= 1000;
  bool get any => detail;

  double get detailWidth => (width * 0.2).clamp(140.0, 280.0);
  double get artistWidth => (width * 0.16).clamp(120.0, 220.0);
  static const double sourceWidth = 160;

  /// The row's trailing slot, sized so its columns end at [gutter] from the
  /// edge; [inset] is what the row already holds between the slot and it.
  double trailingWidth(double inset) => gutter - inset;
}

/// Hands each row of a listing the columns its width earns. Placed outside
/// the row's own padding so its width is the row's.
class RowColumnsScope extends StatelessWidget {
  final Widget Function(BuildContext context, RowColumns columns) builder;

  const RowColumnsScope({super.key, required this.builder});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        builder(context, RowColumns(constraints.maxWidth)),
  );
}

/// The cells right of a row's title, each after a hairline. A row with
/// nothing for a column leaves it empty, keeping the lines unbroken.
class RowColumnCells extends ConsumerWidget {
  final RowColumns columns;

  /// A track's album; for any other row, what its second line said of it.
  final String? detail;
  final String? artist;

  /// The entity whose source the source column names.
  final String? sourceOf;

  /// In place of [sourceOf]'s, where a row draws its sources itself.
  final Widget? sourceCell;

  /// The file's format — FLAC, MP3 — said after the source where the source
  /// gives one, so a listing without formats keeps no empty column.
  final String? format;

  const RowColumnCells({
    super.key,
    required this.columns,
    this.detail,
    this.artist,
    this.sourceOf,
    this.sourceCell,
    this.format,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!columns.any) return const SizedBox.shrink();
    Widget text(String? value) => Text(
      value ?? '',
      style: KalinkaTextStyles.trackRowSubtitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (columns.artist) ...[
          const ColumnSeparator(),
          SizedBox(width: columns.artistWidth, child: text(artist)),
        ],
        const ColumnSeparator(),
        SizedBox(width: columns.detailWidth, child: text(detail)),
        if (columns.source) ...[
          const ColumnSeparator(),
          SizedBox(
            width: RowColumns.sourceWidth,
            child:
                sourceCell ??
                (sourceOf == null
                    ? null
                    : _SourceCell(entityId: sourceOf!, format: format)),
          ),
        ],
      ],
    );
  }
}

class _SourceCell extends ConsumerWidget {
  final String entityId;
  final String? format;

  const _SourceCell({required this.entityId, this.format});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = sourceOfId(entityId);
    final title = source == null
        ? null
        : ref.watch(sourceDisplayInfoProvider)[source]?.title;
    return Row(
      children: [
        if (sourceBadgeVisible(ref, entityId)) ...[
          SourceBadge(entityId: entityId),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            title ?? '',
            style: KalinkaTextStyles.trackRowSubtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // A long source name gives way; the format is never cut.
        if (format != null && format!.isNotEmpty)
          Text(
            title == null || title.isEmpty ? format! : ' · ${format!}',
            style: KalinkaTextStyles.trackRowSubtitle,
            maxLines: 1,
          ),
      ],
    );
  }
}

/// Names a listing's columns above its first row, while its rows have any.
/// A listing of tracks alone calls the details its album and the trailing
/// figure its time; any other listing calls them details.
class RowColumnsHeader extends StatelessWidget {
  /// Whether every row is a track.
  final bool tracks;

  /// Where the first row's words begin, for the name's label to start too.
  final double titleInset;

  const RowColumnsHeader({
    super.key,
    required this.tracks,
    required this.titleInset,
  });

  @override
  Widget build(BuildContext context) {
    return RowColumnsScope(
      builder: (context, columns) {
        if (!columns.any) return const SizedBox.shrink();
        Widget label(String text) => Text(
          text,
          style: KalinkaTextStyles.sectionLabel.copyWith(
            fontSize: KalinkaTypography.baseSize - 3,
            letterSpacing: 1.2,
            color: KalinkaColors.textMuted,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
        const line = ColumnSeparator(height: 14);
        return Semantics(
          container: true,
          child: Padding(
            padding: EdgeInsets.only(left: titleInset, top: 4, bottom: 8),
            child: Row(
              children: [
                Expanded(child: label(tracks ? 'TITLE' : 'NAME')),
                if (columns.artist) ...[
                  line,
                  SizedBox(width: columns.artistWidth, child: label('ARTIST')),
                ],
                line,
                SizedBox(
                  width: columns.detailWidth,
                  child: label(tracks ? 'ALBUM' : 'DETAILS'),
                ),
                if (columns.source) ...[
                  line,
                  SizedBox(
                    width: RowColumns.sourceWidth,
                    child: label('SOURCE'),
                  ),
                ],
                // Over the duration, which a track row sets 8 in from its
                // edge.
                SizedBox(
                  width: RowColumns.gutter,
                  child: tracks
                      ? Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: label('TIME'),
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A row's trailing controls, held to the slot [RowColumns] keeps for them
/// while the row shows columns; as they are otherwise.
class RowTrailing extends StatelessWidget {
  final RowColumns columns;

  /// Room the row keeps between this slot and its right edge.
  final double inset;
  final Widget child;

  const RowTrailing({
    super.key,
    required this.columns,
    required this.child,
    this.inset = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (!columns.any) return child;
    return SizedBox(
      width: columns.trailingWidth(inset),
      child: Align(alignment: Alignment.centerRight, child: child),
    );
  }
}
