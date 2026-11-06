import 'package:flutter/material.dart';

import '../../data_model/browse_filters.dart';
import '../../data_model/data_model.dart';
import '../../data_model/search_results.dart';
import '../../providers/listing_presentation_provider.dart';
import '../browse_filters/filters_match_nothing.dart';
import '../browse_filters/presentation_toggle.dart';
import '../browse_rows_shimmer.dart';
import '../search_cards/artwork_grid.dart';
import '../search_cards/artwork_grid_card.dart';
import '../search_cards/browse_item_rows.dart';
import '../shelf_heading.dart';
import '../source_badge.dart';
import 'source_unavailable_row.dart';

/// What the selected sources found by name, as one ranked list. Narrow
/// overviews with inspired results show a short preview and View All.
///
/// Waits for every source before showing anything: the list is a merge, and
/// a merge that fills in as sources answer would reshuffle under the eye. A
/// source that failed is named below the rows instead of thinning them.
class NameMatchesBlock extends StatelessWidget {
  final SearchResults results;
  final NarrowedResults narrowed;
  final BrowseFilterQuery filter;

  final VoidCallback onViewAll;
  final ValueChanged<String> onRetry;
  final VoidCallback onReset;
  final ListingLayout? layout;
  final bool grid;

  /// Narrow overviews preview names only when inspired results follow.
  final bool preview;

  /// How many lead the block before View All.
  static const previewCount = 4;

  const NameMatchesBlock({
    super.key,
    required this.results,
    required this.narrowed,
    required this.filter,
    required this.onViewAll,
    required this.onRetry,
    required this.onReset,
    this.preview = true,
    this.layout,
    this.grid = false,
  });

  /// Whether the block has anything to say under [filter]: rows, rows still
  /// coming, or a source that could not answer.
  static bool visible(
    SearchResults results,
    NarrowedResults narrowed,
    BrowseFilterQuery filter,
  ) {
    if (filter.kind == ResultKind.recommendations) return false;
    return ListingLayout.forSearch(filter.type) != null ||
        !results.matchesSettled ||
        narrowed.matches.isNotEmpty ||
        _unavailable(results, filter).isNotEmpty;
  }

  static List<String> _unavailable(
    SearchResults results,
    BrowseFilterQuery filter,
  ) => [
    for (final source in results.unavailableMatchSources)
      if (filter.sources.isEmpty || filter.sources.contains(source)) source,
  ];

  @override
  Widget build(BuildContext context) {
    final settled = results.matchesSettled;
    final all = narrowed.matches;
    final expanded = filter.kind == ResultKind.nameMatches || !preview;
    final shown = expanded ? all : all.take(previewCount).toList();
    final unavailable = _unavailable(results, filter);
    final inset = grid ? ArtworkGridCard.inset : 0.0;

    // A sliver: opened in full it can hold hundreds of rows, and only those
    // in view are built.
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: inset),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final heading = ShelfHeading(
                      title: 'NAME MATCHES',
                      count: settled ? all.length : null,
                      onViewAll: settled && shown.length < all.length
                          ? onViewAll
                          : null,
                    );
                    final layout = this.layout;
                    if (layout == null) return heading;
                    return Row(
                      children: [
                        Expanded(child: heading),
                        const SizedBox(width: 12),
                        PresentationToggle(
                          layout: layout,
                          compact:
                              constraints.maxWidth <
                              600 *
                                  MediaQuery.textScalerOf(context).scale(16) /
                                  16,
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
        if (settled && shown.isEmpty && unavailable.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: inset, vertical: 28),
              child: FiltersMatchNothing(onReset: onReset),
            ),
          )
        else if (grid)
          SourceAttributionScope(
            source: null,
            child: SliverArtworkGrid(
              items: shown,
              loading: !settled,
              artists: filter.type == SearchType.artist,
            ),
          )
        else if (!settled)
          const SliverToBoxAdapter(
            child: BrowseRowsShimmer(count: previewCount),
          )
        else
          SourceAttributionScope(
            source: null,
            child: SliverBrowseItemRows(items: shown),
          ),
        if (unavailable.isNotEmpty)
          SliverList.list(
            children: [
              for (final failed in unavailable)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: inset),
                  child: SourceUnavailableRow(
                    source: failed,
                    title: results.sources.titleOf(failed),
                    onRetry: () => onRetry(failed),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
