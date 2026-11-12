import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/browse_filters.dart';
import '../../data_model/data_model.dart';
import '../../data_model/search_results.dart';
import '../../providers/search_session_provider.dart';
import '../../theme/app_theme.dart';
import '../search_cards/browse_item_rows.dart';
import '../shelf_heading.dart';
import '../source_badge.dart';
import 'browse_visit_scope.dart';
import 'inspired_block.dart';
import 'results_tabs.dart';
import 'track_group_actions.dart';

/// A single browse visit over the overview's filtered result snapshot: one
/// source's suggestions, a shelf per kind. Source switches replace its
/// selection, so Back always restores the overview.
class InspiredSuggestionsView extends ConsumerWidget {
  const InspiredSuggestionsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = visitOf(context, ref);
    final results = session.results;
    if (results == null) return const SizedBox.shrink();
    final groups = results
        .narrow(session.resultsFilter)
        .groups
        .where((g) => g.items.isNotEmpty)
        .toList();
    if (groups.isEmpty) {
      return Center(
        child: Text(
          'No matching suggestions',
          style: KalinkaTextStyles.trackRowSubtitle,
        ),
      );
    }
    final selected = groups.indexWhere(
      (g) => g.source == session.expandedBlock?.source,
    );
    final index = selected < 0 ? 0 : selected;
    final group = groups[index];
    final trackIds = [for (final item in group.tracks) item.id];
    String label(InspiredGroup g) => results.sources.titleOf(g.source);
    return SourceAttributionScope(
      source: group.source,
      child: CustomScrollView(
        key: PageStorageKey('inspired-${session.visitId}-${group.source}'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            sliver: SliverMainAxisGroup(
              slivers: [
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: InspiredHeading(caption: false),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (groups.length > 1)
                        ResultsTabs(
                          labels: [for (final g in groups) label(g)],
                          leading: [
                            for (var i = 0; i < groups.length; i++)
                              _sourceBadge(
                                context,
                                groups[i].source,
                                selected: index == i,
                              ),
                          ],
                          selected: index,
                          onSelected: (next) => ref
                              .read(searchSessionProvider.notifier)
                              .selectInspiredSource(groups[next].source),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              _sourceBadge(
                                context,
                                group.source,
                                selected: true,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  label(group).toUpperCase(),
                                  style: KalinkaTextStyles.sectionLabel
                                      .copyWith(
                                        color: KalinkaColors.textPrimary,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (trackIds.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: TrackGroupActions(
                            key: ValueKey(group.source),
                            trackIds: trackIds,
                            addLabel: 'Add to queue',
                          ),
                        )
                      else
                        const SizedBox(height: 16),
                    ],
                  ),
                ),
                for (final (i, (type, items)) in group.shelves.indexed) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, i == 0 ? 0 : 24, 16, 10),
                      child: Semantics(
                        header: true,
                        child: ShelfHeading(
                          title: _shelfTitle(type),
                          count: items.length,
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverBrowseItemRows(
                      items: items,
                      queueContextIds: type == SearchType.track
                          ? trackIds
                          : null,
                      labelled: false,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _shelfTitle(SearchType type) => switch (type) {
    SearchType.artist => 'ARTISTS',
    SearchType.album => 'ALBUMS',
    SearchType.playlist => 'PLAYLISTS',
    SearchType.track => 'TRACKS',
    SearchType.invalid => '',
  };

  Widget _sourceBadge(
    BuildContext context,
    String source, {
    required bool selected,
  }) => ExcludeSemantics(
    child: SourceTile(
      source: source,
      small: true,
      size: 20,
      foreground: selected
          ? KalinkaColors.textPrimary
          : KalinkaColors.textSecondary,
    ),
  );
}
