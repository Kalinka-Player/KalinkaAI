import 'package:flutter/material.dart';

import '../../data_model/browse_filters.dart';
import '../../data_model/search_results.dart';
import '../../theme/app_theme.dart';
import '../browse_rows_shimmer.dart';
import '../search_cards/browse_item_rows.dart';
import '../shelf_heading.dart';
import '../source_badge.dart';
import 'source_unavailable_row.dart';
import 'track_group_actions.dart';

/// What the sources suggest for the query, kept apart by source: their
/// rankings are not comparable, so each group keeps its own order, its own
/// batch actions and its own way of opening in full. Each group stands on
/// its own answer — one still loading shimmers, one that failed says so,
/// while the others show. The heading holds them together as the one section
/// they are, and the display face gives the block a voice of its own: these
/// are answers offered, not a listing of what a source holds.
class InspiredBlock extends StatelessWidget {
  final SearchResults results;
  final NarrowedResults narrowed;
  final BrowseFilterQuery filter;

  /// Opens one source's recommendations in full.
  final ValueChanged<String> onViewAll;
  final ValueChanged<String> onRetry;

  /// How far the page edge lies left of the block: the heading's wash runs
  /// out to it.
  final double gutter;

  /// How many of a group's tracks lead before View All.
  static const previewCount = 3;

  const InspiredBlock({
    super.key,
    required this.results,
    required this.narrowed,
    required this.filter,
    required this.onViewAll,
    required this.onRetry,
    this.gutter = 0,
  });

  /// Whether any group has anything to show under [filter].
  static bool visible(
    SearchResults results,
    NarrowedResults narrowed,
    BrowseFilterQuery filter,
  ) {
    if (filter.kind == ResultKind.nameMatches) return false;
    return narrowed.groups.any(_groupVisible);
  }

  static bool _groupVisible(InspiredGroup group) =>
      group.state is! LegReady || group.tracks.isNotEmpty;

  /// The narrowest a group reads well at, and the room between two side by
  /// side.
  static const groupMinWidth = 400.0;
  static const groupGutter = 28.0;

  @override
  Widget build(BuildContext context) {
    final groups = narrowed.groups.where(_groupVisible).toList();
    final expanded = filter.kind == ResultKind.recommendations;
    Widget groupOf(InspiredGroup group, {bool sliver = false}) => _SourceGroup(
      group: group,
      title: results.sources.titleOf(group.source),
      expanded: expanded,
      sliver: sliver,
      onViewAll: () => onViewAll(group.source),
      onRetry: () => onRetry(group.source),
    );

    // A sliver: a group opened in full lists its tracks lazily, one after
    // another; previews keep their grid.
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(child: _InspiredHeading(gutter: gutter)),
        if (expanded)
          for (var i = 0; i < groups.length; i++) ...[
            if (i > 0) const SliverToBoxAdapter(child: SizedBox(height: 14)),
            groupOf(groups[i], sliver: true),
          ]
        else
          SliverToBoxAdapter(child: _previews(groups, groupOf)),
      ],
    );
  }

  Widget _previews(
    List<InspiredGroup> groups,
    Widget Function(InspiredGroup) groupOf,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      // Two sources side by side where both fit; a third starts the
      // next row at the same width, in source order. Each keeps its
      // own list, so nothing is merged or reflowed between them.
      final columns = constraints.maxWidth >= groupMinWidth * 2 + groupGutter
          ? 2
          : 1;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A later source stands further off the rows above it than
          // rows stand off each other, so it reads as a group, not the
          // next row.
          for (var i = 0; i < groups.length; i += columns) ...[
            if (i > 0) const SizedBox(height: 14),
            if (columns == 1)
              groupOf(groups[i])
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: groupOf(groups[i])),
                  const SizedBox(width: groupGutter),
                  Expanded(
                    child: i + 1 < groups.length
                        ? groupOf(groups[i + 1])
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
          ],
        ],
      );
    },
  );
}

/// What the block is and then its name, in the shape a page title takes: an
/// eyebrow over the display face, nothing ruled through either. The eyebrow
/// is quieter than the shelf labels so the name leads; the sparkle is the
/// Discover mark. No tally here: each source carries its own.
class _InspiredHeading extends StatelessWidget {
  final double gutter;

  const _InspiredHeading({required this.gutter});

  /// A neutral lift of the ground behind the heading, edge to edge, peaking
  /// just above the name and gone by the heading's foot. Not berry: a berry
  /// wash beside the berry now-playing row read as the same signal twice.
  static final _wash = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      KalinkaColors.surfaceElevated.withValues(alpha: 0),
      KalinkaColors.surfaceElevated,
      KalinkaColors.surfaceElevated.withValues(alpha: 0),
    ],
    stops: const [0, 0.4, 1],
  );

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: -gutter,
          right: -gutter,
          top: 0,
          bottom: 0,
          child: IgnorePointer(
            child: DecoratedBox(decoration: BoxDecoration(gradient: _wash)),
          ),
        ),
        Padding(
          // The wash rises through the air above the eyebrow.
          padding: const EdgeInsets.only(top: 14, bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.auto_awesome,
                    size: 14,
                    color: KalinkaColors.accentTint,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'SMART RECOMMENDATIONS',
                    style: KalinkaTextStyles.blockEyebrow,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Inspired by your request',
                style: KalinkaTextStyles.blockTitle,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One source's answer: its name and tally, the actions over the whole of
/// it, and a preview of its rows.
class _SourceGroup extends StatelessWidget {
  final InspiredGroup group;
  final String title;
  final bool expanded;

  /// Built as a sliver, its rows only as they come into view.
  final bool sliver;
  final VoidCallback onViewAll;
  final VoidCallback onRetry;

  const _SourceGroup({
    required this.group,
    required this.title,
    required this.expanded,
    required this.onViewAll,
    required this.onRetry,
    this.sliver = false,
  });

  @override
  Widget build(BuildContext context) {
    final state = group.state;
    if (state is LegFailed) {
      final row = SourceUnavailableRow(
        source: group.source,
        title: title,
        onRetry: onRetry,
      );
      return sliver ? SliverToBoxAdapter(child: row) : row;
    }
    final tracks = group.tracks;
    final trackIds = [for (final item in tracks) item.id];
    final more = !expanded && tracks.length > InspiredBlock.previewCount;
    // The tally MATCHES BY NAME carries too: it says a preview is a preview.
    final count = state is LegLoading ? null : tracks.length;
    final shown = expanded
        ? tracks
        : tracks.take(InspiredBlock.previewCount).toList();

    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SourceTile(source: group.source),
            const SizedBox(width: 10),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      title.toUpperCase(),
                      style: KalinkaTextStyles.sectionLabel.copyWith(
                        color: KalinkaColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (count != null) ...[
                    const SizedBox(width: 8),
                    ShelfTally(count),
                  ],
                ],
              ),
            ),
            if (more) ...[
              const SizedBox(width: 12),
              ViewAllAction(label: 'View All', onTap: onViewAll),
            ],
          ],
        ),
        // Its own row under the name, like an unrolled album's actions.
        if (tracks.isNotEmpty) ...[
          const SizedBox(height: 8),
          TrackGroupActions(trackIds: trackIds),
        ],
        const SizedBox(height: 8),
      ],
    );
    const shimmer = BrowseRowsShimmer(count: InspiredBlock.previewCount);
    if (sliver) {
      return SliverMainAxisGroup(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.only(top: 16),
            sliver: SliverToBoxAdapter(child: head),
          ),
          if (state is LegLoading)
            const SliverToBoxAdapter(child: shimmer)
          else
            SliverBrowseItemRows(
              items: shown,
              queueContextIds: trackIds,
              labelled: false,
            ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          head,
          if (state is LegLoading)
            shimmer
          else
            // Tapping a track plays the group from it: the group is the
            // queue, which gives it a coherent identity. The heading already
            // names the source and the kind.
            BrowseItemRows(
              items: shown,
              queueContextIds: trackIds,
              labelled: false,
            ),
        ],
      ),
    );
  }
}
