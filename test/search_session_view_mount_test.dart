import 'support/receivers.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/browse_filters.dart';
import 'package:kalinka/providers/pinned_catalogs_provider.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/indexer_status_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/browse_filters/search_filter_button.dart';
import 'package:kalinka/widgets/home/home_layout.dart';
import 'package:kalinka/widgets/kalinka_top_bar.dart';
import 'package:kalinka/widgets/overlay_card.dart';
import 'package:kalinka/widgets/search/folder_trail.dart';
import 'package:kalinka/widgets/search/album_page_header.dart';
import 'package:kalinka/widgets/search/catalog_page_view.dart';
import 'package:kalinka/widgets/search_cards/search_track_row.dart';
import 'package:kalinka/widgets/search/catalog_sliver_header.dart';
import 'package:kalinka/widgets/search/search_composer.dart';
import 'package:kalinka/widgets/search/search_session_view.dart';

import 'support/server_answer.dart';

/// Mounting the whole Find Music surface is the only thing that exercises its
/// `initState` — where a second AnimationController on a
/// SingleTickerProviderStateMixin threw on the first build.
class _FakeApi implements KalinkaPlayerProxy {
  final bool withHomeContent;
  final List<SearchSuggestion> suggestions;
  _FakeApi({this.withHomeContent = false, this.suggestions = const []});

  @override
  Future<BrowseItemsList> getFavorite(
    SearchType queryType, {
    int offset = 0,
    int limit = 10,
    String filter = '',
  }) async => BrowseItemsList(
    0,
    limit,
    withHomeContent && queryType == SearchType.track ? 6 : 0,
    [
      if (withHomeContent && queryType == SearchType.track)
        for (var i = 0; i < 6; i++)
          BrowseItem(
            id: 'kalinka:localfiles:track:$i',
            canBrowse: false,
            canAdd: true,
            track: Track(
              id: '$i',
              title: 'Favourite $i',
              duration: 200,
              performer: Artist(id: 'artist', name: 'Artist'),
            ),
          ),
    ],
  );

  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async => id == 'kalinka:localfiles:album:example'
      ? BrowseItemsList(offset, limit, 50, [
          for (var i = offset; i < (offset + limit).clamp(0, 50); i++)
            BrowseItem(
              id: 'kalinka:localfiles:track:$i',
              canBrowse: false,
              canAdd: true,
              track: Track(id: '$i', title: 'Album track $i', duration: 180),
            ),
        ])
      : BrowseItemsList(offset, limit, 0, const []);

  @override
  Future<SearchSuggestionList> searchSuggestions({
    int count = 4,
    int? tzOffsetMin,
  }) async => SearchSuggestionList(suggestions: suggestions);

  @override
  Future<BrowseItemsList> searchMatches(
    String query, {
    List<String>? sources,
  }) async => BrowseItemsList(0, 10, 0, const []);

  @override
  Future<BrowseItemsList> aiSearch(
    String query, {
    int offset = 0,
    int limit = 10,
    List<String>? sources,
  }) async => BrowseItemsList(offset, limit, 0, const []);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FixedConnection extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

/// The real notifier polls `/indexer/status` on a repeating timer.
class _IdleIndexer extends IndexerStatusNotifier {
  @override
  IndexerStatusState build() => const IndexerStatusState();

  @override
  void acquire() {}

  @override
  void release() {}
}

Future<void> _captureHome(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
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
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final (family, file) in [
      (KalinkaFonts.sansFamily, 'IBMPlexSans-Regular.ttf'),
      (KalinkaFonts.monoFamily, 'IBMPlexMono-Regular.ttf'),
      (KalinkaFonts.displayFamily, 'PlayfairDisplay-Regular.ttf'),
    ]) {
      final loader = FontLoader(family)
        ..addFont(rootBundle.load('assets/fonts/$file'));
      await loader.load();
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

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'Kalinka.host': 'localhost',
      'Kalinka.port': 8080,
      'Kalinka.name': 'Test',
    });
    prefs = await SharedPreferences.getInstance();
  });

  ProviderContainer makeContainer({
    List<ModuleInfo> modules = const [],
    bool withHomeContent = false,
    List<SearchSuggestion> suggestions = const [],
  }) {
    if (withHomeContent) {
      prefs.setString(
        'Kalinka.pinnedCatalogs.v1:id:box-1',
        jsonEncode([
          for (var i = 0; i < 10; i++)
            PinnedCatalog(
              page: CatalogPage.category(
                id: 'kalinka:localfiles:catalog:$i',
                title: 'Catalog $i',
                provider: 'My music',
              ),
              filter: const BrowseFilterQuery(),
              preview: HomePreviewType.artwork,
            ).toJson(),
        ]),
      );
    }
    final container = ProviderContainer(
      overrides: [
        noReceivers,
        sharedPrefsProvider.overrideWithValue(prefs),
        kalinkaProxyProvider.overrideWithValue(
          _FakeApi(withHomeContent: withHomeContent, suggestions: suggestions),
        ),
        sourceModulesProvider.overrideWith((ref) => modules),
        connectionStateProvider.overrideWith(_FixedConnection.new),
        serverAnswering('box-1'),
        playerStateProvider.overrideWithValue(PlaybackState.empty),
        indexerStatusProvider.overrideWith(_IdleIndexer.new),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<ProviderContainer> pumpSurface(
    WidgetTester tester, {
    List<ModuleInfo> modules = const [],
    bool withHomeContent = false,
    double textScale = 1,
    bool reduceMotion = false,
    double topInset = 0,
    List<SearchSuggestion> suggestions = const [],
    GlobalKey? captureKey,
    bool navigationVisible = false,
  }) async {
    final container = makeContainer(
      modules: modules,
      withHomeContent: withHomeContent,
      suggestions: suggestions,
    );
    container.read(searchSessionProvider.notifier).refresh();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: reduceMotion,
              padding: EdgeInsets.only(top: topInset),
            ),
            child: child!,
          ),
          home: RepaintBoundary(
            key: captureKey,
            child: Scaffold(
              body: SearchSessionView(navigationVisible: navigationVisible),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    return container;
  }

  testWidgets('the surface mounts without throwing', (tester) async {
    await pumpSurface(tester);
    expect(tester.takeException(), isNull);
    // The top level carries the app's own bar, not a breadcrumb.
    expect(find.byType(KalinkaTopBar), findsOneWidget);
    expect(find.text('HOME'), findsNothing);
  });

  testWidgets('the Discover root offers no filter control', (tester) async {
    await pumpSurface(tester);
    // Nothing to narrow at the root — the button would be a dead affordance.
    expect(find.byType(SearchFilterButton), findsNothing);
  });

  for (final (size, scale) in [
    (const Size(375, 812), 1.0),
    (const Size(375, 812), 3.0),
  ]) {
    testWidgets(
      'album art spans system inset through list at $size, ${scale}x',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final container = await pumpSurface(
          tester,
          topInset: 24,
          textScale: scale,
          reduceMotion: true,
        );
        container
            .read(searchSessionProvider.notifier)
            .openCatalog(
              id: 'kalinka:localfiles:album:example',
              title: 'Abbey Road',
              description: 'The Beatles',
              totalDurationSeconds: 9000,
            );
        await tester.pumpAndSettle();

        final cover = find.byKey(const ValueKey('album-backdrop'));
        final surface = find.byKey(const ValueKey('album-header-surface'));
        final coverRect = tester.getRect(cover);
        final headerRect = tester.getRect(find.byType(AlbumPageHeader));
        final navRect = tester.getRect(surface);
        expect(coverRect.top, 0);
        expect(coverRect.width, size.width);
        expect(coverRect.bottom, headerRect.bottom);
        expect(navRect.height, kKalinkaTopBarHeight + 24);
        expect(headerRect.top, navRect.bottom);
        // Behind the bar, and behind the list, where it stretches with it.
        expect(find.byType(AlbumArtwork), findsNWidgets(2));
        expect(
          tester.getRect(find.byKey(const ValueKey('album-backdrop-top'))),
          coverRect,
        );
        expect(find.text('50 tracks · 2 hr 30 min'), findsOneWidget);

        final systemStyle = tester
            .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
              find.ancestor(
                of: surface,
                matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
              ),
            )
            .value;
        expect(systemStyle.statusBarColor, Colors.transparent);
        expect(systemStyle.statusBarIconBrightness, Brightness.light);

        // The title stays the page's own, over a clear bar, until it has
        // scrolled away under that bar.
        final barTitle = find.byKey(const ValueKey('album-bar-title'));
        final title = find.descendant(
          of: find.byType(AlbumPageHeader),
          matching: find.text('Abbey Road'),
        );
        final titleGone = tester.getRect(title).bottom - navRect.bottom;
        double barFill() => tester.widget<ColoredBox>(surface).color.a;
        double coverOpacity() => tester
            .widget<Opacity>(
              find.ancestor(of: cover, matching: find.byType(Opacity)).first,
            )
            .opacity;
        expect(tester.widget<Opacity>(barTitle).opacity, 0);
        expect(barFill(), 0);
        expect(coverOpacity(), 1);
        // Back stands on a disc of its own over the cover.
        final disc = find.byKey(const ValueKey('album-back-disc'));
        Color discColor() =>
            (tester.widget<DecoratedBox>(disc).decoration as BoxDecoration)
                .color!;
        expect(discColor().a, greaterThan(0.5));

        final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        // The page rises over the cover, which stays put and fades.
        scrollable.position.jumpTo(80);
        await tester.pump();
        expect(tester.getRect(cover), coverRect);
        expect(coverOpacity(), lessThan(1));
        expect(tester.getRect(surface), navRect);

        // How dark the header's own shade is where it meets the bar, read
        // from the gradients it draws.
        double shadeAtSeam() {
          final seam = navRect.bottom;
          for (final element
              in find
                  .descendant(
                    of: find.byType(AlbumPageHeader),
                    matching: find.byType(DecoratedBox),
                  )
                  .evaluate()) {
            final decoration = (element.widget as DecoratedBox).decoration;
            if (decoration is! BoxDecoration ||
                decoration.gradient is! LinearGradient) {
              continue;
            }
            final box = element.renderObject! as RenderBox;
            final rect = box.localToGlobal(Offset.zero) & box.size;
            if (seam < rect.top || seam > rect.bottom) continue;
            final colors = (decoration.gradient! as LinearGradient).colors;
            return ui.lerpDouble(
              colors.first.a,
              colors.last.a,
              (seam - rect.top) / rect.height,
            )!;
          }
          return 0;
        }

        // The bar darkens with the shade rising to it, never a step apart,
        // while the title is still the page's own.
        for (var offset = 0.0; offset < titleGone; offset += 8) {
          scrollable.position.jumpTo(offset);
          await tester.pump();
          if (offset < titleGone - kKalinkaTopBarHeight) {
            expect(barFill(), closeTo(shadeAtSeam(), 0.01), reason: '$offset');
            expect(tester.widget<Opacity>(barTitle).opacity, 0);
          } else {
            expect(barFill(), greaterThanOrEqualTo(shadeAtSeam() - 0.01));
          }
        }

        scrollable.position.jumpTo(titleGone);
        await tester.pump();
        expect(tester.getRect(cover), coverRect);
        expect(
          tester.widget<ColoredBox>(surface).color,
          KalinkaColors.background,
        );
        expect(tester.widget<Opacity>(barTitle).opacity, 1);
        expect(discColor().a, 0);
        expect(tester.takeException(), isNull);

        // Rows remain below pinned navigation; leaving the album removes its
        // cover and returns Home to its own backdrop.
        await tester.scrollUntilVisible(find.text('Album track 4'), 300);
        expect(find.byType(SearchTrackRow), findsWidgets);
        container.read(searchSessionProvider.notifier).backToCatalogsRoot();
        await tester.pumpAndSettle();
        expect(cover, findsNothing);
        expect(find.byType(KalinkaTopBar), findsOneWidget);
      },
    );
  }

  final rootList = find.byKey(const PageStorageKey('discoverRoot'));
  final backdrop = find.byKey(const ValueKey('discover-backdrop'));
  final headerSurface = find.byKey(const ValueKey('discover-header-surface'));
  // Opaque at the top of the status area, clear at the bar's foot.
  List<Color> headerColors(WidgetTester tester) =>
      ((tester.widget<DecoratedBox>(headerSurface).decoration as BoxDecoration)
                  .gradient!
              as LinearGradient)
          .colors;
  final scrolledHeader = [
    KalinkaColors.background,
    KalinkaColors.background.withValues(alpha: 0),
  ];

  ScrollPosition rootPosition(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(of: rootList, matching: find.byType(Scrollable)).first,
      )
      .position;

  for (final (size, scale, reduceMotion, topInset) in [
    (const Size(375, 812), 1.0, false, 0.0),
    (const Size(375, 812), 1.0, false, 24.0),
    (const Size(768, 1024), 1.0, false, 24.0),
    (const Size(812, 375), 1.0, false, 24.0),
    (const Size(1200, 800), 1.0, false, 24.0),
    (const Size(375, 812), 2.0, true, 24.0),
  ]) {
    testWidgets(
      'Home backdrop follows content at $size, ${scale}x text, inset $topInset',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final captureKey = GlobalKey();
        await pumpSurface(
          tester,
          withHomeContent: true,
          textScale: scale,
          reduceMotion: reduceMotion,
          topInset: topInset,
          captureKey: captureKey,
        );
        await tester.pumpAndSettle();

        final headerRect = tester.getRect(find.byType(KalinkaTopBar));
        final backdropRect = tester.getRect(backdrop);
        final entry = find.descendant(
          of: find
              .descendant(of: rootList, matching: find.byType(SliverList))
              .first,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.label == 'Search',
          ),
        );
        expect(find.text('What shall we play?'), findsNothing);
        final entryRect = tester.getRect(entry);
        final bloom = find.descendant(
          of: backdrop,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                widget.decoration is BoxDecoration &&
                (widget.decoration as BoxDecoration).gradient is RadialGradient,
          ),
        );
        final gradient =
            (tester.widget<DecoratedBox>(bloom).decoration as BoxDecoration)
                    .gradient!
                as RadialGradient;
        final bloomBounds = Offset.zero & tester.getSize(bloom);
        final bloomCentre =
            tester.getTopLeft(bloom) +
            MatrixUtils.transformPoint(
              gradient.transform!.transform(bloomBounds)!,
              bloomBounds.center,
            );
        expect(bloomCentre.dy, closeTo(entryRect.center.dy, 0.1));
        expect(backdropRect.left, 0);
        expect(backdropRect.width, size.width);
        // From a little above the top, so the bloom never meets an edge.
        expect(backdropRect.top, lessThan(0));
        expect(headerRect.height, kKalinkaTopBarHeight + topInset);
        expect(tester.getRect(headerSurface), headerRect);
        // The viewport reaches the screen edge, with the header reserving its
        // initial space in the scroll; content can pass behind the gradient.
        expect(tester.getRect(rootList).top, headerRect.top);
        expect(entryRect.top, headerRect.bottom + 8);
        expect(headerColors(tester).first.a, 0);
        await _captureHome(
          tester,
          captureKey,
          'home-${size.width}-$scale-$topInset',
        );

        // One frame is enough: decoration moves with the list without easing.
        rootPosition(tester).jumpTo(80);
        await tester.pump();
        expect(
          tester.getRect(backdrop),
          backdropRect.shift(const Offset(0, -80)),
        );
        expect(tester.getRect(entry), entryRect.shift(const Offset(0, -80)));
        expect(tester.getRect(find.byType(KalinkaTopBar)), headerRect);
        expect(headerColors(tester), scrolledHeader);
        expect(tester.getRect(headerSurface).top, 0);
        expect(headerRect.overlaps(tester.getRect(entry)), isTrue);
        rootPosition(tester).jumpTo(180);
        await tester.pump();
        await _captureHome(
          tester,
          captureKey,
          'home-scrolled-${size.width}-$scale-$topInset',
        );

        expect(
          rootPosition(tester).maxScrollExtent,
          greaterThanOrEqualTo(backdropRect.bottom),
        );
        rootPosition(tester).jumpTo(backdropRect.bottom);
        await tester.pump();
        expect(tester.getRect(backdrop).bottom, lessThanOrEqualTo(0));
        expect(tester.takeException(), isNull);

        rootPosition(tester).jumpTo(0);
        await tester.pump();
        expect(tester.getRect(backdrop), backdropRect);
        expect(headerColors(tester).first.a, 0);
      },
    );
  }

  for (final (size, scale, fits) in [
    (const Size(375, 812), 1.0, false),
    (const Size(430, 932), 1.0, true),
    (const Size(812, 375), 1.0, true),
    (const Size(1200, 800), 1.0, true),
    (const Size(375, 812), 2.0, false),
  ]) {
    testWidgets(
      'pinned Home moves search into available header space at $size, $scale',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await pumpSurface(tester, withHomeContent: true, textScale: scale);
        await tester.pumpAndSettle();
        final search = find.byKey(const ValueKey('home-header-search'));
        final searchButton = find.byKey(
          const ValueKey('home-header-search-button'),
        );
        expect(find.text('What shall we play?'), findsNothing);
        expect(search, findsNothing);
        expect(searchButton, findsNothing);
        rootPosition(tester).jumpTo(61);
        await tester.pumpAndSettle();
        expect(search, findsNothing);
        expect(searchButton, findsNothing);
        rootPosition(tester).jumpTo(80);
        await tester.pumpAndSettle();
        expect(search, fits ? findsOneWidget : findsNothing);
        expect(searchButton, fits ? findsNothing : findsOneWidget);
        final entry = fits ? search : searchButton;
        final bounds = tester.getRect(entry);
        final header = tester.getRect(find.byType(KalinkaTopBar));
        expect(header.contains(bounds.topLeft), isTrue);
        expect(header.contains(bounds.bottomRight), isTrue);
        expect(bounds.size.shortestSide, greaterThanOrEqualTo(48));
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(find.byType(SearchComposer), findsOneWidget);
        await tester.tap(find.bySemanticsLabel('Close search'));
        await tester.pumpAndSettle();
        rootPosition(tester).jumpTo(0);
        await tester.pumpAndSettle();
        expect(search, findsNothing);
        expect(searchButton, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final (width, navigationVisible) in [
    (375.0, false),
    (900.0, false),
    (900.0, true),
  ]) {
    testWidgets(
      'saved results suppress header search only without the rail: $width, $navigationVisible',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final container = await pumpSurface(
          tester,
          withHomeContent: true,
          navigationVisible: navigationVisible,
        );
        await tester.pumpAndSettle();
        container.read(searchSessionProvider.notifier).submit('Evening music');
        container.read(searchSessionProvider.notifier).backToCatalogsRoot();
        await tester.pumpAndSettle();
        rootPosition(tester).jumpTo(80);
        await tester.pumpAndSettle();
        expect(
          find.byTooltip('Back to search results'),
          navigationVisible ? findsNothing : findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('home-header-search')),
          navigationVisible ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const ValueKey('home-header-search-button')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('with reduced motion the backdrop rises with the first pin', (
    tester,
  ) async {
    final container = await pumpSurface(tester, reduceMotion: true);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-pin-hint')), findsOneWidget);
    expect(find.text('What shall we play?'), findsOneWidget);
    final centred = tester.getRect(backdrop);

    await container
        .read(pinnedCatalogsProvider.notifier)
        .pin(
          PinnedCatalog(
            page: CatalogPage.category(
              id: 'kalinka:localfiles:catalog:new',
              title: 'New',
            ),
            filter: const BrowseFilterQuery(),
            preview: HomePreviewType.compact,
          ),
        );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('home-pin-hint')), findsNothing);
    expect(tester.getRect(backdrop).top, lessThan(centred.top));
    expect(tester.getRect(backdrop).top, lessThan(0));
  });

  testWidgets('an album flung down, left and opened again keeps its cover', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(427, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = await pumpSurface(tester, topInset: 24);
    void open() => container
        .read(searchSessionProvider.notifier)
        .openCatalog(id: 'kalinka:localfiles:album:example', title: 'Abbey');
    final list = find
        .descendant(
          of: find.byType(CatalogPageView),
          matching: find.byType(Scrollable),
        )
        .first;
    final cover = find.byKey(const ValueKey('album-backdrop'));

    open();
    await tester.pumpAndSettle();
    final opened = tester.getRect(cover);
    // Flings land mid-layout as later rows arrive; nothing may throw.
    for (var i = 0; i < 10; i++) {
      await tester.fling(list, const Offset(0, -400), 2000);
      await tester.pump(const Duration(milliseconds: 50));
    }
    container.read(searchSessionProvider.notifier).goBack();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    open();
    await tester.pumpAndSettle();
    expect(tester.state<ScrollableState>(list).position.pixels, 0);
    expect(tester.getRect(cover), opened);
  });

  testWidgets('an album cover stretches with its list', (tester) async {
    tester.view.physicalSize = const Size(427, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = await pumpSurface(tester, topInset: 24);
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(id: 'kalinka:localfiles:album:example', title: 'Abbey');
    await tester.pumpAndSettle();
    final cover = find.byKey(const ValueKey('album-backdrop'));
    final header = find.byType(AlbumPageHeader);
    expect(tester.getRect(cover).bottom, tester.getRect(header).bottom);

    // Pulled down past the top: the header moves, and the cover with it.
    final pull = await tester.startGesture(const Offset(200, 300));
    await pull.moveBy(const Offset(0, 120));
    await pull.moveBy(const Offset(0, 120));
    await tester.pump();
    final stretched = tester.getRect(header).bottom;
    expect(stretched, greaterThan(tester.getRect(cover).top + 1));
    expect(tester.getRect(cover).bottom, closeTo(stretched, 0.5));
    await pull.up();
    await tester.pumpAndSettle();
    expect(tester.getRect(cover).bottom, tester.getRect(header).bottom);
  });

  testWidgets('returning from a catalog restores the backdrop with the list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = await pumpSurface(tester, withHomeContent: true);
    await tester.pumpAndSettle();
    await tester.drag(rootList, const Offset(0, -160));
    await tester.pumpAndSettle();
    final offset = rootPosition(tester).pixels;
    final rect = tester.getRect(backdrop);
    expect(offset, greaterThan(52));

    container
        .read(searchSessionProvider.notifier)
        .openCatalog(
          id: 'kalinka:localfiles:catalog:albums',
          title: 'My Albums',
        );
    await tester.pumpAndSettle();
    expect(backdrop, findsNothing);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(rootPosition(tester).pixels, offset);
    expect(tester.getRect(backdrop), rect);
    expect(headerColors(tester), scrolledHeader);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a catalog page carries the filter control, and it opens', (
    tester,
  ) async {
    final container = await pumpSurface(tester);

    container
        .read(searchSessionProvider.notifier)
        .openCatalog(
          id: 'kalinka:localfiles:catalog:albums',
          title: 'My Albums',
          // The control stands for what the source declared, so a category
          // that declared nothing has none to show.
          filters: const [
            FilterSpec(
              id: 'q',
              kind: FilterKind.text,
              label: 'Search albums and artists',
            ),
            FilterSpec(
              id: 'genre',
              kind: FilterKind.choice,
              label: 'Genre',
              ops: [FilterOp.any],
            ),
          ],
        );
    await tester.pumpAndSettle();

    expect(find.byType(SearchFilterButton), findsNothing);
    expect(find.byTooltip('Filters'), findsOneWidget);

    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('FILTERS'), findsOneWidget);

    // Cancel folds it away again without touching the applied filter.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('FILTERS'), findsNothing);
    expect(container.read(searchSessionProvider).catalogFilter.isEmpty, isTrue);
  });

  for (final width in [375.0, 1100.0]) {
    testWidgets(
      'results reuse Home search and clear opens an empty draft at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final captureKey = GlobalKey();
        final container = await pumpSurface(
          tester,
          captureKey: captureKey,
          modules: [
            ModuleInfo(
              name: 'qobuz',
              title: 'Qobuz',
              enabled: true,
              state: ModuleState.ready,
              capabilities: const [ModuleCapability.catalogs],
            ),
          ],
        );
        container.read(searchSessionProvider.notifier).submit('the beatles');
        // Past the minimum loading hold, so the legs have landed.
        await tester.pump(const Duration(milliseconds: 700));

        expect(find.text('the beatles'), findsOneWidget);
        expect(find.byType(SearchFilterButton), findsNothing);
        expect(find.byType(CatalogFiltersButton), findsOneWidget);
        expect(find.byType(SearchComposer), findsNothing);
        expect(find.byType(TextField), findsNothing);
        final searchWidth = tester
            .getSize(find.byKey(const ValueKey('results-search-entry')))
            .width;
        expect(searchWidth, lessThanOrEqualTo(kHomeSearchMaxWidth));
        if (width > kHomeSearchMaxWidth + 200) {
          expect(searchWidth, kHomeSearchMaxWidth);
        }
        expect(
          tester.widget<Text>(find.text('the beatles')).style,
          KalinkaTextStyles.searchPlaceholder,
        );
        await tester.tap(find.byKey(const ValueKey('results-search-entry')));
        await tester.pumpAndSettle();
        expect(find.byType(SearchComposer), findsOneWidget);
        final composer = find.byType(TextField);
        expect(
          tester.widget<TextField>(composer).controller!.text,
          'the beatles',
        );

        await _captureHome(tester, captureKey, 'search-edit-$width');

        // Editing and dismissing uses the same draft rules as Home.
        await tester.enterText(composer, 'discarded draft');
        await tester.tap(find.byType(OverlayCloseButton));
        await tester.pumpAndSettle();
        expect(
          container.read(searchSessionProvider).searchQuery,
          'the beatles',
        );
        await tester.tap(find.byTooltip('Clear search'));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(composer).controller!.text, isEmpty);
        await _captureHome(tester, captureKey, 'search-empty-$width');
        expect(
          container.read(searchSessionProvider).searchQuery,
          'the beatles',
        );
        await tester.tap(find.byType(OverlayCloseButton));
        await tester.pumpAndSettle();
        expect(find.text('the beatles'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('results-search-entry')));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(composer).controller!.text,
          'the beatles',
        );
        await tester.enterText(composer, 'abbey road');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pump();
        expect(container.read(searchSessionProvider).searchQuery, 'abbey road');
        await tester.pump(const Duration(milliseconds: 700));
        expect(find.text('abbey road'), findsOneWidget);
      },
    );
  }

  Future<void> openSearch(WidgetTester tester) async {
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == 'Search',
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the smart search card names itself and closes', (tester) async {
    await pumpSurface(
      tester,
      modules: [
        ModuleInfo(
          name: 'localfiles',
          title: 'My Library',
          enabled: true,
          state: ModuleState.ready,
          capabilities: const [ModuleCapability.aiSearch],
        ),
      ],
    );
    await openSearch(tester);

    // The card carries its own name and dismiss, the same chrome the filter
    // card uses, so the composer inside it needs neither.
    expect(find.text('SMART SEARCH'), findsOneWidget);

    await tester.tap(find.byType(OverlayCloseButton));
    await tester.pumpAndSettle();
    expect(find.text('SMART SEARCH'), findsNothing);
  });

  group('curated prompts under the search entry', () {
    const suggestions = [
      SearchSuggestion(query: 'calm piano for deep focus'),
      SearchSuggestion(query: 'upbeat indie'),
      SearchSuggestion(query: 'something unvetted', experimental: true),
    ];
    final smartLibrary = ModuleInfo(
      name: 'localfiles',
      title: 'My Library',
      enabled: true,
      state: ModuleState.ready,
      capabilities: const [ModuleCapability.aiSearch],
    );

    testWidgets('run as searches of exactly their words', (tester) async {
      final container = await pumpSurface(
        tester,
        modules: [smartLibrary],
        suggestions: suggestions,
      );
      await tester.pumpAndSettle();

      expect(find.text('upbeat indie'), findsOneWidget);
      expect(find.text('something unvetted'), findsNothing);
      // Marked by what each asks for.
      for (final (query, icon) in [
        ('calm piano for deep focus', Icons.menu_book_outlined),
        ('upbeat indie', Icons.equalizer_rounded),
      ]) {
        final chip = find.ancestor(
          of: find.text(query),
          matching: find.byType(InkWell),
        );
        expect(
          find.descendant(of: chip, matching: find.byIcon(icon)),
          findsOneWidget,
        );
        // No taller than the search entry above them.
        expect(
          tester.getSize(chip).height,
          lessThanOrEqualTo(
            tester
                .getSize(
                  find
                      .byWidgetPredicate(
                        (w) => w is Semantics && w.properties.label == 'Search',
                      )
                      .first,
                )
                .height,
          ),
        );
      }
      // Under the note on which sources answer.
      expect(
        tester.getTopLeft(find.text('upbeat indie')).dy,
        greaterThan(
          tester.getBottomLeft(find.textContaining('Smart search · ')).dy,
        ),
      );

      await tester.tap(find.text('calm piano for deep focus'));
      await tester.pumpAndSettle();
      final session = container.read(searchSessionProvider);
      expect(session.activeView, FindMusicView.results);
      expect(session.searchQuery, 'calm piano for deep focus');
    });

    testWidgets('are absent without smart search', (tester) async {
      await pumpSurface(tester, suggestions: suggestions);
      await tester.pumpAndSettle();
      expect(find.text('upbeat indie'), findsNothing);
    });
  });

  testWidgets('without smart search the card is a plain name search', (
    tester,
  ) async {
    await pumpSurface(tester);
    expect(
      find.text('Search your music by artist, album or track.'),
      findsNothing,
    );
    await openSearch(tester);

    expect(find.text('SMART SEARCH'), findsNothing);
    expect(find.text('SEARCH'), findsOneWidget);
    expect(find.textContaining('mood'), findsNothing);
  });

  testWidgets('the expanded catalog keeps its title in the page only', (
    tester,
  ) async {
    final container = await pumpSurface(tester);
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(
          id: 'kalinka:localfiles:catalog:albums',
          title: 'My Albums',
        );
    await tester.pumpAndSettle();

    expect(find.text('My Albums'), findsOneWidget);
    expect(find.byKey(const ValueKey('catalog-collapsed-title')), findsNothing);
    expect(find.text('HOME'), findsNothing);
  });

  testWidgets('a page of folders shows its trail in the bar', (tester) async {
    final container = await pumpSurface(tester);
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(
          id: 'kalinka:localfiles:catalog:files',
          title: 'My Library',
          folderLayout: true,
        );
    await tester.pumpAndSettle();

    expect(find.text('My Library'), findsOneWidget);
    expect(find.byType(FolderTrail), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(container.read(searchSessionProvider).catalogPage.isRoot, isTrue);
  });

  testWidgets('back leaves the app only from the top level', (tester) async {
    final container = await pumpSurface(tester);
    bool canPop() => tester
        .widget<PopScope>(
          find
              .descendant(
                of: find.byType(SearchSessionView),
                matching: find.byWidgetPredicate((w) => w is PopScope),
              )
              .first,
        )
        .canPop;

    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(canPop(), isTrue);

    container
        .read(searchSessionProvider.notifier)
        .openCatalog(
          id: 'kalinka:localfiles:catalog:albums',
          title: 'My Albums',
        );
    await tester.pumpAndSettle();
    expect(canPop(), isFalse);
  });

  testWidgets('a panel over Home takes the back press', (tester) async {
    final container = makeContainer();
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(
          id: 'kalinka:localfiles:catalog:albums',
          title: 'My Albums',
        );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SearchSessionView(handlesBack: false)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(container.read(searchSessionProvider).catalogPage.isRoot, isFalse);
  });
}
