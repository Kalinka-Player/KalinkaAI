import 'dart:io';
import 'dart:ui' as ui;

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
import 'package:kalinka/widgets/mini_player.dart';
import 'package:kalinka/widgets/search/album_page_header.dart';
import 'package:kalinka/widgets/search/catalog_page_view.dart';
import 'package:kalinka/widgets/search/track_group_actions.dart';
import 'package:kalinka/widgets/search_cards/search_track_row.dart';
import 'package:kalinka/widgets/shelf_heading.dart';
import 'package:kalinka/widgets/top_bar_content_fade.dart';

import 'support/queue_api.dart';
import 'support/home_shell.dart';
import 'support/focus.dart';

final _trackScroll = find.descendant(
  of: find.byKey(const ValueKey('album-tracks')),
  matching: find.byType(Scrollable),
);
final _identityScroll = find.descendant(
  of: find.byType(AlbumIdentityColumn),
  matching: find.byType(Scrollable),
);

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

BrowseItem _track(
  int index, {
  int? number,
  int? disc,
  String? artist,
  int? year,
}) {
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
      album: Album(id: _page.id!, title: 'Abbey Road', year: year),
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

class _HomeAlbumApi extends HomeApi {
  final _AlbumApi album;

  _HomeAlbumApi(this.album);

  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) => album.browse(id, offset: offset, limit: limit, filter: filter);
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final directory = Platform.environment['KALINKA_REVIEW_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$directory/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
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
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
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

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      '1024x600 album keeps actions and last track above mini-player at ${scale}x',
      (tester) async {
        final api = _AlbumApi([
          for (var i = 1; i <= 40; i++)
            _track(i, disc: i <= 20 ? 1 : 2, year: 2013),
        ]);
        final captureKey = GlobalKey();
        final container = await pumpHomeShell(
          tester,
          queue: SettableQueue(queueOf(1)),
          api: _HomeAlbumApi(api),
          size: const Size(1024, 600),
          textScaler: TextScaler.linear(scale),
          themed: true,
          reducedMotion: true,
          captureKey: captureKey,
        );
        container
            .read(searchSessionProvider.notifier)
            .openCatalog(
              id: _longTitlePage.id!,
              title: _longTitlePage.title!,
              description: _longTitlePage.description,
              provider: 'My Library',
              totalDurationSeconds: 7200,
            );
        await tester.pumpAndSettle();
        expect(find.byType(MiniPlayer), findsOneWidget);
        expect(find.text(_longTitlePage.title!), findsOneWidget);
        expect(find.text(_longTitlePage.title!.toUpperCase()), findsNothing);
        final back = find.widgetWithIcon(IconButton, Icons.arrow_back);
        final backSurface = tester.widget<Material>(
          find.descendant(of: back, matching: find.byType(Material)).first,
        );
        expect(backSurface.shape, isA<CircleBorder>());
        expect(tester.getSize(back), const Size(48, 48));
        final dock = tester.getRect(find.byType(MiniPlayer));
        final play = tester.getRect(find.byType(PlayAllChip));
        final enqueue = tester.getRect(find.byType(AddAllChip));
        final cover = tester.getRect(find.byType(AlbumArtwork));
        for (final button in [
          find.byType(PlayAllChip),
          find.byType(AddAllChip),
        ]) {
          final bounds = tester.getRect(button);
          expect(bounds.height, greaterThanOrEqualTo(48));
          expect(bounds.bottom, lessThan(dock.top));
          expect(bounds.top, greaterThan(tester.getRect(back).bottom));
          expect(button.hitTestable(), findsOneWidget);
        }
        expect(cover.width, cover.height);
        expect(
          cover.width,
          tester.getSize(find.byType(AlbumIdentityColumn)).width - 32,
        );
        expect(
          cover.contains(tester.getTopLeft(find.text(_longTitlePage.title!))),
          isTrue,
        );
        expect(tester.getRect(_trackScroll).top, 0);
        expect(
          tester.getRect(find.text('DISC 1')).top,
          greaterThanOrEqualTo(tester.getRect(back).bottom),
        );
        expect(find.text('DISC 1'), findsOneWidget);
        await _capture(tester, captureKey, 'album-1024x600-${scale}x-entry');

        if (scale == 1) {
          expect(
            tester
                .state<ScrollableState>(_identityScroll)
                .position
                .maxScrollExtent,
            0,
          );
          expect(
            play.top -
                tester.getRect(find.text('2013 · 40 tracks · 2 hr')).bottom,
            closeTo(24, 0.01),
          );
          expect(enqueue.bottom, lessThan(dock.top - 24));
        } else {
          final tracksOffset = tester
              .state<ScrollableState>(_trackScroll)
              .position
              .pixels;
          await tester.drag(_identityScroll, const Offset(0, -120));
          await tester.pumpAndSettle();
          expect(
            tester.state<ScrollableState>(_identityScroll).position.pixels,
            greaterThan(0),
          );
          expect(
            tester.getRect(find.text(_longTitlePage.title!)).top,
            lessThan(tester.getRect(back).bottom),
          );
          expect(
            tester.state<ScrollableState>(_trackScroll).position.pixels,
            tracksOffset,
          );
          expect(tester.getRect(find.byType(PlayAllChip)), play);
          expect(tester.getRect(find.byType(AddAllChip)), enqueue);
          await _capture(
            tester,
            captureKey,
            'album-1024x600-${scale}x-identity-scroll',
          );
        }

        await tester.scrollUntilVisible(
          find.text('DISC 2'),
          300,
          scrollable: _trackScroll,
        );
        await tester.pumpAndSettle();
        expect(find.text('DISC 2'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Song 40'),
          300,
          scrollable: _trackScroll,
        );
        await tester.pumpAndSettle();
        final tracks = tester.state<ScrollableState>(_trackScroll).position;
        tracks.jumpTo(tracks.maxScrollExtent);
        await tester.pumpAndSettle();
        final last = tester.getRect(
          find.ancestor(
            of: find.text('Song 40'),
            matching: find.byType(SearchTrackRow),
          ),
        );
        expect(last.bottom, lessThan(dock.top));
        expect(find.text('Song 40').hitTestable(), findsOneWidget);
        expect(tester.getRect(find.byType(PlayAllChip)), play);
        expect(tester.getRect(find.byType(AddAllChip)), enqueue);
        expect(api.offsets, [0, 30]);
        expect(tester.takeException(), isNull);
        await _capture(
          tester,
          captureKey,
          'album-1024x600-${scale}x-last-track',
        );

        // A retained visit follows changing system insets after rotation.
        final trackTop = tester.getTopLeft(_trackScroll).dy;
        tester.view.padding = const FakeViewPadding(top: 24);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(_trackScroll).dy, trackTop);
        expect(
          tester
              .widget<TopBarContentFade>(find.byType(TopBarContentFade))
              .extent,
          24 + kKalinkaTopBarHeight,
        );
        expect(
          tester.getRect(find.byType(TopBarContentFade)),
          tester.getRect(find.byType(CatalogPageView)),
        );
        final insetPlay = tester.getRect(find.byType(PlayAllChip));
        final insetEnqueue = tester.getRect(find.byType(AddAllChip));
        expect(insetEnqueue.bottom, lessThan(dock.top));
        tracks.jumpTo(0);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.text('DISC 1')).top,
          greaterThanOrEqualTo(24 + kKalinkaTopBarHeight),
        );
        tracks.jumpTo(tester.getTopLeft(find.text('Song 1')).dy - 44);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.text('Song 1')).dy, closeTo(44, 0.01));
        expect(tester.getRect(find.byType(PlayAllChip)), insetPlay);
        expect(tester.getRect(find.byType(AddAllChip)), insetEnqueue);
        await _capture(
          tester,
          captureKey,
          'album-1024x600-${scale}x-android-fade',
        );
        expect(tester.takeException(), isNull);
        tester.view.resetPadding();
        await tester.pumpAndSettle();

        if (scale == 1) {
          // More height moves the details below the same full-size cover;
          // the actions follow those details instead of the viewport bottom.
          tester.view.physicalSize = const Size(1024, 900);
          await tester.pumpAndSettle();
          final tallCover = tester.getRect(find.byType(AlbumArtwork));
          expect(tallCover.size, cover.size);
          expect(
            tester.getTopLeft(find.text(_longTitlePage.title!)).dy,
            greaterThan(tallCover.bottom),
          );
          expect(
            tester.getRect(find.byType(PlayAllChip)).top -
                tester.getRect(find.text('2013 · 40 tracks · 2 hr')).bottom,
            closeTo(24, 0.01),
          );
          expect(
            tester.getRect(find.byType(AddAllChip)).bottom,
            lessThan(tester.getRect(find.byType(MiniPlayer)).top - 100),
          );
          await _capture(tester, captureKey, 'album-1024x900-entry');
          tester.view.physicalSize = const Size(1024, 600);
          await tester.pumpAndSettle();
          expect(tester.getSize(find.byType(AlbumArtwork)), cover.size);
          expect(tester.getRect(find.byType(PlayAllChip)), play);
          expect(tester.takeException(), isNull);
        }

        // The circular Back control keeps the existing navigation behaviour.
        await tester.tap(back);
        await tester.pumpAndSettle();
        expect(container.read(searchSessionProvider).atHome, isTrue);
      },
    );
  }

  for (final size in [
    const Size(812, 375),
    const Size(616, 375),
    const Size(616, 600),
  ]) {
    testWidgets('wide album remains usable at $size with 3x text and dock', (
      tester,
    ) async {
      final api = _AlbumApi([
        for (var i = 1; i <= 40; i++)
          _track(i, disc: i <= 20 ? 1 : 2, year: 2013),
      ]);
      final captureKey = GlobalKey();
      final container = await pumpHomeShell(
        tester,
        queue: SettableQueue(queueOf(1)),
        api: _HomeAlbumApi(api),
        size: size,
        textScaler: const TextScaler.linear(3),
        themed: true,
        reducedMotion: true,
        captureKey: captureKey,
      );
      container
          .read(searchSessionProvider.notifier)
          .openCatalog(
            id: _longTitlePage.id!,
            title: _longTitlePage.title!,
            description: _longTitlePage.description,
            totalDurationSeconds: 7200,
          );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final dock = tester.getRect(find.byType(MiniPlayer));
      final play = tester.getRect(find.byType(PlayAllChip));
      final enqueue = tester.getRect(find.byType(AddAllChip));
      for (final button in [
        find.byType(PlayAllChip),
        find.byType(AddAllChip),
      ]) {
        final bounds = tester.getRect(button);
        expect(bounds.height, greaterThanOrEqualTo(48));
        expect(bounds.top, greaterThanOrEqualTo(kKalinkaTopBarHeight));
        expect(bounds.bottom, lessThan(dock.top));
        expect(bounds.right, lessThanOrEqualTo(size.width));
        expect(button.hitTestable(), findsOneWidget);
        final label = find.descendant(of: button, matching: find.byType(Text));
        expect(bounds.contains(tester.getTopLeft(label)), isTrue);
        expect(bounds.contains(tester.getBottomRight(label)), isTrue);
      }
      final viewport = tester.getRect(_identityScroll);
      expect(viewport.bottom - kKalinkaTopBarHeight, greaterThanOrEqualTo(48));
      final dragStart = Offset(viewport.center.dx, viewport.bottom - 8);
      await tester.dragFrom(dragStart, const Offset(0, -70));
      await tester.pumpAndSettle();
      final identity = tester.state<ScrollableState>(_identityScroll).position;
      expect(identity.pixels, greaterThan(0));
      expect(tester.state<ScrollableState>(_trackScroll).position.pixels, 0);
      identity.jumpTo(identity.maxScrollExtent);
      await tester.pumpAndSettle();
      // The summary can span more than the viewport at 3x; its final line
      // must still be reachable below the mask at the end of the scroll.
      expect(
        find
            .text('2013 · 40 tracks · 2 hr')
            .hitTestable(at: const Alignment(0, 0.9)),
        findsOneWidget,
      );
      expect(tester.getRect(find.byType(PlayAllChip)), play);
      expect(tester.getRect(find.byType(AddAllChip)), enqueue);
      await _capture(
        tester,
        captureKey,
        'album-${size.width}x${size.height}-3x',
      );

      await tester.scrollUntilVisible(
        find.text('Song 40'),
        250,
        scrollable: _trackScroll,
        maxScrolls: 50,
      );
      await tester.pumpAndSettle();
      expect(find.text('Song 40').hitTestable(), findsOneWidget);
      final tracks = tester.state<ScrollableState>(_trackScroll).position;
      tracks.jumpTo(tracks.maxScrollExtent);
      await tester.pumpAndSettle();
      final last = find.ancestor(
        of: find.text('Song 40'),
        matching: find.byType(SearchTrackRow),
      );
      expect(tester.getRect(last).bottom, lessThan(dock.top));
      expect(
        tester.getRect(last).bottom,
        lessThanOrEqualTo(tester.getRect(_trackScroll).bottom),
      );
      expect(tester.getRect(find.byType(PlayAllChip)), play);
      expect(tester.getRect(find.byType(AddAllChip)), enqueue);
      expect(api.offsets, [0, 30]);
      expect(tester.takeException(), isNull);

      tester.view.padding = const FakeViewPadding(top: 24);
      await tester.pumpAndSettle();
      final insetViewport = tester.getRect(_identityScroll);
      expect(
        insetViewport.bottom - 24 - kKalinkaTopBarHeight,
        greaterThanOrEqualTo(48),
      );
      identity.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.dragFrom(
        Offset(insetViewport.center.dx, insetViewport.bottom - 8),
        const Offset(0, -70),
      );
      await tester.pumpAndSettle();
      expect(identity.pixels, greaterThan(0));
      expect(find.byType(PlayAllChip).hitTestable(), findsOneWidget);
      expect(find.byType(AddAllChip).hitTestable(), findsOneWidget);

      // Reflow, then cross the phone breakpoint, without fetching again.
      for (final resized in [
        const Size(616, 600),
        const Size(390, 900),
        size,
      ]) {
        tester.view.physicalSize = resized;
        await tester.pumpAndSettle();
        expect(api.offsets, [
          0,
          30,
        ], reason: 'After resizing $size to $resized');
        expect(_trackScroll, findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('backward keyboard traversal reveals tracks below the toolbar', (
    tester,
  ) async {
    final container = await pumpHomeShell(
      tester,
      queue: SettableQueue(queueOf(1)),
      api: _HomeAlbumApi(_AlbumApi([for (var i = 1; i <= 40; i++) _track(i)])),
      size: const Size(1024, 600),
      themed: true,
      reducedMotion: true,
    );
    tester.view.padding = const FakeViewPadding(top: 24);
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(id: _page.id!, title: _page.title!);
    await tester.pumpAndSettle();
    final song5 = find.ancestor(
      of: find.text('Song 5'),
      matching: find.byType(SearchTrackRow),
    );
    final song6 = find.ancestor(
      of: find.text('Song 6'),
      matching: find.byType(SearchTrackRow),
    );
    Focus.of(tester.element(find.text('Song 6'))).requestFocus();
    await tester.pumpAndSettle();
    final tracks = tester.state<ScrollableState>(_trackScroll).position;
    const barBottom = 24 + kKalinkaTopBarHeight;
    tracks.jumpTo(tracks.pixels + tester.getRect(song6).top - barBottom);
    await tester.pumpAndSettle();
    expect(tester.getRect(song5).top, lessThan(barBottom));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(focusIsOn(song5), isTrue);
    expect(tester.getRect(song5).top, greaterThanOrEqualTo(barBottom));
    expect(
      tester.getRect(song5).bottom,
      lessThan(tester.getRect(find.byType(MiniPlayer)).top),
    );
    expect(find.text('Song 5').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
    expect(find.text('DISC 1'), findsOneWidget);
    expect(find.text('DISC 2'), findsOneWidget);
    // A disc's name starts at its tracks' own edge, with no rule after it.
    expect(
      tester.getRect(find.text('DISC 2')).left,
      closeTo(
        tester
            .getRect(
              find.ancestor(
                of: find.text('Song 3'),
                matching: find.byType(SearchTrackRow),
              ),
            )
            .left,
        0.01,
      ),
    );
    expect(
      find.descendant(
        of: find.byType(ShelfHeading),
        matching: find.byType(Divider),
      ),
      findsNothing,
    );
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
    expect(find.textContaining('DISC '), findsNothing);

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

  testWidgets('wide tracks scroll independently of identity and actions', (
    tester,
  ) async {
    final api = _AlbumApi([for (var i = 1; i <= 40; i++) _track(i)]);
    await pumpPage(tester, api, size: const Size(812, 375));
    expect(api.offsets, [0]);
    expect(find.byType(SearchTrackRow).evaluate().length, lessThan(30));
    final scroll = tester.state<ScrollableState>(_trackScroll);
    final play = tester.getRect(find.byType(PlayAllChip));
    final enqueue = tester.getRect(find.byType(AddAllChip));
    await tester.dragFrom(const Offset(100, 250), const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, 0);
    final cover = tester.getRect(find.byType(AlbumArtwork));
    expect(tester.getRect(find.byType(PlayAllChip)), play);
    expect(tester.getRect(find.byType(AddAllChip)), enqueue);
    await tester.drag(_trackScroll, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, greaterThan(0));
    expect(tester.getRect(find.byType(AlbumArtwork)), cover);
    expect(tester.getRect(find.byType(PlayAllChip)), play);
    expect(tester.getRect(find.byType(AddAllChip)), enqueue);
    await tester.scrollUntilVisible(
      find.text('Song 35'),
      400,
      scrollable: _trackScroll,
    );
    await tester.pumpAndSettle();
    expect(api.offsets, [0, 30]);
    await tester.tap(find.text('Song 35'));
    await tester.pumpAndSettle();
    expect(api.replaced.single, [_page.id]);
    expect(api.played.single, 34);
    await tester.tap(find.byType(PlayAllChip));
    await tester.pumpAndSettle();
    expect(api.replaced.last, [_page.id]);
    expect(api.played.last, 0);
    await tester.tap(find.byType(AddAllChip));
    await tester.pumpAndSettle();
    expect(api.added.single.$1, [_page.id]);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('resizing an album preserves its loaded tracks', (tester) async {
    final api = _AlbumApi([for (var i = 1; i <= 40; i++) _track(i)]);
    await pumpPage(tester, api, size: const Size(812, 375));
    await tester.scrollUntilVisible(
      find.text('Song 35'),
      400,
      scrollable: _trackScroll,
    );
    await tester.pumpAndSettle();
    for (final size in [const Size(390, 900), const Size(812, 375)]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(_trackScroll, findsOneWidget);
      expect(api.offsets, [0, 30]);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('complete album duration is shown beside its track count', (
    tester,
  ) async {
    await pumpPage(tester, _AlbumApi([_track(1), _track(2), _track(3)]));
    expect(find.text('3 tracks · 9 min'), findsOneWidget);
  });

  testWidgets('the album\'s year leads its summary', (tester) async {
    await pumpPage(
      tester,
      _AlbumApi([for (var i = 1; i <= 3; i++) _track(i, year: 1969)]),
    );
    expect(find.text('1969 · 3 tracks · 9 min'), findsOneWidget);
  });

  testWidgets('the year the album was opened with shows without its tracks', (
    tester,
  ) async {
    await pumpPage(
      tester,
      _AlbumApi([_track(1), _track(2), _track(3)]),
      page: CatalogPage.fromItem(
        BrowseItem(
          id: _page.id!,
          name: 'Abbey Road',
          canBrowse: true,
          canAdd: true,
          album: Album(id: _page.id!, title: 'Abbey Road', year: 1969),
        ),
      ),
    );
    expect(find.text('1969 · 3 tracks · 9 min'), findsOneWidget);
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
        expect(_trackScroll, findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Song 1'),
          300,
          scrollable: _trackScroll,
        );
        if (size.width >= kAlbumSideLayoutWidth) {
          expect(find.byType(AddAllChip).hitTestable(), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets(
      'wide actions follow the identity without a bottom gap at ${scale}x',
      (tester) async {
        await pumpPage(
          tester,
          _AlbumApi([_track(1)]),
          size: const Size(1024, 768),
          textScale: scale,
          page: _longTitlePage,
        );
        final pane = tester.getRect(find.byType(AlbumIdentityColumn));
        for (final chip in [
          find.byType(PlayAllChip),
          find.byType(AddAllChip),
        ]) {
          final target = tester.getRect(chip);
          expect(target.height, greaterThanOrEqualTo(48));
          expect(target.left, greaterThanOrEqualTo(pane.left));
          expect(target.right, lessThanOrEqualTo(pane.right));
          expect(target.bottom, lessThanOrEqualTo(pane.bottom - 16));
          expect(chip.hitTestable(), findsOneWidget);
        }
        final identity = tester.state<ScrollableState>(_identityScroll);
        if (identity.position.maxScrollExtent == 0) {
          expect(
            tester.getRect(find.byType(PlayAllChip)).top -
                tester.getRect(find.text('1 track · 3 min')).bottom,
            closeTo(24, 0.01),
          );
        } else {
          expect(
            tester.getRect(find.byType(AddAllChip)).bottom,
            pane.bottom - 16,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final size in [const Size(375, 400), const Size(812, 375)]) {
    for (final fail in [false, true]) {
      testWidgets(
        'tall album header scrolls with ${fail ? 'an error' : 'no tracks'} at $size',
        (tester) async {
          await pumpPage(
            tester,
            _AlbumApi([], fail: fail),
            size: size,
            textScale: 3,
          );
          expect(tester.takeException(), isNull);
          expect(_trackScroll, findsOneWidget);
          expect(find.text(_page.title!), findsOneWidget);
          await tester.scrollUntilVisible(
            find.text(fail ? 'Return to Catalogs' : 'Nothing here yet'),
            300,
            scrollable: _trackScroll,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
