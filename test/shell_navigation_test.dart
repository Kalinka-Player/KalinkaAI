import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/browse_filters.dart';
import 'package:kalinka/data_model/plugin_catalog.dart';
import 'package:kalinka/data_model/log_export.dart';
import 'package:kalinka/providers/log_export_provider.dart';
import 'package:kalinka/providers/box_control_provider.dart';
import 'package:kalinka/providers/power_off_status_provider.dart';
import 'package:kalinka/providers/supervisor_api.dart';
import 'package:kalinka/widgets/settings_controls/settings_enum_pills.dart';
import 'package:kalinka/widgets/settings_controls/settings_toggle.dart';
import 'package:kalinka/data_model/renderer_config.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/catalog_cards_provider.dart';
import 'package:kalinka/providers/catalog_sources_provider.dart';
import 'package:kalinka/providers/collection_edit_provider.dart';
import 'package:kalinka/providers/collections_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/modules_state_provider.dart';
import 'package:kalinka/providers/plugin_catalog_provider.dart';
import 'package:kalinka/providers/renderer_settings_provider.dart';
import 'package:kalinka/providers/renderer_settings_route_provider.dart';
import 'package:kalinka/providers/restart_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/providers/server_info_provider.dart';
import 'package:kalinka/providers/server_update_provider.dart';
import 'package:kalinka/providers/settings_provider.dart';
import 'package:kalinka/screens/plugin_catalog_screen.dart';
import 'package:kalinka/providers/kiosk_provider.dart';
import 'package:kalinka/screens/log_export_screen.dart';
import 'package:kalinka/widgets/settings_controls/settings_action_row.dart';
import 'package:kalinka/screens/renderer_settings_screen.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/theme/kalinka_icons.dart';
import 'package:kalinka/widgets/home/home_source_list.dart';
import 'package:kalinka/widgets/mini_player.dart';
import 'package:kalinka/widgets/now_playing_content.dart';
import 'package:kalinka/widgets/renderer_switcher.dart';
import 'package:kalinka/widgets/search/search_composer.dart';
import 'package:kalinka/widgets/search/search_session_view.dart';
import 'package:kalinka/widgets/search/catalog_cards_section.dart';
import 'package:kalinka/widgets/search/collections_section.dart';
import 'package:kalinka/widgets/search/results_view.dart';
import 'package:kalinka/widgets/shell_navigation.dart';
import 'package:kalinka/widgets/server_chip.dart';
import 'package:kalinka/widgets/server_sheet.dart';
import 'package:kalinka/widgets/settings_renderer.dart';

import 'support/focus.dart';
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

class _RendererApi extends _Api {
  @override
  Future<List<RendererInfo>> listRenderers() async => const [
    RendererInfo(
      rendererId: 'living',
      friendlyName: 'Living Room',
      status: 'connected',
      active: true,
      selected: true,
    ),
  ];

  @override
  Future<RendererConfigSnapshot> getRendererConfig(String rendererId) async =>
      RendererConfigSnapshot.fromJson({
        'sections': [
          {
            'path': 'output',
            'title': 'Output',
            'fields': [
              for (final name in ['Mono', 'Mute', 'Normalise'])
                {
                  'path': 'output.$name',
                  'title': name,
                  'type': 'bool',
                  'value': 'false',
                },
              {
                'path': 'output.name',
                'title': 'Output name',
                'type': 'string',
                'value': '',
              },
            ],
          },
        ],
      });
}

class _Settings extends SettingsNotifier {
  @override
  SettingsState build() => const SettingsState();
  @override
  Future<void> loadConfig({bool preserveStagedChanges = false}) async {}
  void stage() => state = state.copyWith(stagedChanges: {'example': true});
}

class _Restart extends RestartNotifier {
  @override
  RestartState build() => const RestartState();
  void complete() =>
      state = const RestartState(isRestarting: true, isDone: true);
}

class _IdlePluginOperations extends PluginOperationsNotifier {
  @override
  Future<void> reattach() async {}
}

Finder _nav(String id) => find.byKey(ValueKey('navigation-$id'));

const _streamerBox = BoxControl(
  SupervisorInfo(
    version: 'test',
    protocol: 1,
    minProtocol: 1,
    serverId: 'home-shell',
    actions: {'reboot', 'poweroff'},
  ),
  'home-shell',
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
  TextScaler textScaler = TextScaler.noScaling,
  bool reducedMotion = false,
  bool onScreenKeyboard = false,
  Key? captureKey,
  _Api? api,
  List<Override> extra = const [],
  SettableQueue? queue,
}) => pumpHomeShell(
  tester,
  queue: queue ?? SettableQueue(queueOf(3)),
  api: api ?? _Api(),
  size: size,
  sources: _modules,
  textScaler: textScaler,
  reducedMotion: reducedMotion,
  onScreenKeyboard: onScreenKeyboard,
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
      (ref) async =>
          const ServerInfo(version: 'test', latencyMs: 1, pluginCatalog: true),
    ),
    modulesStateProvider.overrideWithBuild(
      (ref, _) async =>
          ModulesAndDevices(inputModules: _modules, devices: const []),
    ),
    pluginCatalogProvider.overrideWith(
      (ref) async => const PluginCatalog(status: 'available'),
    ),
    pluginOperationsProvider.overrideWith(_IdlePluginOperations.new),
    serverUpdateProvider.overrideWith((ref) async => null),
    ...extra,
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Optional review captures use the bundled fonts, just like the real app.
  final captures = kIsWeb ? null : Platform.environment['KALINKA_REVIEW_DIR'];
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

  for (final (size, kind, kiosk) in [
    (const Size(1440, 900), ui.PointerDeviceKind.mouse, false),
    (const Size(1024, 600), ui.PointerDeviceKind.touch, true),
  ]) {
    testWidgets('keyboard rail overlays browsing and hands back to $kind', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        size: size,
        extra: [
          localDisplayKioskProvider.overrideWithValue(kiosk),
          supervisorApiProvider.overrideWithValue(null),
        ],
      );
      final rail = find.byKey(const ValueKey('navigation-rail'));
      final home = _nav('home');
      final source = _nav('source-localfiles');
      final pane = find.byType(SearchSessionView);
      final normal = tester.getSize(rail).width;
      expect(normal, size.width == 1440 ? 200 : 88);
      Future<void> press(LogicalKeyboardKey key) async {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
      }

      await press(LogicalKeyboardKey.mediaPlayPause);
      expect(tester.getSize(rail).width, normal);
      await press(LogicalKeyboardKey.tab);
      expect(focusIsOn(home), isTrue);
      expect(tester.getSize(rail).width, 200);
      final paneWithLabels = tester.getRect(pane);
      expect(paneWithLabels.left, 64);
      final homeNode = traversableFocusNodesIn(home).single;
      await press(LogicalKeyboardKey.arrowRight);
      expect(tester.getSize(rail).width, 64);
      expect(tester.getRect(pane), paneWithLabels);
      expect(traversableFocusNodesIn(home).single, same(homeNode));
      final button = find.descendant(
        of: source,
        matching: find.byType(TextButton),
      );
      expect(tester.getSize(button).shortestSide, greaterThanOrEqualTo(48));
      expect(
        tester.getSemantics(button),
        isSemantics(label: 'My Library', isButton: true),
      );
      await press(LogicalKeyboardKey.escape);
      expect(focusIsOn(home), isTrue);
      expect(tester.getSize(rail).width, 200);
      await press(LogicalKeyboardKey.arrowRight);

      final gesture = await tester.createGesture(kind: kind);
      final position = tester.getCenter(source);
      if (kind == ui.PointerDeviceKind.mouse) {
        await gesture.addPointer(location: Offset.zero);
        await gesture.moveTo(position);
        await tester.pump();
        expect(tester.getSize(rail).width, 64);
      }
      await gesture.down(position);
      await tester.pumpAndSettle();
      expect(tester.getSize(rail).width, 64);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        container.read(searchSessionProvider).catalogPage.id,
        'kalinka:localfiles:catalog:root',
      );
      expect(tester.getSize(rail).width, normal);
      await gesture.removePointer();
      await press(LogicalKeyboardKey.tab);
      if (focusIsOn(rail)) await press(LogicalKeyboardKey.arrowRight);
      expect(tester.getSize(rail).width, 64);
      final item = find.text('Album collection 0').hitTestable();
      final bounds = tester.getRect(item);
      final tap = await tester.startGesture(bounds.center, kind: kind);
      await tester.pump();
      expect(tester.getRect(item), bounds);
      await tap.up();
      await tester.pumpAndSettle();
      expect(
        container.read(searchSessionProvider).catalogPage.id,
        'kalinka:localfiles:catalog:albums-0',
      );
      expect(tester.getSize(rail).width, normal);
    });
  }

  testWidgets('Back from Settings opens the rail without moving its rows', (
    tester,
  ) async {
    await _pump(
      tester,
      extra: [
        localDisplayKioskProvider.overrideWithValue(true),
        supervisorApiProvider.overrideWithValue(null),
        boxControlProvider.overrideWith((ref) async => _streamerBox),
      ],
    );
    final rail = find.byType(ShellNavigation);
    final settings = _nav('configuration');
    expect(_nav('changeServer'), findsNothing);
    List<Offset> iconPositions() => [
      for (final id in [
        'home',
        'results',
        'source-localfiles',
        'configuration',
        'restart',
        'powerOff',
      ])
        tester.getCenter(
          find.descendant(of: _nav(id), matching: find.byType(Icon)).first,
        ),
    ];
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    for (var i = 0; i < 12 && !focusIsOn(settings); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    expect(focusIsOn(settings), isTrue);
    final positions = iconPositions();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final streamer = find.byKey(const ValueKey('catalog-tab-server'));
    traversableFocusNodesIn(streamer).first.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final scroll = tester
        .widget<CustomScrollView>(find.byKey(const ValueKey('catalog-scroll')))
        .controller!;
    scroll.jumpTo(scroll.position.maxScrollExtent / 2);
    await tester.pumpAndSettle();
    final offset = scroll.offset;
    expect(offset, greaterThan(0));
    final pane = tester.getRect(find.byType(PluginCatalogScreen));
    expect(tester.getSize(rail).width, lessThan(100));
    expect(iconPositions(), positions);
    final railScroll = tester.state<ScrollableState>(
      find.descendant(of: rail, matching: find.byType(Scrollable)),
    );
    expect(railScroll.position.maxScrollExtent, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    for (var frame = 0; frame < 16; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(iconPositions(), positions, reason: 'rail icons on frame $frame');
      expect(tester.getRect(find.byType(PluginCatalogScreen)), pane);
      expect(scroll.offset, offset);
    }
    expect(focusIsOn(settings), isTrue);
    expect(tester.getSize(rail).width, greaterThan(100));
  });

  testWidgets('More keeps rail labels until the keyboard leaves its shelf', (
    tester,
  ) async {
    BoxPowerStatus? timer = const BoxPowerStatus(
      serverId: 'home-shell',
      state: 'scheduled',
      remainingSeconds: 1800,
    );
    final container = await _pump(
      tester,
      size: const Size(1024, 480),
      extra: [
        supervisorApiProvider.overrideWithValue(null),
        boxControlProvider.overrideWith((ref) async => _streamerBox),
        currentPowerOffStatusProvider.overrideWith((ref) => timer),
      ],
    );
    final rail = find.byKey(const ValueKey('navigation-rail'));
    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    await press(LogicalKeyboardKey.tab);
    final more = _nav('more');
    for (var i = 0; i < 12 && !focusIsOn(more); i++) {
      await press(LogicalKeyboardKey.arrowDown);
    }
    expect(focusIsOn(more), isTrue);
    await press(LogicalKeyboardKey.enter);
    final folded = _nav('collections');
    expect(folded.hitTestable(), findsOneWidget);
    await press(LogicalKeyboardKey.arrowRight);
    expect(focusIsOn(find.byType(ShellNavigation)), isTrue);
    expect(focusIsOn(more), isFalse);
    expect(tester.getSize(rail).width, 200);
    await press(LogicalKeyboardKey.tab);
    expect(folded.hitTestable(), findsNothing);
    expect(tester.getSize(rail).width, 64);
    for (final id in [
      'configuration',
      'restart',
      if (!kIsWeb) 'changeServer',
      'powerOff',
    ]) {
      expect(_nav(id).hitTestable(), findsOneWidget, reason: id);
    }
    final power = _nav('powerOff');
    Finder onPower(Finder child) => find.descendant(of: power, matching: child);
    expect(
      onPower(find.byIcon(Icons.power_settings_new)).hitTestable(),
      findsOneWidget,
    );
    expect(onPower(find.text('30m')).hitTestable(), findsOneWidget);
    timer = const BoxPowerStatus(
      serverId: 'home-shell',
      state: 'scheduled',
      remainingSeconds: 60,
    );
    container.invalidate(currentPowerOffStatusProvider);
    await tester.pumpAndSettle();
    expect(onPower(find.text('1m')).hitTestable(), findsOneWidget);
    expect(find.byTooltip('Power off in 1 minute'), findsOneWidget);
    timer = null;
    container.invalidate(currentPowerOffStatusProvider);
    await tester.pumpAndSettle();
    expect(onPower(find.text('1m')), findsNothing);
    expect(
      onPower(find.byIcon(Icons.power_settings_new)).hitTestable(),
      findsOneWidget,
    );
  });

  for (final kiosk in [false, true]) {
    testWidgets(
      'Back unwinds the source then focuses its rail button (kiosk $kiosk)',
      (tester) async {
        final container = await _pump(
          tester,
          extra: [localDisplayKioskProvider.overrideWithValue(kiosk)],
        );
        final source = _nav('source-localfiles');
        traversableFocusNodesIn(source).first.requestFocus();
        await tester.pump();
        Future<void> press(LogicalKeyboardKey key) async {
          await tester.sendKeyEvent(key);
          await tester.pumpAndSettle();
        }

        // Arrow navigation marks an ordinary keyboard as active as well.
        await press(LogicalKeyboardKey.arrowRight);
        await press(LogicalKeyboardKey.escape);
        expect(focusIsOn(source), isTrue);
        await press(LogicalKeyboardKey.enter);
        final root = container.read(searchSessionProvider).catalogPage.id;
        expect(root, 'kalinka:localfiles:catalog:root');
        expect(
          FocusManager.instance.primaryFocus?.nearestScope?.debugLabel,
          'content',
        );
        container
            .read(searchSessionProvider.notifier)
            .openCatalog(
              id: 'kalinka:localfiles:catalog:albums-2',
              title: 'Album collection 2',
            );
        await tester.pumpAndSettle();
        await press(LogicalKeyboardKey.escape);
        expect(container.read(searchSessionProvider).catalogPage.id, root);
        expect(
          FocusManager.instance.primaryFocus?.nearestScope?.debugLabel,
          'content',
        );
        await press(LogicalKeyboardKey.escape);
        expect(focusIsOn(source), isTrue);
        expect(container.read(searchSessionProvider).catalogPage.id, root);
      },
    );
  }

  testWidgets(
    'remote enters Settings from the rail and keeps nested pages in the main pane',
    (tester) async {
      await _pump(
        tester,
        extra: [
          localDisplayKioskProvider.overrideWithValue(true),
          logExportProvider.overrideWithBuild(
            (_, _) => const LogExportView(
              status: LogExportStatus(
                state: LogExportState.none,
                availableSources: [LogSource.localRenderer],
              ),
            ),
          ),
        ],
      );
      Future<void> activate(Finder target) async {
        traversableFocusNodesIn(target).first.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
      }

      await activate(_nav('configuration'));
      expect(focusIsOn(find.byType(PluginCatalogScreen)), isTrue);
      expect(
        FocusManager.instance.primaryFocus?.nearestScope?.debugLabel,
        'content',
      );
      await activate(_nav('configuration'));
      expect(focusIsOn(find.byType(PluginCatalogScreen)), isTrue);
      final streamer = find.byKey(const ValueKey('catalog-tab-server'));
      await activate(streamer);
      expect(focusIsOn(streamer), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(focusIsOn(streamer), isFalse);
      final logs = find.widgetWithText(
        SettingsActionRow,
        'Download server logs',
      );
      await tester.ensureVisible(logs);
      await tester.pumpAndSettle();
      await activate(logs);
      final panel = find.byType(LogExportScreen);
      expect(focusIsOn(panel), isTrue);
      expect(
        FocusManager.instance.primaryFocus?.nearestScope?.debugLabel,
        'content',
      );
      final pills = find.descendant(
        of: panel,
        matching: find.byType(SettingsEnumPills),
      );
      List<FocusNode> segments() => traversableFocusNodesIn(pills).toList();
      expect(segments(), hasLength(3));
      expect(focusIsOn(pills), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(tester.widget<SettingsEnumPills>(pills).selected, '24 hours');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(tester.widget<SettingsEnumPills>(pills).selected, '7 days');
      final toggle = find.descendant(
        of: panel,
        matching: find.byType(SettingsToggle),
      );
      expect(traversableFocusNodesIn(toggle), hasLength(1));
      await activate(toggle);
      expect(tester.widget<SettingsToggle>(toggle).value, isTrue);
      expect(focusIsOn(toggle), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(focusIsOn(logs), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(focusIsOn(_nav('configuration')), isTrue);
      expect(find.byType(PluginCatalogScreen), findsOneWidget);
    },
  );

  testWidgets('the keyboard keeps the active renderer field above its keys', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      api: _RendererApi(),
      size: const Size(1024, 480),
      reducedMotion: true,
      onScreenKeyboard: true,
      extra: [localDisplayKioskProvider.overrideWithValue(true)],
    );
    container
        .read(rendererSettingsRouteProvider.notifier)
        .open('living', 'Living Room');
    await tester.pumpAndSettle();
    final field = find.descendant(
      of: find.byType(RendererSettingsScreen),
      matching: find.byType(TextField),
    );
    await Scrollable.ensureVisible(tester.element(field), alignment: 1);
    await tester.pumpAndSettle();
    final original = tester.getRect(field);
    await tester.tap(field);
    await tester.pumpAndSettle();
    final panel = tester.getRect(
      find.byKey(const ValueKey('on-screen-keyboard')),
    );
    expect(original.bottom, greaterThan(panel.top));
    expect(tester.getRect(field).bottom, lessThanOrEqualTo(panel.top));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(container.read(rendererSettingsProvider('living')).staged, {
      'output.name': 'q',
    });
    expect(tester.getRect(field).bottom, lessThanOrEqualTo(panel.top));
    expect(field.hitTestable(), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('on-screen-keyboard')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final mouseEntry in [true, false]) {
    testWidgets(
      'opening Output settings waits for navigation (mouse: $mouseEntry)',
      (tester) async {
        await _pump(
          tester,
          api: _RendererApi(),
          extra: [localDisplayKioskProvider.overrideWithValue(true)],
        );
        final output = find
            .byWidgetPredicate(
              (w) =>
                  w is RendererSwitcherButton || w is RendererSwitcherDropdown,
            )
            .hitTestable()
            .first;
        final mouse = await tester.createGesture(
          kind: ui.PointerDeviceKind.mouse,
        );
        await mouse.addPointer();
        addTearDown(mouse.removePointer);
        Future<void> activate(Finder target) async {
          if (mouseEntry) {
            final point = tester.getCenter(target);
            await mouse.moveTo(point);
            await mouse.down(point);
            await mouse.up();
          } else {
            traversableFocusNodesIn(target).first.requestFocus();
            await tester.pump();
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          }
          await tester.pumpAndSettle();
        }

        await activate(output);
        await activate(find.byTooltip('Output settings'));
        final panel = find.byType(RendererSettingsScreen);
        expect(focusIsOn(panel), isTrue);
        expect(FocusManager.instance.primaryFocus, isA<FocusScopeNode>());
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(panel, findsOneWidget);
        expect(FocusManager.instance.primaryFocus, isA<FocusScopeNode>());
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        final mono = find.byWidgetPredicate(
          (w) => w is SchemaFieldRenderer && w.field.label == 'Mono',
        );
        expect(focusIsOn(mono), isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(panel, findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  }

  for (final width in [375.0, 1440.0]) {
    testWidgets(
      'renderer settings own toolbar and content over Streamer at $width',
      (tester) async {
        final container = await _pump(
          tester,
          api: _RendererApi(),
          size: Size(width, 900),
        );
        if (width < 400) {
          await tester.tap(find.byType(ServerChip));
          await tester.pumpAndSettle();
          await tester.tap(
            find.descendant(
              of: find.byType(ServerSheetContent),
              matching: find.text('Settings'),
            ),
          );
        } else {
          await tester.tap(_nav('configuration'));
        }
        await tester.pumpAndSettle();
        final streamer = find.byKey(const ValueKey('catalog-tab-server'));
        await tester.tap(streamer);
        await tester.pumpAndSettle();
        traversableFocusNodesIn(streamer).first.requestFocus();
        await tester.pump();
        expect(
          FocusManager.instance.primaryFocus?.nearestScope?.debugLabel,
          'toolbar',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus?.nearestScope?.debugLabel,
          'content',
        );
        expect(focusIsOn(find.byType(PluginCatalogScreen)), isTrue);
        final output = find
            .byWidgetPredicate(
              (widget) =>
                  widget is RendererSwitcherButton ||
                  widget is RendererSwitcherDropdown,
            )
            .hitTestable()
            .first;
        traversableFocusNodesIn(output).single.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        final gear = find.byTooltip('Output settings');
        traversableFocusNodesIn(gear).first.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        final panel = find.byType(RendererSettingsScreen);
        final back = find.descendant(
          of: panel,
          matching: find.byKey(const ValueKey('settings-back')),
        );
        expect(focusIsOn(panel), isTrue);
        expect(FocusManager.instance.primaryFocus, isA<FocusScopeNode>());
        expect(focusIsOn(back), isFalse);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(focusIsOn(back), isTrue);
        expect(
          traversableFocusNodesIn(find.byType(PluginCatalogScreen)),
          isEmpty,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus?.nearestScope?.debugLabel,
          'content',
        );
        Finder field(String label) => find.byWidgetPredicate(
          (widget) =>
              widget is SchemaFieldRenderer && widget.field.label == label,
        );
        expect(focusIsOn(field('Mono')), isTrue);
        for (final (key, label) in [
          (LogicalKeyboardKey.arrowDown, 'Mute'),
          (LogicalKeyboardKey.arrowDown, 'Normalise'),
          (LogicalKeyboardKey.arrowUp, 'Mute'),
        ]) {
          await tester.sendKeyEvent(key);
          await tester.pumpAndSettle();
          expect(focusIsOn(field(label)), isTrue);
        }
        final renderer = rendererSettingsProvider('living');
        expect(container.read(renderer).staged, isEmpty);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(container.read(renderer).staged, {'output.Mute': true});
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(panel, findsNothing);
        expect(traversableFocusNodesIn(streamer), isNotEmpty);
        expect(
          focusIsOn(output),
          isTrue,
          reason: 'Back returns to the output selector',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

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

  testWidgets('player metadata navigation honours Cancel and Discard', (
    tester,
  ) async {
    final queue = queueOf(1);
    queue.trackList.single.performer = Artist(
      id: 'kalinka:localfiles:artist:someone',
      name: 'Someone',
    );
    final container = await _pump(tester, queue: SettableQueue(queue));
    final artist = find.descendant(
      of: find.byType(NowPlayingContent),
      matching: find.text('Someone'),
    );
    await tester.tap(_nav('configuration'));
    await tester.pumpAndSettle();
    (container.read(settingsProvider.notifier) as _Settings).stage();
    await tester.pumpAndSettle();

    await tester.tap(artist);
    await tester.pumpAndSettle();
    expect(find.text('Apply your changes?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(PluginCatalogScreen), findsOneWidget);
    expect(container.read(settingsProvider).hasPendingChanges, isTrue);
    expect(container.read(searchSessionProvider).catalogPage.isRoot, isTrue);

    await tester.tap(artist);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('configuration-discard')));
    await tester.pumpAndSettle();
    expect(find.byType(PluginCatalogScreen), findsNothing);
    expect(container.read(settingsProvider).hasPendingChanges, isFalse);
    expect(
      container.read(searchSessionProvider).catalogPage.id,
      'kalinka:localfiles:artist:someone',
    );
    expect(container.read(playQueueStateStoreProvider), same(queue));
    expect(tester.takeException(), isNull);
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
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
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
        matching: find.text('Settings'),
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
    await tester.ensureVisible(find.byKey(const ValueKey('home-source-tidal')));
    await tester.pumpAndSettle();
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
      expect(find.byTooltip('Music source settings'), findsOneWidget);
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
    ('tablet-larger-text', const Size(1143, 714), 1.4),
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
      final invitation = find.byKey(const ValueKey('home-pin-hint-customise'));
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

  // The window the desktop app opens at is too short for every item: the
  // rest go behind More, from the foot up, rather than the rail scrolling.
  testWidgets('a source carries its icon and the count the server gives it', (
    tester,
  ) async {
    final drives = ModuleInfo(
      name: 'drives',
      title: 'Drives',
      icon: 'hard_drive_outlined',
      enabled: true,
      state: ModuleState.ready,
      capabilities: const [ModuleCapability.catalogs],
      builtin: true,
      count: 2,
    );
    await _pump(
      tester,
      extra: [
        catalogSourcesProvider.overrideWith(
          (ref) async => [
            for (final module in [..._modules, drives])
              (module: module, root: _catalog(module.name, module.title)),
          ],
        ),
      ],
    );
    await tester.pumpAndSettle();

    final rail = _nav('source-drives');
    expect(
      find.descendant(
        of: rail,
        matching: find.byIcon(KalinkaIcons.hardDriveOutlined),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.descendant(
          of: rail,
          matching: find.byKey(const ValueKey('navigation-count')),
        ),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _nav('source-localfiles'),
        matching: find.byKey(const ValueKey('navigation-count')),
      ),
      findsNothing,
    );
  });

  // Larger system text in a rail still 88 wide split "Collections" mid-word.
  for (final (scale, width) in [(1.0, 88.0), (1.25, 106.0), (1.5, 124.0)]) {
    testWidgets('the narrow rail keeps its names their room at ${scale}x', (
      tester,
    ) async {
      final textScaler = TextScaler.linear(scale);
      await _pump(tester, size: const Size(1143, 714), textScaler: textScaler);
      final rail = tester.getSize(
        find.byKey(const ValueKey('navigation-rail')),
      );
      // Stated, not asked of the rule under test.
      expect(rail.width, width);
      expect(kalinkaCompactRailWidth(textScaler), width);
      // Icons still over their labels, however wide it has grown.
      expect(
        tester.getCenter(find.byIcon(Icons.home_outlined)).dy,
        lessThan(tester.getCenter(find.text('Home')).dy),
      );
      // As many of the enlarged letters to a line as of the standard ones.
      final label = tester.renderObject<RenderParagraph>(
        find.descendant(of: _nav('home'), matching: find.text('Home')),
      );
      expect(
        label.constraints.maxWidth,
        scale == 1.0
            ? kKalinkaRailLabelWidth
            : greaterThanOrEqualTo(kKalinkaRailLabelWidth * scale),
      );
    });
  }

  testWidgets('a short rail folds what does not fit behind More', (
    tester,
  ) async {
    final container = await _pump(tester, size: const Size(1024, 637));
    await tester.pumpAndSettle();
    final rail = find
        .descendant(
          of: find.byType(ShellNavigation),
          matching: find.byType(Scrollable),
        )
        .first;
    expect(tester.state<ScrollableState>(rail).position.maxScrollExtent, 0);
    for (final id in [
      'home',
      'results',
      'source-localfiles',
      'source-tidal',
      'source-jamendo',
      'more',
    ]) {
      expect(_nav(id).hitTestable(), findsOneWidget, reason: id);
    }
    const folded = ['collections', 'configuration', 'changeServer'];
    for (final id in folded) {
      expect(_nav(id), findsNothing, reason: id);
    }

    await tester.tap(_nav('more'));
    await tester.pumpAndSettle();
    for (final id in folded) {
      expect(_nav(id).hitTestable(), findsOneWidget, reason: id);
    }
    // Level with More, past the rail's edge.
    final shelf = find
        .ancestor(of: _nav('collections'), matching: find.byType(Material))
        .first;
    expect(
      tester.getCenter(shelf).dy,
      closeTo(tester.getCenter(_nav('more')).dy, 0.5),
    );
    expect(
      tester.getRect(shelf).left,
      greaterThan(
        tester.getRect(find.byKey(const ValueKey('navigation-rail'))).right,
      ),
    );

    await tester.tap(_nav('collections'));
    await tester.pumpAndSettle();
    expect(
      container.read(searchSessionProvider).destination,
      BrowseDestination.collections,
    );
    expect(_nav('collections'), findsNothing);
    // The destination shown is behind it.
    expect(
      find.descendant(
        of: _nav('more'),
        matching: find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.selected == true,
        ),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
