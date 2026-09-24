import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/browse_filters.dart';
import '../../data_model/search_results.dart';
import '../../providers/source_modules_provider.dart';
import '../browse_rows_shimmer.dart';
import '../search_cards/action_pill_button.dart';
import '../search_cards/browse_item_rows.dart';
import '../shelf_heading.dart';
import '../source_badge.dart';
import 'source_unavailable_row.dart';

/// What every source found by name, as one list — the best few, with the
/// rest a VIEW ALL away.
///
/// Waits for every source before showing anything: the list is a merge, and
/// a merge that fills in as sources answer would reshuffle under the eye. A
/// source that failed is named below the rows instead of thinning them.
class NameMatchesBlock extends StatelessWidget {
  final SearchResults results;
  final NarrowedResults narrowed;
  final BrowseFilterQuery filter;

  /// The one source being read, or null for the merged list. Ignored when it
  /// names a source these results no longer hold.
  final String? source;

  final ValueChanged<String?> onSource;
  final VoidCallback onViewAll;
  final ValueChanged<String> onRetry;

  /// How many lead the block before VIEW ALL.
  static const previewCount = 4;

  const NameMatchesBlock({
    super.key,
    required this.results,
    required this.narrowed,
    required this.filter,
    required this.source,
    required this.onSource,
    required this.onViewAll,
    required this.onRetry,
  });

  /// Whether the block has anything to say under [filter]: rows, rows still
  /// coming, or a source that could not answer.
  static bool visible(
    SearchResults results,
    NarrowedResults narrowed,
    BrowseFilterQuery filter,
  ) {
    if (filter.kind == ResultKind.recommendations) return false;
    return !results.matchesSettled ||
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

  /// The sources the merged list actually holds, in display order.
  ///
  /// Read off the rows rather than off the module list, so a pill is never
  /// offered for a source that found nothing — and never for one the filter
  /// already excluded, since these rows have been through it. Computed
  /// before [source] is applied, so picking one does not take the others
  /// away.
  List<String> get _present {
    final held = {
      for (final item in narrowed.matches) SearchResults.sourceOf(item),
    };
    return [
      for (final option in results.sources)
        if (held.contains(option.name)) option.name,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final settled = results.matchesSettled;
    final present = _present;
    final picked = present.contains(source) ? source : null;
    final all = picked == null
        ? narrowed.matches
        : [
            for (final item in narrowed.matches)
              if (SearchResults.sourceOf(item) == picked) item,
          ];
    final expanded = filter.kind == ResultKind.nameMatches;
    final shown = expanded ? all : all.take(previewCount).toList();
    final unavailable = [
      for (final failed in _unavailable(results, filter))
        if (picked == null || failed == picked) failed,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShelfHeading(
          title: 'MATCHES BY NAME',
          count: settled ? all.length : null,
          onViewAll: settled && shown.length < all.length ? onViewAll : null,
        ),
        if (settled && present.length > 1) ...[
          const SizedBox(height: 10),
          _SourceChoices(sources: present, picked: picked, onPick: onSource),
        ],
        const SizedBox(height: 10),
        if (!settled)
          const BrowseRowsShimmer(count: previewCount)
        else
          BrowseItemRows(items: shown),
        for (final failed in unavailable)
          SourceUnavailableRow(
            source: failed,
            title: results.sources.titleOf(failed),
            onRetry: () => onRetry(failed),
          ),
      ],
    );
  }
}

/// Which source's matches to read: each named in full behind the letter it
/// wears on its rows, the one being read highlighted like a Play all beside
/// a plain Enqueue. All is on when no source is.
///
/// A line that scrolls rather than wraps — the names are as long as the
/// sources are, and a control that reflows as sources come and go is harder
/// to aim at than one that runs off the edge.
class _SourceChoices extends ConsumerWidget {
  final List<String> sources;
  final String? picked;
  final ValueChanged<String?> onPick;

  const _SourceChoices({
    required this.sources,
    required this.picked,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(sourceDisplayInfoProvider);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        spacing: 8,
        children: [
          ActionPillButton(
            label: 'All',
            accent: picked == null,
            selected: picked == null,
            onTap: () => onPick(null),
            semanticsLabel: 'All sources',
          ),
          for (final source in sources)
            ActionPillButton(
              leading: SourceTile(source: source, size: 18),
              label: info[source]?.title ?? source,
              accent: picked == source,
              selected: picked == source,
              onTap: () => onPick(source),
            ),
        ],
      ),
    );
  }
}
