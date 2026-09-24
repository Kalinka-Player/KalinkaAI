import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/browse_filters.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/browse_rows_shimmer.dart';
import 'package:kalinka/widgets/search_cards/action_pill_button.dart';
import 'package:kalinka/widgets/search/results_view.dart';
import 'package:kalinka/widgets/search/inspired_block.dart';
import 'package:kalinka/widgets/search_cards/search_track_row.dart';
import 'package:kalinka/widgets/shelf_heading.dart';
import 'package:kalinka/widgets/source_badge.dart';

BrowseItem _artist(String source, String id, String name, MatchTier tier) =>
    BrowseItem(
      id: 'kalinka:$source:artist:$id',
      name: name,
      canBrowse: true,
      canAdd: false,
      artist: Artist(id: 'kalinka:$source:artist:$id', name: name),
      match: NameMatch(tier: tier, score: tier == MatchTier.exact ? 100 : 60),
    );

BrowseItem _track(String source, String id, String title, {MatchTier? tier}) =>
    BrowseItem(
      id: 'kalinka:$source:track:$id',
      canBrowse: false,
      canAdd: true,
      track: Track(
        id: 'kalinka:$source:track:$id',
        title: title,
        duration: 200,
        album: Album(id: 'kalinka:$source:album:al', title: 'An Album'),
        performer: Artist(id: 'kalinka:$source:artist:ar', name: 'Someone'),
      ),
      match: tier == null
          ? null
          : NameMatch(tier: tier, score: tier == MatchTier.exact ? 100 : 60),
    );

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

/// Answers each source's legs from a script; a source in [failing] throws
/// on its name-match leg until [heal] is called; [gates] hold a source's
/// name-match answer open until released.
class _ScriptedApi implements KalinkaPlayerProxy {
  final Map<String, List<BrowseItem>> matches;
  final Map<String, List<BrowseItem>> inspired;
  final Set<String> failing;
  final Map<String, Completer<void>> gates;
  final Map<String, int> matchCalls = {};

  _ScriptedApi({
    this.matches = const {},
    this.inspired = const {},
    Set<String> failing = const {},
    this.gates = const {},
  }) : failing = {...failing};

  void heal() => failing.clear();

  @override
  Future<BrowseItemsList> searchMatches(
    String query, {
    List<String>? sources,
  }) async {
    final source = sources!.single;
    matchCalls[source] = (matchCalls[source] ?? 0) + 1;
    if (failing.contains(source)) throw Exception('upstream down');
    await gates[source]?.future;
    return _list(matches[source] ?? const []);
  }

  @override
  Future<BrowseItemsList> aiSearch(
    String query, {
    int offset = 0,
    int limit = 10,
    List<String>? sources,
  }) async {
    final source = sources!.single;
    final tracks = inspired[source];
    return tracks == null ? _list(const []) : _card(source, tracks);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FixedConnection extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

// Both suggest: this file is about how their suggestions are laid out.
final _modules = <ModuleInfo>[
  ModuleInfo(
    name: 'qobuz',
    title: 'Qobuz',
    enabled: true,
    state: ModuleState.ready,
    capabilities: const [ModuleCapability.aiSearch],
  ),
  ModuleInfo(
    name: 'localfiles',
    title: 'Local Library',
    enabled: true,
    state: ModuleState.ready,
    capabilities: const [ModuleCapability.aiSearch],
  ),
];

late SharedPreferences _prefs;

/// The legs hold their answer on screen for a moment even when it is
/// instant, so a settled screen is one pump past that hold.
const _settle = Duration(milliseconds: 700);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _ScriptedApi api, {
  List<ModuleInfo>? modules,
}) async {
  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(_prefs),
      kalinkaProxyProvider.overrideWithValue(api),
      sourceModulesProvider.overrideWith((ref) => modules ?? _modules),
      connectionStateProvider.overrideWith(_FixedConnection.new),
      playerStateProvider.overrideWithValue(PlaybackState.empty),
    ],
  );
  addTearDown(container.dispose);
  container.read(searchSessionProvider.notifier).open();
  container.read(searchSessionProvider.notifier).submit('jazz');

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: ResultsView())),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'Kalinka.host': 'localhost',
      'Kalinka.port': 8080,
      'Kalinka.name': 'Test',
    });
    _prefs = await SharedPreferences.getInstance();
  });

  testWidgets('the name block shimmers until every source has answered', (
    tester,
  ) async {
    final gate = Completer<void>();
    final api = _ScriptedApi(
      matches: {
        'localfiles': [
          _artist('localfiles', '1', 'Local Act', MatchTier.exact),
        ],
        'qobuz': [_artist('qobuz', '1', 'Slow Act', MatchTier.exact)],
      },
      gates: {'qobuz': gate},
    );
    await _pump(tester, api);
    await tester.pump(_settle);

    // The local source answered, but the list is a merge: nothing shows
    // until the slow one has too.
    expect(find.text('MATCHES BY NAME'), findsOneWidget);
    expect(find.byType(BrowseRowsShimmer), findsWidgets);
    expect(find.text('Local Act'), findsNothing);

    gate.complete();
    await tester.pump(_settle);
    expect(find.byType(BrowseRowsShimmer), findsNothing);
    expect(find.text('Local Act'), findsOneWidget);
    expect(find.text('Slow Act'), findsOneWidget);
  });

  testWidgets('four lead, and VIEW ALL opens the rest as a filter', (
    tester,
  ) async {
    final api = _ScriptedApi(
      matches: {
        'qobuz': [
          for (var i = 1; i <= 6; i++)
            _artist('qobuz', '$i', 'Act $i', MatchTier.partial),
        ],
      },
    );
    await _pump(tester, api);
    await tester.pump(_settle);

    expect(find.text('Act 4'), findsOneWidget);
    expect(find.text('Act 5'), findsNothing);
    expect(find.text('VIEW ALL'), findsOneWidget);

    await tester.tap(find.text('VIEW ALL'));
    await tester.pump();

    expect(find.text('Name matches'), findsOneWidget);
    expect(find.text('Act 6'), findsOneWidget);
    expect(find.text('VIEW ALL'), findsNothing);
  });

  testWidgets('an exact hit wears its badge, a partial one does not', (
    tester,
  ) async {
    final api = _ScriptedApi(
      matches: {
        'qobuz': [
          _artist('qobuz', '1', 'Jazz', MatchTier.exact),
          _artist('qobuz', '2', 'Jazz Club', MatchTier.partial),
        ],
      },
    );
    await _pump(tester, api);
    await tester.pump(_settle);

    expect(find.text('EXACT NAME'), findsOneWidget);
  });

  testWidgets('a source that failed is named, and retried in place', (
    tester,
  ) async {
    final api = _ScriptedApi(
      matches: {
        'localfiles': [
          _artist('localfiles', '1', 'Local Act', MatchTier.exact),
        ],
        'qobuz': [_artist('qobuz', '1', 'Remote Act', MatchTier.exact)],
      },
      failing: {'qobuz'},
    );
    await _pump(tester, api);
    await tester.pump(_settle);

    expect(find.text('Local Act'), findsOneWidget);
    expect(find.text('Qobuz · Source unavailable'), findsOneWidget);
    expect(find.text('Remote Act'), findsNothing);

    api.heal();
    await tester.tap(find.text('RETRY'));
    await tester.pump(_settle);

    expect(api.matchCalls['qobuz'], 2);
    expect(api.matchCalls['localfiles'], 1);
    expect(find.text('Qobuz · Source unavailable'), findsNothing);
    expect(find.text('Remote Act'), findsOneWidget);
  });

  testWidgets('recommendations stay grouped by source, with their actions', (
    tester,
  ) async {
    final api = _ScriptedApi(
      inspired: {
        'localfiles': [_track('localfiles', 'l1', 'Home Song')],
        'qobuz': [
          for (var i = 1; i <= 5; i++) _track('qobuz', '$i', 'Away Song $i'),
        ],
      },
    );
    await _pump(tester, api);
    await tester.pump(_settle);

    expect(find.text('Inspired by your request'), findsOneWidget);
    expect(find.text('LOCAL LIBRARY'), findsOneWidget);
    expect(find.text('QOBUZ'), findsOneWidget);
    // Every source is named and lettered, the listener's own included.
    expect(find.byType(SourceTile), findsNWidgets(2));
    expect(find.text('Play all'), findsNWidgets(2));
    // Each source's heading counts what it suggested, as MATCHES BY NAME does.
    expect(find.text('· 5'), findsOneWidget);
    expect(find.text('· 1'), findsOneWidget);
    expect(find.text('Away Song 3'), findsOneWidget);
    expect(find.text('Away Song 4'), findsNothing);
    // Only the group holding more than its preview offers to open in full,
    // and it sits on the block's right edge, like the block's own link.
    expect(find.text('VIEW ALL'), findsOneWidget);
    expect(
      tester.getTopRight(find.byType(ViewAllAction)).dx,
      closeTo(tester.getTopRight(find.byType(InspiredBlock)).dx, 0.5),
    );
    // The Discover mark on the heading; the query chip wears the same glyph
    // outside the block.
    expect(
      find.descendant(
        of: find.byType(InspiredBlock),
        matching: find.byIcon(Icons.auto_awesome),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('VIEW ALL'));
    await tester.pump();

    // One source in full: its kind and its source, each a chip of its own.
    expect(find.text('Recommendations'), findsOneWidget);
    expect(find.text('Qobuz'), findsOneWidget);
    expect(find.text('Away Song 5'), findsOneWidget);
    expect(find.text('· 5'), findsOneWidget);
    expect(find.text('LOCAL LIBRARY'), findsNothing);
    expect(find.text('MATCHES BY NAME'), findsNothing);
  });

  testWidgets('with one source, VIEW ALL narrows by kind alone', (
    tester,
  ) async {
    final api = _ScriptedApi(
      inspired: {
        'qobuz': [
          for (var i = 1; i <= 5; i++) _track('qobuz', '$i', 'Away Song $i'),
        ],
      },
    );
    await _pump(tester, api, modules: [_modules.first]);
    await tester.pump(_settle);

    await tester.tap(find.text('VIEW ALL'));
    await tester.pump();

    expect(find.text('Recommendations'), findsOneWidget);
    expect(find.text('Qobuz'), findsNothing);
    expect(find.text('Away Song 5'), findsOneWidget);
  });

  testWidgets('the inspired heading is a name and a line, nothing drawn', (
    tester,
  ) async {
    final api = _ScriptedApi(
      inspired: {
        'localfiles': [
          for (var i = 1; i <= 5; i++) _track('localfiles', '$i', 'Song $i'),
        ],
      },
    );
    await _pump(tester, api);
    await tester.pump(_settle);

    expect(find.text('Inspired by your request'), findsOneWidget);
    expect(find.text('SMART RECOMMENDATIONS'), findsOneWidget);
    // Its own heading, not the labelled shelf the name matches take.
    final headings = tester.widgetList<ShelfHeading>(find.byType(ShelfHeading));
    expect(
      headings.map((h) => h.title),
      isNot(contains(startsWith('Inspired'))),
    );
    // Nothing is ruled through the heading; the only hairlines are between
    // its rows (three shown of five, so two). The tally is the source's, not
    // the block's.
    expect(
      find.descendant(
        of: find.byType(InspiredBlock),
        matching: find.byType(Divider),
      ),
      findsNWidgets(2),
    );
    expect(find.text('· 5'), findsOneWidget);
    expect(
      find.descendant(
        of: find
            .ancestor(of: find.text('· 5'), matching: find.byType(Row))
            .first,
        matching: find.text('LOCAL LIBRARY'),
      ),
      findsOneWidget,
    );
  });

  /// The name leads in the display face over a quiet eyebrow, on a wash that
  /// is grey: a berry one beside the berry now-playing row read as one signal.
  testWidgets('the inspired heading leads with its name on a neutral wash', (
    tester,
  ) async {
    final api = _ScriptedApi(
      inspired: {
        'localfiles': [
          for (var i = 1; i <= 5; i++) _track('localfiles', '$i', 'Song $i'),
        ],
      },
    );
    await _pump(tester, api);
    await tester.pump(_settle);

    final title = tester.widget<Text>(find.text('Inspired by your request'));
    final eyebrow = tester.widget<Text>(find.text('SMART RECOMMENDATIONS'));
    final shelf = tester.widget<Text>(find.text('LOCAL LIBRARY'));
    expect(title.style!.fontFamily, KalinkaFonts.displayFamily);
    expect(title.style!.fontSize!, greaterThan(2 * eyebrow.style!.fontSize!));
    // Quieter than the shelf labels under it.
    expect(eyebrow.style!.fontSize!, lessThan(shelf.style!.fontSize!));
    expect(
      eyebrow.style!.fontWeight!.value,
      lessThan(shelf.style!.fontWeight!.value),
    );
    expect(eyebrow.style!.color, KalinkaColors.textSecondary);

    // One wash, and no colour in it leans red.
    final washes = find.descendant(
      of: find.byType(InspiredBlock),
      matching: find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).gradient != null,
      ),
    );
    expect(washes, findsOneWidget);
    final gradient =
        (tester.widget<DecoratedBox>(washes).decoration as BoxDecoration)
            .gradient!;
    for (final c in gradient.colors) {
      expect(c.r - c.g, lessThan(0.05));
    }
    // Edge to edge, and gone before the first group's name.
    final wash = tester.getRect(washes);
    final block = tester.getRect(find.byType(InspiredBlock));
    expect(wash.left, lessThan(block.left));
    expect(wash.right, greaterThan(block.right));
    expect(wash.top, closeTo(block.top, 0.5));
    expect(
      wash.bottom,
      lessThanOrEqualTo(tester.getTopLeft(find.text('LOCAL LIBRARY')).dy),
    );
  });

  /// Under a heading that names the source, in a group that is all tracks,
  /// "Track" and the source badge would only repeat it. The mixed name
  /// matches keep both.
  testWidgets('a source\'s rows say the artist and album, not the kind again', (
    tester,
  ) async {
    final api = _ScriptedApi(
      matches: {
        'qobuz': [_track('qobuz', 'm', 'Named Song', tier: MatchTier.exact)],
      },
      inspired: {
        'qobuz': [
          for (var i = 1; i <= 5; i++) _track('qobuz', '$i', 'Away Song $i'),
        ],
      },
    );
    await _pump(tester, api);
    await tester.pump(_settle);

    final inspired = find.byType(InspiredBlock);
    expect(
      find.descendant(of: inspired, matching: find.text('Someone · An Album')),
      findsNWidgets(3),
    );
    expect(
      find.descendant(of: inspired, matching: find.textContaining('Track ·')),
      findsNothing,
    );
    expect(
      find.descendant(of: inspired, matching: find.byType(SourceBadge)),
      findsNothing,
    );
    expect(find.textContaining('Track · Someone · An Album'), findsOneWidget);
  });

  /// A later source stands further off the rows above it than rows stand off
  /// each other; the first hangs closer, off the block's heading.
  testWidgets('a later source stands further off than the rows do', (
    tester,
  ) async {
    final api = _ScriptedApi(
      inspired: {
        'localfiles': [
          _track('localfiles', '1', 'Home Song 1'),
          _track('localfiles', '2', 'Home Song 2'),
        ],
        'qobuz': [_track('qobuz', '1', 'Away Song 1')],
      },
    );
    await _pump(tester, api);
    await tester.pump(_settle);

    // The heading row, found from its letter tile (the title is in a nested
    // row).
    Finder heading(String source) => find
        .ancestor(
          of: find.byWidgetPredicate(
            (w) => w is SourceTile && w.source == source,
          ),
          matching: find.byType(Row),
        )
        .first;
    Finder row(String title) => find.ancestor(
      of: find.text(title),
      matching: find.byType(SearchTrackRow),
    );

    final title = tester.getRect(find.text('Inspired by your request'));
    final rowGap =
        tester.getRect(row('Home Song 2')).top -
        tester.getRect(row('Home Song 1')).bottom;
    final afterTitle = tester.getRect(heading('localfiles')).top - title.bottom;
    final betweenSources =
        tester.getRect(heading('qobuz')).top -
        tester.getRect(row('Home Song 2')).bottom;

    expect(betweenSources, greaterThanOrEqualTo(2 * rowGap));
    expect(betweenSources, greaterThan(afterTitle));
  });

  /// The block's own control: which of the sources that answered is being
  /// read. It stands where the subtitle used to, and it is drawn from the
  /// rows rather than from the module list.
  group('the source pills', () {
    /// The pill carrying [label], wherever it sits — the block draws other
    /// action pills too, so an index would be aiming blind.
    Finder pill(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byType(ActionPillButton),
    );

    testWidgets('name only the sources the list actually holds', (
      tester,
    ) async {
      final api = _ScriptedApi(
        matches: {
          'qobuz': [_artist('qobuz', '1', 'Q Act', MatchTier.exact)],
          'localfiles': [_artist('localfiles', '1', 'L Act', MatchTier.exact)],
        },
      );
      await _pump(tester, api);
      await tester.pump(_settle);

      expect(pill('All'), findsOneWidget);
      expect(pill('Qobuz'), findsOneWidget);
      expect(pill('Local Library'), findsOneWidget);
    });

    testWidgets('stay away when only one source found anything', (
      tester,
    ) async {
      final api = _ScriptedApi(
        matches: {
          'qobuz': [_artist('qobuz', '1', 'Q Act', MatchTier.exact)],
        },
      );
      await _pump(tester, api);
      await tester.pump(_settle);

      // Both sources answered; only one had something to say, so there is
      // nothing to choose between.
      expect(find.byType(ActionPillButton), findsNothing);
      expect(find.text('Q Act'), findsOneWidget);
    });

    /// The layout as the block builds it. A pill that sizes itself from
    /// anything but its content once came out as a column of full-width
    /// slabs, so this is measured rather than assumed.
    testWidgets('sit on one line, each as wide as what it holds', (
      tester,
    ) async {
      final api = _ScriptedApi(
        matches: {
          'qobuz': [_artist('qobuz', '1', 'Q Act', MatchTier.exact)],
          'localfiles': [_artist('localfiles', '1', 'L Act', MatchTier.exact)],
        },
      );
      await _pump(tester, api);
      await tester.pump(_settle);

      final rects = [
        for (final label in ['All', 'Qobuz', 'Local Library'])
          tester.getRect(pill(label)),
      ];

      expect(rects.map((r) => r.top).toSet(), hasLength(1));
      expect(rects.map((r) => r.height).toSet(), hasLength(1));
      // A name behind a letter tile is wider than the bare word All, and
      // none of them has taken the line.
      expect(rects[1].width, greaterThan(rects[0].width));
      final line = tester.getSize(find.byType(ResultsView)).width;
      for (final rect in rects) {
        expect(rect.width, lessThan(line / 2));
      }
    });

    /// The palette gives a screen at rest one crimson fill, and this row is
    /// chrome that stays up for the session — so the one being read is lit
    /// the way Play all is, a wash inside an edge, not a fill.
    testWidgets('light the one being read like a Play all, not a fill', (
      tester,
    ) async {
      final api = _ScriptedApi(
        matches: {
          'qobuz': [_artist('qobuz', '1', 'Q Act', MatchTier.exact)],
          'localfiles': [_artist('localfiles', '1', 'L Act', MatchTier.exact)],
        },
      );
      await _pump(tester, api);
      await tester.pump(_settle);

      Color lit(String label) => tester
          .widget<Material>(
            find
                .descendant(of: pill(label), matching: find.byType(Material))
                .first,
          )
          .color!;

      // All is on to start with.
      expect(lit('All'), KalinkaColors.accentSubtle);
      expect(lit('Qobuz'), KalinkaColors.surfaceElevated);

      await tester.tap(pill('Qobuz'));
      await tester.pump();

      expect(lit('All'), KalinkaColors.surfaceElevated);
      expect(lit('Qobuz'), KalinkaColors.accentSubtle);
    });

    testWidgets('picking one reads that source alone, ALL brings them back', (
      tester,
    ) async {
      final api = _ScriptedApi(
        matches: {
          'qobuz': [_artist('qobuz', '1', 'Q Act', MatchTier.exact)],
          'localfiles': [_artist('localfiles', '1', 'L Act', MatchTier.exact)],
        },
      );
      await _pump(tester, api);
      await tester.pump(_settle);
      expect(find.text('L Act'), findsOneWidget);

      await tester.tap(pill('Qobuz'));
      await tester.pump();

      expect(find.text('Q Act'), findsOneWidget);
      expect(find.text('L Act'), findsNothing);
      // The others stay offered — a pick that hid them could not be undone.
      expect(pill('Local Library'), findsOneWidget);
      expect(find.textContaining('· 1'), findsOneWidget);

      await tester.tap(pill('All'));
      await tester.pump();

      expect(find.text('L Act'), findsOneWidget);
      expect(find.text('Q Act'), findsOneWidget);
    });

    testWidgets('offer nothing the screen filter has already excluded', (
      tester,
    ) async {
      final api = _ScriptedApi(
        matches: {
          'qobuz': [_artist('qobuz', '1', 'Q Act', MatchTier.exact)],
          'localfiles': [_artist('localfiles', '1', 'L Act', MatchTier.exact)],
          'jamendo': [_artist('jamendo', '1', 'J Act', MatchTier.exact)],
        },
      );
      final container = await _pump(
        tester,
        api,
        modules: [
          ..._modules,
          ModuleInfo(
            name: 'jamendo',
            title: 'Jamendo',
            enabled: true,
            state: ModuleState.ready,
            capabilities: const [ModuleCapability.aiSearch],
          ),
        ],
      );
      await tester.pump(_settle);
      expect(pill('Jamendo'), findsOneWidget);

      container
          .read(searchSessionProvider.notifier)
          .setResultsFilter(
            const BrowseFilterQuery(sources: ['qobuz', 'localfiles']),
          );
      await tester.pump();

      expect(pill('Qobuz'), findsOneWidget);
      expect(pill('Local Library'), findsOneWidget);
      expect(pill('Jamendo'), findsNothing);
    });

    testWidgets('a pick the screen filter rules out is dropped', (
      tester,
    ) async {
      final api = _ScriptedApi(
        matches: {
          'qobuz': [_artist('qobuz', '1', 'Q Act', MatchTier.exact)],
          'localfiles': [_artist('localfiles', '1', 'L Act', MatchTier.exact)],
        },
      );
      final container = await _pump(tester, api);
      await tester.pump(_settle);

      await tester.tap(pill('Qobuz'));
      await tester.pump();
      expect(container.read(searchSessionProvider).matchSource, 'qobuz');

      container
          .read(searchSessionProvider.notifier)
          .setResultsFilter(const BrowseFilterQuery(sources: ['localfiles']));
      await tester.pump();

      expect(container.read(searchSessionProvider).matchSource, isNull);
      expect(find.text('L Act'), findsOneWidget);
    });

    testWidgets('a new search starts on ALL again', (tester) async {
      final api = _ScriptedApi(
        matches: {
          'qobuz': [_artist('qobuz', '1', 'Q Act', MatchTier.exact)],
          'localfiles': [_artist('localfiles', '1', 'L Act', MatchTier.exact)],
        },
      );
      final container = await _pump(tester, api);
      await tester.pump(_settle);

      await tester.tap(pill('Qobuz'));
      await tester.pump();
      expect(container.read(searchSessionProvider).matchSource, 'qobuz');

      container.read(searchSessionProvider.notifier).submit('blues');
      await tester.pump(_settle);

      expect(container.read(searchSessionProvider).matchSource, isNull);
    });
  });

  testWidgets('nothing found says so', (tester) async {
    await _pump(tester, _ScriptedApi());
    await tester.pump(_settle);

    expect(find.text('No matches'), findsOneWidget);
  });
}
