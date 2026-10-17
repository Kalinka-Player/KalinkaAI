import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/browse_filters.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/collections_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/pinned_catalogs_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/browse_rows_shimmer.dart';
import 'package:kalinka/widgets/home/catalog_tile.dart';
import 'package:kalinka/widgets/home/preview_shelf.dart';
import 'package:kalinka/widgets/loading_shimmer.dart';
import 'package:kalinka/widgets/search/catalog_cards_section.dart';
import 'package:kalinka/widgets/search/collections_section.dart';
import 'package:kalinka/widgets/search/search_zero_state.dart';

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

class _DelayedApi implements KalinkaPlayerProxy {
  final roots = Completer<BrowseItemsList>();
  final preview = Completer<BrowseItemsList>();
  final calls = <String>[];

  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) {
    calls.add(id);
    return id.isEmpty ? roots.future : preview.future;
  }

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
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    'Kalinka.host': 'localhost',
    'Kalinka.port': 8080,
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      kalinkaProxyProvider.overrideWithValue(api),
      connectionStateProvider.overrideWith(_Connected.new),
      sourceModulesProvider.overrideWith((ref) => modules),
      collectionsShelfProvider.overrideWith((ref) async => null),
    ],
  );
  addTearDown(container.dispose);
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
          body: SearchZeroState(onOpenCatalog: (_, _, {focusItemId}) {}),
        ),
      ),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  testWidgets(
    'slow Home loading keeps section-shaped placeholders until data arrives',
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
      final sourceTiles = find.descendant(
        of: sources,
        matching: find.byType(CatalogTileShimmer),
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('Unavailable'), findsNothing);
      expect(sourceTiles, findsNWidgets(3));
      expect(
        find.descendant(
          of: find.byType(CollectionsSection),
          matching: find.byType(BrowseRowsShimmer),
        ),
        findsOneWidget,
      );
      expect(find.byType(PreviewShelfShimmer), findsNWidgets(2));
      expect(
        tester
            .widgetList<BrowseRowsShimmer>(find.byType(BrowseRowsShimmer))
            .map((s) => s.count),
        contains(5),
      );
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
      expect(find.text('Customise Home'), findsOneWidget);
      expect(find.byType(PreviewShelfShimmer), findsNWidgets(2));

      api.preview.complete(BrowseItemsList(0, 8, 0, const []));
      await tester.pumpAndSettle();
      expect(find.byType(ShimmerPulse), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('Unavailable'), findsNothing);
      expect(tester.takeException(), isNull);
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
      expect(find.text('Customise Home'), findsNothing);
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
