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
import 'package:kalinka/widgets/server_chip.dart';
import 'package:kalinka/widgets/top_bar_content_fade.dart';
import 'package:kalinka/widgets/search_cards/action_pill_button.dart';

import 'support/queue_api.dart';
import 'support/home_shell.dart';
import 'support/focus.dart';

final _trackScroll = find.descendant(
  of: find.byKey(const ValueKey('album-tracks')),
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
    GlobalKey? captureKey,
    bool settle = true,
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
          theme: captureKey == null ? ThemeData.dark() : AppTheme.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: Scaffold(
            backgroundColor: KalinkaColors.background,
            body: RepaintBoundary(
              key: captureKey,
              child: ColoredBox(
                color: KalinkaColors.background,
                child: CatalogPageView(page: page, onBackToCatalogs: () {}),
              ),
            ),
          ),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
    'long album metadata leaves tracks usable at enlarged text sizes',
    (tester) async {
      const page = CatalogPage.category(
        id: 'kalinka:demo:album:orchestra',
        title: 'Symphonies',
        description:
            'Royal Philharmonic Orchestra and London Philharmonic Choir',
        provider: 'My Library',
        totalDurationSeconds: 8000,
      );
      final api = _AlbumApi([
        for (var i = 1; i <= 44; i++)
          _track(i, artist: page.description, disc: i <= 22 ? 1 : 2),
      ]);
      final captureKey = GlobalKey();
      await pumpPage(
        tester,
        api,
        page: page,
        size: const Size(600, 400),
        textScale: 3,
        captureKey: captureKey,
        settle: false,
      );
      final firstHeader = tester.getRect(find.byType(WideAlbumHeader));
      expect(firstHeader.bottom, lessThanOrEqualTo(400 - 120));
      expect(
        tester.getRect(find.byType(AlbumArtwork)).top,
        closeTo(firstHeader.bottom + 12, .01),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<WideAlbumHeader>(find.byType(WideAlbumHeader))
            .metadataInTracks,
        isTrue,
      );
      expect(tester.getSize(find.byType(AlbumArtwork)).height, greaterThan(0));
      expect(find.byType(PlayAllChip).hitTestable(), findsOneWidget);
      expect(find.byType(AddAllChip).hitTestable(), findsOneWidget);
      await _capture(tester, captureKey, 'album-long-metadata-600x400-3');

      await tester.scrollUntilVisible(
        find.text('Song 1'),
        80,
        scrollable: _trackScroll,
      );
      await tester.pumpAndSettle();
      expect(find.text('Song 1').hitTestable(), findsOneWidget);
      final firstRow = find.ancestor(
        of: find.text('Song 1'),
        matching: find.byType(SearchTrackRow),
      );
      expect(await tabTo(tester, firstRow), isTrue);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(firstRow).top,
        greaterThanOrEqualTo(
          tester.getRect(find.byType(WideAlbumHeader)).bottom,
        ),
      );
      final scroll = tester.state<ScrollableState>(_trackScroll);
      for (var i = 0; i < 4; i++) {
        scroll.position.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
      }
      expect(find.text('Song 44').hitTestable(), findsOneWidget);
      expect(api.offsets, [0, 30]);

      for (final height in [900.0, 400.0, 550.0]) {
        tester.view.physicalSize = Size(600, height);
        // The placement decision and fade must be correct within this frame.
        await tester.pump();
        final bar = tester.getRect(find.byType(WideAlbumHeader));
        expect(bar.bottom, lessThanOrEqualTo(height - 120));
        expect(
          tester
              .widget<WideAlbumHeader>(find.byType(WideAlbumHeader))
              .metadataInTracks,
          height != 900,
        );
        expect(
          tester
              .widget<TopBarContentFade>(
                find.byKey(const ValueKey('album-content-fade')),
              )
              .extent,
          bar.height,
        );
        await tester.pumpAndSettle();
        expect(tester.state<ScrollableState>(_trackScroll), same(scroll));
        expect(api.offsets, [0, 30]);
        expect(tester.takeException(), isNull);
      }
    },
  );

  for (final (size, scale) in [
    (const Size(1024, 600), 1.0),
    (const Size(1024, 600), 2.0),
    (const Size(1600, 900), 1.0),
    (const Size(760, 680), 1.0),
    (const Size(616, 600), 1.0),
    (const Size(812, 375), 3.0),
    (const Size(616, 375), 3.0),
    (const Size(616, 600), 3.0),
  ]) {
    testWidgets(
      'wide album fits artwork and keeps header fixed at $size / $scale',
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
          size: size,
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
        // The very first frame must already reserve the measured toolbar.
        // A post-frame size callback used to show the cover behind it first,
        // then rebuild the entire page to correct the columns next frame.
        await tester.pump();
        final firstHeader = tester.getRect(find.byType(WideAlbumHeader));
        final firstCover = tester.getRect(find.byType(AlbumArtwork));
        expect(firstCover.top, closeTo(firstHeader.bottom + 12, 0.01));
        expect(
          tester
              .widget<TopBarContentFade>(
                find.byKey(const ValueKey('album-content-fade')),
              )
              .extent,
          firstHeader.height,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final header = tester.getRect(find.byType(WideAlbumHeader));
        final pane = tester.getRect(find.byType(CatalogPageView));
        final dockTop = find.byType(MiniPlayer).evaluate().isEmpty
            ? pane.bottom
            : tester.getRect(find.byType(MiniPlayer)).top;
        final play = tester.getRect(find.byType(PlayAllChip));
        final enqueue = tester.getRect(find.byType(AddAllChip));
        final cover = tester.getRect(find.byType(AlbumArtwork));
        final tracks = tester.getRect(_trackScroll);
        final status = tester.getRect(
          find.descendant(
            of: find.byType(WideAlbumHeader),
            matching: find.byType(ServerChip),
          ),
        );
        expect(play.right, lessThan(enqueue.left));
        expect(enqueue.right, lessThan(status.left));
        expect(
          tester.getRect(find.text(_longTitlePage.title!)).bottom,
          lessThan(cover.top),
        );
        expect(
          find.byKey(const ValueKey('album-tracks-heading')),
          findsNothing,
        );
        expect(find.text('DISC 1'), findsOneWidget);
        for (final button in [
          find.byType(PlayAllChip),
          find.byType(AddAllChip),
        ]) {
          final bounds = tester.getRect(button);
          expect(bounds.height, greaterThanOrEqualTo(48));
          expect(bounds.width, greaterThanOrEqualTo(48));
          expect(header.contains(bounds.center), isTrue);
          expect(bounds.bottom, lessThan(cover.top));
          expect(button.hitTestable(), findsOneWidget);
        }
        final primary = tester.widget<ActionPillButton>(
          find.descendant(
            of: find.byType(PlayAllChip),
            matching: find.byType(ActionPillButton),
          ),
        );
        expect(primary.primary, isTrue);
        expect(cover.width, closeTo(cover.height, .01));
        expect(cover.bottom, lessThanOrEqualTo(dockTop - 12));
        expect(cover.right + 16, closeTo(tracks.left, .01));
        expect(tracks.top, pane.top);
        expect(cover.top, closeTo(header.bottom + 12, .01));
        final fade = tester.widget<TopBarContentFade>(
          find.byKey(const ValueKey('album-content-fade')),
        );
        expect(fade.extent, closeTo(header.height, .01));
        final playWidget = tester.widget<PlayAllChip>(find.byType(PlayAllChip));
        final enqueueWidget = tester.widget<AddAllChip>(
          find.byType(AddAllChip),
        );
        expect(playWidget.iconOnly, enqueueWidget.iconOnly);
        if (playWidget.iconOnly) {
          for (final control in [
            find.byType(PlayAllChip),
            find.byType(AddAllChip),
          ]) {
            final face = find.descendant(
              of: control,
              matching: find.byType(Material),
            );
            final glyph = find.descendant(
              of: control,
              matching: find.byType(Icon),
            );
            final bounds = tester.getRect(face);
            expect(bounds.size, const Size.square(kKalinkaPillHeight));
            expect(
              tester.getSize(control),
              const Size.square(kKalinkaPillTarget),
            );
            expect(tester.getCenter(glyph), bounds.center);
            expect(tester.getCenter(control), bounds.center);
          }
        }
        if (scale == 1 && size.width >= 760) {
          expect(playWidget.iconOnly, isFalse);
          expect(find.text('Play all').hitTestable(), findsOneWidget);
          expect(find.text('Enqueue').hitTestable(), findsOneWidget);
        }
        // The cover reaches a height or width limit, rather than a fixed cap.
        final reservedTracks = (552 * scale).clamp(0.0, pane.width * .69);
        expect(
          cover.width,
          closeTo(
            (pane.width - reservedTracks - 32).clamp(
              0.0,
              tracks.height - header.height - 24,
            ),
            .01,
          ),
        );
        expect(tracks.width, greaterThanOrEqualTo(reservedTracks));
        if (scale == 1 && size.width >= 1024) {
          expect(cover.width, greaterThan(280));
        }
        await _capture(
          tester,
          captureKey,
          'album-header-${size.width}-${size.height}-$scale',
        );

        final metadata = find.byKey(const ValueKey('album-metadata'));
        expect(
          find.descendant(of: metadata, matching: find.byType(Scrollable)),
          findsNothing,
        );
        final summary = find.text('2013 · 40 tracks · 2 hr');
        if (tester
            .widget<WideAlbumHeader>(find.byType(WideAlbumHeader))
            .metadataInTracks) {
          await tester.scrollUntilVisible(
            summary,
            60,
            scrollable: _trackScroll,
          );
          await tester.pumpAndSettle();
        } else {
          final bounds = tester.getRect(metadata);
          expect(bounds.bottom, lessThanOrEqualTo(header.bottom));
          expect(bounds.right, lessThanOrEqualTo(header.right));
          expect(
            tester.getRect(summary).right,
            lessThanOrEqualTo(bounds.right + .01),
          );
        }
        expect(summary.hitTestable(at: const Alignment(.9, 0)), findsOneWidget);
        expect(tester.getRect(find.byType(PlayAllChip)), play);

        // The scroll viewport now includes the toolbar. Drag in the usable
        // area below it, even when enlarged text takes over half the pane.
        final dragStart = Offset(
          tracks.center.dx,
          (header.bottom + tracks.bottom) / 2,
        );
        for (
          var i = 0;
          find.text('Song 40').evaluate().isEmpty && i < 220;
          i++
        ) {
          await tester.dragFrom(
            dragStart,
            Offset(
              0,
              -((tracks.height - header.height) * .6).clamp(40.0, 160.0),
            ),
          );
          await tester.pumpAndSettle();
        }
        expect(find.text('Song 40'), findsOneWidget);
        await tester.ensureVisible(find.text('Song 40'));
        await tester.pumpAndSettle();
        final position = tester.state<ScrollableState>(_trackScroll).position;
        position.jumpTo(position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(find.text('Song 40').hitTestable(), findsOneWidget);
        expect(tester.getRect(find.byType(AlbumArtwork)), cover);
        expect(tester.getRect(find.byType(PlayAllChip)), play);
        expect(tester.getRect(find.byType(AddAllChip)), enqueue);
        expect(api.offsets, [0, 30]);
        expect(tester.takeException(), isNull);

        // Insets, larger panes, and phone/wide changes retain the loaded visit.
        tester.view.padding = const FakeViewPadding(top: 24);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byType(PlayAllChip)).top,
          greaterThanOrEqualTo(24),
        );
        for (final resized in [
          const Size(1024, 900),
          const Size(390, 900),
          size,
        ]) {
          tester.view.physicalSize = resized;
          await tester.pumpAndSettle();
          expect(api.offsets, [0, 30], reason: 'After resizing to $resized');
          expect(_trackScroll, findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_back));
        await tester.pumpAndSettle();
        expect(container.read(searchSessionProvider).atHome, isTrue);
      },
    );
  }

  testWidgets(
    'full wide pane grows artwork to the bottom and retains artist navigation',
    (tester) async {
      const artistId = 'kalinka:demo:artist:beatles';
      final captureKey = GlobalKey();
      final page = CatalogPage.fromItem(
        BrowseItem(
          id: _page.id!,
          name: 'Abbey Road',
          canBrowse: true,
          canAdd: true,
          album: Album(
            id: _page.id!,
            title: 'Abbey Road',
            year: 1969,
            artist: Artist(id: artistId, name: 'The Beatles'),
          ),
        ),
      );
      final container = await pumpPage(
        tester,
        _AlbumApi([for (var i = 1; i <= 17; i++) _track(i)]),
        page: page,
        size: const Size(1600, 700),
        captureKey: captureKey,
      );
      final cover = tester.getRect(find.byType(AlbumArtwork));
      final tracks = tester.getRect(_trackScroll);
      expect(cover.bottom, closeTo(688, .01));
      expect(cover.width, closeTo(cover.height, .01));
      expect(cover.width, greaterThan(550));
      expect(tracks.width, greaterThanOrEqualTo(552));
      expect(
        tester.getRect(find.text('Song 1')).top,
        greaterThanOrEqualTo(cover.top),
      );
      expect(find.text('1969 · 17 tracks · 51 min'), findsOneWidget);
      await _capture(tester, captureKey, 'album-full-pane-1600-700');
      await tester.tap(find.text('The Beatles'));
      await tester.pumpAndSettle();
      expect(container.read(searchSessionProvider).catalogPage.id, artistId);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'album actions switch together and metadata reflows without clipping',
    (tester) async {
      const page = CatalogPage.category(
        id: 'kalinka:demo:album:back-to-black',
        title: 'Back To Black (20th Anniversary Edition)',
        description: 'Amy Winehouse',
        provider: 'Qobuz',
        totalDurationSeconds: 7800,
      );
      final api = _AlbumApi([
        for (var i = 1; i <= 42; i++) _track(i, year: 2006),
      ]);
      final key = GlobalKey();
      await pumpPage(
        tester,
        api,
        page: page,
        size: const Size(1200, 750),
        captureKey: key,
      );
      for (final width in [1200.0, 760.0, 616.0, 560.0, 528.0, 1000.0]) {
        tester.view.physicalSize = Size(width, 750);
        await tester.pumpAndSettle();
        final play = tester.widget<PlayAllChip>(find.byType(PlayAllChip));
        final enqueue = tester.widget<AddAllChip>(find.byType(AddAllChip));
        expect(play.iconOnly, width <= 560);
        expect(enqueue.iconOnly, play.iconOnly);
        for (final (control, label) in [
          (find.byType(PlayAllChip), 'Play all'),
          (find.byType(AddAllChip), 'Enqueue'),
        ]) {
          expect(control.hitTestable(), findsOneWidget);
          expect(
            find.descendant(of: control, matching: find.text(label)),
            play.iconOnly ? findsNothing : findsOneWidget,
          );
          if (play.iconOnly) expect(find.byTooltip(label), findsOneWidget);
        }
        final header = tester.getRect(find.byType(WideAlbumHeader));
        for (final text in [
          'Amy Winehouse',
          'Qobuz',
          '2006 · 42 tracks · 2 hr 10 min',
        ]) {
          final bounds = tester.getRect(find.text(text));
          expect(bounds.left, greaterThanOrEqualTo(header.left));
          expect(bounds.right, lessThanOrEqualTo(header.right));
          expect(bounds.bottom, lessThanOrEqualTo(header.bottom));
          expect(find.text(text).hitTestable(), findsOneWidget);
        }
        if (width == 616) {
          expect(
            find.byKey(const ValueKey('album-metadata-full-row')),
            findsOneWidget,
          );
          expect(
            tester.getRect(find.byType(WideAlbumMetadata)).top,
            greaterThanOrEqualTo(
              tester.getRect(find.byType(PlayAllChip)).bottom,
            ),
          );
        }
        expect(api.offsets, [0]);
        expect(tester.takeException(), isNull);
        await _capture(tester, key, 'album-actions-${width.round()}');
      }
      // Both compact controls still perform the original queue actions.
      tester.view.physicalSize = const Size(528, 750);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PlayAllChip));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AddAllChip));
      await tester.pumpAndSettle();
      expect(api.replaced.single, [page.id]);
      expect(api.played.single, 0);
      expect(api.added.single.$1, [page.id]);
      expect(find.byTooltip('Added to queue'), findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
    },
  );

  testWidgets(
    'tracks move behind the transparent album bar and fade through its system inset',
    (tester) async {
      final key = GlobalKey();
      final container = await pumpHomeShell(
        tester,
        queue: SettableQueue(queueOf(1)),
        api: _HomeAlbumApi(
          _AlbumApi([for (var i = 1; i <= 40; i++) _track(i)]),
        ),
        size: const Size(1024, 600),
        themed: true,
        reducedMotion: true,
        captureKey: key,
      );
      tester.view.padding = const FakeViewPadding(top: 24);
      container
          .read(searchSessionProvider.notifier)
          .openCatalog(
            id: _page.id!,
            title: _page.title!,
            description: _page.description,
          );
      await tester.pumpAndSettle();
      final bar = tester.getRect(find.byType(WideAlbumHeader));
      final fade = find.byKey(const ValueKey('album-content-fade'));
      final cover = tester.getRect(find.byType(AlbumArtwork));
      expect(tester.getRect(fade).top, 0);
      expect(tester.getRect(_trackScroll).top, 0);
      expect(tester.widget<TopBarContentFade>(fade).extent, bar.bottom);
      final scroll = tester.state<ScrollableState>(_trackScroll).position;
      for (final fraction in [.75, .4, .1]) {
        final song = find.text('Song 3');
        scroll.jumpTo(
          scroll.pixels + tester.getCenter(song).dy - bar.height * fraction,
        );
        await tester.pumpAndSettle();
        expect(tester.getCenter(song).dy, closeTo(bar.height * fraction, .01));
        expect(song.hitTestable(), findsNothing);
        expect(find.byType(PlayAllChip).hitTestable(), findsOneWidget);
        expect(find.byType(AddAllChip).hitTestable(), findsOneWidget);
        expect(tester.getRect(find.byType(AlbumArtwork)), cover);
        await _capture(tester, key, 'album-fade-$fraction');
      }
      expect(tester.takeException(), isNull);
    },
  );

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
    final barBottom = tester.getRect(find.byType(WideAlbumHeader)).bottom + 12;
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
