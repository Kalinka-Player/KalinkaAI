import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/browse_filters.dart';
import '../../data_model/search_results.dart';
import '../../providers/search_session_provider.dart';
import '../../theme/app_theme.dart';
import '../browse_filters/active_filter_chips.dart';
import '../browse_filters/filters_match_nothing.dart';
import 'browse_visit_scope.dart';
import 'inspired_block.dart';
import 'name_matches_block.dart';
import 'search_loading_indicator.dart';

/// The Results layer: the chips of the genres narrowing the query, which the
/// bar names, then what was found by name and what was found for it. A block
/// opened with VIEW ALL is a visit of its own, left with Back. Holds a single query —
/// a new search replaces it. Going back to Catalogs is the title bar's `‹`
/// (or system back), never a button here.
class ResultsView extends ConsumerWidget {
  const ResultsView({super.key});

  static const _gutter = 16.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = visitOf(context, ref);
    final notifier = ref.read(searchSessionProvider.notifier);
    final results = session.results;

    // Slivers, so a block opened in full builds only the rows in view.
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(_gutter, 21, _gutter, 24),
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: ActiveFilterChips(
                  capabilities: session.resultsFilterCapabilities,
                  // Wait for the source list before showing filters.
                  query: results == null
                      ? const BrowseFilterQuery()
                      : session.resultsFilter,
                  onChanged: notifier.setResultsFilter,
                  padding: const EdgeInsets.only(bottom: 16),
                ),
              ),
              if (session.searchLoading)
                const SliverToBoxAdapter(child: SearchLoadingIndicator())
              else if (session.searchError != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 4,
                    ),
                    child: Text(
                      session.searchError!,
                      style: KalinkaTextStyles.trackRowSubtitle.copyWith(
                        color: KalinkaColors.actionDelete,
                      ),
                    ),
                  ),
                )
              else if (results != null)
                ..._blocks(
                  results,
                  session.resultsShown,
                  session.matchSource,
                  notifier,
                ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _blocks(
    SearchResults results,
    BrowseFilterQuery filter,
    String? matchSource,
    SearchSessionNotifier notifier,
  ) {
    final narrowed = results.narrow(filter);
    final matches = NameMatchesBlock.visible(results, narrowed, filter);
    final inspired = InspiredBlock.visible(results, narrowed, filter);
    if (!matches && !inspired) {
      // Sorting alone cannot cause an empty result, nor a source picked: it
      // is only ever one that found something.
      final filtered =
          filter.copyWith(order: NameMatchOrder.relevance).activeCount > 0;
      if (!filtered) return const [SliverToBoxAdapter(child: _NoMatches())];
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: FiltersMatchNothing(onReset: notifier.resetResults),
          ),
        ),
      ];
    }
    return [
      if (matches)
        NameMatchesBlock(
          results: results,
          narrowed: narrowed,
          filter: filter,
          source: matchSource,
          onSource: notifier.setMatchSource,
          onViewAll: () => notifier.expandBlock((
            kind: ResultKind.nameMatches,
            source: null,
          )),
          onRetry: (source) => notifier.retry(ResultsLeg.matches, source),
          gutter: _gutter,
        ),
      if (matches && inspired)
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      if (inspired)
        InspiredBlock(
          results: results,
          narrowed: narrowed,
          filter: filter,
          onViewAll: (source) => notifier.expandBlock((
            kind: ResultKind.recommendations,
            source: source,
          )),
          onRetry: (source) => notifier.retry(ResultsLeg.inspired, source),
          gutter: _gutter,
        ),
    ];
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 40,
            color: KalinkaColors.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text('No matches', style: KalinkaTextStyles.cardTitle),
          const SizedBox(height: 4),
          Text(
            'Try rephrasing your request',
            style: KalinkaTextStyles.trackRowSubtitle,
          ),
        ],
      ),
    );
  }
}
