import 'browse_filters.dart';
import 'data_model.dart';

/// The two requests a search makes of each source: its hits by name, and
/// what it suggests for the query.
enum ResultsLeg { matches, inspired }

/// One request's standing for one source.
sealed class LegState {
  const LegState();
}

class LegLoading extends LegState {
  const LegLoading();
}

class LegReady extends LegState {
  final BrowseItemsList list;

  const LegReady(this.list);
}

class LegFailed extends LegState {
  final String reason;

  const LegFailed(this.reason);
}

/// Skipped because the filter hides everything this leg would return.
class LegNotRequested extends LegState {
  const LegNotRequested();
}

/// One source's recommendations: its standing, and the tracks it suggested
/// once it answered.
class InspiredGroup {
  final String source;
  final LegState state;
  final List<BrowseItem> tracks;

  const InspiredGroup({
    required this.source,
    required this.state,
    required this.tracks,
  });
}

/// Everything a search has heard back, source by source.
///
/// Each leg is asked of each source separately, so each can land, fail and be
/// retried on its own — but only of a source that can answer it: one with no
/// audio of its own to suggest is asked for names alone. The name matches of
/// every source merge into one list by the tier and score the server put on
/// each hit; the recommendations stay grouped by the source that made them.
class SearchResults {
  final String query;

  /// The sources asked, in display order — the listener's own library first.
  /// Includes sources the filter skipped, so they can still be picked.
  final List<SourceOption> sources;

  final Map<String, LegState> matches;
  final Map<String, LegState> inspired;

  const SearchResults({
    required this.query,
    required this.sources,
    required this.matches,
    required this.inspired,
  });

  /// Nothing heard yet from anyone.
  ///
  /// [suggesting] names the sources an AI-search leg was asked of; null waits
  /// on all of them. A source that was never asked holds no leg here, so it
  /// is never shown waiting for an answer that is not coming.
  SearchResults.pending(this.query, this.sources, {Set<String>? suggesting})
    : matches = {for (final s in sources) s.name: const LegLoading()},
      inspired = {
        for (final s in sources)
          if (suggesting == null || suggesting.contains(s.name))
            s.name: const LegLoading(),
      };

  List<String> get sourceNames => [for (final s in sources) s.name];

  Map<String, LegState> legsOf(ResultsLeg leg) => switch (leg) {
    ResultsLeg.matches => matches,
    ResultsLeg.inspired => inspired,
  };

  static bool reaches(
    BrowseFilterQuery filter,
    ResultsLeg leg,
    String source,
  ) =>
      (filter.sources.isEmpty || filter.sources.contains(source)) &&
      switch (leg) {
        ResultsLeg.matches => filter.kind != ResultKind.recommendations,
        ResultsLeg.inspired => filter.kind != ResultKind.nameMatches,
      };

  SearchResults askingOnly(BrowseFilterQuery filter) {
    Map<String, LegState> only(ResultsLeg leg, Map<String, LegState> legs) => {
      for (final MapEntry(key: source, value: state) in legs.entries)
        source: reaches(filter, leg, source) ? state : const LegNotRequested(),
    };
    return SearchResults(
      query: query,
      sources: sources,
      matches: only(ResultsLeg.matches, matches),
      inspired: only(ResultsLeg.inspired, inspired),
    );
  }

  List<({ResultsLeg leg, String source})> unaskedUnder(
    BrowseFilterQuery filter,
  ) => [
    for (final source in sourceNames)
      for (final leg in ResultsLeg.values)
        if (legsOf(leg)[source] is LegNotRequested &&
            reaches(filter, leg, source))
          (leg: leg, source: source),
  ];

  SearchResults withLeg(ResultsLeg leg, String source, LegState state) {
    final next = Map<String, LegState>.from(legsOf(leg))..[source] = state;
    return SearchResults(
      query: query,
      sources: sources,
      matches: leg == ResultsLeg.matches ? next : matches,
      inspired: leg == ResultsLeg.inspired ? next : inspired,
    );
  }

  /// Every source has answered or failed its name-match leg — the merged
  /// list can be shown without reshuffling under the reader's eye.
  bool get matchesSettled => !matches.values.any((s) => s is LegLoading);

  bool get settled =>
      matchesSettled && !inspired.values.any((s) => s is LegLoading);

  /// Sources whose name-match leg failed, in display order.
  List<String> get unavailableMatchSources => [
    for (final source in sourceNames)
      if (matches[source] is LegFailed) source,
  ];

  /// The run each kind takes within a tier — the less granular first, as
  /// the server orders one source's hits.
  static const _kindOrder = <SearchType, int>{
    SearchType.artist: 0,
    SearchType.album: 1,
    SearchType.playlist: 2,
    SearchType.track: 3,
  };

  /// The name matches of every answered source as one list: tier first, kind
  /// within it so the list reads as runs rather than a shuffle, score within
  /// the kind, then the source order — a stable merge that keeps each
  /// source's own order among its ties, so nothing is ranked here.
  List<BrowseItem> get rankedMatches {
    final entries =
        <
          ({
            int tier,
            int kind,
            double score,
            int source,
            int index,
            BrowseItem item,
          })
        >[];
    for (var rank = 0; rank < sources.length; rank++) {
      final state = matches[sources[rank].name];
      if (state is! LegReady) continue;
      for (final item in state.list.items) {
        final match = item.match;
        entries.add((
          tier: match?.tier.index ?? MatchTier.values.length,
          kind: _kindOrder[_typeOf(item)] ?? _kindOrder.length,
          score: match?.score ?? 0,
          source: rank,
          index: entries.length,
          item: item,
        ));
      }
    }
    entries.sort((a, b) {
      if (a.tier != b.tier) return a.tier.compareTo(b.tier);
      if (a.kind != b.kind) return a.kind.compareTo(b.kind);
      if (a.score != b.score) return b.score.compareTo(a.score);
      if (a.source != b.source) return a.source.compareTo(b.source);
      return a.index.compareTo(b.index);
    });
    return [for (final entry in entries) entry.item];
  }

  /// One group per source that was asked, in display order, whatever its
  /// standing.
  List<InspiredGroup> get inspiredGroups => [
    for (final source in sourceNames)
      if (inspired[source] case final state? when state is! LegNotRequested)
        InspiredGroup(source: source, state: state, tracks: _tracksOf(state)),
  ];

  static List<BrowseItem> _tracksOf(LegState? state) {
    if (state is! LegReady) return const [];
    return [
      for (final card in state.list.items)
        for (final item in card.sections ?? const <BrowseItem>[])
          if (item.track != null) item,
    ];
  }

  /// The entity kinds the name matches hold, in the canonical order.
  List<SearchType> get typesPresent {
    final present = {
      for (final item in rankedMatches) _typeOf(item),
      if (inspiredGroups.any((g) => g.tracks.isNotEmpty)) SearchType.track,
    };
    return [
      for (final type in BrowseFilterCapabilities.allTypes)
        if (present.contains(type)) type,
    ];
  }

  /// The genres the results carry, most common first. Keyed by name rather
  /// than by the sources' own ids, which never agree with each other.
  List<Genre> get genresPresent {
    final counts = <String, int>{};
    final names = <String, String>{};
    void count(BrowseItem item) {
      for (final genre in _genresOf(item)) {
        counts[genre.id] = (counts[genre.id] ?? 0) + 1;
        names.putIfAbsent(genre.id, () => genre.name);
      }
    }

    rankedMatches.forEach(count);
    for (final group in inspiredGroups) {
      group.tracks.forEach(count);
    }
    final ids = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        return byCount != 0 ? byCount : names[a]!.compareTo(names[b]!);
      });
    return [for (final id in ids) Genre(id: id, name: names[id]!)];
  }

  /// What the reader sees under [filter]: the name matches it leaves, in the
  /// order it asks for, and the recommendation groups it leaves.
  NarrowedResults narrow(BrowseFilterQuery filter) {
    final ranked = rankedMatches;
    final artistGenres = _artistGenres(ranked);
    bool keep(BrowseItem item) =>
        (filter.type == null || _typeOf(item) == filter.type) &&
        (filter.sources.isEmpty || filter.sources.contains(sourceOf(item))) &&
        (filter.genreIds.isEmpty ||
            _genresOf(
              item,
              inherited: artistGenres,
            ).any((g) => filter.genreIds.contains(g.id)));

    final matches = filter.kind == ResultKind.recommendations
        ? <BrowseItem>[]
        : ranked.where(keep).toList();
    if (filter.order == NameMatchOrder.alphabetical) {
      matches.sort(
        (a, b) => (a.name ?? '').toLowerCase().compareTo(
          (b.name ?? '').toLowerCase(),
        ),
      );
    }

    final groups = filter.kind == ResultKind.nameMatches
        ? const <InspiredGroup>[]
        : [
            for (final group in inspiredGroups)
              if (filter.sources.isEmpty ||
                  filter.sources.contains(group.source))
                InspiredGroup(
                  source: group.source,
                  state: group.state,
                  tracks: group.tracks.where(keep).toList(),
                ),
          ];
    return NarrowedResults(matches: matches, groups: groups);
  }

  /// An artist's genres are its albums' and tracks' — the ones among these
  /// results, which is all the app has in hand.
  Map<String, Set<String>> _artistGenres(List<BrowseItem> items) {
    final genres = <String, Set<String>>{};
    for (final item in items) {
      final artistId =
          item.album?.artist?.id ??
          item.track?.performer?.id ??
          item.track?.album?.artist?.id;
      if (artistId == null) continue;
      genres
          .putIfAbsent(artistId, () => {})
          .addAll(_genresOf(item).map((g) => g.id));
    }
    return genres;
  }

  static SearchType _typeOf(BrowseItem item) => switch (item.browseType) {
    BrowseType.artist => SearchType.artist,
    BrowseType.album => SearchType.album,
    BrowseType.track => SearchType.track,
    BrowseType.playlist => SearchType.playlist,
    _ => SearchType.invalid,
  };

  /// The source segment of an item's id.
  static String sourceOf(BrowseItem item) {
    try {
      return EntityId.fromString(item.id).source;
    } catch (_) {
      return '';
    }
  }

  /// The genres an item carries, keyed by folded name rather than by the
  /// sources' own ids, which never agree with each other.
  static List<Genre> _genresOf(
    BrowseItem item, {
    Map<String, Set<String>> inherited = const {},
  }) {
    final genres = item.album?.genres ?? item.track?.album?.genres;
    if (genres != null && genres.isNotEmpty) {
      return [
        for (final genre in genres)
          Genre(id: genre.name.toLowerCase(), name: genre.name),
      ];
    }
    final artist = item.artist;
    if (artist != null) {
      return [
        for (final id in inherited[artist.id] ?? const <String>{})
          Genre(id: id, name: id),
      ];
    }
    return const [];
  }
}

/// The results as narrowed by a filter.
class NarrowedResults {
  final List<BrowseItem> matches;
  final List<InspiredGroup> groups;

  const NarrowedResults({required this.matches, required this.groups});

  int get recommendationCount =>
      groups.fold(0, (sum, group) => sum + group.tracks.length);
}
