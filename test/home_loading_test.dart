import 'support/receivers.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/browse_filters.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/box_control_provider.dart';
import 'package:kalinka/providers/collections_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/catalog_section_provider.dart';
import 'package:kalinka/providers/pinned_catalogs_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/browse_rows_shimmer.dart';
import 'package:kalinka/widgets/home/catalog_tile.dart';
import 'package:kalinka/widgets/home/home_list_preview.dart';
import 'package:kalinka/widgets/home/home_pins_shimmer.dart';
import 'package:kalinka/widgets/home/home_section_plan.dart';
import 'package:kalinka/widgets/home/pinned_catalogs_section.dart';
import 'package:kalinka/widgets/home/planned_home_sections.dart';
import 'package:kalinka/widgets/home/preview_shelf.dart';
import 'package:kalinka/widgets/loading_shimmer.dart';
import 'package:kalinka/widgets/search/catalog_cards_section.dart';
import 'package:kalinka/widgets/search/collections_section.dart';
import 'package:kalinka/widgets/search/search_zero_state.dart';

import 'support/home_shell.dart' show SettableConnection;
import 'support/server_answer.dart';
import 'support/adaptive_home_fixtures.dart' show demoAlbum, demoTrack;

class _Connected extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

ModuleInfo _module(String name, {bool catalogs = true}) => ModuleInfo(
  name: name,
  title: name,
  enabled: true,
  state: ModuleState.ready,
  capabilities: [if (catalogs) ModuleCapability.catalogs],
);

BrowseItem _root(String source) => BrowseItem(
  id: 'kalinka:$source:catalog:root',
  canBrowse: true,
  canAdd: false,
  catalog: Catalog(id: 'kalinka:$source:catalog:root', title: source),
);

/// One compact pin titled [title], as the app keeps a list of them.
String _savedPin(String title) => jsonEncode([
  PinnedCatalog(
    page: CatalogPage.category(
      id: 'kalinka:Alpha:catalog:${title.length}',
      title: title,
    ),
    filter: const BrowseFilterQuery(),
    preview: HomePreviewType.compact,
  ).toJson(),
]);

class _DelayedApi implements KalinkaPlayerProxy {
  final roots = Completer<BrowseItemsList>();
  final preview = Completer<BrowseItemsList>();
  final previews = <String, Completer<BrowseItemsList>>{};
  final metadata = <String, Completer<BrowseItem>>{};
  final calls = <String>[];

  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) {
    calls.add(id);
    return id.isEmpty ? roots.future : (previews[id] ?? preview).future;
  }

  @override
  Future<BrowseItem> getMetadata(String id) => metadata[id]!.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<ProviderContainer> _mount(
  WidgetTester tester, {
  required _DelayedApi api,
  required Future<List<ModuleInfo>> modules,
  List<HomePreviewType> pins = const [],
  Size size = const Size(560, 1400),
  double textScale = 1,
  bool reducedMotion = false,
  ServersByHost? servers,
  Map<String, Object> saved = const {},
  List<PinnedCatalog> catalogs = const [],
  HomeSectionPlanner? planner,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    'Kalinka.host': 'localhost',
    'Kalinka.port': 8080,
    ...saved,
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      noReceivers,
      sharedPrefsProvider.overrideWithValue(prefs),
      kalinkaProxyProvider.overrideWithValue(api),
      if (servers == null) ...[
        connectionStateProvider.overrideWith(_Connected.new),
        serverAnswering('box-1'),
      ] else ...[
        connectionStateProvider.overrideWith(SettableConnection.new),
        servers.client,
      ],
      sourceModulesProvider.overrideWith((ref) => modules),
      collectionsShelfProvider.overrideWith((ref) async => null),
      homeSectionPlannerProvider.overrideWithValue(
        planner ??
            HomeSectionPlanner(
              calculate: (input) async => planHomeSections(input),
            ),
      ),
    ],
  );
  addTearDown(container.dispose);
  if (servers == null) await container.read(serverAnswerProvider.future);
  for (final type in pins) {
    await container
        .read(pinnedCatalogsProvider.notifier)
        .pin(
          PinnedCatalog(
            page: CatalogPage.category(
              id: 'kalinka:Alpha:catalog:${type.name}',
              title: '${type.label} selection',
            ),
            filter: const BrowseFilterQuery(),
            preview: type,
          ),
        );
  }
  for (final pin in catalogs) {
    await container.read(pinnedCatalogsProvider.notifier).pin(pin);
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reducedMotion,
          ),
          child: child!,
        ),
        home: Scaffold(
          // Customise Home keeps the source tiles; their loading is checked
          // here beside Home's own sections.
          body: SearchZeroState(
            onOpenCatalog: (_, _, {focusItemId}) {},
            leading: const [CatalogCardsSection()],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  for (final width in [375.0, 1248.0]) {
    testWidgets('pins reveal together after data and layout at $width', (
      tester,
    ) async {
      const types = [
        HomePreviewType.automatic,
        HomePreviewType.large,
        HomePreviewType.cards,
        HomePreviewType.list,
        HomePreviewType.compact,
      ];
      final api = _DelayedApi()
        ..roots.complete(BrowseItemsList(0, 100, 0, const []));
      for (final type in types) {
        api.previews['kalinka:Alpha:catalog:${type.name}'] = Completer();
      }
      final jobs = <HomeSectionRequest>[];
      final layout = Completer<HomeSectionLayout>();
      final container = await _mount(
        tester,
        api: api,
        modules: Future.value([_module('Alpha')]),
        pins: types,
        size: Size(width, 900),
        reducedMotion: true,
        textScale: width == 375 ? 2 : 1,
        planner: HomeSectionPlanner(
          calculate: (request) {
            jobs.add(request);
            return layout.future;
          },
        ),
      );
      final shimmer = find.byType(HomePinsShimmer);
      final before = tester.getRect(shimmer);
      final element = tester.element(shimmer);
      for (final type in types) {
        api.previews['kalinka:Alpha:catalog:${type.name}']!.complete(
          BrowseItemsList(0, 8, 1, [_root('Alpha')]),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(shimmer, findsOneWidget);
        expect(tester.element(shimmer), same(element));
        expect(tester.getRect(shimmer), before);
        expect(find.byType(PinnedCatalogPreview), findsNothing);
        if (type != types.last) expect(jobs, isEmpty);
      }
      expect(jobs, hasLength(1));
      layout.complete(planHomeSections(jobs.single));
      await tester.pumpAndSettle();
      expect(shimmer, findsNothing);
      expect(find.byType(PinnedCatalogPreview), findsNWidgets(types.length));
      expect(find.byType(HomeListPreviewShimmer), findsNothing);
      expect(find.byType(PreviewShelfShimmer), findsNothing);
      final calls = api.calls.length;
      await tester.pump(const Duration(seconds: 1));
      expect(api.calls, hasLength(calls));
      expect(jobs, hasLength(1));

      // Refresh holds all pins again, even though the unchanged geometry is
      // cached. Once the last response arrives it can reveal without a worker.
      for (final id in api.previews.keys.toList()) {
        api.previews[id] = Completer();
      }
      container.invalidate(pinnedPreviewProvider);
      await tester.pump();
      expect(shimmer, findsOneWidget);
      expect(find.byType(PinnedCatalogPreview), findsNothing);
      for (final response in api.previews.values) {
        response.complete(BrowseItemsList(0, 8, 1, [_root('Alpha')]));
      }
      await tester.pumpAndSettle();
      expect(shimmer, findsNothing);
      expect(jobs, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('folder verification finishes before any pins are revealed', (
    tester,
  ) async {
    final album = demoAlbum('verified', 'Verified album', 'Artist');
    final track = demoTrack(
      'one',
      'Folder track',
      'Artist',
      album: album.album,
    );
    final api = _DelayedApi()
      ..roots.complete(BrowseItemsList(0, 100, 0, const []));
    final pins = [
      for (final id in ['first', 'second'])
        PinnedCatalog(
          page: CatalogPage.category(
            id: 'kalinka:localfiles:catalog:$id',
            title: id,
            folderLayout: true,
          ),
          filter: const BrowseFilterQuery(),
          preview: HomePreviewType.automatic,
        ),
    ];
    for (final pin in pins) {
      api.previews[pin.page.id!] = Completer();
    }
    api.previews[album.id] = Completer()
      ..complete(BrowseItemsList(0, 200, 1, [track]));
    api.metadata[album.id] = Completer();
    final jobs = <HomeSectionRequest>[];
    await _mount(
      tester,
      api: api,
      modules: Future.value([_module('localfiles')]),
      catalogs: pins,
      reducedMotion: true,
      planner: HomeSectionPlanner(
        calculate: (request) async {
          jobs.add(request);
          return planHomeSections(request);
        },
      ),
    );
    final shimmer = find.byType(HomePinsShimmer);
    final before = tester.getRect(shimmer);
    for (final pin in pins) {
      api.previews[pin.page.id!]!.complete(BrowseItemsList(0, 8, 1, [track]));
      await tester.pumpAndSettle();
      expect(shimmer, findsOneWidget);
      expect(tester.getRect(shimmer), before);
      expect(find.text('Folder track'), findsNothing);
      expect(find.byType(HomeAlbumFolderGroup), findsNothing);
      expect(jobs, isEmpty);
    }
    api.metadata[album.id]!.complete(album);
    await tester.pumpAndSettle();
    expect(shimmer, findsNothing);
    expect(find.byType(HomeAlbumFolderGroup), findsOneWidget);
    expect(jobs, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed preview reveals Retry and can load again', (
    tester,
  ) async {
    final api = _DelayedApi()
      ..roots.complete(BrowseItemsList(0, 100, 0, const []));
    const id = 'kalinka:Alpha:catalog:automatic';
    api.previews[id] = Completer();
    await _mount(
      tester,
      api: api,
      modules: Future.value([_module('Alpha')]),
      pins: [HomePreviewType.automatic],
      reducedMotion: true,
    );
    api.previews[id]!.completeError(StateError('Offline'));
    await tester.pumpAndSettle();
    expect(find.byType(HomePinsShimmer), findsNothing);
    final retry = find.text('Could not load preview. Retry');
    expect(retry, findsOneWidget);
    api.previews[id] = Completer();
    await tester.tap(retry);
    await tester.pump();
    expect(find.byType(HomePinsShimmer), findsOneWidget);
    api.previews[id]!.complete(BrowseItemsList(0, 8, 0, const []));
    await tester.pumpAndSettle();
    expect(find.byType(HomePinsShimmer), findsNothing);
    expect(retry, findsNothing);
    expect(find.text('No items match this catalog.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'slow Home loading keeps one pin placeholder until all data arrives',
    (tester) async {
      final modules = Completer<List<ModuleInfo>>();
      final api = _DelayedApi();
      await _mount(
        tester,
        api: api,
        modules: modules.future,
        pins: [
          HomePreviewType.list,
          HomePreviewType.compact,
          HomePreviewType.cards,
        ],
      );
      final sources = find.byType(CatalogCardsSection);
      expect(find.text('LISTENING ON'), findsNothing);
      final sourceTiles = find.descendant(
        of: sources,
        matching: find.byType(CatalogTileShimmer),
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('Unavailable'), findsNothing);
      expect(sourceTiles, findsNWidgets(3));
      // Collections hold no place until there are some.
      expect(
        find.descendant(
          of: find.byType(CollectionsSection),
          matching: find.byType(BrowseRowsShimmer),
        ),
        findsNothing,
      );
      expect(find.byType(HomePinsShimmer), findsOneWidget);
      expect(find.byType(PinnedCatalogPreview), findsNothing);
      final placeholderRect = tester.getRect(find.byType(HomePinsShimmer));
      expect(api.calls, isEmpty);

      modules.complete([
        _module('Alpha'),
        _module('Beta'),
        _module('Receiver', catalogs: false),
      ]);
      await tester.pump();
      await tester.pump();
      expect(sourceTiles, findsNWidgets(2));
      expect(find.textContaining('Unavailable'), findsNothing);
      final grid = find.descendant(
        of: sources,
        matching: find.byType(CatalogTileGrid),
      );
      final loadingRect = tester.getRect(grid);
      api.roots.complete(
        BrowseItemsList(0, 100, 3, [
          _root('Alpha'),
          _root('Beta'),
          _root('Receiver'),
        ]),
      );
      await tester.pump();
      await tester.pump();
      expect(sourceTiles, findsNothing);
      expect(
        find.descendant(of: sources, matching: find.byType(CatalogTile)),
        findsNWidgets(2),
      );
      expect(tester.getRect(grid), loadingRect);
      expect(
        find.byKey(const ValueKey('customise-home-button')),
        findsOneWidget,
      );
      expect(find.byType(HomePinsShimmer), findsOneWidget);
      expect(
        tester.getRect(find.byType(HomePinsShimmer)).size,
        placeholderRect.size,
      );
      expect(find.byType(PinnedCatalogPreview), findsNothing);

      api.preview.complete(BrowseItemsList(0, 8, 0, const []));
      await tester.pumpAndSettle();
      expect(find.byType(ShimmerPulse), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('Unavailable'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Home shows no pins until the server says who it is, keeps them while it '
    'is away, and waits for it again once back',
    (tester) async {
      final servers = ServersByHost()
        ..ids['localhost'] = 'box-a'
        ..silent.add('localhost');
      final container = await _mount(
        tester,
        api: _DelayedApi()
          ..preview.complete(BrowseItemsList(0, 1, 0, const [])),
        modules: Future.value([_module('Alpha')]),
        servers: servers,
        saved: {
          'Kalinka.pinnedCatalogs.v1:id:box-a': _savedPin('Box pick'),
          'Kalinka.pinnedCatalogs.v1:http://localhost:8080': _savedPin(
            'Address pick',
          ),
        },
      );
      void expectLoading() {
        expect(find.byType(HomePinsShimmer), findsOneWidget);
        expect(find.byKey(const ValueKey('home-pin-hint')), findsNothing);
        expect(find.text('Box pick'), findsNothing);
        expect(find.text('Address pick'), findsNothing);
      }

      void expectPins() {
        expect(find.byType(HomePinsShimmer), findsNothing);
        expect(find.text('Box pick'), findsOneWidget);
        expect(find.text('Address pick'), findsNothing);
      }

      // Dio's request needs the clock to move, not only a frame.
      Future<void> settle([Duration by = const Duration(milliseconds: 1)]) =>
          tester.pump(by);

      await settle();
      expect(servers.asked, 1);
      expectLoading();

      // A failed call is asked again, first after two seconds.
      servers.silent.clear();
      await settle(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      expect(servers.asked, 2);
      expectPins();

      final connection = container.read(
        connectionStateProvider.notifier,
      ) as SettableConnection;
      connection.set(ConnectionStatus.reconnecting);
      await settle();
      expectPins();
      // Back, whoever is at the address now has to say so first.
      servers.silent.add('localhost');
      connection.set(ConnectionStatus.connected);
      await settle();
      expect(servers.asked, 3);
      expectLoading();

      servers.silent.clear();
      connection.set(ConnectionStatus.reconnecting);
      await settle();
      connection.set(ConnectionStatus.connected);
      await settle();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      expect(servers.asked, 4);
      expectPins();
    },
  );

  testWidgets(
    'with the server away from the start, Home shows the pins of the one '
    'last recorded at its address',
    (tester) async {
      final servers = ServersByHost()..silent.add('localhost');
      final container = await _mount(
        tester,
        api: _DelayedApi()
          ..preview.complete(BrowseItemsList(0, 1, 0, const [])),
        modules: Future.value([_module('Alpha')]),
        servers: servers,
        saved: {
          'Kalinka.serverIdAt.localhost:8080': 'box-a',
          'Kalinka.pinnedCatalogs.v1:id:box-a': _savedPin('Box pick'),
        },
      );
      (container.read(connectionStateProvider.notifier) as SettableConnection)
          .set(ConnectionStatus.reconnecting);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      expect(find.byType(HomePinsShimmer), findsNothing);
      expect(find.text('Box pick'), findsOneWidget);
    },
  );

  testWidgets(
    'unsupported sources leave no source placeholders or customise action',
    (tester) async {
      final modules = Completer<List<ModuleInfo>>();
      final api = _DelayedApi();
      await _mount(tester, api: api, modules: modules.future);
      expect(find.byType(CatalogTileShimmer), findsNWidgets(3));
      modules.complete([_module('Receiver', catalogs: false)]);
      await tester.pumpAndSettle();
      expect(find.byType(ShimmerPulse), findsNothing);
      expect(find.byKey(const ValueKey('customise-home-button')), findsNothing);
      expect(api.calls, isEmpty);
    },
  );

  for (final width in [375.0, 600.0]) {
    testWidgets(
      'source placeholders match loaded tiles at width $width and large text',
      (tester) async {
        final api = _DelayedApi();
        await _mount(
          tester,
          api: api,
          modules: Future.value([_module('Alpha'), _module('Beta')]),
          size: Size(width, 812),
          textScale: 2,
          reducedMotion: true,
        );
        await tester.pumpAndSettle();
        final grid = find.byType(CatalogTileGrid);
        final before = tester.getRect(grid);
        expect(find.byType(CatalogTileShimmer), findsNWidgets(2));
        expect(tester.binding.hasScheduledFrame, isFalse);
        api.roots.complete(
          BrowseItemsList(0, 100, 2, [_root('Alpha'), _root('Beta')]),
        );
        await tester.pumpAndSettle();
        expect(tester.getRect(grid), before);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('shared shimmer honours reduced motion when it changes', (
    tester,
  ) async {
    Future<void> mount(bool reducedMotion) => tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reducedMotion),
          child: Scaffold(
            body: Column(
              children: [
                const BrowseRowsShimmer(count: 1),
                PreviewShelfShimmer(
                  preview: Preview(type: PreviewType.imageText),
                ),
                const CatalogTileShimmer(),
              ],
            ),
          ),
        ),
      ),
    );
    await mount(false);
    final pulses = find.byType(ShimmerPulse);
    expect(pulses, findsNWidgets(3));
    final fade = find.descendant(
      of: pulses.first,
      matching: find.byType(FadeTransition),
    );
    final initial = tester.widget<FadeTransition>(fade).opacity.value;
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.widget<FadeTransition>(fade).opacity.value,
      greaterThan(initial),
    );
    await mount(true);
    await tester.pumpAndSettle();
    expect(fade, findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await mount(false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(fade, findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
