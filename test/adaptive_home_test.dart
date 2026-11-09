import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/providers/pinned_catalogs_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/widgets/home/pinned_catalogs_section.dart';
import 'package:kalinka/widgets/home/preview_shelf.dart';
import 'package:kalinka/widgets/search_cards/search_track_row.dart';
import 'package:kalinka/widgets/search_cards/search_album_row.dart';
import 'package:kalinka/widgets/search_cards/search_folder_row.dart';
import 'package:kalinka/widgets/shelf_heading.dart';
import 'package:kalinka/widgets/search/search_session_view.dart';
import 'package:kalinka/widgets/now_playing_content.dart';

import 'support/adaptive_home_fixtures.dart';
import 'support/home_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final captures = Platform.environment['KALINKA_REVIEW_DIR'];
  final artDirectory = Platform.environment['KALINKA_REVIEW_ART'];

  setUpAll(() async {
    if (captures == null) return;
    for (final (family, file) in [
      ('IBM Plex Sans', 'IBMPlexSans-Regular.ttf'),
      ('IBM Plex Sans', 'IBMPlexSans-SemiBold.ttf'),
      ('IBM Plex Mono', 'IBMPlexMono-SemiBold.ttf'),
      ('Playfair Display', 'PlayfairDisplay-Regular.ttf'),
      ('KalinkaIcons', 'KalinkaIcons.ttf'),
    ]) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$file'))).load();
    }
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
          rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
        ))
        .load();
    final material = File(
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (material.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(ByteData.sublistView(material.readAsBytesSync())),
          ))
          .load();
    }
  });

  Future<void> warmArtwork(WidgetTester tester) async {
    if (artDirectory == null) return;
    final previousBudget = imageCache.maximumSizeBytes;
    imageCache.maximumSizeBytes = 512 << 20;
    addTearDown(() => imageCache.maximumSizeBytes = previousBudget);
    await tester.runAsync(() async {
      for (final file in Directory(
        artDirectory,
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.jpg'))) {
        final name = file.uri.pathSegments.last;
        final codec = await ui.instantiateImageCodec(await file.readAsBytes());
        final frame = await codec.getNextFrame();
        codec.dispose();
        final network = NetworkImage('https://review.invalid/$name');
        final providers = <ImageProvider>[
          network,
          for (var size = 64; size <= 512; size += 64)
            ResizeImage(network, width: size),
          ResizeImage(network, width: 132, height: 132),
          ResizeImage(network, width: 44, height: 44),
          ResizeImage(network, width: 1024),
        ];
        for (final provider in providers) {
          final key = await provider.obtainKey(ImageConfiguration.empty);
          imageCache.putIfAbsent(
            key,
            () => OneFrameImageStreamCompleter(
              Future.value(ImageInfo(image: frame.image.clone())),
            ),
          );
        }
        frame.image.dispose();
      }
    });
    addTearDown(() {
      imageCache.clear();
      imageCache.clearLiveImages();
    });
  }

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    if (captures == null) return;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$captures/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final (name, size, scenario, scale) in [
    ('three-pin-phone', const Size(390, 1200), 'three', 1.0),
    ('three-pin-desktop', const Size(1920, 1000), 'three', 1.0),
    ('three-pin-split-kiosk', const Size(1024, 600), 'three', 1.0),
    ('album-folder-and-tracks', const Size(1920, 1000), 'folders', 1.0),
    ('album-folder-phone', const Size(390, 844), 'album', 1.0),
    ('zero-pins', const Size(390, 844), 'zero', 1.0),
    ('shortcuts-only', const Size(390, 844), 'shortcuts', 1.0),
    ('one-catalogue', const Size(1920, 1000), 'catalogue', 1.0),
    ('small-phone-large-text', const Size(320, 700), 'three', 2.0),
    ('landscape-large-text', const Size(812, 375), 'three', 2.0),
  ]) {
    testWidgets('$name keeps previews usable and destinations intact', (
      tester,
    ) async {
      await warmArtwork(tester);
      final api = AdaptiveHomeApi(art: artDirectory != null);
      final key = GlobalKey();
      final container = await pumpHomeShell(
        tester,
        queue: SettableQueue(
          captures == null
              ? queueOf(0)
              : PlayQueueState(
                  playbackState: PlaybackState(
                    state: PlayerStateType.paused,
                    index: 0,
                  ),
                  trackList: [api.looseTracks.first.track!],
                  playbackMode: PlaybackMode.empty,
                  seq: 0,
                ),
        ),
        api: api,
        size: size,
        sources: demoSources,
        themed: true,
        captureKey: key,
        textScaler: TextScaler.linear(scale),
        reducedMotion: true,
        // The main shell currently chooses a single pane at 1024. Exercise
        // the same Home inside a 592dp split-kiosk pane as well, without
        // changing the application's navigation/player breakpoints.
        screen: size.width == 1024
            ? const Scaffold(
                body: Row(
                  children: [
                    Expanded(child: SearchSessionView()),
                    SizedBox(
                      width: 432,
                      child: NowPlayingContent(isTablet: true),
                    ),
                  ],
                ),
              )
            : null,
      );
      final pins = switch (scenario) {
        'three' => threePins,
        'folders' => [folderPin(album: true), folderPin()],
        'album' => [folderPin(album: true)],
        'shortcuts' =>
          threePins
              .map((pin) => pin.withPreview(HomePreviewType.compact))
              .toList(),
        'catalogue' => [awardsPin],
        _ => <PinnedCatalog>[],
      };
      for (final pin in pins) {
        await container.read(pinnedCatalogsProvider.notifier).pin(pin);
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(tester, key, name);

      if (scenario == 'zero' || scenario == 'shortcuts') {
        expect(find.text('What shall we play?'), findsOneWidget);
      }
      if (scenario == 'three') {
        final trackSection = find.byKey(ValueKey(threePins.first.key));
        final awardsSection = find.byKey(ValueKey(awardsPin.key));
        final artistSection = find.byKey(ValueKey(artistPin.key));
        if (size.width == 1920) {
          expect(
            find.byKey(const ValueKey('home-album-collage')),
            findsOneWidget,
          );
          expect(
            tester.getTopLeft(trackSection).dx,
            tester.getTopLeft(artistSection).dx,
          );
          expect(
            tester.getTopLeft(awardsSection).dx,
            greaterThan(tester.getTopLeft(trackSection).dx),
          );
          expect(
            tester.getTopLeft(artistSection).dy,
            greaterThan(tester.getTopLeft(trackSection).dy),
          );
          expect(
            find.descendant(
              of: find.byType(PinnedCatalogsSection),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.right,
              ),
            ),
            findsNothing,
          );
        } else {
          expect(
            find.byKey(const ValueKey('home-album-collage')),
            findsNothing,
          );
          await tester.ensureVisible(awardsSection);
          await tester.pumpAndSettle();
          expect(
            tester.getTopLeft(awardsSection).dy,
            greaterThan(tester.getTopLeft(trackSection).dy),
          );
          await tester.ensureVisible(artistSection);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (size.width == 1024) await capture(tester, key, '$name-scrolled');
        }
        expect(api.replaced, isEmpty);
      }
      if (scenario == 'folders' || scenario == 'album') {
        expect(find.text('Oxygène, Pt. 1'), findsNothing);
        expect(find.text('SUNDAY LISTENING'), findsOneWidget);
        final albumTile = find.byKey(
          ValueKey('home-album-${api.albums.first.id}'),
        );
        expect(albumTile, findsOneWidget);
        expect(tester.getSize(albumTile).width, lessThanOrEqualTo(198));
        if (scenario == 'folders') {
          expect(find.byType(SearchTrackRow), findsNWidgets(3));
          expect(find.text('A fourth track stays in the folder'), findsNothing);
          expect(
            tester
                .getTopLeft(
                  find.descendant(
                    of: find.byType(PinnedCatalogsSection),
                    matching: find.text('A Walk'),
                  ),
                )
                .dy,
            lessThan(tester.getTopLeft(find.text('Roygbiv')).dy),
          );
        }
        final heading = tester.widget<ShelfHeading>(
          find.descendant(
            of: find.byKey(ValueKey(pins.first.key)),
            matching: find.byType(ShelfHeading),
          ),
        );
        heading.onViewAll!();
        expect(
          container.read(searchSessionProvider).catalogPage.id,
          albumFolderId,
        );
        expect(api.replaced, isEmpty);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  List<PinnedCatalog> albumFolderPins(AdaptiveHomeApi api) {
    final first = folderPin(album: true);
    const secondId = 'kalinka:localfiles:catalog:folder-equinoxe';
    final second = PinnedCatalog(
      page: CatalogPage.fromJson({
        ...first.page.toJson(),
        'id': secondId,
        'title': '1978 - Jean-Michel Jarre - Equinoxe [FLAC]',
      }),
      filter: first.filter,
      preview: HomePreviewType.automatic,
    );
    final tracks = [
      for (var i = 0; i < 8; i++)
        demoTrack(
          'equinoxe-$i',
          'Équinoxe, Pt. $i',
          'Jean-Michel Jarre',
          album: api.albums[1].album,
        ),
    ];
    api.listings[secondId] = tracks;
    api.listings[api.albums[1].id] = tracks;
    return [first, second];
  }

  for (final (name, size, scale) in [
    ('grouped-album-folders-desktop', const Size(1920, 1000), 1.0),
    ('grouped-album-folders-phone', const Size(390, 1000), 1.0),
    ('grouped-album-folders-large-text', const Size(320, 700), 2.0),
  ]) {
    testWidgets(
      '$name shares compact space and keeps both folder destinations',
      (tester) async {
        await warmArtwork(tester);
        final api = AdaptiveHomeApi(art: artDirectory != null);
        final pins = albumFolderPins(api);
        final captureKey = GlobalKey();
        final container = await pumpHomeShell(
          tester,
          queue: SettableQueue(queueOf(0)),
          api: api,
          sources: demoSources,
          size: size,
          textScaler: TextScaler.linear(scale),
          themed: true,
          captureKey: captureKey,
        );
        final notifier = container.read(pinnedCatalogsProvider.notifier);
        await notifier.pin(awardsPin);
        for (final pin in pins) {
          await notifier.pin(pin);
        }
        await tester.pumpAndSettle();
        expect(find.byType(HomeAlbumFolderGroup), findsOneWidget);
        expect(find.text('PINNED FOLDERS'), findsOneWidget);
        expect(find.text('Sunday listening'), findsOneWidget);
        expect(find.text(pins[1].title.toUpperCase()), findsNothing);
        expect(find.text('Oxygène, Pt. 1'), findsNothing);
        final first = find.byKey(ValueKey(pins.first.key));
        final second = find.byKey(ValueKey(pins.last.key));
        expect(tester.getTopLeft(first).dy, tester.getTopLeft(second).dy);
        expect(
          tester.getTopLeft(second).dx,
          closeTo(tester.getTopRight(first).dx, 0.01),
        );
        expect(tester.getSize(first).width, lessThanOrEqualTo(198));
        expect(tester.takeException(), isNull);
        if (size.width < 800) {
          await tester.ensureVisible(find.byType(HomeAlbumFolderGroup));
          await tester.pumpAndSettle();
        }
        await capture(tester, captureKey, name);
        final navigation = container.read(searchSessionProvider.notifier);
        for (final pin in pins) {
          final card = find.byKey(ValueKey(pin.key));
          expect(
            find.descendant(of: card, matching: find.text('View All')),
            findsNothing,
          );
          await tester.ensureVisible(card);
          await tester.pumpAndSettle();
          await tester.tap(card);
          expect(
            container.read(searchSessionProvider).catalogPage.id,
            pin.page.id,
          );
          expect(
            container.read(searchSessionProvider).catalogFilter.toJson(),
            pin.filter.toJson(),
          );
          navigation.goBack();
          await tester.pumpAndSettle();
        }
        expect(api.replaced, isEmpty);
        expect(container.read(pinnedCatalogsProvider)!.map((pin) => pin.key), [
          awardsPin.key,
          ...pins.map((pin) => pin.key),
        ]);
      },
    );
  }

  testWidgets(
    'album groups follow reordering, stop at other pins and tolerate duplicate albums',
    (tester) async {
      final api = AdaptiveHomeApi();
      final pins = albumFolderPins(api);
      final container = await pumpHomeShell(
        tester,
        queue: SettableQueue(queueOf(0)),
        api: api,
        sources: demoSources,
        size: const Size(1920, 1000),
      );
      final notifier = container.read(pinnedCatalogsProvider.notifier);
      for (final pin in pins) {
        await notifier.pin(pin);
      }
      await tester.pumpAndSettle();
      expect(find.byType(HomeAlbumFolderGroup), findsOneWidget);
      await notifier.pin(folderPin().withPreview(HomePreviewType.compact));
      await notifier.reorder(2, 1);
      await tester.pumpAndSettle();
      expect(find.byType(HomeAlbumFolderGroup), findsNothing);
      await notifier.setPreview(folderPin().key, HomePreviewType.automatic);
      await tester.pumpAndSettle();
      expect(find.byType(HomeAlbumFolderGroup), findsNothing);
      expect(find.byType(SearchTrackRow), findsNWidgets(3));
      await notifier.reorder(1, 3);
      await tester.pumpAndSettle();
      expect(find.byType(HomeAlbumFolderGroup), findsOneWidget);
      await notifier.unpin(folderPin().key);
      // Another path to the same album must retain a distinct card/destination.
      const duplicateId = 'kalinka:localfiles:catalog:another-oxygene-folder';
      final duplicate = PinnedCatalog(
        page: CatalogPage.fromJson({
          ...pins.first.page.toJson(),
          'id': duplicateId,
        }),
        filter: pins.first.filter,
        preview: HomePreviewType.automatic,
        homeName: 'Another copy',
      );
      api.listings[duplicateId] = api.albumTracks;
      await notifier.pin(duplicate);
      await tester.pumpAndSettle();
      expect(find.byType(HomeAlbumFolderGroup), findsOneWidget);
      expect(find.byKey(ValueKey(duplicate.key)), findsOneWidget);
      expect(find.text('Another copy'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await notifier.unpin(pins.first.key);
      await notifier.unpin(duplicate.key);
      await tester.pumpAndSettle();
      expect(find.byType(HomeAlbumFolderGroup), findsNothing);
      expect(find.text(pins.last.title.toUpperCase()), findsOneWidget);
    },
  );

  testWidgets(
    'a left-hand collage stacks the next album pin below the right shelf',
    (tester) async {
      await warmArtwork(tester);
      final api = AdaptiveHomeApi(art: artDirectory != null);
      const releasesId = 'kalinka:qobuz:catalog:new-releases';
      const albumsId = 'kalinka:localfiles:catalog:albums';
      final releasesPin = PinnedCatalog(
        page: CatalogPage.category(
          id: releasesId,
          title: 'New Releases',
          provider: 'Qobuz',
          description: "New albums spotlighted by Qobuz’s editors",
          preview: Preview(
            type: PreviewType.imageText,
            cardSize: CardSize.small,
          ),
        ),
        filter: awardsPin.filter,
        preview: HomePreviewType.automatic,
      );
      final albumsPin = PinnedCatalog(
        page: CatalogPage.category(
          id: albumsId,
          title: 'Albums',
          provider: 'My Library',
          description: 'Recently added albums',
          preview: Preview(
            type: PreviewType.imageText,
            cardSize: CardSize.small,
          ),
        ),
        filter: awardsPin.filter,
        preview: HomePreviewType.automatic,
      );
      api.listings[awardsId] = [
        ...api.awards,
        for (final album in api.albums.take(2))
          demoAlbum(
            album.id.split(':').last,
            album.album!.title,
            album.album!.artist!.name,
            source: 'qobuz',
            art: artDirectory != null,
          ),
      ];
      api.listings[releasesId] = api.awards;
      api.listings[albumsId] = api.albums;
      final captureKey = GlobalKey();
      final container = await pumpHomeShell(
        tester,
        queue: SettableQueue(queueOf(0)),
        api: api,
        sources: demoSources,
        size: const Size(1920, 1000),
        themed: true,
        captureKey: captureKey,
      );
      final notifier = container.read(pinnedCatalogsProvider.notifier);
      await notifier.pin(awardsPin);
      await notifier.pin(releasesPin);
      await tester.pumpAndSettle();
      await notifier.pin(albumsPin);
      await tester.pumpAndSettle();

      final awards = find.byKey(ValueKey(awardsPin.key));
      final releases = find.byKey(ValueKey(releasesPin.key));
      final albums = find.byKey(ValueKey(albumsPin.key));
      expect(tester.getTopLeft(albums).dx, tester.getTopLeft(releases).dx);
      expect(
        tester.getTopLeft(albums).dx,
        greaterThan(tester.getTopLeft(awards).dx),
      );
      expect(
        tester.getTopLeft(albums).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(releases).dy),
      );
      expect(
        tester.getTopLeft(albums).dy,
        lessThan(tester.getBottomLeft(awards).dy),
      );
      expect(tester.takeException(), isNull);
      await capture(tester, captureKey, 'left-collage-albums-stacked');

      tester.view.physicalSize = const Size(390, 1200);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(awards).dx, tester.getTopLeft(releases).dx);
      expect(tester.getTopLeft(releases).dx, tester.getTopLeft(albums).dx);
      expect(
        tester.getTopLeft(releases).dy,
        greaterThan(tester.getTopLeft(awards).dy),
      );
      expect(
        tester.getTopLeft(albums).dy,
        greaterThan(tester.getTopLeft(releases).dy),
      );
      expect(container.read(pinnedCatalogsProvider)!.map((pin) => pin.key), [
        awardsPin.key,
        releasesPin.key,
        albumsPin.key,
      ]);

      // A shortcut between the shelves must still prevent stacking across it.
      tester.view.physicalSize = const Size(1920, 1000);
      await notifier.pin(folderPin().withPreview(HomePreviewType.compact));
      await notifier.reorder(3, 2);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(albums).dy,
        greaterThan(tester.getBottomLeft(awards).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Large preview can be selected for a standard catalogue and restored to Automatic',
    (tester) async {
      await warmArtwork(tester);
      final api = AdaptiveHomeApi(art: artDirectory != null);
      const releasesId = 'kalinka:qobuz:catalog:new-releases';
      final pin = PinnedCatalog(
        page: CatalogPage.category(
          id: releasesId,
          title: 'New Releases',
          provider: 'Qobuz',
          preview: Preview(
            type: PreviewType.imageText,
            cardSize: CardSize.small,
          ),
        ),
        filter: awardsPin.filter,
        preview: HomePreviewType.automatic,
      );
      api.listings[releasesId] = [
        ...api.awards,
        for (final album in api.albums.take(2))
          demoAlbum(
            album.id.split(':').last,
            album.album!.title,
            album.album!.artist!.name,
            source: 'qobuz',
            art: artDirectory != null,
          ),
      ];
      final captureKey = GlobalKey();
      final container = await pumpHomeShell(
        tester,
        queue: SettableQueue(queueOf(0)),
        api: api,
        sources: demoSources,
        size: const Size(1920, 1000),
        themed: true,
        captureKey: captureKey,
      );
      final notifier = container.read(pinnedCatalogsProvider.notifier);
      for (final item in [folderPin(), pin, artistPin]) {
        await notifier.pin(item);
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-album-collage')), findsNothing);
      await tester.ensureVisible(find.text('Customise Home'));
      await tester.tap(find.text('Customise Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Preview for New Releases'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-preview-option-large')));
      await tester.pumpAndSettle();
      expect(
        container.read(pinnedCatalogsProvider)![1].preview,
        HomePreviewType.large,
      );
      await capture(tester, captureKey, 'large-preview-picker');
      // Back first dismisses the picker, then returns from Customise Home.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-album-collage')), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(ValueKey(artistPin.key))).dx,
        tester.getTopLeft(find.byKey(ValueKey(folderPin().key))).dx,
      );
      await capture(tester, captureKey, 'large-preview-new-releases');
      final saved = container.read(pinnedCatalogsProvider)![1];
      expect(saved.page.preview!.cardSize, CardSize.small);
      expect(saved.key, pin.key);
      tester.view.physicalSize = const Size(390, 1000);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-album-collage')), findsNothing);
      expect(
        container.read(pinnedCatalogsProvider)![1].preview,
        HomePreviewType.large,
      );
      tester.view.physicalSize = const Size(1920, 1000);
      await notifier.setPreview(pin.key, HomePreviewType.automatic);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-album-collage')), findsNothing);
      expect(
        find.byKey(const ValueKey('home-album-bounded-row')),
        findsWidgets,
      );
      expect(api.replaced, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (large, forced) in [(true, false), (false, false), (true, true)]) {
    testWidgets(
      '${forced
          ? 'User-chosen collage'
          : large
          ? 'Collage'
          : 'Equal row'} fills its column and loads more albums as it grows',
      (tester) async {
        final api = AdaptiveHomeApi();
        api.listings[awardsId] = [
          for (var i = 0; i < 32; i++)
            demoAlbum('award-$i', 'Award $i', 'Artist $i', source: 'qobuz'),
        ];
        final pin = PinnedCatalog(
          page: CatalogPage.fromJson({
            ...awardsPin.page.toJson(),
            'preview': Preview(
              type: PreviewType.imageText,
              cardSize: large && !forced ? CardSize.large : CardSize.small,
            ).toJson(),
          }),
          filter: awardsPin.filter,
          preview: forced ? HomePreviewType.large : HomePreviewType.automatic,
        );
        final width = ValueNotifier(360.0);
        addTearDown(width.dispose);
        await pumpHomeShell(
          tester,
          queue: SettableQueue(queueOf(0)),
          api: api,
          sources: demoSources,
          size: const Size(2000, 1000),
          screen: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: ValueListenableBuilder<double>(
                valueListenable: width,
                builder: (_, value, _) => SizedBox(
                  width: value,
                  child: PinnedCatalogPreview(pin: pin, wide: true),
                ),
              ),
            ),
          ),
        );
        var previousCount = 0;
        for (final size in [
          360.0,
          480.0,
          520.0,
          600.0,
          720.0,
          880.0,
          1248.0,
          1800.0,
        ]) {
          width.value = size;
          await tester.pumpAndSettle();
          final tiles = find.byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'home-album-kalinka:',
                ),
          );
          final rects = tiles
              .evaluate()
              .map((element) => tester.getRect(find.byWidget(element.widget)))
              .toList();
          final shelf = tester.getRect(find.byType(AdaptiveAlbumPreview));
          expect(tester.takeException(), isNull, reason: 'width $size');
          expect(rects.length, greaterThanOrEqualTo(previousCount));
          expect(rects.first.left, closeTo(shelf.left, 0.01));
          // A full first row uses the whole allocated column, including frames.
          final firstRow = rects.where(
            (rect) => (rect.top - rects.first.top).abs() < 0.01,
          );
          expect(firstRow.last.right, closeTo(shelf.right, 0.01));
          for (final rect in rects) {
            expect(rect.right, lessThanOrEqualTo(shelf.right + 0.01));
          }
          if (large) {
            expect(rects.first.width, greaterThan(rects[1].width));
            expect(rects.first.width, lessThanOrEqualTo(350.01));
            expect(rects[1].width, lessThanOrEqualTo(182.01));
            expect(rects.last.top, greaterThan(rects.first.top));
          } else {
            for (final rect in rects) {
              expect(rect.width, closeTo(rects.first.width, 0.01));
              expect(rect.top, closeTo(rects.first.top, 0.01));
              expect(rect.width, lessThanOrEqualTo(198.01));
            }
          }
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.right,
            ),
            findsNothing,
          );
          previousCount = rects.length;
        }
        expect(previousCount, greaterThan(8));
        expect(
          api.calls.where((call) => call.id == awardsId).last.limit,
          greaterThan(8),
        );
        final loads = api.calls.where((call) => call.id == awardsId).length;
        expect(loads, lessThanOrEqualTo(large ? 3 : 2));
        for (final size in [520.0, 1248.0, 1800.0]) {
          width.value = size;
          await tester.pumpAndSettle();
        }
        expect(api.calls.where((call) => call.id == awardsId).length, loads);
        expect(api.replaced, isEmpty);
      },
    );
  }

  for (final columns in [2, 3, 4]) {
    testWidgets('$columns equal Home columns use all their available width', (
      tester,
    ) async {
      final api = AdaptiveHomeApi();
      final pins = [
        for (var i = 0; i < columns; i++)
          PinnedCatalog(
            page: CatalogPage.category(
              id: 'kalinka:qobuz:catalog:section-$i',
              title: 'Catalogue $i',
              provider: 'Qobuz',
              preview: Preview(
                type: PreviewType.imageText,
                cardSize: i == 0 ? CardSize.large : CardSize.small,
              ),
            ),
            filter: awardsPin.filter,
            preview: HomePreviewType.automatic,
          ),
      ];
      for (final pin in pins) {
        api.listings[pin.page.id!] = [
          for (var i = 0; i < 24; i++)
            demoAlbum(
              '${pin.page.id!}-$i',
              'Album $i',
              'Artist',
              source: 'qobuz',
            ),
        ];
      }
      await pumpHomeShell(
        tester,
        queue: SettableQueue(queueOf(0)),
        api: api,
        sources: demoSources,
        size: Size(columns * 552 - 32, 1000),
        screen: Scaffold(body: PinnedCatalogsSection(pins: pins)),
      );
      final shelves = find
          .byType(AdaptiveAlbumPreview)
          .evaluate()
          .map((element) => tester.getRect(find.byWidget(element.widget)))
          .toList();
      expect(shelves.length, columns);
      for (var i = 0; i < columns; i++) {
        expect(shelves[i].width, closeTo(520, 0.01));
        expect(shelves[i].left, closeTo(i * 552, 0.01));
        expect(shelves[i].top, shelves.first.top);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Small preview overrides a large plugin hint and Automatic restores it',
    (tester) async {
      final api = AdaptiveHomeApi();
      final container = await pumpHomeShell(
        tester,
        queue: SettableQueue(queueOf(0)),
        api: api,
        sources: demoSources,
        size: const Size(1920, 1000),
      );
      final notifier = container.read(pinnedCatalogsProvider.notifier);
      await notifier.pin(awardsPin);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-album-collage')), findsOneWidget);
      await notifier.setPreview(awardsPin.key, HomePreviewType.preview);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-album-collage')), findsNothing);
      expect(
        find.byKey(const ValueKey('home-album-bounded-row')),
        findsOneWidget,
      );
      expect(
        container.read(pinnedCatalogsProvider)!.single.page.preview!.cardSize,
        CardSize.large,
      );
      await notifier.setPreview(awardsPin.key, HomePreviewType.automatic);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-album-collage')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a phone artist shelf builds only nearby covers and reuses its listing while scrolling',
    (tester) async {
      final api = AdaptiveHomeApi();
      api.listings[artistId] = [
        for (var i = 0; i < 100; i++)
          demoAlbum('artist-album-$i', 'Album $i', 'Artist'),
      ];
      final container = await pumpHomeShell(
        tester,
        queue: SettableQueue(queueOf(0)),
        api: api,
        sources: demoSources,
        size: const Size(390, 844),
      );
      await container.read(pinnedCatalogsProvider.notifier).pin(artistPin);
      await tester.pumpAndSettle();
      final tiles = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'home-album-kalinka:',
            ),
      );
      expect(tiles.evaluate().length, inInclusiveRange(3, 6));
      expect(find.text('Album 99'), findsNothing);
      final scroll = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(AdaptiveAlbumPreview),
          matching: find.byType(Scrollable),
        ),
      );
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('Album 99'), findsOneWidget);
      expect(tiles.evaluate().length, lessThanOrEqualTo(6));
      expect(api.calls.where((call) => call.id == artistId), hasLength(1));
      await tester.tap(find.text('Album 99'));
      expect(
        container.read(searchSessionProvider).catalogPage.id,
        api.listings[artistId]!.last.id,
      );
      expect(api.replaced, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'phone albums swipe and local artist covers open their own albums',
    (tester) async {
      final api = AdaptiveHomeApi();
      final container = await pumpHomeShell(
        tester,
        queue: SettableQueue(queueOf(0)),
        api: api,
        sources: demoSources,
      );
      await container.read(pinnedCatalogsProvider.notifier).pin(artistPin);
      await tester.pumpAndSettle();
      final row = find.byType(AdaptiveAlbumPreview);
      final rail = find.descendant(of: row, matching: find.byType(ListView));
      final third = find.byKey(ValueKey('home-album-${api.albums[2].id}'));
      expect(tester.getRect(third).left, lessThan(tester.getRect(row).right));
      expect(
        tester.getRect(third).right,
        greaterThan(tester.getRect(row).right),
      );
      await tester.drag(rail, const Offset(-250, 0));
      await tester.pumpAndSettle();
      await tester.tap(third);
      expect(
        container.read(searchSessionProvider).catalogPage.id,
        api.albums[2].id,
      );
      expect(api.replaced, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rows play through the existing actions and mixed children stay ordered',
    (tester) async {
      final api = AdaptiveHomeApi();
      final container = await pumpHomeShell(
        tester,
        queue: SettableQueue(queueOf(0)),
        api: api,
        sources: demoSources,
      );
      await container.read(pinnedCatalogsProvider.notifier).pin(folderPin());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Roygbiv'));
      await tester.pumpAndSettle();
      expect(api.replaced, [
        [api.looseTracks[1].id],
      ]);
      expect(api.played, [0]);
      api.listings[folderId] = [
        api.looseTracks.first,
        api.albums.first,
        BrowseItem(
          id: 'kalinka:localfiles:catalog:subfolder',
          name: 'A subfolder',
          canBrowse: true,
          canAdd: false,
          catalog: Catalog(
            id: 'kalinka:localfiles:catalog:subfolder',
            title: 'A subfolder',
            previewConfig: Preview(type: PreviewType.folder),
          ),
        ),
      ];
      container.read(searchSessionProvider.notifier).refreshAll();
      await tester.pumpAndSettle();
      expect(find.byType(SearchTrackRow), findsOneWidget);
      expect(find.byType(SearchAlbumRow), findsOneWidget);
      expect(find.byType(SearchFolderRow), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(SearchTrackRow)).dy,
        lessThan(tester.getTopLeft(find.byType(SearchAlbumRow)).dy),
      );
      expect(
        tester.getTopLeft(find.byType(SearchAlbumRow)).dy,
        lessThan(tester.getTopLeft(find.byType(SearchFolderRow)).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
