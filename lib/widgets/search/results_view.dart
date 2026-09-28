import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/browse_filters.dart';
import '../../data_model/search_results.dart';
import '../../providers/search_session_provider.dart';
import '../../theme/app_theme.dart';
import '../browse_filters/active_filter_chips.dart';
import 'inspired_block.dart';
import 'name_matches_block.dart';
import 'search_loading_indicator.dart';

/// The Results layer: the query as a chip beside whatever narrows it, then
/// what was found by name and what was found for it. Holds a single query —
/// a new search replaces it. Going back to Catalogs is the title bar's `‹`
/// (or system back), never a button here.
class ResultsView extends ConsumerWidget {
  const ResultsView({super.key});

  static const _gutter = 16.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(searchSessionProvider);
    final notifier = ref.read(searchSessionProvider.notifier);
    final results = session.results;

    return ListView(
      padding: const EdgeInsets.fromLTRB(_gutter, 4, _gutter, 24),
      children: [
        ActiveFilterChips(
          capabilities: session.resultsFilterCapabilities,
          query: session.resultsFilter,
          onChanged: notifier.setResultsFilter,
          padding: const EdgeInsets.only(bottom: 16),
          // The query is not a facet, but it sits where the facets do: the
          // one thing every row below answers to. Removing it removes them.
          leading: ActiveFilterChip(
            label: '“${session.searchQuery}”',
            icon: Icons.auto_awesome,
            onRemove: notifier.clearSearch,
          ),
        ),
        if (session.searchLoading)
          const SearchLoadingIndicator()
        else if (session.searchError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
            child: Text(
              session.searchError!,
              style: KalinkaTextStyles.trackRowSubtitle.copyWith(
                color: KalinkaColors.actionDelete,
              ),
            ),
          )
        else if (results != null)
          ..._blocks(
            results,
            session.resultsFilter,
            session.matchSource,
            notifier,
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
    if (!matches && !inspired) return const [_NoMatches()];
    return [
      if (matches)
        NameMatchesBlock(
          results: results,
          narrowed: narrowed,
          filter: filter,
          source: matchSource,
          onSource: notifier.setMatchSource,
          onViewAll: () => notifier.setResultsFilter(
            filter.copyWith(kind: ResultKind.nameMatches),
            remember: false,
          ),
          onRetry: (source) => notifier.retry(ResultsLeg.matches, source),
        ),
      if (matches && inspired) const SizedBox(height: 28),
      if (inspired)
        InspiredBlock(
          results: results,
          narrowed: narrowed,
          filter: filter,
          // The source facet only where there is a choice to narrow.
          onViewAll: (source) => notifier.setResultsFilter(
            filter.copyWith(
              kind: ResultKind.recommendations,
              sources: results.sources.length > 1 ? [source] : null,
            ),
            remember: false,
          ),
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
