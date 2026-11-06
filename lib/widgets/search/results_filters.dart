import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data_model/browse_filters.dart';
import '../../data_model/data_model.dart';
import '../browse_filters/active_filter_chips.dart';
import 'results_tabs.dart';

/// The overview's type tabs and receipts for its applied facets.
/// Genre and Source are edited together from the top bar's filter popup.
class ResultsFilters extends StatelessWidget {
  final BrowseFilterCapabilities capabilities;
  final BrowseFilterQuery query;
  final ValueChanged<BrowseFilterQuery> onChanged;

  const ResultsFilters({
    super.key,
    required this.capabilities,
    required this.query,
    required this.onChanged,
  });

  static const _types = <SearchType?>[
    null,
    SearchType.artist,
    SearchType.album,
    SearchType.playlist,
    SearchType.track,
  ];

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ResultsTabs(
        labels: const ['All', 'Artists', 'Albums', 'Playlists', 'Tracks'],
        selected: math.max(0, _types.indexOf(query.type)),
        onSelected: (index) => onChanged(
          query.copyWith(type: _types[index], clearType: index == 0),
        ),
      ),
      ActiveFilterChips(
        capabilities: capabilities,
        query: BrowseFilterQuery(
          genreIds: query.genreIds,
          sources: query.sources,
        ),
        onChanged: (facets) => onChanged(
          query.copyWith(genreIds: facets.genreIds, sources: facets.sources),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      ),
    ],
  );
}
