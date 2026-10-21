import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart';
import '../../providers/source_modules_provider.dart';
import '../../theme/app_theme.dart';
import '../source_badge.dart';
import 'row_enqueue_button.dart';

/// The columns a listing row adds as it widens, each taking over what the
/// row's second line said: the details first — a track's album, an album's
/// year and size, what a folder or playlist holds — then the artist, then the
/// source. Every width here comes from the row's own width and the columns
/// end a fixed [gutter] from its right edge, so rows of one listing —
/// whatever they list — align their metadata with the same headings.
class RowColumns {
  /// The row's full width, edge to edge.
  final double width;

  /// False where no row of the listing has details to show, so none keeps
  /// an empty column for them.
  final bool details;

  /// False where no row of the listing names an artist; the details take
  /// that column's room instead.
  final bool artists;
  final bool showSource;
  final bool tracks;
  final double textScale;

  const RowColumns(
    this.width, {
    this.details = true,
    this.artists = true,
    this.showSource = true,
    this.tracks = false,
    this.textScale = 1,
  });

  static const none = RowColumns(0);

  /// What a row keeps right of its columns for its own controls: a gap, a
  /// play button and a chevron.
  static const double gutter = gap + 92;
  static const double gap = 16;

  bool get detail => details && width >= (tracks ? 576 : 600) * textScale;
  bool get _artistFits => width >= (tracks ? 1000 : 800) * textScale;
  bool get artist => artists && _artistFits;
  bool get source => showSource && width >= (tracks ? 1200 : 1000) * textScale;
  bool get any => detail || artist || source;

  /// Wide enough for a track's Album column; a track row then has room for
  /// its own enqueue button, where it otherwise relies on a swipe.
  bool get wide => width >= 576 * textScale;

  double get detailWidth =>
      (width * (tracks ? 0.26 : 0.2)).clamp(
        (tracks ? 200.0 : 140.0) * textScale,
        (tracks ? 320.0 : 280.0) * textScale,
      ) +
      (!artists && _artistFits ? artistWidth + gap : 0);
  double get artistWidth =>
      (width * 0.16).clamp(120.0 * textScale, 220.0 * textScale);
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
    builder: (context, constraints) => builder(
      context,
      RowColumns(
        constraints.maxWidth,
        details:
            RowColumnsListing.tableOf(context) &&
            RowColumnsListing.detailsOf(context),
        artists:
            RowColumnsListing.tableOf(context) &&
            RowColumnsListing.artistsOf(context),
        showSource:
            RowColumnsListing.tableOf(context) &&
            SourceAttributionScope.of(context) == null,
        tracks: RowColumnsListing.tracksOf(context),
        textScale: MediaQuery.textScalerOf(context).scale(14) / 14,
      ),
    ),
  );
}

/// Tells a listing's rows and its header whether any row has details, so
/// a listing whose source sends none — albums without a year, size or genre
/// — draws no Details column at all.
class RowColumnsListing extends InheritedWidget {
  final bool details;
  final bool artists;
  final bool tracks;
  final bool hideTrackType;

  /// False where the rows are of more than one kind: a column would hold an
  /// album under one row and an artist's count under the next, so each row
  /// says what it is on its own second line and no header names columns.
  final bool table;

  const RowColumnsListing({
    super.key,
    required this.details,
    this.artists = true,
    this.tracks = false,
    this.hideTrackType = false,
    this.table = true,
    required super.child,
  });

  static bool tableOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RowColumnsListing>()?.table ??
      true;

  /// Whether [items] are all of one kind, and so read as a table.
  static bool oneKind(Iterable<BrowseItem> items) =>
      items.map((item) => item.browseType).toSet().length <= 1;

  static bool detailsOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<RowColumnsListing>()
          ?.details ??
      true;

  static bool artistsOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<RowColumnsListing>()
          ?.artists ??
      true;

  static bool tracksOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RowColumnsListing>()?.tracks ??
      false;

  static bool hideTrackTypeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<RowColumnsListing>()
          ?.hideTrackType ??
      false;

  /// Whether any of [items] would fill the Details column. Only albums are
  /// known to come without; any other row is taken to have some.
  static bool anyDetails(Iterable<BrowseItem> items) => items.any((item) {
    final album = item.album;
    if (item.browseType != BrowseType.album || album == null) return true;
    return album.year != null ||
        album.trackCount != null ||
        album.genres.isNotEmpty;
  });

  /// Whether any of [items] would fill the Artist column: only tracks and
  /// albums name one.
  static bool anyArtists(Iterable<BrowseItem> items) => items.any(
    (item) =>
        item.browseType == BrowseType.track ||
        item.browseType == BrowseType.album,
  );

  @override
  bool updateShouldNotify(RowColumnsListing oldWidget) =>
      details != oldWidget.details ||
      artists != oldWidget.artists ||
      tracks != oldWidget.tracks ||
      hideTrackType != oldWidget.hideTrackType ||
      table != oldWidget.table;
}

/// Cells align with the header through shared widths and quiet whitespace.
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
          const SizedBox(width: RowColumns.gap),
          SizedBox(width: columns.artistWidth, child: text(artist)),
        ],
        if (columns.detail) ...[
          const SizedBox(width: RowColumns.gap),
          SizedBox(width: columns.detailWidth, child: text(detail)),
        ],
        if (columns.source) ...[
          const SizedBox(width: RowColumns.gap),
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
        const line = SizedBox(width: RowColumns.gap);
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
                if (columns.detail) ...[
                  line,
                  SizedBox(
                    width: columns.detailWidth,
                    child: label(tracks ? 'ALBUM' : 'DETAILS'),
                  ),
                ],
                if (columns.source) ...[
                  line,
                  SizedBox(
                    width: RowColumns.sourceWidth,
                    child: label('SOURCE'),
                  ),
                ],
                // Over the duration, which a track row sets 8 in from its
                // edge and, as wide as this, before its +.
                SizedBox(
                  width: RowColumns.gutter,
                  child: tracks
                      ? Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: EdgeInsets.only(
                              right:
                                  8 +
                                  (columns.wide
                                      ? RowEnqueueButton.gap +
                                            RowEnqueueButton.size
                                      : 0),
                            ),
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
