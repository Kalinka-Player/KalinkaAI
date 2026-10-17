import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/catalog_cards_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/indexer_status_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/browse_filters/search_filter_button.dart';
import 'package:kalinka/widgets/kalinka_top_bar.dart';
import 'package:kalinka/widgets/overlay_card.dart';
import 'package:kalinka/widgets/search/folder_trail.dart';
import 'package:kalinka/widgets/search/album_page_header.dart';
import 'package:kalinka/widgets/search_cards/search_track_row.dart';
import 'package:kalinka/widgets/search/search_session_view.dart';

/// Mounting the whole Find Music surface is the only thing that exercises its
/// `initState` — where a second AnimationController on a
/// SingleTickerProviderStateMixin threw on the first build.
class _FakeApi implements KalinkaPlayerProxy {
  final bool withHomeContent;
  _FakeApi({this.withHomeContent = false});

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
  }) async => const SearchSuggestionList(suggestions: []);

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
  }) {
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        kalinkaProxyProvider.overrideWithValue(
          _FakeApi(withHomeContent: withHomeContent),
        ),
        sourceModulesProvider.overrideWith((ref) => modules),
        connectionStateProvider.overrideWith(_FixedConnection.new),
        playerStateProvider.overrideWithValue(PlaybackState.empty),
        catalogCardGroupsProvider.overrideWith(
          (ref) async => [
            if (withHomeContent)
              CatalogCardGroup(
                sourceName: 'localfiles',
                sourceTitle: 'My music',
                cards: [
                  for (var i = 0; i < 6; i++)
                    CatalogCardPlan(
                      id: 'kalinka:localfiles:catalog:$i',
                      title: 'Catalog $i',
                      sourceName: 'localfiles',
                    ),
                ],
              ),
          ],
        ),
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
  }) async {
    final container = makeContainer(
      modules: modules,
      withHomeContent: withHomeContent,
    );
    container.read(searchSessionProvider.notifier).refresh();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: reduceMotion,
              padding: EdgeInsets.only(top: topInset),
            ),
            child: child!,
          ),
          home: const Scaffold(body: SearchSessionView()),
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
    (const Size(812, 375), 1.0),
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
        expect(find.byType(AlbumArtwork), findsOneWidget);
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

        final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        scrollable.position.jumpTo(80);
        await tester.pump();
        expect(tester.getRect(cover), coverRect.shift(const Offset(0, -80)));
        expect(tester.getRect(surface), navRect);
        expect(
          tester.widget<ColoredBox>(surface).color,
          KalinkaColors.background,
        );
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
  final artwork = find.byWidgetPredicate(
    (widget) =>
        widget is SvgPicture &&
        widget.bytesLoader is SvgAssetLoader &&
        (widget.bytesLoader as SvgAssetLoader).assetName ==
            'assets/images/header_artwork.svg',
  );

  ScrollPosition rootPosition(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(of: rootList, matching: find.byType(Scrollable)).first,
      )
      .position;

  for (final (size, scale, reduceMotion) in [
    (const Size(375, 812), 1.0, false),
    (const Size(812, 375), 1.0, false),
    (const Size(1200, 800), 1.0, false),
    (const Size(375, 812), 2.0, true),
  ]) {
    testWidgets('Home backdrop follows content at $size, ${scale}x text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpSurface(
        tester,
        withHomeContent: true,
        textScale: scale,
        reduceMotion: reduceMotion,
        topInset: 24,
      );
      await tester.pumpAndSettle();

      final headerRect = tester.getRect(find.byType(KalinkaTopBar));
      final backdropRect = tester.getRect(backdrop);
      final artRect = tester.getRect(artwork);
      final titleRect = tester.getRect(find.text('What shall we play?'));
      expect(headerRect.height, kKalinkaTopBarHeight + 24);
      expect(tester.widget<ColoredBox>(headerSurface).color.a, 0);

      // One frame is enough: decoration moves with the list without easing.
      rootPosition(tester).jumpTo(80);
      await tester.pump();
      expect(
        tester.getRect(backdrop),
        backdropRect.shift(const Offset(0, -80)),
      );
      expect(tester.getRect(artwork), artRect.shift(const Offset(0, -80)));
      expect(
        tester.getRect(find.text('What shall we play?')),
        titleRect.shift(const Offset(0, -80)),
      );
      expect(tester.getRect(find.byType(KalinkaTopBar)), headerRect);
      expect(
        tester.widget<ColoredBox>(headerSurface).color,
        KalinkaColors.background,
      );

      expect(
        rootPosition(tester).maxScrollExtent,
        greaterThanOrEqualTo(backdropRect.height),
      );
      rootPosition(tester).jumpTo(backdropRect.height);
      await tester.pump();
      expect(tester.getRect(backdrop).bottom, lessThanOrEqualTo(0));
      expect(tester.takeException(), isNull);

      rootPosition(tester).jumpTo(0);
      await tester.pump();
      expect(tester.getRect(backdrop), backdropRect);
      expect(tester.widget<ColoredBox>(headerSurface).color.a, 0);
    });
  }

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
    await tester.tap(find.text('HOME'));
    await tester.pumpAndSettle();

    expect(rootPosition(tester).pixels, offset);
    expect(tester.getRect(backdrop), rect);
    expect(
      tester.widget<ColoredBox>(headerSurface).color,
      KalinkaColors.background,
    );
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
          ],
        );
    await tester.pumpAndSettle();

    expect(find.byType(SearchFilterButton), findsOneWidget);

    await tester.tap(find.byType(SearchFilterButton));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('SEARCH & FILTERS'), findsOneWidget);

    // Cancel folds it away again without touching the applied filter.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('SEARCH & FILTERS'), findsNothing);
    expect(container.read(searchSessionProvider).catalogFilter.isEmpty, isTrue);
  });

  testWidgets('the Results view carries the filter control, and it opens', (
    tester,
  ) async {
    final container = await pumpSurface(
      tester,
      modules: [
        ModuleInfo(
          name: 'qobuz',
          title: 'Qobuz',
          enabled: true,
          state: ModuleState.ready,
        ),
      ],
    );
    container.read(searchSessionProvider.notifier).submit('the beatles');
    // Past the minimum loading hold, so the legs have landed.
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byType(SearchFilterButton), findsOneWidget);

    await tester.tap(find.byType(SearchFilterButton));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('REFINE RESULTS'), findsOneWidget);
    // The field re-searches rather than narrowing, and says so.
    expect(find.text('A new query starts a new search.'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('REFINE RESULTS'), findsNothing);
    expect(container.read(searchSessionProvider).resultsFilter.isEmpty, isTrue);
  });

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

  testWidgets('without smart search the card is a plain name search', (
    tester,
  ) async {
    await pumpSurface(tester);
    expect(
      find.text('Search your music by artist, album or track.'),
      findsOneWidget,
    );
    await openSearch(tester);

    expect(find.text('SMART SEARCH'), findsNothing);
    expect(find.text('SEARCH'), findsOneWidget);
    expect(find.textContaining('mood'), findsNothing);
  });

  testWidgets('the HOME crumb goes back, like the arrow', (tester) async {
    final container = await pumpSurface(tester);
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(
          id: 'kalinka:localfiles:catalog:albums',
          title: 'My Albums',
        );
    await tester.pumpAndSettle();
    expect(container.read(searchSessionProvider).catalogPage.isRoot, isFalse);

    await tester.tap(find.text('HOME'));
    await tester.pumpAndSettle();
    expect(container.read(searchSessionProvider).catalogPage.isRoot, isTrue);
  });

  testWidgets('a page of folders keeps the bar\'s crumb, its trail below', (
    tester,
  ) async {
    final container = await pumpSurface(tester);
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(
          id: 'kalinka:localfiles:catalog:files',
          title: 'My Library',
          folderLayout: true,
        );
    await tester.pumpAndSettle();

    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('MY LIBRARY'), findsOneWidget);
    expect(find.byType(FolderTrail), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(container.read(searchSessionProvider).catalogPage.isRoot, isTrue);
  });

  testWidgets('the HOME crumb highlights under the pointer', (tester) async {
    final container = await pumpSurface(tester);
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(
          id: 'kalinka:localfiles:catalog:albums',
          title: 'My Albums',
        );
    await tester.pumpAndSettle();

    Color? crumbFill() {
      final box = tester.widget<AnimatedContainer>(
        find
            .ancestor(
              of: find.text('HOME'),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      return (box.decoration as BoxDecoration).color;
    }

    expect(crumbFill(), Colors.transparent);

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);
    await pointer.moveTo(tester.getCenter(find.text('HOME')));
    await tester.pumpAndSettle();
    expect(crumbFill()!.a, greaterThan(0));
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
