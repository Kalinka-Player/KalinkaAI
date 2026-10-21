import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/data_model/browse_filters.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/search_results.dart';

BrowseItem _artist(
  String source,
  String id,
  String name,
  MatchTier tier, {
  double score = 100,
}) => BrowseItem(
  id: 'kalinka:$source:artist:$id',
  name: name,
  canBrowse: true,
  canAdd: false,
  artist: Artist(id: 'kalinka:$source:artist:$id', name: name),
  match: NameMatch(tier: tier, score: score),
);

BrowseItem _album(
  String source,
  String id,
  String title,
  MatchTier tier, {
  double score = 100,
  String? artistId,
  List<String> genres = const [],
}) => BrowseItem(
  id: 'kalinka:$source:album:$id',
  name: title,
  canBrowse: true,
  canAdd: true,
  album: Album(
    id: 'kalinka:$source:album:$id',
    title: title,
    artist: artistId == null
        ? null
        : Artist(id: 'kalinka:$source:artist:$artistId', name: 'x'),
    genres: _genreList(genres),
  ),
  match: NameMatch(tier: tier, score: score),
);

BrowseItem _track(
  String source,
  String id,
  String title, {
  List<String> genres = const [],
  MatchTier? tier,
  double score = 100,
}) => BrowseItem(
  id: 'kalinka:$source:track:$id',
  name: title,
  canBrowse: false,
  canAdd: true,
  track: Track(
    id: 'kalinka:$source:track:$id',
    title: title,
    duration: 100,
    album: Album(
      id: 'kalinka:$source:album:al-$id',
      title: '',
      genres: _genreList(genres),
    ),
  ),
  match: tier == null ? null : NameMatch(tier: tier, score: score),
);

List<Genre> _genreList(List<String> names) => [
  for (final name in names) Genre(id: name.toLowerCase(), name: name),
];

BrowseItemsList _list(List<BrowseItem> items) =>
    BrowseItemsList(0, items.length, items.length, items);

BrowseItemsList _card(String source, List<BrowseItem> tracks) => _list([
  BrowseItem(
    id: 'kalinka:$source:catalog:ai',
    name: 'AI SUGGESTIONS',
    canBrowse: false,
    canAdd: false,
    catalog: Catalog(id: 'ai', title: 'AI SUGGESTIONS', sources: [source]),
    sections: tracks,
  ),
]);

const _sources = <SourceOption>[
  (name: 'localfiles', title: 'Local Library'),
  (name: 'qobuz', title: 'Qobuz'),
];

List<String> _ids(List<BrowseItem> items) => [
  for (final item in items) item.id.split(':').last,
];

void main() {
  group('merging name matches', () {
    test('tier leads, then kind, score and the source order', () {
      final results = SearchResults.pending('the beatles', _sources)
          .withLeg(
            ResultsLeg.matches,
            'qobuz',
            LegReady(
              _list([
                _artist('qobuz', 'q-exact', 'The Beatles', MatchTier.exact),
                _album(
                  'qobuz',
                  'q-long',
                  'The Beatles 1962',
                  MatchTier.partial,
                  score: 60,
                ),
              ]),
            ),
          )
          .withLeg(
            ResultsLeg.matches,
            'localfiles',
            LegReady(
              _list([
                _artist(
                  'localfiles',
                  'l-exact',
                  'The Beatles',
                  MatchTier.exact,
                ),
                _album(
                  'localfiles',
                  'l-close',
                  'The Beatels',
                  MatchTier.close,
                  score: 80,
                ),
              ]),
            ),
          );

      expect(_ids(results.rankedMatches), [
        'l-exact',
        'q-exact',
        'l-close',
        'q-long',
      ]);
    });

    test('within a tier the kind runs together, score inside it', () {
      final results = SearchResults.pending('come together', _sources)
          .withLeg(
            ResultsLeg.matches,
            'localfiles',
            LegReady(
              _list([
                _track(
                  'localfiles',
                  'l-track',
                  'Come Together (Live)',
                  tier: MatchTier.partial,
                  score: 79,
                ),
                _album(
                  'localfiles',
                  'l-album',
                  'Come Together: The Very Best',
                  MatchTier.partial,
                  score: 42,
                ),
              ]),
            ),
          )
          .withLeg(
            ResultsLeg.matches,
            'qobuz',
            LegReady(
              _list([
                _album(
                  'qobuz',
                  'q-album',
                  'Come Together Now',
                  MatchTier.partial,
                  score: 70,
                ),
              ]),
            ),
          );

      expect(_ids(results.rankedMatches), ['q-album', 'l-album', 'l-track']);
    });

    test('a hit with no annotation merges last', () {
      final plain = BrowseItem(
        id: 'kalinka:qobuz:artist:plain',
        name: 'Plain',
        canBrowse: true,
        canAdd: false,
      );
      final results = SearchResults.pending('x', _sources)
          .withLeg(ResultsLeg.matches, 'qobuz', LegReady(_list([plain])))
          .withLeg(
            ResultsLeg.matches,
            'localfiles',
            LegReady(
              _list([_artist('localfiles', 'weak', 'Y', MatchTier.weak)]),
            ),
          );
      expect(_ids(results.rankedMatches), ['weak', 'plain']);
    });

    test('the list settles only once every source has answered or failed', () {
      var results = SearchResults.pending('x', _sources);
      expect(results.matchesSettled, isFalse);

      results = results.withLeg(
        ResultsLeg.matches,
        'qobuz',
        LegReady(_list([])),
      );
      expect(results.matchesSettled, isFalse);

      results = results.withLeg(
        ResultsLeg.matches,
        'localfiles',
        const LegFailed('down'),
      );
      expect(results.matchesSettled, isTrue);
      expect(results.unavailableMatchSources, ['localfiles']);
    });
  });

  group('recommendations', () {
    test('stay grouped by source in display order', () {
      final results = SearchResults.pending('x', _sources)
          .withLeg(
            ResultsLeg.inspired,
            'qobuz',
            LegReady(_card('qobuz', [_track('qobuz', 'q1', 'One')])),
          )
          .withLeg(ResultsLeg.inspired, 'localfiles', const LegFailed('down'));

      final groups = results.inspiredGroups;
      expect([for (final g in groups) g.source], ['localfiles', 'qobuz']);
      expect(groups.first.state, isA<LegFailed>());
      expect(_ids(groups.last.tracks), ['q1']);
    });
  });

  group('narrowing', () {
    final results = SearchResults.pending('the beatles', _sources)
        .withLeg(
          ResultsLeg.matches,
          'localfiles',
          LegReady(
            _list([
              _artist('localfiles', 'beatles', 'The Beatles', MatchTier.exact),
              _album(
                'localfiles',
                'abbey',
                'Abbey Road',
                MatchTier.contextual,
                score: 50,
                artistId: 'beatles',
                genres: ['Rock', 'Pop'],
              ),
            ]),
          ),
        )
        .withLeg(
          ResultsLeg.matches,
          'qobuz',
          LegReady(
            _list([
              _album(
                'qobuz',
                'jazz',
                'Beatles Jazz',
                MatchTier.partial,
                score: 70,
                genres: ['Jazz'],
              ),
            ]),
          ),
        )
        .withLeg(
          ResultsLeg.inspired,
          'qobuz',
          LegReady(
            _card('qobuz', [
              _track('qobuz', 't-rock', 'Come Together', genres: ['Rock']),
              _track('qobuz', 't-jazz', 'Something', genres: ['Jazz']),
            ]),
          ),
        )
        .withLeg(ResultsLeg.inspired, 'localfiles', LegReady(_list([])));

    test('offers the kinds, sources and genres the results hold', () {
      expect(results.typesPresent, [
        SearchType.artist,
        SearchType.album,
        SearchType.track,
      ]);
      expect(
        [for (final g in results.genresPresent) g.name],
        ['Jazz', 'Rock', 'Pop'],
      );
    });

    test('by kind', () {
      final matchesOnly = results.narrow(
        const BrowseFilterQuery(kind: ResultKind.nameMatches),
      );
      expect(matchesOnly.matches, hasLength(3));
      expect(matchesOnly.groups, isEmpty);

      final recommendationsOnly = results.narrow(
        const BrowseFilterQuery(kind: ResultKind.recommendations),
      );
      expect(recommendationsOnly.matches, isEmpty);
      expect(recommendationsOnly.recommendationCount, 2);
    });

    test('by type, on both blocks', () {
      final albums = results.narrow(
        const BrowseFilterQuery(type: SearchType.album),
      );
      expect(_ids(albums.matches), ['jazz', 'abbey']);
      expect(albums.recommendationCount, 0);
    });

    test('by source', () {
      final local = results.narrow(
        const BrowseFilterQuery(sources: ['localfiles']),
      );
      expect(_ids(local.matches), ['beatles', 'abbey']);
      expect([for (final g in local.groups) g.source], ['localfiles']);
    });

    test('by genre, with an artist inheriting its albums\' genres', () {
      final rock = results.narrow(const BrowseFilterQuery(genreIds: ['rock']));
      expect(_ids(rock.matches), ['beatles', 'abbey']);
      expect(_ids(rock.groups.last.tracks), ['t-rock']);
    });

    test('A–Z with recommendations alone has nothing to sort', () {
      final results = SearchResults.pending('jazz', _sources).withLeg(
        ResultsLeg.inspired,
        'qobuz',
        LegReady(_card('qobuz', [_track('qobuz', 't1', 'Take Five')])),
      );
      final narrowed = results.narrow(
        const BrowseFilterQuery(
          kind: ResultKind.recommendations,
          order: NameMatchOrder.alphabetical,
        ),
      );
      expect(narrowed.matches, isEmpty);
      expect(narrowed.recommendationCount, 1);
    });

    test('A–Z reorders the name matches and nothing else', () {
      final sorted = results.narrow(
        const BrowseFilterQuery(order: NameMatchOrder.alphabetical),
      );
      expect(_ids(sorted.matches), ['abbey', 'jazz', 'beatles']);
      expect(_ids(sorted.groups.last.tracks), ['t-rock', 't-jazz']);
    });
  });
}
