import 'dart:math';

import 'package:flutter/material.dart';
import '../../data_model/data_model.dart';
import '../../theme/app_theme.dart';
import 'collection_row.dart';
import 'search_album_row.dart';
import 'search_artist_row.dart';
import 'search_catalog_row.dart';
import 'search_folder_row.dart';
import 'search_playlist_row.dart';
import 'search_track_row.dart';
import 'show_more_row.dart';

/// Renders a list of [BrowseItem]s as stacked rows, dispatching to the correct
/// Search*Row widget by [BrowseItem.browseType]. Rows are separated by
/// hairline dividers — every list of rows in the app is, whether its rows are
/// independent hits or a set that plays as one queue, so there is no flag to
/// turn them off with.
///
/// When [visibleLimit] is set and [items.length] exceeds it, the list is
/// truncated and a [ShowMoreRow] is appended that toggles [isExpanded] via
/// [onToggleExpand].
///
/// Used by both the search-results feed (AI groups) and the zero-state
/// surface (Recently Favourited, Based on Now Playing) so tap-to-play
/// animation, sibling dim, and row styling stay consistent between them.
class BrowseItemRows extends StatelessWidget {
  final List<BrowseItem> items;
  final int? visibleLimit;
  final bool isExpanded;
  final VoidCallback? onToggleExpand;

  /// When set, tapping a track row plays this whole list as the queue,
  /// starting from the tapped track, instead of playing the track alone.
  final List<String>? queueContextIds;

  /// Whether each row names its kind and source. Off under a heading that
  /// already does (a source's group of tracks). Only the track row reads it.
  final bool labelled;

  const BrowseItemRows({
    super.key,
    required this.items,
    this.visibleLimit,
    this.isExpanded = false,
    this.onToggleExpand,
    this.queueContextIds,
    this.labelled = true,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final limit = visibleLimit;
    final shownCount = (limit == null || isExpanded)
        ? items.length
        : min(limit, items.length);
    final displayed = items.take(shownCount).toList();

    final children = <Widget>[];
    for (int i = 0; i < displayed.length; i++) {
      // Per-row RepaintBoundary: each row becomes its own composited layer
      // so scroll just shifts layers instead of re-rasterising the whole
      // section. Matters most for sections that pack many rows into a single
      // outer ListView child (BASED ON NOW PLAYING, RECENTLY FAVOURITED).
      children.add(
        RepaintBoundary(
          child: buildRow(
            displayed[i],
            queueContextIds: queueContextIds,
            labelled: labelled,
          ),
        ),
      );
      if (i < displayed.length - 1) {
        // Inset by the row above it: the hairline is that row's bottom edge,
        // so it starts where that row's words do.
        children.add(
          Padding(
            padding: EdgeInsets.only(left: textInsetOf(displayed[i])),
            child: const Divider(
              color: KalinkaColors.borderSubtle,
              thickness: 1,
              height: 14,
            ),
          ),
        );
      }
    }

    final hiddenCount = items.length - shownCount;
    final showMore =
        limit != null &&
        onToggleExpand != null &&
        (hiddenCount > 0 || isExpanded);
    if (showMore) {
      children.add(
        RepaintBoundary(
          child: ShowMoreRow(
            remainingCount: items.length - limit,
            isExpanded: isExpanded,
            onTap: onToggleExpand!,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  /// Where a row's text column begins, so a hairline drawn under it starts
  /// past the artwork instead of cutting the column of thumbnails in two.
  ///
  /// A table rather than one number: the rows are built five different ways
  /// and their artwork runs from 44 to 64, so no single offset both clears
  /// every thumbnail and stays against every text column. Measured, and held
  /// to the measurement by a test — a row that changes its leading geometry
  /// has to say so here.
  static double textInsetOf(BrowseItem item) => switch (item.browseType) {
    BrowseType.track => 57,
    BrowseType.album || BrowseType.artist || BrowseType.catalog => 75,
    BrowseType.folder => 84,
    BrowseType.playlist => item.canEdit ? 81 : 71,
    BrowseType.unknown => 57,
  };

  /// Maps a single [BrowseItem] to its Search*Row widget. Public so lazy
  /// lists (e.g. paged/infinite-scroll surfaces) can build one row at a time
  /// while keeping the exact same dispatch, tap-to-play, and expansion
  /// behavior as the stacked [BrowseItemRows] Column.
  static Widget buildRow(
    BrowseItem item, {
    List<String>? queueContextIds,
    bool labelled = true,
  }) {
    switch (item.browseType) {
      case BrowseType.track:
        return SearchTrackRow(
          item: item,
          queueContextIds: queueContextIds,
          labelled: labelled,
        );
      case BrowseType.album:
        return SearchAlbumRow(item: item);
      case BrowseType.artist:
        return SearchArtistRow(item: item);
      case BrowseType.playlist:
        // A playlist the server will edit for you is a collection: it unrolls
        // like any other, but says what it is made of and how to change it.
        return item.canEdit
            ? CollectionRow(item: item)
            : SearchPlaylistRow(item: item);
      case BrowseType.catalog:
        return SearchCatalogRow(item: item);
      case BrowseType.folder:
        return SearchFolderRow(item: item);
      case BrowseType.unknown:
        return const SizedBox.shrink();
    }
  }
}
