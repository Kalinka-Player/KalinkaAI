import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/browse_filters.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/catalog_sources_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/listing_presentation_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/browse_rows_shimmer.dart';
import 'package:kalinka/widgets/search/results_view.dart';
import 'package:kalinka/widgets/search/inspired_block.dart';
import 'package:kalinka/widgets/search_cards/search_track_row.dart';
import 'package:kalinka/widgets/search_cards/search_album_row.dart';
import 'package:kalinka/widgets/search_cards/search_artist_row.dart';
import 'package:kalinka/widgets/search_cards/search_playlist_row.dart';
import 'package:kalinka/widgets/search_cards/artwork_grid.dart';
import 'package:kalinka/widgets/search_cards/artwork_grid_card.dart';
import 'package:kalinka/widgets/browse_filters/presentation_toggle.dart';
import 'package:kalinka/widgets/shelf_heading.dart';
import 'package:kalinka/widgets/source_badge.dart';
import 'package:kalinka/widgets/module_artwork.dart';
import 'package:kalinka/widgets/kalinka_popover.dart';
import 'package:kalinka/widgets/section_tab_button.dart';

import 'support/server_answer.dart';
import 'support/receivers.dart';

import 'package:kalinka/providers/indexer_status_provider.dart';
import 'package:kalinka/widgets/search/search_session_view.dart';
import 'package:kalinka/widgets/search/inspired_tracks_view.dart';
import 'package:kalinka/widgets/search/results_tabs.dart';
import 'package:kalinka/widgets/search/track_group_actions.dart';
import 'package:kalinka/widgets/search/catalog_sliver_header.dart';
import 'package:kalinka/widgets/search_cards/track_row_support.dart';
import 'package:kalinka/widgets/browse_filters/search_filter_overlay.dart';
import 'package:kalinka/widgets/browse_filters/active_filter_chips.dart';

BrowseItem _artist(String source, String id, String name, MatchTier tier) =>
    BrowseItem(
      id: 'kalinka:$source:artist:$id',
      name: name,
      canBrowse: true,
      canAdd: false,
      artist: Artist(id: 'kalinka:$source:artist:$id', name: name),
      match: NameMatch(tier: tier, score: tier == MatchTier.exact ? 100 : 60),
    );

BrowseItem _track(
  String source,
  String id,
  String title, {
  MatchTier? tier,
  String? mimeType,
  String genre = 'Jazz',
  String? performer = 'Someone',
  String? albumArtist,
  String? cover,
}) => BrowseItem(
  id: 'kalinka:$source:track:$id',
  canBrowse: false,
  canAdd: true,
  track: Track(
    id: 'kalinka:$source:track:$id',
    title: title,
    duration: 200,
    image: cover == null ? null : AlbumImage(small: cover),
    album: Album(
      id: 'kalinka:$source:album:al',
      title: 'An Album',
      artist: albumArtist == null
          ? null
          : Artist(id: 'album-artist', name: albumArtist),
      genres: [Genre(id: genre.toLowerCase(), name: genre)],
    ),
    performer: performer == null
        ? null
        : Artist(id: 'kalinka:$source:artist:ar', name: performer),
    mimeType: mimeType,
  ),
  match: tier == null
      ? null
      : NameMatch(tier: tier, score: tier == MatchTier.exact ? 100 : 60),
);

BrowseItemsList _list(List<BrowseItem> items) =>
    BrowseItemsList(0, items.length, items.length, items);

BrowseItem _album(String source, String id, MatchTier tier) => BrowseItem(
  id: 'kalinka:$source:album:$id',
  canBrowse: true,
  canAdd: true,
  album: Album(id: id, title: 'Album $id', year: 2020),
  match: NameMatch(tier: tier, score: tier == MatchTier.exact ? 100 : 60),
);

BrowseItem _playlist(String source, String id) => BrowseItem(
  id: 'kalinka:$source:playlist:$id',
  canBrowse: true,
  canAdd: true,
  playlist: Playlist(id: id, name: 'Playlist $id', trackCount: 12),
  match: NameMatch(tier: MatchTier.partial, score: 60),
);

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
  final List<BrowseItem> roots;
  final Map<String, List<BrowseItem>> matches;
  final Map<String, List<BrowseItem>> inspired;
  final Set<String> failing;
  final Map<String, Completer<void>> gates;
  final Map<String, Completer<void>> inspiredGates;
  final Map<String, int> matchCalls = {};
  final Map<String, int> aiLimits = {};
  final Map<String, int> aiCalls = {};
  final List<List<String>> replacements = [];
  final List<List<String>> additions = [];
  final List<int> plays = [];

  @override
  Future<StatusMessage> replace(List<String> items) async {
    replacements.add([...items]);
    return StatusMessage(count: items.length);
  }

  @override
  Future<StatusMessage> add(List<String> items, {int? index}) async {
    additions.add([...items]);
    return StatusMessage(count: items.length);
  }

  @override
  Future<StatusMessage> play([int? index]) async {
    plays.add(index ?? 0);
    return StatusMessage();
  }

  @override
  Future<SearchSuggestionList> searchSuggestions({
    int count = 4,
    int? tzOffsetMin,
  }) async => SearchSuggestionList(suggestions: const []);
  @override
  Future<BrowseItemsList> getFavorite(
    SearchType queryType, {
    int offset = 0,
    int limit = 10,
    String filter = '',
  }) async => _list([]);

  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async => _list(roots);

  _ScriptedApi({
    this.roots = const [],
    this.matches = const {},
    this.inspired = const {},
    Set<String> failing = const {},
    this.gates = const {},
    this.inspiredGates = const {},
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
    aiLimits[source] = limit;
    aiCalls[source] = (aiCalls[source] ?? 0) + 1;
    await inspiredGates[source]?.future;
    final tracks = inspired[source];
    return tracks == null ? _list(const []) : _card(source, tracks);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _IdleIndexer extends IndexerStatusNotifier {
  @override
  IndexerStatusState build() => const IndexerStatusState();
  @override
  void acquire() {}
  @override
  void release() {}
}

class _FixedConnection extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

// Both suggest: this file is about how their suggestions are laid out.
final _modules = <ModuleInfo>[
  ModuleInfo(
    name: 'jamendo',
    title: 'Jamendo',
    enabled: true,
    state: ModuleState.ready,
    capabilities: const [ModuleCapability.catalogs, ModuleCapability.aiSearch],
  ),
  ModuleInfo(
    name: 'localfiles',
    title: 'My Library',
    enabled: true,
    state: ModuleState.ready,
    capabilities: const [ModuleCapability.catalogs, ModuleCapability.aiSearch],
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
  Duration? modulesAfter,
  bool shell = false,
  double scale = 1,
  GlobalKey? captureKey,
  bool preloadSources = false,
}) async {
  final container = ProviderContainer(
    overrides: [
      noReceivers,
      indexerStatusProvider.overrideWith(_IdleIndexer.new),
      sharedPrefsProvider.overrideWithValue(_prefs),
      kalinkaProxyProvider.overrideWithValue(api),
      if (modulesAfter == null)
        sourceModulesProvider.overrideWith((ref) => modules ?? _modules)
      else
        sourceModulesProvider.overrideWith(
          (ref) => Future.delayed(modulesAfter, () => modules ?? _modules),
        ),
      connectionStateProvider.overrideWith(_FixedConnection.new),
      serverAnswering('box-1'),
      playerStateProvider.overrideWithValue(PlaybackState.empty),
    ],
  );
  addTearDown(container.dispose);
  container.read(searchSessionProvider.notifier).refresh();
  if (preloadSources) await container.read(catalogSourcesProvider.future);
  container.read(searchSessionProvider.notifier).submit('jazz');

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, child) => RepaintBoundary(
          key: captureKey,
          child: MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
        home: RepaintBoundary(
          child: Scaffold(
            body: shell ? const SearchSessionView() : const ResultsView(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return container;
}

void _size(WidgetTester tester, double width, [double height = 900]) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final dir = Platform.environment['KALINKA_REVIEW_DIR'];
  if (dir == null) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$dir/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    final material = File(
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (material.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(ByteData.sublistView(material.readAsBytesSync())),
          ))
          .load();
    }

    for (final (family, file) in [
      (KalinkaFonts.sansFamily, 'IBMPlexSans-Regular.ttf'),
      (KalinkaFonts.monoFamily, 'IBMPlexMono-Regular.ttf'),
      (KalinkaFonts.displayFamily, 'PlayfairDisplay-Regular.ttf'),
    ]) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$file'))).load();
    }
  });
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
        'jamendo': [_artist('jamendo', '1', 'Slow Act', MatchTier.exact)],
      },
      gates: {'jamendo': gate},
    );
    await _pump(tester, api);
    await tester.pump(_settle);

    // The local source answered, but the list is a merge: nothing shows
    // until the slow one has too.
    expect(find.text('NAME MATCHES'), findsOneWidget);
    expect(find.byType(BrowseRowsShimmer), findsWidgets);
    expect(find.text('Local Act'), findsNothing);

    gate.complete();
    await tester.pump(_settle);
    expect(find.byType(BrowseRowsShimmer), findsNothing);
    expect(find.text('Local Act'), findsOneWidget);
    expect(find.text('Slow Act'), findsOneWidget);
  });

  testWidgets('an exact hit wears its badge, a partial one does not', (
    tester,
  ) async {
    final api = _ScriptedApi(
      matches: {
        'jamendo': [
          _artist('jamendo', '1', 'Jazz', MatchTier.exact),
          _artist('jamendo', '2', 'Jazz Club', MatchTier.partial),
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
        'jamendo': [_artist('jamendo', '1', 'Remote Act', MatchTier.exact)],
      },
      failing: {'jamendo'},
    );
    await _pump(tester, api);
    await tester.pump(_settle);

    expect(find.text('Local Act'), findsOneWidget);
    expect(find.text('Jamendo · Source unavailable'), findsOneWidget);
    expect(find.text('Remote Act'), findsNothing);

    api.heal();
    await tester.tap(find.text('RETRY'));
    await tester.pump(_settle);

    expect(api.matchCalls['jamendo'], 2);
    expect(api.matchCalls['localfiles'], 1);
    expect(find.text('Jamendo · Source unavailable'), findsNothing);
    expect(find.text('Remote Act'), findsOneWidget);
  });

  testWidgets(
    'wide overview gives name matches 55 percent and inspired results 45 percent',
    (tester) async {
      _size(tester, 1280);
      final key = GlobalKey();
      await _pump(
        tester,
        _ScriptedApi(
          matches: {
            'localfiles': [
              _artist('localfiles', 'a', 'Midnight Trio', MatchTier.partial),
            ],
            'jamendo': [
              _artist('jamendo', 'b', 'Midnight Jazz', MatchTier.exact),
            ],
          },
          inspired: {
            'localfiles': [_track('localfiles', '1', 'Blue Hour')],
            'jamendo': [_track('jamendo', '1', 'Streetlights')],
          },
        ),
        shell: true,
        captureKey: key,
      );
      await tester.pumpAndSettle();
      final names = tester.getRect(find.byType(ShelfHeading));
      final inspired = tester.getRect(find.byType(InspiredHeading));
      expect(names.left, lessThan(inspired.left));
      expect(names.width / (names.width + inspired.width), closeTo(.55, .02));
      expect(
        tester.getTopLeft(find.text('Midnight Jazz')).dy,
        lessThan(tester.getTopLeft(find.text('Midnight Trio')).dy),
      );
      expect(find.text('Jamendo'), findsOneWidget);
      expect(find.text('Jamendo ·'), findsNothing);
      expect(find.byType(SourceBadge), findsNWidgets(2));
      expect(find.text('Artist'), findsWidgets);
      expect(find.text('NAME MATCHES'), findsOneWidget);
      expect(
        find.textContaining('Inspired by your request', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('ALL'), findsOneWidget);
      final tabStyle = DefaultTextStyle.of(tester.element(find.text('ALL')))
          .style;
      expect(
        tabStyle,
        KalinkaTextStyles.sectionLabel.copyWith(
          color: KalinkaColors.textPrimary,
        ),
      );
      expect(find.byType(SectionTabButton), findsNWidgets(5));
      final labelLeft = tester.getTopLeft(find.text('ALL')).dx;
      expect(labelLeft, tester.getRect(find.byType(ShelfHeading)).left);
      expect(
        tester.getRect(find.byType(SectionTabButton).first).left,
        labelLeft - SectionTabButton.horizontalPadding,
      );
      final search = tester.getRect(
        find.byKey(const ValueKey('results-search-entry')),
      );
      final filters = tester.getRect(find.byType(CatalogFiltersButton));
      expect(filters.center.dy, closeTo(search.center.dy, 1));
      expect(filters.left, greaterThanOrEqualTo(search.right));
      final searchSurface = tester.getRect(
        find.byKey(const ValueKey('search-entry-surface')),
      );
      final filterPill = tester.getRect(
        find.descendant(
          of: find.byType(CatalogFiltersButton),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(searchSurface.height, kKalinkaPillHeight);
      expect(searchSurface.height, filterPill.height);
      expect(searchSurface.center.dy, filterPill.center.dy);
      expect(search.height, greaterThanOrEqualTo(kKalinkaPillTarget));
      expect(find.text('Genre'), findsNothing);
      expect(find.text('Source'), findsNothing);

      final cardCovers = find.descendant(
        of: find.byType(InspiredSourceCard).first,
        matching: find.byType(TrackThumb),
      );
      expect(
        tester.getTopLeft(cardCovers.at(0)).dy,
        tester.getTopLeft(cardCovers.at(1)).dy,
      );
      expect(
        tester.getTopLeft(cardCovers.at(2)).dx,
        tester.getTopLeft(cardCovers.at(0)).dx,
      );
      expect(
        tester.getTopLeft(cardCovers.at(2)).dy,
        greaterThan(tester.getTopLeft(cardCovers.at(0)).dy),
      );
      await _capture(tester, key, 'search-tablet');
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: const Offset(0, 0));
      await mouse.moveTo(tester.getCenter(find.text('ARTISTS')));
      await tester.pumpAndSettle();
      await _capture(tester, key, 'search-tabs-hover');
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('phone previews names then shows source cards in one scroll', (
    tester,
  ) async {
    _size(tester, 375, 950);
    final key = GlobalKey();
    final container = await _pump(
      tester,
      _ScriptedApi(
        matches: {
          'jamendo': [
            for (var i = 0; i < 6; i++)
              _artist('jamendo', '$i', 'Act $i', MatchTier.partial),
          ],
        },
        inspired: {
          'localfiles': [_track('localfiles', '1', 'Hidden track name')],
          'jamendo': [_track('jamendo', '2', 'Another hidden name')],
        },
      ),
      shell: true,
      captureKey: key,
    );
    await tester.pumpAndSettle();
    expect(find.text('Act 3'), findsOneWidget);
    expect(find.text('Act 4'), findsNothing);
    expect(find.text('View All'), findsOneWidget);
    expect(find.byType(InspiredSourceCard), findsNWidgets(2));
    expect(find.text('Hidden track name'), findsNothing);
    expect(find.text('Play all'), findsNothing);
    expect(find.byType(CustomScrollView), findsOneWidget);
    await _capture(tester, key, 'search-phone');
    await tester.tap(find.text('View All'));
    await tester.pumpAndSettle();
    expect(find.byType(InspiredSourceCard), findsNothing);
    expect(find.text('Act 5'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(container.read(searchSessionProvider).expandedBlock, isNull);
    expect(find.text('View All'), findsOneWidget);
  });

  testWidgets(
    'cards request twenty tracks and show actual counts and fallback art',
    (tester) async {
      final api = _ScriptedApi(
        inspired: {
          'localfiles': [_track('localfiles', '1', 'Song')],
          'jamendo': [
            for (var i = 0; i < 7; i++) _track('jamendo', '$i', 'Song $i'),
          ],
        },
      );
      await _pump(tester, api);
      await tester.pumpAndSettle();
      expect(api.aiLimits, {'localfiles': 20, 'jamendo': 20});
      expect(find.text('1 track'), findsOneWidget);
      expect(find.text('7 tracks'), findsOneWidget);
      expect(find.byType(ArtStandIn), findsNWidgets(8));
      expect(find.byType(SearchTrackRow), findsNothing);
      await tester.ensureVisible(find.text('Jamendo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Jamendo'));
      await tester.pumpAndSettle();
      expect(api.replacements, isEmpty);
      expect(api.additions, isEmpty);
      expect(api.plays, isEmpty);
      expect(find.text('JAMENDO'), findsOneWidget);
      expect(find.text('MY LIBRARY'), findsOneWidget);
      expect(find.text('TRACKS'), findsOneWidget);
      expect(find.text('· 7'), findsOneWidget);
    },
  );

  testWidgets(
    'source tabs keep backend order and actions use only the selected list',
    (tester) async {
      _size(tester, 1100);
      final jamendo = [
        _track('jamendo', 'z', 'Zulu'),
        _track('jamendo', 'a', 'Alpha'),
      ];
      final local = [_track('localfiles', 'b', 'Blue')];
      final api = _ScriptedApi(
        inspired: {'localfiles': local, 'jamendo': jamendo},
      );
      final container = await _pump(tester, api);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Jamendo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Jamendo'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<SourceTile>(find.byType(SourceTile))
            .map((w) => w.source),
        ['localfiles', 'jamendo'],
      );
      expect(
        tester
            .widgetList<ModuleArtwork>(
              find.descendant(
                of: find.byType(ResultsTabs),
                matching: find.byType(ModuleArtwork),
              ),
            )
            .every((w) => w.small),
        isTrue,
      );
      final firstTab = tester.getRect(find.byType(SectionTabButton).first);
      final badge = tester.getRect(find.byType(SourceTile).first);
      expect(find.text('· 2'), findsOneWidget);
      expect(badge.left, tester.getRect(find.byType(ShelfHeading)).left);
      expect(badge.left, tester.getRect(find.byType(TrackGroupActions)).left);
      expect(
        badge.left,
        tester.getRect(find.byType(SearchTrackRow).first).left,
      );
      expect(firstTab.left, badge.left - SectionTabButton.horizontalPadding);
      final visit = container.read(searchSessionProvider).visitId;
      final history = container
          .read(searchSessionProvider)
          .previousVisits
          .length;
      expect(
        tester.getTopLeft(find.text('Zulu')).dy,
        lessThan(tester.getTopLeft(find.text('Alpha')).dy),
      );
      await tester.tap(find.text('Play all'));
      await tester.pumpAndSettle();
      expect(api.replacements.single, jamendo.map((t) => t.id));
      expect(api.plays, [0]);
      await tester.tap(find.text('MY LIBRARY'));
      await tester.pumpAndSettle();
      expect(find.text('· 1'), findsOneWidget);
      expect(find.text('· 2'), findsNothing);
      await tester.tap(find.text('Add to queue'));
      await tester.pumpAndSettle();
      expect(api.additions.single, local.map((t) => t.id));
      await tester.tap(find.text('JAMENDO'));
      await tester.pumpAndSettle();
      expect(find.text('· 2'), findsOneWidget);
      expect(find.text('· 1'), findsNothing);
      expect(container.read(searchSessionProvider).visitId, visit);
      expect(
        container.read(searchSessionProvider).previousVisits.length,
        history,
      );
      // The normal row action queues its source list from the tapped track.
      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      expect(api.replacements.last, jamendo.map((t) => t.id));
      expect(api.plays.last, 1);
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets(
    'one Back restores overview query facets type and scroll after source switches',
    (tester) async {
      _size(tester, 375, 700);
      final key = GlobalKey();
      final container = await _pump(
        tester,
        _ScriptedApi(
          matches: {
            'jamendo': [
              for (var i = 0; i < 8; i++) _track('jamendo', 'n$i', 'Named $i'),
            ],
          },
          inspired: {
            'localfiles': [_track('localfiles', '1', 'Blue Hour')],
            'jamendo': [_track('jamendo', '1', 'Streetlights')],
          },
        ),
        shell: true,
        captureKey: key,
      );
      await tester.pumpAndSettle();
      final notifier = container.read(searchSessionProvider.notifier);
      notifier.setResultsFilter(
        const BrowseFilterQuery(
          type: SearchType.track,
          genreIds: ['jazz'],
          sources: ['localfiles', 'jamendo'],
        ),
      );
      await tester.pumpAndSettle();
      final overview = find.byType(CustomScrollView);
      await tester.drag(overview, const Offset(0, -350));
      await tester.pumpAndSettle();
      final position = tester
          .state<ScrollableState>(
            find
                .descendant(of: overview, matching: find.byType(Scrollable))
                .first,
          )
          .position;
      final offset = position.pixels;
      expect(offset, greaterThan(0));
      final card = find.widgetWithText(InspiredSourceCard, 'Jamendo');
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      final savedOffset = position.pixels;
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(ActiveFilterChips), findsNothing);
      expect(find.byKey(const ValueKey('results-query-title')), findsOneWidget);
      expect(find.text('jazz'), findsOneWidget);
      for (final title in ['MY LIBRARY', 'JAMENDO', 'MY LIBRARY']) {
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
      }
      await _capture(tester, key, 'search-phone-tracks');
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      final state = container.read(searchSessionProvider);
      expect(state.searchQuery, 'jazz');
      expect(state.resultsFilter.type, SearchType.track);
      expect(state.resultsFilter.genreIds, ['jazz']);
      expect(state.resultsFilter.sources, ['localfiles', 'jamendo']);
      expect(state.expandedBlock, isNull);
      expect(position.pixels, savedOffset);
      expect(
        find.byKey(const ValueKey('results-search-entry')),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
    },
  );

  testWidgets(
    'all five tabs remain available and inspired cards appear only under All and Tracks',
    (tester) async {
      _size(tester, 1100);
      await _pump(
        tester,
        _ScriptedApi(
          inspired: {
            'jamendo': [_track('jamendo', '1', 'Streetlights')],
          },
        ),
      );
      await tester.pumpAndSettle();
      for (final label in ['ARTISTS', 'ALBUMS', 'PLAYLISTS']) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(find.byType(InspiredBlock), findsNothing);
        expect(find.text('Nothing matches these filters'), findsOneWidget);
      }
      for (final label in ['TRACKS', 'ALL']) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(find.byType(InspiredSourceCard), findsOneWidget);
      }
    },
  );

  testWidgets('name matches use full width when no inspired results remain', (
    tester,
  ) async {
    _size(tester, 1100);
    await _pump(
      tester,
      _ScriptedApi(
        matches: {
          'jamendo': [
            for (var i = 0; i < 7; i++)
              _artist('jamendo', '$i', 'Artist $i', MatchTier.partial),
          ],
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(InspiredBlock), findsNothing);
    expect(tester.getSize(find.byType(ShelfHeading)).width, closeTo(1068, 1));
    expect(find.text('Artist 6'), findsOneWidget);
    expect(find.text('View All'), findsNothing);
  });

  testWidgets('result tabs keep independent catalogue view preferences', (
    tester,
  ) async {
    _size(tester, 1100);
    final key = GlobalKey();
    final api = _ScriptedApi(
      matches: {
        'localfiles': [
          _album('localfiles', 'partial', MatchTier.partial),
          _artist('localfiles', 'artist', 'Local artist', MatchTier.partial),
          _playlist('localfiles', 'local'),
          _track('localfiles', 'track', 'A track'),
        ],
        'jamendo': [
          _album('jamendo', 'exact', MatchTier.exact),
          _artist('jamendo', 'artist', 'Other artist', MatchTier.exact),
          _playlist('jamendo', 'other'),
        ],
      },
    );
    final container = await _pump(tester, api, captureKey: key);
    await tester.pumpAndSettle();
    final visit = container.read(searchSessionProvider).visitId;
    final history = container.read(searchSessionProvider).previousVisits.length;
    expect(find.byType(PresentationToggle), findsNothing);
    expect(find.byType(ArtworkGridCard), findsNothing);

    await tester.tap(find.text('ALBUMS'));
    await tester.pumpAndSettle();
    expect(find.byType(ArtworkGridCard), findsNWidgets(2));
    expect(
      tester
          .widgetList<ArtworkGridCard>(find.byType(ArtworkGridCard))
          .map((card) => card.item.id),
      ['kalinka:jamendo:album:exact', 'kalinka:localfiles:album:partial'],
    );
    expect(tester.getRect(find.byType(PresentationToggle)).right, 1084);
    expect(
      tester.getRect(find.byType(ArtStandIn).first).left,
      tester.getRect(find.byType(ShelfHeading)).left,
    );
    expect(find.byType(SourceBadge), findsNWidgets(2));
    await _capture(tester, key, 'search-albums-grid-wide');
    await tester.tap(find.byTooltip('List view'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchAlbumRow), findsNWidgets(2));
    expect(find.byType(ArtworkGridCard), findsNothing);

    await tester.tap(find.text('ARTISTS'));
    await tester.pumpAndSettle();
    expect(find.byType(ArtworkGridCard), findsNWidgets(2));
    await tester.tap(find.text('PLAYLISTS'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchPlaylistRow), findsNWidgets(2));
    await tester.tap(find.byTooltip('Grid view'));
    await tester.pumpAndSettle();
    expect(find.byType(ArtworkGridCard), findsNWidgets(2));

    for (final label in ['ALL', 'TRACKS']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.byType(PresentationToggle), findsNothing);
      expect(find.byType(ArtworkGridCard), findsNothing);
    }
    await tester.tap(find.text('ALBUMS'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchAlbumRow), findsNWidgets(2));
    await tester.tap(find.text('ARTISTS'));
    await tester.pumpAndSettle();
    expect(find.byType(ArtworkGridCard), findsNWidgets(2));
    await tester.tap(find.text('PLAYLISTS'));
    await tester.pumpAndSettle();
    expect(find.byType(ArtworkGridCard), findsNWidgets(2));
    expect(container.read(searchSessionProvider).visitId, visit);
    expect(
      container.read(searchSessionProvider).previousVisits.length,
      history,
    );
    expect(api.matchCalls, {'localfiles': 1, 'jamendo': 1});
    expect(api.replacements, isEmpty);
    expect(api.plays, isEmpty);

    // A new visit and widget tree still use each tab's saved choice.
    await _pump(tester, api);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ALBUMS'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchAlbumRow), findsNWidgets(2));
    await tester.tap(find.text('PLAYLISTS'));
    await tester.pumpAndSettle();
    expect(find.byType(ArtworkGridCard), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  for (final offset in [2500.0, 6500.0]) {
    testWidgets('grid resize preserves the visible item and offset at $offset', (
      tester,
    ) async {
      _size(tester, 375);
      final container = await _pump(
        tester,
        _ScriptedApi(
          matches: {
            'localfiles': [
              for (var i = 0; i < 100; i++)
                BrowseItem(
                  id: 'kalinka:localfiles:album:$i',
                  canBrowse: true,
                  canAdd: true,
                  album: Album(
                    id: '$i',
                    title: i % 3 == 0
                        ? 'Album $i with a longer title that wraps across lines'
                        : 'Album $i',
                    year: i % 2 == 0 ? 2020 : null,
                  ),
                  match: const NameMatch(tier: MatchTier.partial, score: 60),
                ),
            ],
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('ALBUMS'));
      await tester.pumpAndSettle();
      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      scrollable.position.jumpTo(offset);
      await tester.pumpAndSettle();
      final viewport = tester.getRect(find.byType(CustomScrollView));
      final cards = find.byType(ArtworkGridCard);
      final visible = [
        for (var i = 0; i < cards.evaluate().length; i++)
          if (tester.getRect(cards.at(i)).bottom > viewport.top &&
              tester.getRect(cards.at(i)).top < viewport.bottom)
            cards.at(i),
      ];
      final id = tester.widget<ArtworkGridCard>(visible.first).item.id;
      final top = tester.getRect(visible.first).top - viewport.top;
      final anchor = find.byWidgetPredicate(
        (widget) => widget is ArtworkGridCard && widget.item.id == id,
      );
      for (final width in [1100.0, 640.0, 375.0, 1200.0]) {
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpAndSettle();
        expect(anchor, findsOneWidget, reason: 'anchor lost at $width');
        expect(
          tester.getRect(anchor).top -
              tester.getRect(find.byType(CustomScrollView)).top,
          closeTo(top, 1),
          reason: 'anchor moved at $width',
        );
        expect(tester.takeException(), isNull);
      }
      // Changing the result set must not restore an old, unrelated anchor.
      container
          .read(searchSessionProvider.notifier)
          .setResultsFilter(const BrowseFilterQuery(type: SearchType.artist));
      await tester.pumpAndSettle();
      expect(find.text('Nothing matches these filters'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (width, scale) in [(375.0, 1.0), (320.0, 2.0)]) {
    testWidgets(
      'result view switch and grid adapt at $width with $scale text',
      (tester) async {
        _size(tester, width);
        final key = GlobalKey();
        final container = await _pump(
          tester,
          _ScriptedApi(
            matches: {
              'localfiles': [
                for (var i = 0; i < 5; i++)
                  _artist(
                    'localfiles',
                    '$i',
                    'A long artist name $i',
                    MatchTier.partial,
                  ),
              ],
            },
          ),
          scale: scale,
          captureKey: key,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('ARTISTS'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<PresentationToggle>(find.byType(PresentationToggle))
              .compact,
          isTrue,
        );
        expect(find.byTooltip('List view'), findsOneWidget);
        expect(find.byTooltip('Grid view'), findsNothing);
        expect(find.byType(ArtworkGridCard), findsWidgets);
        await _capture(tester, key, 'search-artists-grid-${width.toInt()}');
        await tester.tap(find.byTooltip('List view'));
        await tester.pumpAndSettle();
        expect(find.byType(SearchArtistRow), findsWidgets);
        final before = container.read(listingPresentationProvider);
        tester.view.physicalSize = const Size(1600, 1000);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<PresentationToggle>(find.byType(PresentationToggle))
              .compact,
          isFalse,
        );
        expect(container.read(listingPresentationProvider), before);
        expect(find.byType(SearchArtistRow), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'typed results switch their shimmer and keep controls when empty',
    (tester) async {
      _size(tester, 375);
      final gate = Completer<void>();
      final api = _ScriptedApi(gates: {'jamendo': gate});
      final key = GlobalKey();
      await _pump(tester, api, captureKey: key);
      await tester.pump(_settle);
      await tester.tap(find.text('ARTISTS'));
      await tester.pump(_settle);
      expect(find.byType(ArtworkGridShimmer), findsOneWidget);
      expect(
        tester
            .widget<ArtworkGridShimmer>(find.byType(ArtworkGridShimmer))
            .round,
        isTrue,
      );
      expect(find.byType(BrowseRowsShimmer), findsNothing);
      await _capture(tester, key, 'search-artists-grid-shimmer');
      await tester.tap(find.byTooltip('List view'));
      await tester.pump(_settle);
      expect(find.byType(ArtworkGridShimmer), findsNothing);
      expect(find.byType(BrowseRowsShimmer), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(PresentationToggle), findsOneWidget);
      expect(find.text('Nothing matches these filters'), findsOneWidget);
      expect(find.text('· 0'), findsOneWidget);
      expect(api.matchCalls, {'localfiles': 1, 'jamendo': 1});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('wide name results show one source name beside its badge', (
    tester,
  ) async {
    _size(tester, 1400);
    await _pump(
      tester,
      _ScriptedApi(
        matches: {
          'tidal': [
            _track('tidal', '1', 'Midnight Jazz', tier: MatchTier.exact),
          ],
        },
      ),
      modules: [
        ..._modules,
        ModuleInfo(
          name: 'tidal',
          title: 'TIDAL',
          enabled: true,
          state: ModuleState.ready,
          capabilities: const [ModuleCapability.catalogs],
        ),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('SOURCE'), findsOneWidget);
    expect(find.text('TIDAL'), findsOneWidget);
    expect(find.text('TIDAL ·'), findsNothing);
    final badge = find.byType(SourceBadge);
    expect(badge, findsOneWidget);
    final art = tester.widget<ModuleArtwork>(
      find.descendant(of: badge, matching: find.byType(ModuleArtwork)),
    );
    expect(art.small, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cards cheaply preview three distinct performers in the collage layout',
    (tester) async {
      _size(tester, 375);
      final key = GlobalKey();
      final api = _ScriptedApi(
        inspired: {
          'localfiles': [
            _track('localfiles', '0', 'Missing metadata', performer: null),
            _track(
              'localfiles',
              '1',
              'First track',
              performer: '  Mara   Vale  ',
            ),
            _track('localfiles', '2', 'Another track', performer: 'mara vale'),
            _track(
              'localfiles',
              '3',
              'Album fallback',
              performer: 'Unknown',
              albumArtist: 'Ellis North',
            ),
            _track(
              'localfiles',
              '4',
              'Same album artist',
              performer: null,
              albumArtist: 'Ellis North',
            ),
            _track(
              'localfiles',
              '5',
              'Third performer',
              performer: 'Lila Grey',
            ),
            _track(
              'localfiles',
              '6',
              'Fourth performer',
              performer: 'Fourth Name',
            ),
          ],
        },
      );
      await _pump(tester, api, shell: true, captureKey: key);
      await tester.pumpAndSettle();
      expect(find.text('7 tracks'), findsOneWidget);
      expect(find.text('•'), findsNWidgets(3));
      final bullets = find.text('•');
      for (final (i, name) in [
        'Mara Vale',
        'Ellis North',
        'Lila Grey',
      ].indexed) {
        expect(find.text(name), findsOneWidget);
        expect(
          tester.getTopLeft(bullets.at(i)).dx,
          closeTo(tester.getTopLeft(find.byType(SourceTile)).dx + 8, .01),
        );
        expect(
          tester.getTopLeft(find.text(name)).dx,
          greaterThan(tester.getTopLeft(bullets.at(i)).dx),
        );
        if (i > 0) {
          expect(
            tester.getTopLeft(bullets.at(i)).dy,
            greaterThan(tester.getTopLeft(bullets.at(i - 1)).dy),
          );
        }
      }
      expect(find.text('Fourth Name'), findsNothing);
      await _capture(tester, key, 'search-performers-phone');
      tester.view.physicalSize = const Size(1100, 900);
      await tester.pumpAndSettle();
      expect(find.text('•'), findsNothing);
      final inline = find.text('Mara Vale · Ellis North · Lila Grey');
      expect(inline, findsOneWidget);
      expect(tester.widget<Text>(inline).maxLines, 1);
      expect(tester.widget<Text>(inline).overflow, TextOverflow.ellipsis);
      expect(api.aiCalls, {'localfiles': 1, 'jamendo': 1});
      expect(api.matchCalls, {'localfiles': 1, 'jamendo': 1});
      await _capture(tester, key, 'search-performers-wide');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cards omit unavailable performer names instead of inventing entries',
    (tester) async {
      _size(tester, 375);
      await _pump(
        tester,
        _ScriptedApi(
          inspired: {
            'localfiles': [
              _track('localfiles', '0', 'Missing metadata', performer: null),
              _track(
                'localfiles',
                '1',
                'Placeholder',
                performer: 'Unknown artist',
                albumArtist: ' unknown ',
              ),
            ],
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(InspiredSourceCard), findsOneWidget);
      expect(find.text('•'), findsNothing);
      expect(find.text('Unknown artist'), findsNothing);
      expect(find.text('2 tracks'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('inspired covers adapt to their own pane width', (tester) async {
    _size(tester, 375);
    final key = GlobalKey();
    await _pump(
      tester,
      _ScriptedApi(
        inspired: {
          'localfiles': [
            for (var i = 0; i < 4; i++) _track('localfiles', '$i', 'Track $i'),
          ],
        },
      ),
      captureKey: key,
    );
    await tester.pumpAndSettle();
    final covers = find.descendant(
      of: find.byType(InspiredSourceCard),
      matching: find.byType(TrackThumb),
    );
    expect(covers, findsNWidgets(4));
    final phoneSize = tester.getSize(covers.first).width;
    void expectCollage(int columns) {
      final rects = [for (var i = 0; i < 4; i++) tester.getRect(covers.at(i))];
      for (var i = 0; i < 4; i++) {
        expect(
          rects[i].top,
          closeTo(rects.first.top + (i ~/ columns) * rects.first.height, .01),
        );
        expect(
          rects[i].left,
          closeTo(rects.first.left + (i % columns) * rects.first.width, .01),
        );
        expect(rects[i].height, lessThanOrEqualTo(120));
      }
    }

    expectCollage(2);
    tester.view.physicalSize = const Size(1100, 900);
    await tester.pumpAndSettle();
    final wideSize = tester.getSize(covers.first).width;
    expect(wideSize, greaterThan(phoneSize));
    expectCollage(4);
    await _capture(tester, key, 'search-wide-collage');
    expect(tester.takeException(), isNull);
  });

  for (final distinct in [2, 4]) {
    testWidgets(
      'collage finds $distinct distinct covers without changing playback',
      (tester) async {
        final tracks = [
          _track('localfiles', 'missing', 'Missing cover'),
          for (var i = 0; i < distinct; i++) ...[
            _track(
              'localfiles',
              'first-$i',
              'Track $i',
              cover: '/cover-$i.jpg',
            ),
            _track(
              'localfiles',
              'same-$i',
              'Another track $i',
              cover: '/cover-$i.jpg',
            ),
          ],
        ];
        final api = _ScriptedApi(inspired: {'localfiles': tracks});
        await _pump(tester, api);
        await tester.pumpAndSettle();
        final card = find.byType(InspiredSourceCard);
        final covers = tester
            .widgetList<TrackThumb>(
              find.descendant(of: card, matching: find.byType(TrackThumb)),
            )
            .map((cover) => cover.item)
            .toList();
        expect(covers, hasLength(4));
        expect(covers.map((item) => item.image?.smallest).toSet(), {
          for (var i = 0; i < distinct; i++) '/cover-$i.jpg',
        });
        expect(covers.take(distinct).map((item) => item.id), [
          for (var i = 0; i < distinct; i++)
            'kalinka:localfiles:track:first-$i',
        ]);
        expect(api.aiCalls, {'localfiles': 1, 'jamendo': 1});
        await tester.tap(card);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Play all'));
        await tester.pumpAndSettle();
        expect(api.replacements.single, tracks.map((item) => item.id));
        await tester.pump(const Duration(seconds: 4));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final width in [320.0, 640.0, 1100.0]) {
    testWidgets('inspired shimmer matches the four-cover card at $width', (
      tester,
    ) async {
      _size(tester, width);
      final key = GlobalKey();
      final gate = Completer<void>();
      await _pump(
        tester,
        _ScriptedApi(
          inspired: {
            'localfiles': [
              for (var i = 0; i < 4; i++)
                _track('localfiles', '$i', 'Track $i'),
            ],
          },
          inspiredGates: {'localfiles': gate},
        ),
        captureKey: key,
      );
      await tester.pump(_settle);
      final shimmer = find.byType(InspiredSourceCardShimmer);
      expect(shimmer, findsOneWidget);
      final cardBounds = tester.getRect(shimmer);
      final artBounds = [
        for (var i = 0; i < 4; i++)
          tester.getRect(find.byKey(ValueKey('inspired-cover-placeholder-$i'))),
      ];
      final columns = width < 600 ? 2 : 4;
      for (var i = 0; i < 4; i++) {
        expect(
          artBounds[i].top,
          closeTo(
            artBounds.first.top + (i ~/ columns) * artBounds.first.height,
            .01,
          ),
        );
        expect(
          artBounds[i].left,
          closeTo(
            artBounds.first.left + (i % columns) * artBounds.first.width,
            .01,
          ),
        );
        expect(artBounds[i].height, lessThanOrEqualTo(120));
      }
      await _capture(tester, key, 'search-shimmer-${width.toInt()}');
      gate.complete();
      await tester.pumpAndSettle();
      expect(shimmer, findsNothing);
      expect(tester.getRect(find.byType(InspiredSourceCard)), cardBounds);
      final covers = find.descendant(
        of: find.byType(InspiredSourceCard),
        matching: find.byType(TrackThumb),
      );
      for (var i = 0; i < 4; i++) {
        expect(tester.getRect(covers.at(i)), artBounds[i]);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [375.0, 1100.0]) {
    testWidgets('top-bar filter opens a combined staged popup at $width', (
      tester,
    ) async {
      _size(tester, width);
      final key = GlobalKey();
      final container = await _pump(
        tester,
        _ScriptedApi(
          inspired: {
            'localfiles': [_track('localfiles', '1', 'Jazz song')],
            'jamendo': [_track('jamendo', '1', 'Rock song', genre: 'Rock')],
          },
        ),
        shell: true,
        captureKey: key,
      );
      await tester.pumpAndSettle();
      container
          .read(searchSessionProvider.notifier)
          .setResultsFilter(const BrowseFilterQuery(type: SearchType.track));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CatalogFiltersButton>(find.byType(CatalogFiltersButton))
            .count,
        0,
      );
      final trigger = tester.getRect(find.byType(CatalogFiltersButton));
      await tester.tap(find.byType(CatalogFiltersButton));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      final popup = find.byType(SearchFilterOverlay);
      if (width >= 720) {
        final surface = tester.getRect(
          find.byKey(KalinkaAnchoredSurface.surfaceKey),
        );
        expect(surface.overlaps(trigger), isFalse);
        expect(surface.left, greaterThanOrEqualTo(12));
        expect(surface.right, lessThanOrEqualTo(width - 12));
        expect(surface.top, greaterThanOrEqualTo(12));
        expect(
          surface.bottom,
          lessThanOrEqualTo(tester.view.physicalSize.height - 12),
        );
      } else {
        expect(find.byType(KalinkaAnchoredSurface), findsNothing);
        expect(tester.getRect(popup).top, greaterThan(trigger.bottom));
      }
      expect(tester.getRect(popup).width, lessThanOrEqualTo(480));
      expect(
        find.descendant(of: popup, matching: find.text('GENRE')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: popup, matching: find.text('SOURCE')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: popup, matching: find.text('TYPE')),
        findsNothing,
      );
      expect(
        find.descendant(of: popup, matching: find.byType(TextField)),
        findsNothing,
      );
      expect(find.text('Decade'), findsNothing);
      await tester.tap(find.text('Jazz'));
      await tester.pumpAndSettle();
      expect(
        container.read(searchSessionProvider).resultsFilter.genreIds,
        isEmpty,
      );
      await _capture(tester, key, 'search-filter-${width.toInt()}');
      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();
      expect(container.read(searchSessionProvider).resultsFilter.genreIds, [
        'jazz',
      ]);
      expect(find.widgetWithText(InspiredSourceCard, 'Jamendo'), findsNothing);
      await _capture(tester, key, 'search-active-filters-${width.toInt()}');
      await tester.tap(find.widgetWithText(ActiveFilterChip, 'Jazz'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(InspiredSourceCard, 'Jamendo'),
        findsOneWidget,
      );
      await tester.tap(find.byType(CatalogFiltersButton));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: popup, matching: find.text('Jamendo')),
      );
      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();
      expect(container.read(searchSessionProvider).resultsFilter.sources, [
        'jamendo',
      ]);
      expect(
        find.widgetWithText(InspiredSourceCard, 'My Library'),
        findsNothing,
      );
      await tester.tap(find.widgetWithText(InspiredSourceCard, 'Jamendo'));
      await tester.pumpAndSettle();
      expect(find.text('JAMENDO'), findsOneWidget);
      expect(find.byType(ResultsTabs), findsNothing);
      expect(find.text('TRACKS'), findsOneWidget);
      expect(find.text('· 1'), findsOneWidget);
      expect(
        tester.widget<SourceTile>(find.byType(SourceTile)).source,
        'jamendo',
      );
      expect(find.byType(CatalogFiltersButton), findsNothing);
      expect(find.text('Rock song'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CatalogFiltersButton));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: popup, matching: find.text('My Library')),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(SearchFilterOverlay), findsNothing);
      expect(container.read(searchSessionProvider).resultsFilter.sources, [
        'jamendo',
      ]);
      // Reset clears both facets together without resetting the type or query.
      await tester.tap(find.byType(CatalogFiltersButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Jazz'));
      await tester.tap(find.text('RESET'));
      await tester.pumpAndSettle();
      expect(container.read(searchSessionProvider).resultsFilter.sources, [
        'jamendo',
      ]);
      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();
      final reset = container.read(searchSessionProvider);
      expect(reset.resultsFilter.genreIds, isEmpty);
      expect(reset.resultsFilter.sources, isEmpty);
      expect(reset.resultsFilter.type, SearchType.track);
      expect(reset.searchQuery, 'jazz');
      expect(
        tester
            .widget<CatalogFiltersButton>(find.byType(CatalogFiltersButton))
            .count,
        0,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [const Size(320, 740), const Size(740, 375)]) {
    testWidgets('search and source list fit $size with large text', (
      tester,
    ) async {
      _size(tester, size.width, size.height);
      await _pump(
        tester,
        _ScriptedApi(
          inspired: {
            'localfiles': [
              _track(
                'localfiles',
                '1',
                'A long track title',
                performer: 'A very long performer name that exceeds the available space',
              ),
            ],
          },
        ),
        shell: true,
        scale: 2,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(
        find.widgetWithText(InspiredSourceCard, 'My Library'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('My Library'));
      await tester.pumpAndSettle();
      expect(find.byType(InspiredTracksView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'phone filter popup wraps its actions with large text and Back cancels',
    (tester) async {
      _size(tester, 320, 740);
      final container = await _pump(
        tester,
        _ScriptedApi(
          inspired: {
            'localfiles': [_track('localfiles', '1', 'Jazz song')],
          },
        ),
        shell: true,
        scale: 2,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CatalogFiltersButton));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Jazz'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(SearchFilterOverlay), findsNothing);
      expect(
        container.read(searchSessionProvider).resultsFilter.genreIds,
        isEmpty,
      );
      expect(
        container.read(searchSessionProvider).activeView,
        FindMusicView.results,
      );
    },
  );

  testWidgets(
    'Source excludes browse-only folders while retaining searchable catalogs and collections',
    (tester) async {
      _size(tester, 1100);
      ModuleInfo module(
        String name, {
        bool builtin = false,
        bool catalogs = true,
      }) => ModuleInfo(
        name: name,
        title: name,
        enabled: true,
        state: ModuleState.ready,
        builtin: builtin,
        capabilities: [if (catalogs) ModuleCapability.catalogs],
      );
      BrowseItem root(String source, {bool searchable = false}) => BrowseItem(
        id: 'kalinka:$source:catalog:root',
        name: source,
        canBrowse: true,
        canAdd: false,
        catalog: Catalog(
          id: 'kalinka:$source:catalog:root',
          title: source,
          previewConfig: Preview(type: PreviewType.folder),
          filters: [
            if (searchable)
              const FilterSpec(id: 'q', kind: FilterKind.text, label: 'Search'),
          ],
        ),
      );
      final api = _ScriptedApi(
        roots: [
          root('drives'),
          root('other-folders'),
          root('searchable-folders', searchable: true),
        ],
      );
      final container = await _pump(
        tester,
        api,
        shell: true,
        modules: [
          ..._modules,
          module('drives', builtin: true),
          module('other-folders'),
          module('searchable-folders'),
          module('collections', builtin: true, catalogs: false),
          module('receiver', catalogs: false),
        ],
        preloadSources: true,
      );
      await tester.pumpAndSettle();
      expect(
        api.matchCalls.keys,
        unorderedEquals([
          'localfiles',
          'jamendo',
          'searchable-folders',
          'collections',
        ]),
      );
      expect(
        container.read(searchSessionProvider).results!.sourceNames,
        isNot(
          anyOf(
            contains('drives'),
            contains('other-folders'),
            contains('receiver'),
          ),
        ),
      );
      await tester.tap(find.byType(CatalogFiltersButton));
      await tester.pumpAndSettle();
      expect(find.text('drives'), findsNothing);
      expect(find.text('other-folders'), findsNothing);
      expect(find.text('receiver'), findsNothing);
      expect(find.text('searchable-folders'), findsOneWidget);
      expect(find.text('collections'), findsOneWidget);
    },
  );

  testWidgets('nothing found retains the query controls', (tester) async {
    await _pump(tester, _ScriptedApi(), shell: true);
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);
    expect(find.text('Try rephrasing your request'), findsOneWidget);
    expect(find.byType(CatalogFiltersButton), findsOneWidget);
    expect(find.text('Genre'), findsNothing);
    expect(find.text('Source'), findsNothing);
  });
}
