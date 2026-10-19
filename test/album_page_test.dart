import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/providers/selection_state_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/search/album_page_header.dart';
import 'package:kalinka/widgets/search/catalog_page_view.dart';
import 'package:kalinka/widgets/search/track_group_actions.dart';
import 'package:kalinka/widgets/search_cards/search_track_row.dart';

import 'support/queue_api.dart';

const _page = CatalogPage.category(
  id: 'kalinka:demo:album:abbey',
  title: 'Abbey Road',
  description: 'The Beatles',
);

const _longTitlePage = CatalogPage.category(
  id: 'kalinka:demo:album:random-access-memories',
  title: 'Random Access Memories (10th Anniversary Edition)',
  description: 'Daft Punk',
);

BrowseItem _track(int index, {int? number, int? disc, String? artist}) {
  final id = 'kalinka:demo:track:$index';
  return BrowseItem(
    id: id,
    name: 'Song $index',
    canBrowse: false,
    canAdd: true,
    track: Track(
      id: id,
      title: 'Song $index',
      duration: 180,
      trackNumber: number,
      discNumber: disc,
      performer: Artist(id: 'artist', name: artist ?? 'The Beatles'),
      album: Album(id: _page.id!, title: 'Abbey Road'),
    ),
  );
}

class _AlbumApi extends QueueApi {
  final List<BrowseItem> tracks;
  final bool fail;
  final offsets = <int>[];

  _AlbumApi(this.tracks, {this.fail = false});

  /// The server expands the album into all of its tracks.
  @override
  Future<StatusMessage> replace(List<String> items) async {
    await super.replace(items);
    return StatusMessage(count: tracks.length);
  }

  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async {
    offsets.add(offset);
    if (fail) throw Exception('Offline');
    return BrowseItemsList(
      offset,
      limit,
      tracks.length,
      tracks.skip(offset).take(limit).toList(),
    );
  }
}

void main() {
  late SharedPreferences prefs;

  setUpAll(() async {
    // Real fonts exercise wrapping and system text sizes, unlike Ahem's
    // square glyphs (especially for the large album title).
    for (final (family, file) in [
      ('IBM Plex Sans', 'IBMPlexSans-Regular.ttf'),
      ('IBM Plex Mono', 'IBMPlexMono-Regular.ttf'),
      ('Playfair Display', 'PlayfairDisplay-Regular.ttf'),
    ]) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$file'))).load();
    }
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<ProviderContainer> pumpPage(
    WidgetTester tester,
    _AlbumApi api, {
    CatalogPage page = _page,
    Size size = const Size(390, 900),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        kalinkaProxyProvider.overrideWithValue(api),
        playerStateProvider.overrideWithValue(PlaybackState.empty),
        sourceModulesProvider.overrideWith((ref) => const <ModuleInfo>[]),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: Scaffold(
            backgroundColor: KalinkaColors.background,
            body: CatalogPageView(page: page, onBackToCatalogs: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  test('optional album tags survive JSON and availability copies', () {
    final json = {
      'id': 'track',
      'title': 'Song',
      'duration': 180,
      'track_number': '7',
      'disc_number': 2,
    };
    final track = Track.fromJson(json).copyWith(unavailable: true);
    expect(track.trackNumber, 7);
    expect(track.discNumber, 2);
    expect(Track.fromJson(track.toJson()).discNumber, 2);
    for (final invalid in [null, 0, -1, '', 'unknown']) {
      final absent = Track.fromJson({
        ...json,
        'track_number': invalid,
        'disc_number': invalid,
      });
      expect(absent.trackNumber, isNull);
      expect(absent.discNumber, isNull);
    }
  });

  testWidgets('album rows show positions, disc headings and guest performers', (
    tester,
  ) async {
    await pumpPage(
      tester,
      _AlbumApi([
        _track(1, number: 2, disc: 1),
        _track(2, disc: 1),
        _track(3, number: 1, disc: 2, artist: 'Guest artist'),
        _track(4, disc: 2),
      ]),
    );
    final rows = tester.widgetList<SearchTrackRow>(find.byType(SearchTrackRow));
    expect(rows.map((row) => row.albumTrackNumber), [2, 3, 1, 2]);
    expect(find.text('Disc 1'), findsOneWidget);
    expect(find.text('Disc 2'), findsOneWidget);
    expect(find.text('The Beatles'), findsOneWidget);
    expect(find.text('Guest artist'), findsOneWidget);
    expect(find.text('Abbey Road'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SearchTrackRow),
        matching: find.byType(Image),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('untagged albums use listing order without guessing discs', (
    tester,
  ) async {
    final tracks = [_track(1), _track(2), _track(3)];
    final api = _AlbumApi(tracks);
    final container = await pumpPage(tester, api);
    expect(
      tester
          .widgetList<SearchTrackRow>(find.byType(SearchTrackRow))
          .map((row) => row.albumTrackNumber),
      [1, 2, 3],
    );
    expect(find.textContaining('Disc '), findsNothing);

    // The whole album queues by its id, so pages not loaded yet come too.
    await tester.tap(find.text('Song 2'));
    await tester.pumpAndSettle();
    expect(api.replaced.single, [_page.id]);
    expect(api.played.single, 1);

    container
        .read(selectionStateProvider.notifier)
        .enterSelectionMode(tracks[0].id);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Song 2'));
    await tester.pumpAndSettle();
    expect(
      container.read(selectionStateProvider).selectedIds,
      contains(tracks[1].id),
    );
    expect(api.replaced, hasLength(1));
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('album actions send the album id, including unloaded tracks', (
    tester,
  ) async {
    final api = _AlbumApi([_track(1)]);
    await pumpPage(tester, api);
    await tester.tap(find.byType(PlayAllChip));
    await tester.pumpAndSettle();
    expect(api.replaced.single, [_page.id]);
    expect(api.played.single, 0);
    await tester.tap(find.byType(AddAllChip));
    await tester.pumpAndSettle();
    expect(api.added.single.$1, [_page.id]);
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('numbered tracks can be played with the keyboard', (
    tester,
  ) async {
    final api = _AlbumApi([_track(1), _track(2)]);
    await pumpPage(tester, api);
    Focus.of(tester.element(find.text('Song 2'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(api.played.single, 1);
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('album rows are announced by their position', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpPage(tester, _AlbumApi([_track(1, number: 2), _track(2)]));
    expect(find.bySemanticsLabel(RegExp(r'^Track 2\b')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Track 3\b')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('disc positions continue across a paginated boundary', (
    tester,
  ) async {
    final api = _AlbumApi([
      for (var i = 1; i <= 35; i++) _track(i, disc: i < 30 ? 1 : 2),
    ]);
    await pumpPage(tester, api);
    await tester.scrollUntilVisible(find.text('Song 31'), 400);
    await tester.pumpAndSettle();
    expect(api.offsets, contains(30));
    final row = tester.widget<SearchTrackRow>(
      find.ancestor(
        of: find.text('Song 31'),
        matching: find.byType(SearchTrackRow),
      ),
    );
    expect(row.albumTrackNumber, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('complete album duration is shown beside its track count', (
    tester,
  ) async {
    await pumpPage(tester, _AlbumApi([_track(1), _track(2), _track(3)]));
    expect(find.text('3 tracks · 9 min'), findsOneWidget);
  });

  testWidgets('paginated duration waits for the complete album', (
    tester,
  ) async {
    final api = _AlbumApi([for (var i = 1; i <= 35; i++) _track(i)]);
    await pumpPage(tester, api);
    expect(api.offsets, [0]);
    expect(find.text('35 tracks'), findsOneWidget);
    expect(find.textContaining('90 min'), findsNothing);

    await tester.scrollUntilVisible(find.text('Song 31'), 400);
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    scrollable.position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('35 tracks · 1 hr 45 min'), findsOneWidget);
  });

  testWidgets('source duration is available before all tracks are loaded', (
    tester,
  ) async {
    final api = _AlbumApi([for (var i = 1; i <= 35; i++) _track(i)]);
    await pumpPage(
      tester,
      api,
      page: const CatalogPage.category(
        id: 'kalinka:demo:album:abbey',
        title: 'Abbey Road',
        totalDurationSeconds: 7200,
      ),
    );
    expect(api.offsets, [0]);
    expect(find.text('35 tracks · 2 hr'), findsOneWidget);
  });

  testWidgets('missing track durations do not produce a misleading total', (
    tester,
  ) async {
    final unknown = _track(2)..track!.duration = 0;
    await pumpPage(tester, _AlbumApi([_track(1), unknown]));
    expect(find.text('2 tracks'), findsOneWidget);
    expect(find.text('2 tracks · 3 min'), findsNothing);
  });

  for (final width in [375.0, 430.0]) {
    testWidgets('long album title leaves artwork visible at width $width', (
      tester,
    ) async {
      final size = Size(width, 900);
      await pumpPage(tester, _AlbumApi([_track(1)]), size: size);
      final shortTitleSize = tester
          .widget<Text>(find.text(_page.title!))
          .style!
          .fontSize!;

      await pumpPage(
        tester,
        _AlbumApi([_track(1)]),
        page: _longTitlePage,
        size: size,
      );
      final title = find.text(_longTitlePage.title!);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: title, matching: find.byType(RichText)),
      );
      expect(
        tester.widget<Text>(title).style!.fontSize,
        lessThan(shortTitleSize),
      );
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(
        tester.getSize(title).height,
        lessThan(tester.getSize(find.byType(AlbumPageHeader)).height / 4),
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [const Size(375, 812), const Size(812, 375)]) {
    for (final scale in [1.0, 3.0]) {
      testWidgets('album layout fits $size at ${scale}x text', (tester) async {
        await pumpPage(
          tester,
          _AlbumApi([_track(1)]),
          page: _longTitlePage,
          size: size,
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
        // Wider than a phone, the cover's column scrolls on its own beside
        // the tracks.
        await tester.scrollUntilVisible(
          find.text('Song 1'),
          300,
          scrollable: find.byType(Scrollable).last,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final fail in [false, true]) {
    testWidgets(
      'tall album header scrolls with ${fail ? 'an error' : 'no tracks'}',
      (tester) async {
        await pumpPage(
          tester,
          _AlbumApi([], fail: fail),
          size: const Size(375, 400),
          textScale: 3,
        );
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text(fail ? 'Return to Catalogs' : 'Nothing here yet'),
          300,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
