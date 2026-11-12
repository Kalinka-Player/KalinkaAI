import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/browse_filters.dart';
import '../../data_model/search_results.dart';
import '../../providers/listing_presentation_provider.dart';
import '../../providers/search_session_provider.dart';
import '../../theme/app_theme.dart';
import '../browse_filters/filters_match_nothing.dart';
import '../fast_scroller.dart';
import '../search_cards/artwork_grid_card.dart';
import 'browse_visit_scope.dart';
import 'inspired_block.dart';
import 'inspired_suggestions_view.dart';
import 'results_filters.dart';
import 'name_matches_block.dart';
import 'search_loading_indicator.dart';

/// One overview scroll holds type tabs, filters, ranked name matches and
/// source cards. Wide panes put the two result sections alongside each other.
/// Opening a complete listing creates a separate retained browse visit.
class ResultsView extends ConsumerStatefulWidget {
  const ResultsView({super.key});

  static const _gutter = 16.0;

  @override
  ConsumerState<ResultsView> createState() => _ResultsViewState();
}

class _ResultsViewState extends ConsumerState<ResultsView> {
  static const _gutter = ResultsView._gutter;

  final _controller = DeferringScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = visitOf(context, ref);
    if (session.expandedBlock?.kind == ResultKind.recommendations) {
      return const InspiredSuggestionsView();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >=
            900 * MediaQuery.textScalerOf(context).scale(1);
        Widget list = _buildList(context, wide: wide);
        if (FastScroller.wanted(context)) {
          list = FastScroller(
            controller: _controller,
            padding: const EdgeInsets.only(bottom: 8),
            child: list,
          );
        }
        return list;
      },
    );
  }

  Widget _buildList(BuildContext context, {required bool wide}) {
    final session = visitOf(context, ref);
    final notifier = ref.read(searchSessionProvider.notifier);
    final results = session.results;
    final layout = ListingLayout.forSearch(session.resultsShown.type);
    final grid =
        layout != null &&
        watchPresentation(ref, layout) == ListingPresentation.grid;
    // The cards' frames extend into the gutter; their artwork and captions
    // align with the heading, as in the catalogues.
    final gridInset = grid && results != null && session.searchError == null
        ? ArtworkGridCard.inset
        : 0.0;
    final hasFilterChips =
        session.expandedBlock == null &&
        (session.resultsFilter.genreIds.isNotEmpty ||
            session.resultsFilter.sources.isNotEmpty);

    // Slivers, so a block opened in full builds only the rows in view.
    return CustomScrollView(
      controller: _controller,
      slivers: [
        if (session.expandedBlock == null)
          SliverToBoxAdapter(
            child: ResultsFilters(
              capabilities: session.resultsFilterCapabilities,
              query: session.resultsFilter,
              onChanged: notifier.setResultsFilter,
            ),
          ),
        SliverPadding(
          // Share the gap above the results evenly around applied chips.
          padding: EdgeInsets.fromLTRB(
            _gutter - gridInset,
            hasFilterChips ? 13 : 21,
            _gutter - gridInset,
            24,
          ),
          sliver: SliverMainAxisGroup(
            slivers: [
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
                  notifier,
                  wide: wide,
                  layout: layout,
                  grid: grid,
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
    SearchSessionNotifier notifier, {
    required bool wide,
    required ListingLayout? layout,
    required bool grid,
  }) {
    final narrowed = results.narrow(filter);
    final inspired = InspiredBlock.visible(results, narrowed, filter);
    final matches = NameMatchesBlock.visible(
      results,
      narrowed,
      filter,
      suggestionsShown: inspired,
    );
    if (!matches && !inspired) {
      // Sorting alone cannot cause an empty result.
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
    final names = NameMatchesBlock(
      results: results,
      narrowed: narrowed,
      filter: filter,
      onViewAll: () =>
          notifier.expandBlock((kind: ResultKind.nameMatches, source: null)),
      onRetry: (source) => notifier.retry(ResultsLeg.matches, source),
      onReset: notifier.resetResults,
      preview: !wide && inspired,
      layout: layout,
      grid: grid,
    );
    final suggestions = InspiredBlock(
      results: results,
      narrowed: narrowed,
      filter: filter,
      onViewAll: (source) => notifier.expandBlock((
        kind: ResultKind.recommendations,
        source: source,
      )),
      onRetry: (source) => notifier.retry(ResultsLeg.inspired, source),
      gutter: wide && matches ? 0 : _gutter,
    );
    if (wide && matches && inspired) {
      return [
        SliverCrossAxisGroup(
          slivers: [
            SliverCrossAxisExpanded(
              flex: 11,
              sliver: SliverPadding(
                padding: const EdgeInsets.only(right: 24),
                sliver: names,
              ),
            ),
            SliverCrossAxisExpanded(
              flex: 9,
              sliver: DecoratedSliver(
                decoration: const BoxDecoration(
                  border: Border(
                    left: BorderSide(color: KalinkaColors.borderSubtle),
                  ),
                ),
                sliver: SliverPadding(
                  padding: const EdgeInsets.only(left: 24),
                  sliver: suggestions,
                ),
              ),
            ),
          ],
        ),
      ];
    }
    return [
      if (matches) names,
      if (matches && inspired)
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      if (inspired) suggestions,
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
