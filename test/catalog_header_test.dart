import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/browse_filters.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/storage.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/providers/kiosk_provider.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/browse_filters/search_filter_overlay.dart';
import 'package:kalinka/widgets/browse_filters/presentation_toggle.dart';
import 'package:kalinka/widgets/browse_filters/active_filter_chips.dart';
import 'package:kalinka/widgets/home/catalog_pin_button.dart';
import 'package:kalinka/widgets/kalinka_back_button.dart';
import 'package:kalinka/widgets/server_chip.dart';
import 'package:kalinka/widgets/search/album_page_header.dart';
import 'package:kalinka/widgets/search/catalog_page_view.dart';
import 'package:kalinka/widgets/search/catalog_sliver_header.dart';
import 'package:kalinka/widgets/search/folder_page_actions.dart';
import 'package:kalinka/widgets/search/folder_trail.dart';
import 'package:kalinka/widgets/breadcrumb_crumb.dart';
import 'package:kalinka/widgets/search/search_session_view.dart';
import 'package:kalinka/widgets/search/track_group_actions.dart';
import 'package:kalinka/widgets/search_cards/search_track_row.dart';
import 'package:kalinka/widgets/search_cards/artwork_grid_card.dart';
import 'package:kalinka/widgets/search_cards/row_columns.dart';
import 'package:kalinka/widgets/column_separator.dart';
import 'package:kalinka/widgets/top_bar_content_fade.dart';

import 'support/focus.dart';
import 'support/home_shell.dart';

final _catalog = CatalogPage.category(
  id: 'kalinka:jamendo:catalog:albums',
  title: 'Albums',
  provider: 'Jamendo',
  preview: Preview(
    type: PreviewType.tile,
    contentType: PreviewContentType.album,
  ),
  filters: const [
    FilterSpec(id: 'q', kind: FilterKind.text, label: 'Search albums'),
    FilterSpec(
      id: 'genre',
      kind: FilterKind.choice,
      label: 'Genre',
      ops: [FilterOp.any],
    ),
  ],
);
final _expanded = find.byKey(const ValueKey('catalog-expanded-title'));
final _collapsed = find.byKey(const ValueKey('catalog-collapsed-title'));
final _barFilters = find.byKey(const ValueKey('bar-filters'));
final _surface = find.byKey(const ValueKey('catalog-header-surface'));

/// Where the header ends and the content starts, across the gutters. Fully
/// collapsed, the header has no height and counts as offstage.
Rect _foot(WidgetTester tester) {
  final surface = tester.getRect(
    find.byKey(const ValueKey('catalog-header-surface'), skipOffstage: false),
  );
  return Rect.fromLTRB(
    surface.left + 16,
    surface.bottom,
    surface.right - 16,
    surface.bottom,
  );
}

final _barSearch = find.byKey(const ValueKey('catalog-bar-search'));
final _unrolled = find.byKey(const ValueKey('catalog-unrolled-search'));
final _barField = find.byKey(const ValueKey('catalog-bar-field'));

/// A control still in the page's header, not the bar's.
Finder _inPage(Finder matching) =>
    find.descendant(of: find.byType(CatalogPageView), matching: matching);
Finder get _scrollable => find
    .descendant(
      of: find.byType(CatalogPageView),
      matching: find.byType(Scrollable),
    )
    .first;

class _Api extends HomeApi {
  final bool catalogs;
  final bool tracks;
  final bool artists;
  final int count;
  final String Function(int)? albumTitle;
  final bool fail;
  final Completer<void>? gate;
  final Completer<void>? albumGate;
  final calls = <({String id, int offset, String? filter})>[];
  final replaced = <List<String>>[];
  final enqueued = <List<String>>[];
  final played = <int?>[];
  _Api({
    this.count = 80,
    this.albumTitle,
    this.fail = false,
    this.gate,
    this.albumGate,
    this.catalogs = false,
    this.tracks = false,
    this.artists = false,
  });

  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async {
    calls.add((id: id, offset: offset, filter: filter));
    if (gate != null) await gate!.future;
    if (id.contains(':album:')) await albumGate?.future;
    if (fail) throw StateError('offline');
    final playlist = id.contains(':playlist:');
    return BrowseItemsList(offset, limit, count, [
      for (var i = offset; i < count && i < offset + limit; i++)
        if (catalogs)
          BrowseItem(
            id: 'kalinka:jamendo:catalog:$i',
            name: [
              'Shortcuts',
              'Custom mixes',
              'Suggested new albums for you',
            ][i % 3],
            canBrowse: true,
            canAdd: false,
            catalog: Catalog(id: '$i', title: 'Category $i'),
          )
        else if (playlist || tracks || id.contains(':album:'))
          BrowseItem(
            id: 'kalinka:jamendo:track:$i',
            canAdd: true,
            canBrowse: false,
            track: Track(
              id: '$i',
              title: 'Track $i',
              duration: 180,
              album: tracks ? Album(id: 'a', title: 'Midnight journeys') : null,
              performer: tracks && i > 0
                  ? Artist(id: 'p', name: 'Night traveller')
                  : null,
            ),
          )
        else if (artists)
          BrowseItem(
            id: 'kalinka:jamendo:artist:$i',
            name: 'Artist $i',
            canBrowse: true,
            canAdd: false,
            artist: Artist(
              id: '$i',
              name: 'Artist $i',
              albumCount: i.isEven ? 3 : null,
            ),
          )
        else
          BrowseItem(
            id: 'kalinka:jamendo:album:$i',
            name: 'Album $i',
            canAdd: true,
            canBrowse: true,
            album: Album(
              id: '$i',
              title: albumTitle?.call(i) ?? 'Album $i',
              artist: Artist(id: 'a', name: 'Northern Lights'),
            ),
          ),
    ]);
  }

  @override
  Future<FilterValueList> getFilterValues(
    String catalogId,
    String field, {
    int offset = 0,
    int limit = 50,
    String query = '',
  }) async => const FilterValueList(offset: 0, limit: 50, total: 0, items: []);
  @override
  Future<StatusMessage> add(List<String> items, {int? index}) async {
    enqueued.add(items);
    return StatusMessage(count: count);
  }

  @override
  Future<StatusMessage> replace(List<String> items) async {
    replaced.add(items);
    return StatusMessage(count: count);
  }

  @override
  Future<StatusMessage> play([int? index]) async {
    played.add(index);
    return StatusMessage();
  }
}

class _DriveApi extends _Api {
  _DriveApi() : super(tracks: true);

  @override
  Future<List<StorageVolume>> listStorageVolumes() async => const [
    StorageVolume(
      id: 'music',
      kind: VolumeKind.removable,
      label: 'Music',
      mountPoint: '/media/music',
    ),
  ];

  @override
  Future<StorageLocation> storageLocation(String id) async => StorageLocation(
    volumeId: 'music',
    subpath: id.endsWith(':root') ? '' : 'Albums',
    path: '/media/music/Albums',
    library: const LocationLibrary(
      module: 'localfiles',
      title: 'My Library',
      holds: true,
      libraryEmpty: false,
      removable: false,
      restartRequired: false,
    ),
  );
}

final _barPresentation = find.byKey(const ValueKey('catalog-bar-presentation'));

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _Api api, {
  Size size = const Size(1200, 800),
  double scale = 1,
  double topInset = 0,
  CatalogPage? page,
  Key? captureKey,
  bool settle = true,
}) async {
  final container = await pumpHomeShell(
    tester,
    queue: SettableQueue(queueOf(0)),
    api: api,
    size: size,
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            padding: EdgeInsets.only(top: topInset),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: RepaintBoundary(
          key: captureKey,
          child: const Scaffold(body: SearchSessionView()),
        ),
      ),
    ),
  );
  container.read(searchSessionProvider.notifier).openPage(page ?? _catalog);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return container;
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
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
          rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
        ))
        .load();
    for (final (family, file) in [
      ('IBM Plex Sans', 'IBMPlexSans-Regular.ttf'),
      ('IBM Plex Mono', 'IBMPlexMono-Regular.ttf'),
      ('Playfair Display', 'PlayfairDisplay-Regular.ttf'),
    ]) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$file'))).load();
    }
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

  testWidgets(
    'one arrow moves one album card and hover and focus reuse the covers',
    (tester) async {
      final api = _Api(
        count: 1000,
        albumTitle: (i) => i == 1
            ? 'An album with a long title that wraps across two lines'
            : 'Album $i',
      );
      final container = await pumpHomeShell(
        tester,
        api: api,
        queue: SettableQueue(queueOf(0)),
        size: const Size(1440, 900),
      );
      container
          .read(searchSessionProvider.notifier)
          .openPage(
            CatalogPage.category(
              id: _catalog.id,
              title: 'Albums',
              preview: Preview(
                type: PreviewType.imageText,
                contentType: PreviewContentType.album,
              ),
            ),
          );
      await tester.pumpAndSettle();
      final cards = find.byType(ArtworkGridCard);
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await tester.pumpAndSettle();
      final first = cards.at(0), second = cards.at(1);
      final center1 = tester.getCenter(first),
          center2 = tester.getCenter(second);
      final row = tester.getTopLeft(first).dy;
      expect(tester.getTopLeft(second).dy, closeTo(row, 1));
      expect(
        tester.getSize(second).height,
        greaterThan(tester.getSize(first).height),
      );
      final cover = find
          .descendant(of: first, matching: find.byType(AspectRatio))
          .first;
      final before = tester.widget(cover);
      await mouse.moveTo(center1);
      await tester.pump();
      final hovered = tester.widget(cover);
      await mouse.moveTo(center2);
      await tester.pump();
      traversableFocusNodesIn(first).single.requestFocus();
      await tester.pump();
      final focused = tester.widget(cover);
      for (final (key, targetRow, targetColumn) in [
        (LogicalKeyboardKey.arrowDown, 1, 0),
        (LogicalKeyboardKey.arrowUp, 0, 0),
        (LogicalKeyboardKey.arrowRight, 0, 1),
        (LogicalKeyboardKey.arrowDown, 1, 1),
        (LogicalKeyboardKey.arrowLeft, 1, 0),
        (LogicalKeyboardKey.arrowUp, 0, 0),
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pump();
        // The first navigation key gives the grid the icon rail's extra room.
        final columns = List.generate(cards.evaluate().length, cards.at)
            .takeWhile((card) => (tester.getTopLeft(card).dy - row).abs() < 1)
            .length;
        final index = targetRow * columns + targetColumn;
        expect(
          focusIsOn(cards.at(index)),
          isTrue,
          reason: 'One ${key.keyLabel} to card $index',
        );
      }
      expect(hovered, same(before));
      expect(focused, same(before));
    },
  );

  for (final (width, scale, topInset) in [
    (528.0, 1.0, 0.0),
    (760.0, 1.0, 0.0),
    (936.0, 1.0, 24.0),
    (1600.0, 1.0, 0.0),
    (936.0, 2.0, 24.0),
    (1600.0, 2.0, 0.0),
    (936.0, 3.0, 24.0),
    (2400.0, 3.0, 0.0),
  ]) {
    testWidgets(
      'catalogue and album controls stay aligned at $width and ${scale}x text',
      (tester) async {
        final key = GlobalKey();
        final container = await _pump(
          tester,
          _Api(count: 44),
          size: Size(width, 800),
          scale: scale,
          topInset: topInset,
          captureKey: key,
        );
        final back = tester.getRect(find.byType(KalinkaBackButton));
        final status = tester.getRect(find.byType(ServerChip));
        final lastAction = tester.getRect(_barPresentation);
        final catalogTitle = find.byKey(
          const ValueKey('catalog-compact-title'),
        );
        final titleLeft = catalogTitle.evaluate().isEmpty
            ? null
            : tester.getRect(catalogTitle).left;
        await _capture(tester, key, 'toolbar-catalogue-$width-$scale');

        for (final (title, artist) in [
          ('Abbey Road', 'The Beatles'),
          (
            'The Best Of Michael Jackson (Anniversary Edition)',
            'Michael Jackson and the Royal Philharmonic Orchestra',
          ),
        ]) {
          container
              .read(searchSessionProvider.notifier)
              .openPage(
                CatalogPage.category(
                  id: 'kalinka:jamendo:album:comparison',
                  title: title,
                  description: artist,
                  provider: 'Jamendo',
                  totalDurationSeconds: 7800,
                ),
              );
          await tester.pumpAndSettle();
          expect(find.byType(WideAlbumHeader), findsOneWidget);
          expect(tester.getRect(find.byType(KalinkaBackButton)), back);
          expect(tester.getRect(find.byType(ServerChip)), status);
          if (titleLeft != null) {
            expect(
              tester
                  .getRect(find.byKey(const ValueKey('album-bar-title')))
                  .left,
              titleLeft,
            );
          }
          for (final action in [PlayAllChip, AddAllChip]) {
            final bounds = tester.getRect(find.byType(action));
            expect(bounds.center.dy, closeTo(back.center.dy, .01));
            expect(find.byType(action).hitTestable(), findsOneWidget);
          }
          expect(
            tester.getRect(find.byType(AddAllChip)).right,
            lastAction.right,
          );
          final metadata = tester.getRect(find.byType(WideAlbumMetadata));
          expect(metadata.top, greaterThanOrEqualTo(back.bottom));
          expect(metadata.right, lessThanOrEqualTo(width));
          await _capture(tester, key, 'toolbar-album-$width-$scale-$title');

          final play = tester.getRect(find.byType(PlayAllChip));
          final enqueue = tester.getRect(find.byType(AddAllChip));
          tester.state<ScrollableState>(_scrollable).position.jumpTo(400);
          await tester.pumpAndSettle();
          expect(tester.getRect(find.byType(KalinkaBackButton)), back);
          expect(tester.getRect(find.byType(ServerChip)), status);
          expect(tester.getRect(find.byType(PlayAllChip)), play);
          expect(tester.getRect(find.byType(AddAllChip)), enqueue);
          await tester.tap(find.byType(KalinkaBackButton));
          await tester.pumpAndSettle();
          expect(
            container.read(searchSessionProvider).catalogPage.id,
            _catalog.id,
          );
          expect(tester.getRect(find.byType(KalinkaBackButton)), back);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets('cached catalog headers follow width changes without reloading', (
    tester,
  ) async {
    final api = _Api();
    final container = await _pump(tester, api, size: const Size(936, 600));
    final nav = container.read(searchSessionProvider.notifier);
    final pageState = tester.state(find.byType(CatalogPageView));
    final scroll = tester.state<ScrollableState>(_scrollable);
    final requests = api.calls.where((call) => call.id == _catalog.id).length;
    final compactTitle = find.byKey(const ValueKey('catalog-compact-title'));

    for (final width in [540.0, 685.0, 936.0]) {
      tester.view.physicalSize = Size(width, 600);
      await tester.pumpAndSettle();
      expect(
        tester.widget<CatalogPageView>(find.byType(CatalogPageView)).titleInBar,
        width >= 600,
      );
      expect(
        (width >= 600 ? compactTitle : _expanded).hitTestable(),
        findsOneWidget,
      );
      expect(find.byType(CatalogPinButton).hitTestable(), findsOneWidget);
      expect(tester.state(find.byType(CatalogPageView)), same(pageState));
      expect(tester.state<ScrollableState>(_scrollable), same(scroll));
    }

    scroll.position.jumpTo(240);
    await tester.pumpAndSettle();
    for (final width in [540.0, 685.0, 936.0]) {
      tester.view.physicalSize = Size(width, 600);
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, closeTo(240, .01));
      expect(find.byType(CatalogPinButton).hitTestable(), findsOneWidget);
    }

    // A page retained behind another visit must also adopt the new mode.
    nav.openCatalog(id: 'kalinka:jamendo:catalog:other', title: 'Other');
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(540, 600);
    await tester.pumpAndSettle();
    nav.goBack();
    await tester.pumpAndSettle();
    expect(
      tester.widget<CatalogPageView>(find.byType(CatalogPageView)).titleInBar,
      isFalse,
    );
    expect(tester.state(find.byType(CatalogPageView)), same(pageState));
    expect(tester.state<ScrollableState>(_scrollable), same(scroll));
    expect(scroll.position.pixels, closeTo(240, .01));
    expect(find.byType(CatalogPinButton).hitTestable(), findsOneWidget);
    expect(api.calls.where((call) => call.id == _catalog.id).length, requests);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Albums uses the toolbar space and bounds its opened search', (
    tester,
  ) async {
    final key = GlobalKey();
    final container = await _pump(
      tester,
      _Api(count: 20),
      size: const Size(685, 640),
      captureKey: key,
      page: CatalogPage.category(
        id: 'kalinka:localfiles:catalog:albums',
        title: 'Albums',
        description: 'All your albums',
        provider: 'My Library',
        preview: Preview(
          type: PreviewType.imageText,
          contentType: PreviewContentType.album,
        ),
        filters: _catalog.filters,
      ),
    );
    final title = find.byKey(const ValueKey('catalog-compact-title'));
    final subtitle = find.byKey(const ValueKey('catalog-toolbar-subtitle'));
    expect(_expanded, findsNothing);
    expect(title, findsOneWidget);
    expect(subtitle, findsOneWidget);
    expect(_inPage(subtitle), findsNothing);
    expect(find.text('All your albums · 20 albums'), findsOneWidget);
    expect(_barSearch, findsOneWidget);
    expect(
      tester.getRect(title).center.dy,
      closeTo(tester.getRect(find.byType(KalinkaBackButton)).center.dy, 1),
    );
    expect(
      tester.getRect(title).right,
      lessThan(tester.getRect(_barSearch).left),
    );
    expect(
      tester.getRect(find.byType(ArtworkGridCard).first).top,
      lessThan(95),
    );
    await _capture(tester, key, 'albums-medium-toolbar');

    await tester.tap(_barSearch);
    await tester.pumpAndSettle();
    final bounds = tester.getRect(_unrolled);
    expect(bounds.width, 360);
    expect(bounds.right, 685 - 16);
    expect(bounds.top, greaterThanOrEqualTo(tester.getRect(subtitle).bottom));
    await _capture(tester, key, 'albums-medium-search-open');
    await tester.enterText(find.byType(TextField), 'blue');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(_unrolled, findsNothing);
    expect(find.text('“blue”'), findsOneWidget);
    final calls = container.read(searchSessionProvider).visitId;

    // Even just above this width the field fits beside the title and controls.
    // Resizing keeps the current query, and shows it only once.
    for (final width in [700.0, 936.0, 600.0]) {
      tester.view.physicalSize = Size(width, 640);
      await tester.pumpAndSettle();
      expect(title, findsOneWidget);
      expect(_expanded, findsNothing);
      expect(width >= 700 ? _barField : _barSearch, findsOneWidget);
      expect(find.text('“blue”'), width >= 700 ? findsNothing : findsOneWidget);
      expect(container.read(searchSessionProvider).visitId, calls);
      expect(tester.takeException(), isNull);
    }
  });

  for (final artists in [false, true]) {
    testWidgets(
      'wide ${artists ? 'artists' : 'albums'} keeps a compact header across heights',
      (tester) async {
        final key = GlobalKey();
        final api = _Api(count: 20, artists: artists);
        final page = CatalogPage.category(
          id: 'kalinka:jamendo:catalog:${artists ? 'artists' : 'albums'}',
          title: artists ? 'Artists' : 'Albums',
          provider: 'Jamendo',
          preview: Preview(
            type: PreviewType.imageText,
            contentType: artists
                ? PreviewContentType.artist
                : PreviewContentType.album,
          ),
          filters: _catalog.filters,
        );
        // The browsing area of a 1024×600 shell, above its 72dp mini-player.
        final container = await _pump(
          tester,
          api,
          size: const Size(936, 528),
          page: page,
          captureKey: key,
        );
        final title = find.byKey(const ValueKey('catalog-compact-title'));
        expect(title, findsOneWidget);
        expect(_expanded, findsNothing);
        expect(find.byType(CatalogPinButton), findsOneWidget);
        expect(
          find.text('Jamendo · 20 ${artists ? 'artists' : 'albums'}'),
          findsOneWidget,
        );
        final titleBounds = tester.getRect(title);
        expect(
          tester.getRect(_barField).center.dy,
          closeTo(titleBounds.center.dy, 1),
        );
        expect(
          tester.getRect(find.byType(CatalogPinButton)).left -
              titleBounds.right,
          lessThanOrEqualTo(8),
        );
        final cards = find.byType(ArtworkGridCard);
        final first = tester.getRect(cards.first);
        expect(first.top, lessThan(95));
        expect(
          first.width - 2 * ArtworkGridCard.inset,
          inInclusiveRange(160, 170),
        );
        expect(tester.getRect(cards.at(4)).top, first.top);
        expect(tester.getRect(cards.at(5)).top, greaterThan(first.top));
        await _capture(
          tester,
          key,
          artists ? 'artists-compact' : 'albums-compact',
        );
        final visit = container.read(searchSessionProvider).visitId;
        final calls = api.calls.length;
        tester.state<ScrollableState>(_scrollable).position.jumpTo(250);
        await tester.pumpAndSettle();
        expect(tester.getRect(title), titleBounds);
        expect(find.byType(CatalogPinButton), findsOneWidget);
        tester.view.physicalSize = const Size(936, 800);
        await tester.pumpAndSettle();
        expect(title, findsOneWidget);
        expect(tester.getRect(title), titleBounds);
        await _capture(tester, key, artists ? 'artists-tall' : 'albums-tall');
        tester.view.physicalSize = const Size(600, 800);
        await tester.pumpAndSettle();
        expect(title, findsOneWidget);
        expect(_barSearch, findsOneWidget);
        expect(_barField, findsNothing);
        expect(container.read(searchSessionProvider).visitId, visit);
        expect(api.calls.length, calls);
        tester.view.physicalSize = const Size(936, 528);
        await tester.pumpAndSettle();
        expect(title, findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('keyboard focus outlines the circular catalog pin', (
    tester,
  ) async {
    await _pump(tester, _Api(catalogs: true));
    final pin = find.byType(CatalogPinButton);
    final button = find
        .descendant(of: pin, matching: find.byType(Material))
        .first;
    final bounds = tester.getRect(button);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    traversableFocusNodesIn(pin).single.requestFocus();
    await tester.pumpAndSettle();
    expect(focusIsOn(pin), isTrue);
    final ring = focusOutlineIn(pin, KalinkaColors.textPrimary);
    final decoration =
        tester.widget<DecoratedBox>(ring).decoration as ShapeDecoration;
    expect(decoration.shape, isA<CircleBorder>());
    expect(tester.getRect(ring), bounds);
    expect(bounds.width, bounds.height);
  });

  testWidgets('keyboard focus follows the faces of Filters and Clear filters', (
    tester,
  ) async {
    final key = GlobalKey();
    final container = await _pump(tester, _Api(), captureKey: key);
    container
        .read(searchSessionProvider.notifier)
        .setCatalogFilter(
          const BrowseFilterQuery(text: 'deep', genreIds: ['Synthwave']),
        );
    await tester.pumpAndSettle();

    final clear = find.widgetWithText(TextButton, 'Clear filters');
    Finder ring(Finder control) =>
        focusOutlineIn(control, KalinkaColors.textPrimary);
    void expectOutlined(Finder control) {
      final outline = ring(control);
      expect(outline, findsOneWidget);
      final decoration =
          tester.widget<DecoratedBox>(outline).decoration as ShapeDecoration;
      expect(decoration.shape, isA<StadiumBorder>());
      final face = find
          .descendant(of: control, matching: find.byType(Material))
          .first;
      expect(tester.getRect(outline), tester.getRect(face));
      final ink = tester.widget<InkWell>(
        find.descendant(of: control, matching: find.byType(InkWell)),
      );
      expect(
        ink.overlayColor!.resolve({WidgetState.focused}),
        Colors.transparent,
      );
    }

    expect(ring(_barFilters), findsNothing);
    expect(ring(clear), findsNothing);
    expect(await tabTo(tester, _barFilters), isTrue);
    await tester.pumpAndSettle();
    expectOutlined(_barFilters);
    await _capture(tester, key, 'filters-keyboard-focus');
    expect(await tabTo(tester, find.byType(ActiveFilterChip).last), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(focusIsOn(clear), isTrue);
    expect(ring(_barFilters), findsNothing);
    expectOutlined(clear);
    expect(tester.getSize(ring(clear)).height, kKalinkaPillHeight);
    expect(
      tester.getSize(clear).height,
      greaterThanOrEqualTo(kKalinkaPillTarget),
    );
    await _capture(tester, key, 'clear-filters-keyboard-focus');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(clear, findsNothing);
    expect(container.read(searchSessionProvider).catalogFilter.text, 'deep');
    expect(
      container.read(searchSessionProvider).catalogFilter.genreIds,
      isEmpty,
    );
  });

  for (final (width, scale, inline) in [
    (516.0, 1.0, true),
    (375.0, 1.0, true),
    (375.0, 2.0, false),
  ]) {
    testWidgets('simple catalog groups controls at $width / $scale', (
      tester,
    ) async {
      final key = GlobalKey();
      await _pump(
        tester,
        _Api(catalogs: true),
        size: Size(width, 720),
        scale: scale,
        captureKey: key,
        page: CatalogPage.category(
          id: 'kalinka:jamendo:catalog:home',
          title: 'Home',
          provider: 'Jamendo',
          preview: Preview(type: PreviewType.imageText),
        ),
      );
      final title = tester.getRect(_expanded);
      final toggle = tester.getRect(_barPresentation);
      final pin = tester.getRect(find.byType(CatalogPinButton));
      final foot = _foot(tester);
      expect(pin.center.dy, closeTo(title.center.dy, 0.01));
      expect(pin.left, closeTo(title.right + 8, 0.01));
      expect(pin.bottom, lessThan(foot.top));
      // Grid/List is the bar's, never the header's.
      expect(toggle.bottom, lessThanOrEqualTo(title.top));
      if (inline) expect(foot.top, lessThan(210));
      expect(toggle.width, greaterThanOrEqualTo(48));
      expect(toggle.height, greaterThanOrEqualTo(48));
      expect(find.byType(PresentationToggle), findsOneWidget);
      final card = tester.getRect(find.byType(ArtworkGridCard).first);
      expect(card.left + ArtworkGridCard.inset, closeTo(foot.left, 0.01));
      await _capture(tester, key, 'compact-catalog-$width-$scale');
      expect(tester.takeException(), isNull);
    });
  }

  for (final (width, scale) in [
    (1920.0, 1.0),
    (1440.0, 1.0),
    (1000.0, 1.0),
    (800.0, 1.0),
    (700.0, 1.0),
    (540.0, 1.0),
    (375.0, 1.0),
    (320.0, 1.0),
    (375.0, 2.0),
  ]) {
    testWidgets(
      'compact track filters and readable columns at $width / $scale',
      (tester) async {
        final key = GlobalKey();
        final api = _Api(tracks: true, count: 5);
        final container = await _pump(
          tester,
          api,
          size: Size(width, 900),
          scale: scale,
          captureKey: key,
          page: CatalogPage.category(
            id: 'kalinka:jamendo:catalog:tracks',
            title: 'Tracks',
            provider: 'Jamendo',
            preview: Preview(
              type: PreviewType.tile,
              contentType: PreviewContentType.track,
            ),
            filters: _catalog.filters,
          ),
        );
        container
            .read(searchSessionProvider.notifier)
            .setCatalogFilter(
              const BrowseFilterQuery(
                text: 'deep',
                genreIds: ['Synthwave', 'New age'],
              ),
            );
        await tester.pumpAndSettle();
        final pin = tester.getRect(find.byType(CatalogPinButton));
        final compact = width >= 600 * scale;
        final title = tester.getRect(
          compact
              ? find.byKey(const ValueKey('catalog-compact-title'))
              : _expanded,
        );
        expect(pin.left - title.right, inInclusiveRange(0, 8.1));
        expect(pin.center.dy, closeTo(title.center.dy, 0.1));
        final inBar = width >= 700 * scale;
        if (inBar) {
          final field = tester.getRect(_barField);
          final filters = tester.getRect(find.byTooltip('Filters, 2 active'));
          expect(field.height, filters.height);
          if (scale == 1) expect(field.height, inInclusiveRange(48, 52));
          expect(find.text('“deep”'), findsNothing);
          expect(find.byType(ActiveFilterChip), findsNWidgets(2));
        } else {
          // No field shows the search, so a chip does.
          expect(find.text('“deep”'), findsOneWidget);
          expect(find.byType(ActiveFilterChip), findsNWidgets(3));
        }
        if (scale == 1) {
          final chip = find.byType(ActiveFilterChip).first;
          expect(tester.getSize(chip).height, greaterThanOrEqualTo(48));
          expect(
            tester
                .getSize(
                  find.descendant(
                    of: chip,
                    matching: find.byType(AnimatedContainer),
                  ),
                )
                .height,
            kKalinkaPillHeight,
          );
        }
        expect(find.text('Clear filters'), findsOneWidget);
        expect(find.byType(ColumnSeparator), findsNothing);
        final firstRow = find.byType(SearchTrackRow).first;
        expect(
          find.descendant(
            of: firstRow,
            matching: find.textContaining('Unknown artist'),
          ),
          findsOneWidget,
        );
        if (width - 32 >= 576 * scale) {
          final columns = tester
              .widget<RowColumnCells>(
                find.descendant(
                  of: firstRow,
                  matching: find.byType(RowColumnCells),
                ),
              )
              .columns;
          expect(find.text('ALBUM'), findsOneWidget);
          expect(columns.detailWidth, greaterThanOrEqualTo(200 * scale));
          final album = find.descendant(
            of: firstRow,
            matching: find.text('Midnight journeys'),
          );
          expect(
            tester.getTopLeft(find.text('ALBUM')).dx,
            closeTo(tester.getTopLeft(album).dx, 0.1),
          );
          expect(
            tester.getTopLeft(find.text('TITLE')).dx,
            closeTo(tester.getTopLeft(find.text('Track 0')).dx, 0.1),
          );
        } else {
          expect(find.text('ALBUM'), findsNothing);
          expect(find.textContaining('Midnight journeys'), findsNothing);
        }
        if (width >= 540 && scale == 1) {
          final chip = tester.getRect(find.byType(ActiveFilterChip).last);
          final clear = tester.getRect(
            find.widgetWithText(TextButton, 'Clear filters'),
          );
          expect(clear.left - chip.right, inInclusiveRange(0, 12));
          expect(clear.center.dy, chip.center.dy);
        }
        await _capture(tester, key, 'tracks-$width-$scale');
        if (width == 540 && scale == 1) {
          Focus.of(tester.element(find.text('Clear filters'))).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        } else {
          await tester.tap(find.text('Clear filters'));
        }
        await tester.pumpAndSettle();
        expect(
          container.read(searchSessionProvider).catalogFilter.text,
          'deep',
        );
        expect(
          container.read(searchSessionProvider).catalogFilter.genreIds,
          isEmpty,
        );
        if (inBar) {
          expect(
            tester
                .widget<EditableText>(
                  find.descendant(
                    of: _barField,
                    matching: find.byType(EditableText),
                  ),
                )
                .controller
                .text,
            'deep',
          );
        } else {
          expect(find.text('“deep”'), findsOneWidget);
        }
        expect(api.calls.last.filter, contains('deep'));
        expect(api.calls.last.filter, isNot(contains('Synthwave')));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final (name, size, scale, page) in [
    (
      'pin-only',
      const Size(540, 700),
      1.0,
      const CatalogPage.category(
        id: 'kalinka:tidal:catalog:home',
        title: 'Home',
        provider: 'TIDAL',
      ),
    ),
    ('filters', const Size(540, 800), 1.0, _catalog),
    ('wrapped-filters', const Size(375, 812), 2.0, _catalog),
    (
      'wrapped-search',
      const Size(320, 812),
      2.0,
      const CatalogPage.category(
        id: 'kalinka:jamendo:catalog:tracks',
        title: 'Tracks',
        filters: [FilterSpec(id: 'q', kind: FilterKind.text, label: 'Search')],
      ),
    ),
  ]) {
    testWidgets('header slides under the bar and hands over: $name', (
      tester,
    ) async {
      final key = GlobalKey();
      await _pump(
        tester,
        _Api(),
        page: page,
        size: size,
        scale: scale,
        captureKey: key,
      );
      // Measure the header's boundary directly: Back's circular visual is
      // smaller than its target and does not define the bar's lower edge.
      final viewportTop =
          tester.getRect(_surface).top +
          tester
              .widget<CatalogPageView>(find.byType(CatalogPageView))
              .topBarInset;
      final initialFootTop = _foot(tester).top;
      final identity = find.byKey(const ValueKey('catalog-identity'));
      // The title hands over once it has passed under the bar.
      final headingClearance = tester.getRect(identity).bottom - viewportTop;
      final header = tester.widget<SliverPersistentHeader>(
        find.byType(SliverPersistentHeader).first,
      );
      final extent = header.delegate.maxExtent - header.delegate.minExtent;
      final scroll = tester.state<ScrollableState>(_scrollable);
      final searches = _inPage(find.byType(TextField)).evaluate().isNotEmpty;
      final steps = [
        for (var offset = 0.0; offset < extent; offset += 4) offset,
        extent,
        extent + 20,
      ];
      for (final offset in [...steps, ...steps.reversed]) {
        scroll.position.jumpTo(offset);
        await tester.pumpAndSettle();
        expect(
          _foot(tester).top,
          closeTo(initialFootTop - offset.clamp(0.0, extent), 0.1),
          reason: 'The list should follow the scroll without a layout jump.',
        );
        expect(find.byType(CatalogPinButton), findsOneWidget);
        final inlinePin = find.descendant(
          of: find.byType(CatalogPageView),
          matching: find.byType(CatalogPinButton),
        );
        if (inlinePin.evaluate().isNotEmpty) {
          final rect = tester.getRect(inlinePin);
          expect(rect.bottom, lessThanOrEqualTo(_foot(tester).top));
        }
        // In the header until it is out of sight under the bar, then only
        // in the bar.
        if (identity.evaluate().isNotEmpty) {
          expect(tester.getRect(identity).bottom, greaterThan(viewportTop));
          expect(_collapsed, findsNothing);
        }
        if (offset < headingClearance - 0.1) {
          expect(_expanded, findsOneWidget);
        } else if (offset >= headingClearance + 0.1) {
          expect(_expanded, findsNothing);
          expect(_collapsed, findsOneWidget);
        }
        for (final control in [
          _inPage(find.byType(TextField)),
          _inPage(find.byTooltip('Filters')),
        ]) {
          if (control.evaluate().isNotEmpty) {
            expect(
              tester.getRect(control).bottom,
              lessThanOrEqualTo(_foot(tester).top),
            );
          }
        }
        if (searches) {
          expect(
            _barSearch.evaluate().isEmpty,
            _inPage(find.byType(TextField)).evaluate().isNotEmpty,
            reason: 'Search is in the header or in the bar, once.',
          );
        }
        expect(tester.widget<ColoredBox>(_surface).color.a, 0);
        expect(tester.takeException(), isNull);
        if ([0.0, 8.0, 16.0, 24.0, 48.0, 80.0, extent].contains(offset)) {
          await _capture(tester, key, 'motion-$name-${offset.round()}');
        }
      }
    });
  }

  for (final (size, scale) in [
    (const Size(1200, 800), 1.0),
    (const Size(812, 375), 1.0),
    (const Size(1600, 1000), 2.0),
    (const Size(375, 812), 1.0),
    (const Size(320, 600), 1.0),
    (const Size(375, 812), 2.0),
    (const Size(640, 800), 2.0),
    (const Size(640, 800), 3.0),
  ]) {
    testWidgets(
      'the bar holds a catalog\'s controls as its identity hands over at $size and ${scale}x text',
      (tester) async {
        final key = GlobalKey();
        await _pump(tester, _Api(), size: size, scale: scale, captureKey: key);
        if (size.width >= 720 * scale) {
          final title = find.byKey(const ValueKey('catalog-compact-title'));
          final bounds = tester.getRect(title);
          for (final offset in [0.0, 8.0, 80.0, 400.0, 700.0, 0.0]) {
            tester.state<ScrollableState>(_scrollable).position.jumpTo(offset);
            await tester.pumpAndSettle();
            expect(tester.getRect(title), bounds);
            expect(find.byType(CatalogPinButton).hitTestable(), findsOneWidget);
            expect(_barFilters.hitTestable(), findsOneWidget);
            expect(_barField.hitTestable(), findsOneWidget);
            expect(_expanded, findsNothing);
            expect(tester.takeException(), isNull);
          }
          await _capture(tester, key, '${size.width}-$scale-toolbar');
          return;
        }
        expect(_expanded, findsOneWidget);
        expect(_collapsed, findsNothing);
        expect(
          find.byTooltip('Pin catalog to Home').hitTestable(),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('catalog-identity')),
            matching: find.byType(CatalogPinButton),
          ),
          findsOneWidget,
        );
        // Filters is the bar's from the start, above the identity.
        expect(_barFilters, findsOneWidget);
        expect(
          tester.getRect(_barFilters).bottom,
          lessThanOrEqualTo(tester.getRect(_expanded).top),
        );
        // Search is the bar's from the start: a field where there is room,
        // else a button.
        final inBar = CatalogSliverHeader.searchInBar(size.width, scale);
        final search = inBar ? _barField : _barSearch;
        expect(search, findsOneWidget);
        expect(inBar ? _barSearch : _barField, findsNothing);
        expect(_inPage(find.byType(TextField)), findsNothing);
        expect(tester.takeException(), isNull);
        await _capture(tester, key, '${size.width}-$scale-expanded');
        final scroll = tester.state<ScrollableState>(_scrollable);
        scroll.position.jumpTo(400);
        await tester.pumpAndSettle();
        expect(_collapsed, findsOneWidget);
        final title = tester.widget<Text>(_collapsed);
        expect(title.data, 'ALBUMS');
        expect(
          title.style,
          KalinkaTextStyles.trayTitle.copyWith(
            color: KalinkaColors.textPrimary,
          ),
        );
        expect(_expanded, findsNothing);
        expect(find.byType(CatalogPinButton), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('catalog-identity')),
            matching: find.byType(CatalogPinButton),
          ),
          findsNothing,
        );
        expect(
          tester.getRect(find.byType(CatalogPinButton)).center.dy,
          tester.getRect(find.byTooltip('Back')).center.dy,
        );
        // Nothing stays under the bar.
        expect(find.byTooltip('Filters').hitTestable(), findsOneWidget);
        final back = tester.getRect(find.byTooltip('Back')).center.dy;
        expect(tester.getRect(search).center.dy, closeTo(back, 0.5));
        expect(tester.getRect(find.byTooltip('Filters')).center.dy, back);
        final barHeight =
            (KalinkaTextStyles.trayTitle.fontSize! * scale * 1.5 + 4).clamp(
              kKalinkaTopBarHeight,
              double.infinity,
            );
        expect(_foot(tester).top, closeTo(barHeight, 0.1));
        final pinned = _foot(tester);
        await _capture(tester, key, '${size.width}-$scale-collapsed');
        scroll.position.jumpTo(700);
        await tester.pumpAndSettle();
        expect(_foot(tester), pinned);
        scroll.position.jumpTo(0);
        await tester.pumpAndSettle();
        expect(_collapsed, findsNothing);
        expect(_expanded, findsOneWidget);
        expect(_barFilters, findsOneWidget);
        expect(search, findsOneWidget);
        expect(find.byTooltip('Filters'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('catalog-identity')),
            matching: find.byType(CatalogPinButton),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a narrow bar\'s search unrolls a field that searches on Enter', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      _Api(),
      size: const Size(375, 812),
      scale: 2,
    );
    container
        .read(searchSessionProvider.notifier)
        .setCatalogFilter(const BrowseFilterQuery(text: 'blue'));
    await tester.pumpAndSettle();
    String text() => container.read(searchSessionProvider).catalogFilter.text;
    // The header holds no field; a chip says what is searched.
    expect(_inPage(find.byType(TextField)), findsNothing);
    expect(find.text('“blue”'), findsOneWidget);
    expect(find.byTooltip('Search, applied'), findsOneWidget);

    await tester.tap(_barSearch);
    await tester.pumpAndSettle();
    expect(_unrolled, findsOneWidget);
    final field = find.descendant(
      of: _unrolled,
      matching: find.byType(EditableText),
    );
    final editable = tester.widget<EditableText>(field);
    expect(editable.controller.text, 'blue');
    expect(editable.focusNode.hasFocus, isTrue);
    // Across the pane, under the bar.
    final unrolled = tester.getRect(_unrolled);
    expect(unrolled.left, 16);
    expect(unrolled.right, 375 - 16);
    expect(
      unrolled.top,
      greaterThanOrEqualTo(tester.getRect(find.byTooltip('Back')).bottom),
    );

    // Typing alone searches nothing, so the list holds still under it.
    await tester.enterText(field, 'green');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(text(), 'blue');
    expect(_unrolled, findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(text(), 'green');
    expect(_unrolled, findsNothing);
    expect(find.text('“green”'), findsOneWidget);

    // A scroll puts it away, and so does Back, which leaves the page be.
    await tester.tap(_barSearch);
    await tester.pumpAndSettle();
    await tester.drag(_scrollable, const Offset(0, -60));
    await tester.pumpAndSettle();
    expect(_unrolled, findsNothing);
    await tester.tap(_barSearch);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(_unrolled, findsNothing);
    expect(container.read(searchSessionProvider).catalogPage.id, _catalog.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a catalog without filters leaves no empty pinned control row', (
    tester,
  ) async {
    await _pump(
      tester,
      _Api(),
      size: const Size(540, 800),
      page: const CatalogPage.category(
        id: 'kalinka:jamendo:catalog:other',
        title: 'Other catalog',
      ),
    );
    tester.state<ScrollableState>(_scrollable).position.jumpTo(400);
    await tester.pumpAndSettle();
    expect(_collapsed, findsOneWidget);
    expect(find.byType(CatalogPinButton), findsOneWidget);
    expect(_foot(tester).top, kKalinkaTopBarHeight);
    expect(tester.takeException(), isNull);
  });

  testWidgets('remote filter keeps focus until Show returns to the listing', (
    tester,
  ) async {
    final container = await pumpHomeShell(
      tester,
      queue: SettableQueue(queueOf(2)),
      api: _Api(),
      size: const Size(1440, 900),
      overrides: [localDisplayKioskProvider.overrideWithValue(true)],
    );
    container.read(searchSessionProvider.notifier).openPage(_catalog);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.nearestScope?.debugLabel,
      'content',
    );
    final filters = find.byTooltip('Filters');
    await tester.tap(filters);
    await tester.pumpAndSettle();
    final card = find.byType(SearchFilterOverlay);
    expect(
      focusIsOn(card),
      isTrue,
      reason: FocusManager.instance.primaryFocus?.toStringDeep(),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      focusIsOn(card),
      isTrue,
      reason: FocusManager.instance.primaryFocus?.toStringDeep(),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(card, findsNothing);
    expect(
      FocusManager.instance.primaryFocus?.nearestScope?.debugLabel,
      'toolbar',
    );
    await tester.tap(filters);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show results'));
    await tester.pumpAndSettle();
    expect(card, findsNothing);
    expect(
      FocusManager.instance.primaryFocus?.nearestScope?.debugLabel,
      'content',
    );
  });

  testWidgets(
    'opening an album and using toolbar Back both leave focus in the listing',
    (tester) async {
      final albumGate = Completer<void>();
      final container = await pumpHomeShell(
        tester,
        queue: SettableQueue(queueOf(2)),
        api: _Api(albumGate: albumGate),
        size: const Size(1440, 900),
        overrides: [localDisplayKioskProvider.overrideWithValue(true)],
      );
      final browse = container.read(searchSessionProvider.notifier);
      browse.openPage(
        CatalogPage.category(
          id: _catalog.id,
          title: 'Albums',
          preview: Preview(
            type: PreviewType.imageText,
            contentType: PreviewContentType.album,
          ),
        ),
      );
      await tester.pumpAndSettle();
      traversableFocusNodesIn(find.byType(ArtworkGridCard).first).single
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      albumGate.complete();
      await tester.pumpAndSettle();
      expect(container.read(searchSessionProvider).catalogPage.isAlbum, isTrue);
      expect(
        FocusManager.instance.primaryFocus?.nearestScope?.debugLabel,
        'content',
      );
      expect(focusIsOn(find.byType(CatalogPageView)), isTrue);
      final back = find.byType(KalinkaBackButton).hitTestable().first;
      traversableFocusNodesIn(back).first.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        container.read(searchSessionProvider).catalogPage.isAlbum,
        isFalse,
      );
      expect(
        FocusManager.instance.primaryFocus?.nearestScope?.debugLabel,
        'content',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(container.read(searchSessionProvider).atHome, isTrue);
      expect(
        FocusManager.instance.primaryFocus?.nearestScope?.debugLabel,
        'content',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.nearestScope?.debugLabel,
        'navigation',
      );
    },
  );

  testWidgets('the bar\'s field searches on Enter and filters remain staged', (
    tester,
  ) async {
    final api = _Api();
    final container = await _pump(tester, api);
    String text() => container.read(searchSessionProvider).catalogFilter.text;
    final field = find.descendant(
      of: _barField,
      matching: find.byType(TextField),
    );
    await tester.enterText(field, 'blue');
    await tester.pump(const Duration(milliseconds: 400));
    expect(text(), isEmpty);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(text(), 'blue');
    expect(api.calls.last.filter, contains('blue'));
    // Scrolled away, the field stays where it is, in the bar.
    tester.state<ScrollableState>(_scrollable).position.jumpTo(400);
    await tester.pumpAndSettle();
    expect(field, findsOneWidget);
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchFilterOverlay), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SearchFilterOverlay),
        matching: find.byType(TextField),
      ),
      findsNothing,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(text(), 'blue');
    await tester.enterText(field, 'green');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show results'));
    await tester.pumpAndSettle();
    expect(text(), 'green');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long catalog has a thumb that drags to its end', (
    tester,
  ) async {
    await _pump(tester, _Api());
    final thumb = find.byKey(const ValueKey('fast-scroll-thumb'));
    expect(thumb, findsNothing);

    await tester.drag(_scrollable, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(thumb.hitTestable(), findsOneWidget);
    expect(find.text('Album 79'), findsNothing);

    await tester.drag(thumb, const Offset(0, 1000));
    await tester.pumpAndSettle();
    expect(find.text('Album 79').hitTestable(), findsOneWidget);
  });

  testWidgets('Back restores the collapsed catalog title and controls', (
    tester,
  ) async {
    final container = await _pump(tester, _Api(), size: const Size(540, 800));
    final scroll = tester.state<ScrollableState>(_scrollable);
    scroll.position.jumpTo(500);
    await tester.pumpAndSettle();
    container
        .read(searchSessionProvider.notifier)
        .openPage(
          const CatalogPage.category(
            id: 'kalinka:jamendo:catalog:other',
            title: 'Other catalog',
          ),
        );
    await tester.pumpAndSettle();
    expect(_collapsed, findsNothing);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(_collapsed, findsOneWidget);
    expect(tester.widget<Text>(_collapsed).data, 'ALBUMS');
    expect(tester.state<ScrollableState>(_scrollable).position.pixels, 500);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'playlists ignore preview shelves and page through their complete tracks',
    (tester) async {
      final api = _Api(count: 40);
      final page = CatalogPage.category(
        id: 'kalinka:jamendo:playlist:evening',
        title: 'Evening',
        canAdd: true,
        sections: [
          BrowseItem(
            id: 'kalinka:jamendo:catalog:preview',
            canBrowse: true,
            canAdd: false,
            catalog: Catalog(id: 'preview', title: 'Tracks'),
          ),
        ],
      );
      await _pump(tester, api, page: page, size: const Size(432, 800));
      expect(find.text('View All'), findsNothing);
      expect(find.byType(SearchTrackRow).evaluate().length, lessThan(30));
      expect(api.calls.map((call) => call.id).toSet(), {page.id});
      await tester.scrollUntilVisible(
        find.text('Track 35'),
        400,
        scrollable: _scrollable,
      );
      await tester.pumpAndSettle();
      expect(api.calls.map((call) => call.offset), contains(30));
      await tester.tap(find.text('Track 35'));
      await tester.pumpAndSettle();
      expect(api.replaced.single, [page.id]);
      expect(api.played.single, 35);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 30));
    },
  );

  for (final fail in [false, true]) {
    testWidgets(
      'catalog controls remain available while loading and ${fail ? 'offline' : 'empty'}',
      (tester) async {
        final gate = Completer<void>();
        await _pump(
          tester,
          _Api(count: 0, gate: gate, fail: fail),
          settle: false,
        );
        expect(_barFilters, findsOneWidget);
        expect(
          find.byKey(const ValueKey('catalog-compact-title')),
          findsOneWidget,
        );
        gate.complete();
        await tester.pumpAndSettle();
        expect(
          find.text(fail ? 'This catalog is unavailable' : 'Nothing here yet'),
          findsOneWidget,
        );
        expect(_barFilters, findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final (width, scale, filtered) in [
    (820.0, 1.0, false),
    (1440.0, 1.0, false),
    (1920.0, 1.0, false),
    (720.0, 1.0, false),
    (375.0, 1.0, false),
    (320.0, 2.0, false),
    (375.0, 3.0, false),
  ]) {
    testWidgets('folder toolbar at $width / $scale, filters $filtered', (
      tester,
    ) async {
      final api = _DriveApi();
      final key = GlobalKey();
      final container = await _pump(
        tester,
        api,
        size: Size(width, width == 720 ? 375 : 812),
        scale: scale,
        topInset: 24,
        captureKey: key,
        page: CatalogPage.category(
          id: 'kalinka:drives:catalog:root',
          title: 'Drives',
          folderLayout: true,
          onStorage: true,
          canAdd: true,
          filters: filtered ? _catalog.filters : const [],
        ),
      );
      final session = container.read(searchSessionProvider.notifier);
      session.openFolder(
        BrowseItem(
          id: 'kalinka:drives:catalog:albums',
          name: 'Music albums and live recordings',
          canBrowse: true,
          canAdd: true,
          catalog: Catalog(
            id: 'albums',
            title: 'Music albums and live recordings',
            onStorage: true,
            previewConfig: Preview(type: PreviewType.folder),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final actions = find.byType(FolderPageActions);
      final play = find.byType(PlayAllChip);
      final up = find.byIcon(Icons.drive_folder_upload_outlined);
      final inline = !filtered && width >= 820;
      expect(actions, findsOneWidget);
      expect(_inPage(actions), findsNothing);
      expect(
        find.byKey(const ValueKey('folder-toolbar-second-row')),
        inline ? findsNothing : findsOneWidget,
      );
      expect(play.hitTestable(), findsOneWidget);
      expect(up.hitTestable(), findsOneWidget);
      final backRect = tester.getRect(find.byType(KalinkaBackButton));
      final actionRect = tester.getRect(actions);
      if (inline) {
        expect(actionRect.center.dy, closeTo(backRect.center.dy, .1));
        expect(find.text('In library'), findsOneWidget);
        expect(
          tester.getRect(find.byType(FolderTrail)).width,
          greaterThan(150),
        );
      } else {
        expect(actionRect.top, greaterThanOrEqualTo(backRect.bottom));
      }
      if (filtered) expect(_barFilters, findsOneWidget);
      final fade = tester.widget<TopBarContentFade>(
        find.byKey(const ValueKey('catalog-content-fade')),
      );
      expect(fade.extent, greaterThanOrEqualTo(actionRect.bottom));
      final scroll = tester.state<ScrollableState>(_scrollable).position;
      for (final offset in [40.0, 300.0, 0.0]) {
        scroll.jumpTo(offset);
        await tester.pumpAndSettle();
        expect(tester.getRect(actions), actionRect);
        expect(play.hitTestable(), findsOneWidget);
        expect(up.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await _capture(tester, key, 'folder-toolbar-$width-$scale-$filtered');
      if (filtered) {
        session.setCatalogFilter(const BrowseFilterQuery(text: 'night'));
        await tester.pumpAndSettle();
        expect(tester.widget<PlayAllChip>(play).enabled, isFalse);
        expect(
          tester.widget<AddAllChip>(find.byType(AddAllChip)).enabled,
          isFalse,
        );
        session.setCatalogFilter(const BrowseFilterQuery());
        await tester.pumpAndSettle();
      }
      await tester.tap(play);
      await tester.pumpAndSettle();
      expect(api.replaced.single, ['kalinka:drives:catalog:albums']);
      await tester.tap(find.byType(AddAllChip));
      await tester.pumpAndSettle();
      expect(api.enqueued.single, ['kalinka:drives:catalog:albums']);
      // Crossing the layout boundary keeps the active enqueue receipt and
      // the existing listing, including its scroll position.
      if (width == 820) {
        scroll.jumpTo(300);
        await tester.pump();
        final requests = api.calls.length;
        tester.view.physicalSize = const Size(375, 812);
        await tester.pumpAndSettle();
        expect(find.text('Added'), findsOneWidget);
        expect(scroll.pixels, 300);
        expect(api.calls.length, requests);
        tester.view.physicalSize = const Size(820, 812);
        await tester.pumpAndSettle();
        expect(find.text('Added'), findsOneWidget);
        expect(tester.getRect(actions), actionRect);
      }
      await tester.pump(kEnqueuedHold);
      await tester.pumpAndSettle();
      await tester.tap(up);
      await tester.pumpAndSettle();
      expect(container.read(searchSessionProvider).folderPath, isEmpty);
      expect(up, findsNothing);
      final more = find.byKey(const ValueKey('drive-more'));
      if (more.evaluate().isNotEmpty) {
        await tester.tap(more);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('drive-menu-eject')), findsOneWidget);
      } else {
        expect(find.byKey(const ValueKey('drive-eject')), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'folder Pin stays available while actions migrate at ${scale}x text',
      (tester) async {
        final container = await _pump(
          tester,
          _Api(tracks: true),
          size: const Size(375, 900),
          scale: scale,
          page: CatalogPage.category(
            id: 'kalinka:localfiles:catalog:music',
            title: 'Music',
            description: '23 tracks · In My Library',
            canAdd: true,
            folderLayout: true,
            filters: _catalog.filters,
          ),
        );
        final pin = find.byType(CatalogPinButton);
        final actions = find.byType(FolderPageActions);
        final inset = tester
            .widget<CatalogPageView>(find.byType(CatalogPageView))
            .topBarInset;
        final identityEnd =
            tester
                .getRect(find.byKey(const ValueKey('catalog-identity')))
                .bottom -
            inset;
        final actionsStart = tester.getRect(actions).top - inset;
        expect(actionsStart, greaterThan(identityEnd));
        final scroll = tester.state<ScrollableState>(_scrollable).position;
        final offsets = [
          for (var offset = 0.0; offset <= actionsStart + 30; offset += 5)
            offset,
        ];
        for (final offset in [...offsets, ...offsets.reversed]) {
          scroll.jumpTo(offset);
          await tester.pumpAndSettle();
          expect(pin, findsOneWidget, reason: 'Pin at offset $offset');
          expect(actions, findsOneWidget);
          expect(
            _inPage(pin),
            offset < identityEnd ? findsOneWidget : findsNothing,
            reason: 'Pin follows the title at offset $offset',
          );
          if (offset >= identityEnd) {
            expect(pin.hitTestable(), findsOneWidget);
          }
          expect(
            _inPage(actions),
            offset < actionsStart ? findsOneWidget : findsNothing,
            reason: 'Actions keep their own handover at offset $offset',
          );
          expect(tester.takeException(), isNull);
        }

        // Returning midway through collapse restores the two independent states.
        final midway = (identityEnd + actionsStart) / 2;
        scroll.jumpTo(midway);
        await tester.pumpAndSettle();
        final nav = container.read(searchSessionProvider.notifier);
        nav.openCatalog(id: 'kalinka:localfiles:catalog:other', title: 'Other');
        await tester.pumpAndSettle();
        nav.goBack();
        await tester.pumpAndSettle();
        expect(scroll.pixels, closeTo(midway, .01));
        expect(_inPage(pin), findsNothing);
        expect(pin.hitTestable(), findsOneWidget);
        expect(_inPage(actions), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final (width, scale) in [
    (1440.0, 1.0),
    (936.0, 1.0),
    (820.0, 1.0),
    (720.0, 1.0),
    (375.0, 1.0),
    (320.0, 2.0),
  ]) {
    testWidgets('library folder actions migrate on scroll at $width / $scale', (
      tester,
    ) async {
      final key = GlobalKey();
      final api = _Api(tracks: true);
      final container = await _pump(
        tester,
        api,
        size: Size(width, 900),
        scale: scale,
        topInset: 24,
        captureKey: key,
        page: CatalogPage.category(
          id: 'kalinka:localfiles:catalog:files',
          title: 'Folders',
          folderLayout: true,
          filters: _catalog.filters,
        ),
      );
      final session = container.read(searchSessionProvider.notifier);
      session.openFolder(
        BrowseItem(
          id: 'kalinka:localfiles:catalog:folder.music',
          name: 'GrayMic - Jazz Ballads - 478781 --- Jamendo - MP3',
          canBrowse: true,
          canAdd: true,
          catalog: Catalog(
            id: 'music',
            title: 'GrayMic - Jazz Ballads - 478781 --- Jamendo - MP3',
            previewConfig: Preview(type: PreviewType.folder),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final actions = find.byType(FolderPageActions);
      final play = find.byType(PlayAllChip);
      final enqueue = find.byType(AddAllChip);
      final up = find.byTooltip('Up one folder');
      final back = find.byType(KalinkaBackButton);
      final title = find.byKey(const ValueKey('catalog-expanded-title'));
      final pageRect = tester.getRect(find.byType(CatalogPageView));
      expect(_inPage(actions), findsOneWidget);
      expect(
        tester.getRect(actions).top,
        greaterThanOrEqualTo(tester.getRect(back).bottom),
      );
      expect(tester.getRect(up).right, closeTo(pageRect.right - 16, .1));
      if (width >= 820) {
        expect(
          tester.getRect(play).left,
          greaterThan(tester.getRect(title).right),
        );
        expect(
          tester.getRect(play).top,
          lessThan(tester.getRect(title).bottom),
        );
      }
      final expandedRect = tester.getRect(actions);
      expect(width >= 936 ? _barField : _barSearch, findsOneWidget);
      await _capture(tester, key, 'library-folder-$width-$scale-expanded');
      await tester.tap(enqueue);
      await tester.pumpAndSettle();
      final requests = api.calls.length;
      final scroll = tester.state<ScrollableState>(_scrollable).position;
      scroll.jumpTo(300);
      await tester.pumpAndSettle();
      expect(_inPage(actions), findsNothing);
      expect(play.hitTestable(), findsOneWidget);
      expect(up.hitTestable(), findsOneWidget);
      final compact = width <= 820;
      expect(tester.widget<PlayAllChip>(play).iconOnly, compact);
      expect(tester.widget<AddAllChip>(enqueue).iconOnly, compact);
      expect(
        find.byTooltip('Added to queue'),
        compact ? findsOneWidget : findsNothing,
      );
      expect(api.calls.length, requests);
      if (width >= 720) {
        expect(
          tester.getRect(actions).center.dy,
          closeTo(tester.getRect(back).center.dy, .1),
        );
        expect(
          tester.getRect(actions).right,
          lessThanOrEqualTo(
            tester.getRect(width >= 1200 ? _barField : _barSearch).left,
          ),
        );
        expect(
          find.byKey(const ValueKey('folder-toolbar-second-row')),
          findsNothing,
        );
        expect(
          tester.getSize(find.byType(FolderTrail)).width,
          greaterThanOrEqualTo(width == 720 ? 292 : 300),
        );
        final current = find.descendant(
          of: find.byType(FolderTrail),
          matching: find.widgetWithText(
            BreadcrumbCrumb,
            'GrayMic - Jazz Ballads - 478781 --- Jamendo - MP3',
          ),
        );
        expect(tester.getSize(current).width, greaterThan(160));
        expect(width >= 1200 ? _barField : _barSearch, findsOneWidget);
      }
      await _capture(tester, key, 'library-folder-$width-$scale-collapsed');
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(_inPage(actions), findsOneWidget);
      expect(tester.getRect(actions), expandedRect);
      expect(api.enqueued, [
        ['kalinka:localfiles:catalog:folder.music'],
      ]);
      expect(
        tester.widget<AddAllChip>(enqueue).iconOnly
            ? find.byTooltip('Added to queue')
            : find.text('Added'),
        findsOneWidget,
      );
      await tester.pump(kEnqueuedHold);
      await tester.pumpAndSettle();
      if (_barSearch.evaluate().isNotEmpty) {
        await tester.tap(_barSearch);
        await tester.pumpAndSettle();
        final field = find.descendant(
          of: _unrolled,
          matching: find.byType(TextField),
        );
        await tester.enterText(field, 'night');
        expect(
          container.read(searchSessionProvider).catalogFilter.text,
          isEmpty,
        );
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        expect(_unrolled, findsNothing);
        expect(
          container.read(searchSessionProvider).catalogFilter.text,
          'night',
        );
        expect(tester.widget<CatalogSearchButton>(_barSearch).active, isTrue);
      } else {
        session.setCatalogFilter(const BrowseFilterQuery(text: 'night'));
        await tester.pumpAndSettle();
      }
      expect(
        find.text('“night”'),
        width >= 936 ? findsNothing : findsOneWidget,
      );
      scroll.jumpTo(300);
      await tester.pumpAndSettle();
      expect(tester.widget<PlayAllChip>(play).enabled, isFalse);
      expect(tester.widget<AddAllChip>(enqueue).enabled, isFalse);
      await tester.tap(up);
      await tester.pumpAndSettle();
      expect(container.read(searchSessionProvider).folderPath, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final kind in [
    'list',
    'grid',
    'sections',
    'playlist',
    'folder',
    'artist',
  ]) {
    testWidgets('$kind fades beneath a transparent bar and status inset', (
      tester,
    ) async {
      const url = 'https://example.test/catalog-backdrop.png';
      final frame = (await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(const Color(0xFF286496), BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(320, 160);
        picture.dispose();
        return image;
      }))!;
      final imageKey = await const ResizeImage(
        NetworkImage(url),
        width: 320,
      ).obtainKey(ImageConfiguration.empty);
      imageCache.putIfAbsent(
        imageKey,
        () => OneFrameImageStreamCompleter(
          Future.value(ImageInfo(image: frame.clone())),
        ),
      );
      addTearDown(() {
        imageCache.clear();
        imageCache.clearLiveImages();
        frame.dispose();
      });

      final key = GlobalKey();
      final entity = ['artist', 'playlist'].contains(kind) ? kind : 'catalog';
      final page = CatalogPage.category(
        id: 'kalinka:jamendo:$entity:fade',
        title: 'Catalogue',
        artPath: url,
        folderLayout: kind == 'folder',
        canAdd: kind == 'folder',
        preview: kind == 'grid'
            ? Preview(
                type: PreviewType.imageText,
                contentType: PreviewContentType.album,
              )
            : null,
        filters: _catalog.filters,
        sections: kind == 'sections'
            ? [
                for (var i = 0; i < 5; i++)
                  BrowseItem(
                    id: 'kalinka:jamendo:catalog:shelf-$i',
                    name: 'Albums $i',
                    canBrowse: true,
                    canAdd: false,
                    catalog: Catalog(id: 'shelf-$i', title: 'Albums $i'),
                  ),
              ]
            : const [],
      );
      await _pump(
        tester,
        _Api(),
        page: page,
        size: const Size(375, 812),
        topInset: 24,
        captureKey: key,
      );
      final art = find.descendant(
        of: find.byType(CatalogArtBackdrop),
        matching: find.byType(RawImage),
      );
      // The backdrop is blurred once on the raster thread.
      await tester.runAsync(() async {
        for (var attempt = 0; attempt < 100; attempt++) {
          await tester.pump();
          if (art.evaluate().isNotEmpty) return;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(art, findsOneWidget);

      final fade = find.byKey(const ValueKey('catalog-content-fade'));
      expect(tester.getRect(fade).top, 0);
      expect(tester.widget<TopBarContentFade>(fade).extent, 76);
      expect(tester.getRect(_scrollable).top, 0);
      if (kind == 'grid') expect(find.byType(ArtworkGridCard), findsWidgets);
      expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
      final scroll = tester.state<ScrollableState>(_scrollable).position;
      expect(scroll.maxScrollExtent, greaterThan(300));
      final backdropSamples = <int, List<int>>{};
      for (final offset in [0.0, 24.0, 300.0, 0.0]) {
        scroll.jumpTo(offset);
        await tester.pumpAndSettle();
        if (kind == 'list' && offset == 300) {
          await tester.tap(_barSearch);
          await tester.pumpAndSettle();
          expect(_unrolled, findsOneWidget);
        }
        final pixels = (await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final pixels = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return pixels;
        }))!;
        // Empty space at the left edge reveals the same blue artwork at
        // rest, mid-collapse and fully collapsed, with no black overlay.
        for (final y in [
          0,
          20,
          50,
          if (kind == 'folder') ...[90, 120],
        ]) {
          final index = (y * 375 + 1) * 4;
          final rgb = [
            for (var channel = 0; channel < 3; channel++)
              pixels.getUint8(index + channel),
          ];
          if (y <= 50) {
            expect(rgb[0], closeTo(22, 2));
            expect(rgb[1], closeTo(49, 2));
            expect(rgb[2], closeTo(72, 2));
          } else {
            // The art itself darkens down the page, but scrolling must not
            // introduce a black strip behind the second row of controls.
            expect(rgb[2] - rgb[0], greaterThan(25));
            expect(rgb, backdropSamples.putIfAbsent(y, () => rgb));
          }
        }
        expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _capture(tester, key, 'transparent-$kind-${offset.round()}');
      }
    });
  }
}
