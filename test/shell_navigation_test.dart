import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/browse_filters.dart';
import 'package:kalinka/data_model/plugin_catalog.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/catalog_cards_provider.dart';
import 'package:kalinka/providers/catalog_sources_provider.dart';
import 'package:kalinka/providers/collection_edit_provider.dart';
import 'package:kalinka/providers/collections_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/modules_state_provider.dart';
import 'package:kalinka/providers/plugin_catalog_provider.dart';
import 'package:kalinka/providers/restart_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/providers/server_info_provider.dart';
import 'package:kalinka/providers/server_update_provider.dart';
import 'package:kalinka/providers/settings_provider.dart';
import 'package:kalinka/screens/plugin_catalog_screen.dart';
import 'package:kalinka/widgets/home/home_source_list.dart';
import 'package:kalinka/widgets/mini_player.dart';
import 'package:kalinka/widgets/now_playing_content.dart';
import 'package:kalinka/widgets/search/search_composer.dart';
import 'package:kalinka/widgets/search/search_session_view.dart';
import 'package:kalinka/widgets/search/catalog_cards_section.dart';
import 'package:kalinka/widgets/search/collections_section.dart';
import 'package:kalinka/widgets/search/results_view.dart';
import 'package:kalinka/widgets/shell_navigation.dart';
import 'package:kalinka/widgets/server_chip.dart';
import 'package:kalinka/widgets/server_sheet.dart';

import 'support/home_shell.dart';

final _modules = [
  for (final (id, title, icon) in [
    ('localfiles', 'My Library', 'folder_outlined'),
    ('tidal', 'TIDAL', 'music_note_outlined'),
    ('jamendo', 'Jamendo', 'music_note_outlined'),
  ])
    ModuleInfo(
      name: id,
      title: title,
      icon: icon,
      enabled: true,
      state: ModuleState.ready,
      capabilities: const [ModuleCapability.catalogs],
    ),
];

BrowseItem _catalog(String source, String name, {String id = 'root'}) =>
    BrowseItem(
      id: 'kalinka:$source:catalog:$id',
      name: name,
      canBrowse: true,
      canAdd: false,
      catalog: Catalog(id: 'kalinka:$source:catalog:$id', title: name),
    );

class _Api extends HomeApi {
  int searchCalls = 0;

  @override
  Future<BrowseItemsList> searchMatches(
    String query, {
    List<String>? sources,
  }) async {
    searchCalls++;
    return BrowseItemsList(0, 1, 1, [
      BrowseItem(
        id: 'kalinka:${sources!.single}:track:evening',
        canBrowse: false,
        canAdd: true,
        track: Track(
          id: 'evening',
          title: 'Evening music',
          duration: 180,
          performer: Artist(id: 'artist', name: 'Someone'),
        ),
      ),
    ]);
  }

  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async {
    final items = id.isEmpty
        ? [for (final module in _modules) _catalog(module.name, module.title)]
        : [
            for (var i = 0; i < 15; i++)
              _catalog('localfiles', 'Album collection $i', id: 'albums-$i'),
          ];
    return BrowseItemsList(
      offset,
      limit,
      items.length,
      items.skip(offset).take(limit).toList(),
    );
  }
}

class _Settings extends SettingsNotifier {
  @override
  SettingsState build() => const SettingsState();
  @override
  Future<void> loadConfig() async {}
  void stage() => state = state.copyWith(stagedChanges: {'example': true});
}

class _Restart extends RestartNotifier {
  @override
  RestartState build() => const RestartState();
  void complete() =>
      state = const RestartState(isRestarting: true, isDone: true);
}

Finder _nav(String id) => find.byKey(ValueKey('navigation-$id'));

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
  TextScaler textScaler = TextScaler.noScaling,
  bool reducedMotion = false,
  Key? captureKey,
  _Api? api,
}) => pumpHomeShell(
  tester,
  queue: SettableQueue(queueOf(3)),
  api: api ?? _Api(),
  size: size,
  sources: _modules,
  textScaler: textScaler,
  reducedMotion: reducedMotion,
  themed: true,
  captureKey: captureKey,
  collections: const CollectionsShelf(
    plan: CatalogCardPlan(
      id: 'kalinka:collections:catalog:root',
      title: 'Your collections',
      sourceName: 'collections',
    ),
    items: [],
    total: 0,
  ),
  overrides: [
    settingsProvider.overrideWith(_Settings.new),
    restartProvider.overrideWith(_Restart.new),
    serverInfoProvider.overrideWith(
      (ref) async => const ServerInfo(
        version: 'test',
        latencyMs: 1,
        pluginCatalogEnabled: true,
      ),
    ),
    modulesStateProvider.overrideWithBuild(
      (ref, _) async =>
          ModulesAndDevices(inputModules: _modules, devices: const []),
    ),
    pluginCatalogProvider.overrideWith(
      (ref) async => const PluginCatalog(status: 'available'),
    ),
    serverUpdateProvider.overrideWith((ref) async => null),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Optional review captures use the bundled fonts, just like the real app.
  final captures = Platform.environment['KALINKA_REVIEW_DIR'];
  setUpAll(() async {
    if (captures == null) return;
    for (final (family, file) in [
      ('IBM Plex Sans', 'IBMPlexSans-Regular.ttf'),
      ('IBM Plex Sans', 'IBMPlexSans-SemiBold.ttf'),
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

  testWidgets('each source keeps its own history and never changes playback', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final container = await _pump(tester);
    final queue = container.read(playQueueStateStoreProvider);
    await tester.tap(_nav('source-localfiles'));
    await tester.pumpAndSettle();
    final local = container.read(searchSessionProvider);
    expect(local.catalogPage.id, 'kalinka:localfiles:catalog:root');
    expect(
      tester.getSemantics(
        find.descendant(
          of: _nav('source-localfiles'),
          matching: find.byType(MergeSemantics),
        ),
      ),
      matchesSemantics(
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
        label: 'My Library',
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    await tester.tap(_nav('source-tidal'));
    await tester.pumpAndSettle();
    expect(
      container.read(searchSessionProvider).catalogPage.id,
      'kalinka:tidal:catalog:root',
    );
    // A source comes back as it was left.
    await tester.tap(_nav('source-localfiles'));
    await tester.pumpAndSettle();
    expect(container.read(searchSessionProvider).visitId, local.visitId);
    // Its first page goes Home, not to the source shown before it.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(container.read(searchSessionProvider).atHome, isTrue);
    expect(container.read(playQueueStateStoreProvider), same(queue));
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  for (final size in [const Size(1440, 900), const Size(375, 812)]) {
    testWidgets(
      'Results returns to the last search without another request at $size',
      (tester) async {
        final api = _Api();
        final container = await _pump(tester, size: size, api: api);
        Future<void> navigate(String id) async {
          if (size.width < 720) {
            while (!container.read(searchSessionProvider).atHome) {
              await tester.tap(find.byTooltip('Back'));
              await tester.pumpAndSettle();
            }
            if (id == 'results') {
              await tester.tap(find.byTooltip('Back to search results'));
            } else if (id == 'source-localfiles') {
              await tester.tap(
                find.byKey(const ValueKey('home-source-localfiles')),
              );
            }
          } else {
            await tester.tap(_nav(id));
          }
          await tester.pumpAndSettle();
        }

        if (size.width < 720) {
          expect(find.byType(Drawer), findsNothing);
          expect(find.byTooltip('Back to search results'), findsNothing);
        } else {
          final button = tester.widget<TextButton>(
            find.descendant(
              of: _nav('results'),
              matching: find.byType(TextButton),
            ),
          );
          expect(button.onPressed, isNull);
          expect(
            find.byTooltip('Search results appear after your first search'),
            findsOneWidget,
          );
        }

        await tester.tap(
          find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == 'Search',
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.descendant(
            of: find.byType(SearchComposer),
            matching: find.byType(TextField),
          ),
          'Evening music',
        );
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        final notifier = container.read(searchSessionProvider.notifier);
        notifier.setResultsFilter(const BrowseFilterQuery(sources: ['tidal']));
        await tester.pumpAndSettle();
        final original = container.read(searchSessionProvider);
        final calls = api.searchCalls;
        expect(calls, 3);

        for (final destination in ['home', 'source-localfiles']) {
          await navigate(destination);
          expect(find.bySemanticsLabel('Back to results'), findsNothing);
          expect(find.text('RESULTS'), findsNothing);
          await navigate('results');
          final resumed = container.read(searchSessionProvider);
          expect(resumed.activeView, FindMusicView.results);
          expect(resumed.searchQuery, original.searchQuery);
          expect(resumed.results, same(original.results));
          expect(resumed.resultsFilter, original.resultsFilter);
          expect(api.searchCalls, calls);
          expect(find.byType(ResultsView).hitTestable(), findsOneWidget);
          expect(find.byType(SearchComposer), findsNothing);
        }
        // Results' first page goes Home, at every width.
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(container.read(searchSessionProvider).atHome, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'saved results remain reachable offline and clear with the search',
    (tester) async {
      final container = await _pump(tester);
      final notifier = container.read(searchSessionProvider.notifier);
      notifier.submit('Evening music');
      await tester.pumpAndSettle();
      await tester.tap(_nav('home'));
      await tester.pumpAndSettle();
      (container.read(connectionStateProvider.notifier) as SettableConnection)
          .set(ConnectionStatus.offline);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(_nav('results'));
      await tester.pump();
      expect(
        container.read(searchSessionProvider).activeView,
        FindMusicView.results,
      );
      notifier.clearSearch();
      await tester.pump();
      final button = tester.widget<TextButton>(
        find.descendant(of: _nav('results'), matching: find.byType(TextButton)),
      );
      expect(button.onPressed, isNull);
    },
  );

  testWidgets('Configuration navigation honours Cancel and Discard', (
    tester,
  ) async {
    final container = await _pump(tester);
    await tester.tap(_nav('configuration'));
    await tester.pumpAndSettle();
    (container.read(settingsProvider.notifier) as _Settings).stage();
    await tester.pumpAndSettle();
    await tester.tap(_nav('home'));
    await tester.pumpAndSettle();
    expect(find.text('Apply your changes?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(PluginCatalogScreen), findsOneWidget);
    expect(container.read(settingsProvider).hasPendingChanges, isTrue);
    await tester.tap(_nav('source-localfiles'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('configuration-discard')));
    await tester.pumpAndSettle();
    expect(find.byType(PluginCatalogScreen), findsNothing);
    expect(container.read(settingsProvider).hasPendingChanges, isFalse);
    expect(
      container.read(searchSessionProvider).catalogPage.id,
      'kalinka:localfiles:catalog:root',
    );
  });

  testWidgets(
    'open search stays bounded and retains its text across resizing',
    (tester) async {
      await _pump(tester, size: const Size(1920, 1080));
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Search',
        ),
      );
      await tester.pumpAndSettle();
      final composer = find.byType(SearchComposer);
      await tester.enterText(
        find.descendant(of: composer, matching: find.byType(TextField)),
        'Evening music',
      );
      final state = tester.state(find.byType(SearchSessionView));
      for (final size in [
        const Size(900, 900),
        const Size(375, 812),
        const Size(1440, 900),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(SearchSessionView)), same(state));
        expect(find.text('Evening music'), findsOneWidget);
        final rect = tester.getRect(composer);
        final pane = tester.getRect(find.byType(SearchSessionView));
        expect(rect.width, lessThanOrEqualTo(880));
        expect(rect.left, greaterThanOrEqualTo(pane.left));
        expect(rect.right, lessThanOrEqualTo(pane.right));
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('navigation cannot silently discard collection edits', (
    tester,
  ) async {
    final container = await _pump(tester);
    final edits = container.read(collectionEditProvider.notifier);
    edits.begin();
    edits.toggleRemoval('a', (name: 'Evening', entryIds: ['1', '2']), '1');
    await tester.pumpAndSettle();
    await tester.tap(_nav('source-tidal'));
    await tester.pumpAndSettle();
    expect(find.text('Discard 1 change?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(container.read(collectionEditProvider).changes, 1);
    expect(container.read(searchSessionProvider).atHome, isTrue);
    await tester.tap(_nav('source-tidal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(container.read(collectionEditProvider).active, isFalse);
    expect(
      container.read(searchSessionProvider).catalogPage.id,
      'kalinka:tidal:catalog:root',
    );
  });

  testWidgets(
    'navigation supports keyboard traversal and activation after restart',
    (tester) async {
      final container = await _pump(tester);
      container.read(searchSessionProvider.notifier).submit('Evening music');
      await tester.pumpAndSettle();
      await tester.tap(_nav('home'));
      (container.read(restartProvider.notifier) as _Restart).complete();
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final focused = FocusManager.instance.primaryFocus!.context!;
      expect(
        find.ancestor(
          of: find.byWidget(focused.widget),
          matching: _nav('home'),
        ),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        container.read(searchSessionProvider).activeView,
        FindMusicView.results,
      );
      expect(find.byType(SearchComposer), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('phone uses its existing server menu and guards pending edits', (
    tester,
  ) async {
    final container = await _pump(tester, size: const Size(375, 812));
    expect(find.byIcon(Icons.menu), findsNothing);
    expect(find.byType(Drawer), findsNothing);
    await tester.dragFrom(const Offset(0, 200), const Offset(250, 0));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
    await tester.tap(find.byType(ServerChip));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(ServerSheetContent),
        matching: find.text('Configuration'),
      ),
    );
    await tester.pumpAndSettle();
    (container.read(settingsProvider.notifier) as _Settings).stage();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.menu), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(PluginCatalogScreen), findsOneWidget);
    expect(find.text('Apply your changes?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).hasPendingChanges, isTrue);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('configuration-discard')));
    await tester.pumpAndSettle();
    expect(find.byType(PluginCatalogScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone source names open pages; resize retains the visit', (
    tester,
  ) async {
    final container = await _pump(tester, size: const Size(375, 812));
    await tester.tap(find.byKey(const ValueKey('home-source-tidal')));
    await tester.pumpAndSettle();
    final visit = container.read(searchSessionProvider).visitId;
    final state = tester.state(find.byType(SearchSessionView));
    expect(find.byType(Drawer), findsNothing);
    expect(container.read(searchSessionProvider).visitId, visit);
    for (final size in [
      const Size(900, 900),
      const Size(1440, 900),
      const Size(375, 812),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(container.read(searchSessionProvider).visitId, visit);
      expect(tester.state(find.byType(SearchSessionView)), same(state));
      expect(find.byIcon(Icons.menu), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('an empty Home keeps its sources beside the rail', (
    tester,
  ) async {
    await _pump(tester);
    final homeState = tester.state(find.byType(SearchSessionView));
    for (final width in [900.0, 720.0, 719.0, 375.0, 1440.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpAndSettle();
      final rail = width >= 720;
      expect(
        find.byType(ShellNavigation),
        rail ? findsOneWidget : findsNothing,
      );
      // Nothing pinned and no collections: the sources are the way in,
      // rail or not, and there is no collections shelf to show.
      expect(find.byType(HomeSourceList), findsOneWidget);
      expect(find.byType(CollectionsSection), findsNothing);
      expect(_nav('collections'), rail ? findsOneWidget : findsNothing);
      expect(find.byType(CatalogCardsSection), findsNothing);
      expect(find.byTooltip('Configure music sources'), findsOneWidget);
      expect(tester.state(find.byType(SearchSessionView)), same(homeState));
      expect(find.byType(Drawer), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'unavailable sources cannot navigate and playback stays visible',
    (tester) async {
      final container = await _pump(tester);
      await container.read(catalogSourcesProvider.future);
      (container.read(connectionStateProvider.notifier) as SettableConnection)
          .set(ConnectionStatus.offline);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(_nav('source-tidal'));
      await tester.pump();
      expect(container.read(searchSessionProvider).atHome, isTrue);
      expect(find.byType(NowPlayingContent), findsOneWidget);
    },
  );

  for (final (name, size, scale) in [
    ('phone', const Size(375, 812), 1.0),
    ('small-phone', const Size(320, 640), 2.0),
    ('landscape', const Size(812, 375), 2.0),
    ('tablet', const Size(900, 900), 1.0),
    ('desktop', const Size(1440, 900), 1.0),
    ('wide', const Size(1920, 1080), 1.0),
    ('large-text', const Size(1200, 900), 3.0),
  ]) {
    testWidgets('$name navigation remains usable with reduced motion', (
      tester,
    ) async {
      final captureKey = GlobalKey();
      final container = await _pump(
        tester,
        size: size,
        textScaler: TextScaler.linear(scale),
        reducedMotion: true,
        captureKey: captureKey,
      );
      Future<void> capture(String filename) async {
        if (captures == null) return;
        await tester.runAsync(() async {
          final boundary =
              captureKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$captures/$filename.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('$name-home');
      final rail = find.byKey(const ValueKey('navigation-rail'));
      if (size.width < 720 || scale > 1.5) {
        expect(rail, findsNothing);
      } else {
        expect(rail, findsOneWidget);
      }
      expect(find.byType(Drawer), findsNothing);
      expect(find.byIcon(Icons.menu), findsNothing);
      final hasRail = size.width >= 720 && scale <= 1.5;
      if (hasRail) expect(find.byType(CatalogCardsSection), findsNothing);
      // Populate the saved search while Home is shown; this case checks the
      // header shortcut and source tiles at each window/text size.
      container.read(searchSessionProvider.notifier).submit('Evening music');
      container.read(searchSessionProvider.notifier).backToCatalogsRoot();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      final resultsShortcut = find.byTooltip('Back to search results');
      if (hasRail) {
        expect(resultsShortcut, findsNothing);
      } else {
        expect(resultsShortcut.hitTestable(), findsOneWidget);
        expect(tester.getSize(resultsShortcut), const Size(48, 48));
      }
      await capture('$name-results');
      final invitation = find.byKey(
        const ValueKey('home-pin-hint-customise'),
      );
      await tester.scrollUntilVisible(
        invitation,
        160,
        scrollable: find
            .descendant(
              of: find.byType(SearchSessionView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(invitation.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture('$name-customise-banner');
      final source = hasRail
          ? _nav('source-tidal')
          : find.byKey(const ValueKey('home-source-tidal'));
      await tester.scrollUntilVisible(
        source,
        -100,
        scrollable: find
            .descendant(
              of: hasRail
                  ? find.byType(ShellNavigation)
                  : find.byType(SearchSessionView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(source.hitTestable(), findsOneWidget);
      expect(find.byType(CatalogCardsSection), findsNothing);
      expect(tester.takeException(), isNull);
      if (size.width >= 720 && size.width <= 900 || scale > 1) {
        expect(find.byType(NowPlayingContent), findsNothing);
        expect(find.byType(MiniPlayer), findsOneWidget);
      }
      await capture(name);
      await tester.tap(source);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
