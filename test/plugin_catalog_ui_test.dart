import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/plugin_catalog.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/plugin_catalog_provider.dart';
import 'package:kalinka/providers/onboarding_provider.dart';
import 'package:kalinka/providers/server_info_provider.dart';
import 'package:kalinka/providers/settings_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/providers/websocket_provider.dart';
import 'package:kalinka/screens/music_player_screen.dart';
import 'package:kalinka/screens/plugin_catalog_screen.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/server_sheet.dart';
import 'package:kalinka/widgets/kalinka_bottom_sheet.dart';
import 'package:kalinka/widgets/server_chip.dart';
import 'package:kalinka/widgets/plugin_catalog_entry.dart';
import 'package:kalinka/widgets/settings_controls/inline_markdown.dart';
import 'package:kalinka/widgets/settings_controls/settings_row.dart';
import 'package:kalinka/widgets/settings_controls/settings_text_input.dart';

PluginCatalog _catalog({String status = 'available'}) =>
    PluginCatalog.fromJson({
      ...(jsonDecode(
            File('test/fixtures/plugin_catalog.json').readAsStringSync(),
          )
          as Map<String, dynamic>),
      'status': status,
    });

class _Connected extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
  void setStatus(ConnectionStatus value) => state = value;
}

class _Settings extends SettingsNotifier {
  @override
  SettingsState build() => const SettingsState();
  @override
  Future<void> loadConfig() async {}
  void saved(bool enabled) =>
      state = state.copyWith(values: {pluginCatalogSettingPath: enabled});
}

class _Proxy implements KalinkaPlayerProxy {
  Map<String, dynamic> capabilities;
  int reads = 0;
  _Proxy(this.capabilities);
  @override
  Future<List<RendererInfo>> listRenderers() async => [];
  @override
  Future<Map<String, dynamic>> getServerVersion() async {
    reads++;
    return {'server_version': '5.5.0', 'plugin_management': capabilities};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _CatalogApi implements PluginCatalogApi {
  PluginCatalog result;
  int reads = 0;
  Completer<PluginCatalog>? pending;
  _CatalogApi(this.result);
  @override
  Future<PluginCatalog> read() async {
    reads++;
    return pending == null ? result : pending!.future;
  }
}

Future<ProviderContainer> _container(
  _Proxy proxy,
  _CatalogApi api, {
  bool player = false,
  _Proxy? otherServer,
}) async {
  SharedPreferences.setMockInitialValues({
    if (player) ...{
      'Kalinka.host': 'localhost',
      'Kalinka.port': 8080,
      'Kalinka.name': 'Test server',
      OnboardingStatusNotifier.sharedPrefOobeComplete: true,
      OnboardingStatusNotifier.sharedPrefCoachMarksShown: true,
    },
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      connectionStateProvider.overrideWith(_Connected.new),
      settingsProvider.overrideWith(_Settings.new),
      kalinkaProxyProvider.overrideWith(
        (ref) =>
            ref.watch(connectionSettingsProvider).host == 'other' &&
                otherServer != null
            ? otherServer
            : proxy,
      ),
      pluginCatalogApiProvider.overrideWithValue(api),
      if (player) ...[
        sourceModulesProvider.overrideWith((ref) => <ModuleInfo>[]),
        sourceCountProvider.overrideWithValue(1),
        webSocketProvider.overrideWith(
          (ref, path) => Completer<WebSocketChannel>().future,
        ),
      ],
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _screen(
  WidgetTester tester,
  ProviderContainer container, {
  Size size = const Size(400, 850),
  double scale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
          ),
          child: const Scaffold(body: PluginCatalogScreen()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _expand(WidgetTester tester, String id) async {
  final header = find.byKey(ValueKey('plugin-$id'));
  final title = find.descendant(of: header, matching: find.byType(Text)).first;
  await tester.scrollUntilVisible(
    header,
    150,
    scrollable: find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await Scrollable.ensureVisible(tester.element(title), alignment: 0.5);
  await tester.pumpAndSettle();
  expect(title.hitTestable(), findsOneWidget);
  await tester.tap(title);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('catalog uses the actual settings row and input typography', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SettingsRow(
            label: 'Setting label',
            sublabel: 'Setting explanation',
            isVertical: true,
            control: SettingsTextInput(
              value: 'Setting value',
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    final labelStyle = tester.widget<Text>(find.text('Setting label')).style;
    final explanationStyle = tester
        .widget<InlineMarkdown>(find.byType(InlineMarkdown))
        .style;
    final inputStyle = tester.widget<TextField>(find.byType(TextField)).style;
    final hintStyle = tester
        .widget<TextField>(find.byType(TextField))
        .decoration!
        .hintStyle;

    final container = await _container(
      _Proxy({'enabled': true, 'catalog_browsing': true}),
      _CatalogApi(_catalog()),
    );
    await _screen(tester, container);
    expect(
      tester.widget<Text>(find.text('OFFICIAL  2')).style,
      KalinkaTextStyles.sectionHeaderMuted,
    );
    expect(
      tester.widget<Text>(find.text('BROWSE')).style,
      KalinkaTextStyles.sectionHeaderMuted.copyWith(
        letterSpacing: 1,
        color: KalinkaColors.textPrimary,
      ),
    );
    final row = find.byKey(const ValueKey('plugin-jamendo'));
    final text = tester
        .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
        .toList();
    expect(text[0].style, labelStyle);
    expect(text[1].style, explanationStyle);
    final search = tester.widget<TextField>(
      find.byKey(const ValueKey('plugin-search')),
    );
    expect(search.style, inputStyle);
    expect(search.decoration!.hintStyle, hintStyle);
    await _expand(tester, 'jamendo');
    expect(
      tester.widget<Text>(find.text('Created by')).style,
      explanationStyle,
    );
    expect(
      tester.widget<Text>(find.text('Declared requirements')).style,
      labelStyle!.copyWith(color: KalinkaColors.statusPendingLight),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('type chips use berry only for the selected choice', (
    tester,
  ) async {
    final container = await _container(
      _Proxy({'enabled': true, 'catalog_browsing': true}),
      _CatalogApi(_catalog()),
    );
    await _screen(tester, container);

    void expectSelection(String selectedLabel) {
      final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
      expect(chips.where((chip) => chip.selected), hasLength(1));
      for (final label in ['All', 'Input sources', 'Device control']) {
        final finder = find.widgetWithText(ChoiceChip, label);
        final chip = tester.widget<ChoiceChip>(finder);
        final selected = label == selectedLabel;
        final foreground = selected
            ? KalinkaColors.textPrimary
            : KalinkaColors.textSecondary;
        expect(chip.selected, selected);
        expect(
          chip.color!.resolve({if (selected) WidgetState.selected}),
          selected ? KalinkaColors.accent : KalinkaColors.surfaceElevated,
        );
        expect(
          chip.side!.color,
          selected ? KalinkaColors.accent : KalinkaColors.borderDefault,
        );
        expect(chip.labelStyle!.color, foreground);
        if (chip.avatar != null) {
          final icon = find.descendant(of: finder, matching: find.byType(Icon));
          expect(IconTheme.of(tester.element(icon)).color, foreground);
        }
      }
    }

    expectSelection('Input sources');
    for (final label in [
      'Device control',
      'All',
      'Input sources',
      'Input sources',
    ]) {
      await tester.tap(find.widgetWithText(ChoiceChip, label));
      await tester.pumpAndSettle();
      expectSelection(label);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('catalog header shows live connection status without a menu', (
    tester,
  ) async {
    final container = await _container(
      _Proxy({'enabled': true, 'catalog_browsing': true}),
      _CatalogApi(_catalog()),
    );
    await _screen(tester, container);
    expect(find.text('ON THIS SERVER'), findsNothing);
    expect(find.byIcon(Icons.more_vert), findsNothing);
    expect(find.byTooltip('Catalog options'), findsNothing);
    expect(find.text('Reload'), findsOneWidget);
    final back = tester.widget<Icon>(find.byIcon(Icons.arrow_back));
    expect(back.size, 22);
    expect(back.color, KalinkaColors.textPrimary);
    expect(
      tester.getSize(find.byKey(const ValueKey('catalog-back'))),
      const Size(42, 42),
    );
    final heading = find.byKey(const ValueKey('catalog-heading'));
    expect(
      find.descendant(of: heading, matching: find.text('Kalinka server')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: heading, matching: find.text('Plugins')),
      findsOneWidget,
    );
    for (final (status, color, label) in [
      (ConnectionStatus.connected, KalinkaColors.statusOnline, 'Server online'),
      (
        ConnectionStatus.reconnecting,
        KalinkaColors.statusPending,
        'Reconnecting',
      ),
      (ConnectionStatus.offline, KalinkaColors.statusOffline, 'Server offline'),
      (ConnectionStatus.connecting, KalinkaColors.statusPending, 'Connecting'),
      (ConnectionStatus.none, KalinkaColors.textMuted, 'Not connected'),
      (ConnectionStatus.connected, KalinkaColors.statusOnline, 'Server online'),
    ]) {
      (container.read(connectionStateProvider.notifier) as _Connected)
          .setStatus(status);
      // Reconnecting deliberately has a continuously pulsing banner.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final dot = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('catalog-connection-status')),
      );
      expect((dot.decoration as BoxDecoration).color, color);
      expect(find.byTooltip(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  for (final capabilities in [
    <String, dynamic>{},
    {'enabled': false, 'catalog_browsing': true},
    {'enabled': true, 'catalog_browsing': false},
  ]) {
    testWidgets(
      'preview stays hidden without both explicit capabilities: $capabilities',
      (tester) async {
        final api = _CatalogApi(_catalog());
        final container = await _container(_Proxy(capabilities), api);
        await _screen(tester, container);
        expect(find.textContaining('preview is off'), findsOneWidget);
        expect(api.reads, 0);
        expect(
          (await container.read(pluginCatalogProvider.future)).status,
          'disabled',
        );
        expect(api.reads, 0);
      },
    );
  }

  test(
    'staged settings never enable the feature; a saved flag refreshes capabilities',
    () async {
      final proxy = _Proxy({'enabled': false, 'catalog_browsing': true});
      final container = await _container(proxy, _CatalogApi(_catalog()));
      final subscription = container.listen(serverInfoProvider, (_, next) {});
      addTearDown(subscription.close);
      await container.read(serverInfoProvider.future);
      expect(container.read(pluginCatalogEnabledProvider), false);
      container
          .read(settingsProvider.notifier)
          .stageChange(pluginCatalogSettingPath, true);
      expect(container.read(pluginCatalogEnabledProvider), false);
      expect(proxy.reads, 1);
      proxy.capabilities = {'enabled': true, 'catalog_browsing': true};
      (container.read(settingsProvider.notifier) as _Settings).saved(true);
      await container.read(serverInfoProvider.future);
      expect(container.read(pluginCatalogEnabledProvider), true);
      expect(proxy.reads, 2);
    },
  );

  test(
    'disconnect revokes access and a late catalog response cannot reopen it',
    () async {
      final api = _CatalogApi(_catalog())..pending = Completer<PluginCatalog>();
      final container = await _container(
        _Proxy({'enabled': true, 'catalog_browsing': true}),
        api,
      );
      final subscription = container.listen(
        pluginCatalogProvider,
        (_, next) {},
      );
      addTearDown(subscription.close);
      await container.read(serverInfoProvider.future);
      await Future<void>.delayed(Duration.zero);
      (container.read(connectionStateProvider.notifier) as _Connected)
          .setStatus(ConnectionStatus.offline);
      expect(container.read(pluginCatalogEnabledProvider), false);
      api.pending!.complete(_catalog());
      expect(
        (await container.read(pluginCatalogProvider.future)).status,
        'disabled',
      );
    },
  );

  testWidgets(
    'inline expansion keeps one entry open and exposes no installation controls',
    (tester) async {
      final api = _CatalogApi(_catalog());
      final container = await _container(
        _Proxy({'enabled': true, 'catalog_browsing': true}),
        api,
      );
      await _screen(tester, container);
      await _expand(tester, 'jamendo');
      int expanded() => tester
          .widgetList<PluginCatalogEntry>(find.byType(PluginCatalogEntry))
          .where((panel) => panel.expanded)
          .length;
      expect(expanded(), 1);
      await _expand(tester, 'localfiles');
      expect(expanded(), 1);
      await _expand(tester, 'localfiles');
      expect(expanded(), 0);
      expect(find.text('Install'), findsNothing);
      expect(find.text('Update'), findsNothing);
      expect(find.text('Install from URL'), findsNothing);
      expect(api.reads, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disabling the preview hides an already open catalog', (
    tester,
  ) async {
    final proxy = _Proxy({'enabled': true, 'catalog_browsing': true});
    final api = _CatalogApi(_catalog());
    final container = await _container(proxy, api);
    await _screen(tester, container);
    expect(find.byKey(const ValueKey('plugin-jamendo')), findsOneWidget);
    proxy.capabilities['enabled'] = false;
    (container.read(settingsProvider.notifier) as _Settings).saved(false);
    await tester.pumpAndSettle();
    expect(find.textContaining('preview is off'), findsOneWidget);
    expect(find.byType(PluginCatalogEntry), findsNothing);
    expect(api.reads, 1);
  });

  testWidgets('switching to a non-opted-in server revokes browsing', (
    tester,
  ) async {
    final api = _CatalogApi(_catalog());
    final other = _Proxy({'enabled': false, 'catalog_browsing': true});
    final container = await _container(
      _Proxy({'enabled': true, 'catalog_browsing': true}),
      api,
      otherServer: other,
    );
    await _screen(tester, container);
    container
        .read(connectionSettingsProvider.notifier)
        .setDeviceEphemeral('Other server', 'other', 8080);
    expect(container.read(pluginCatalogEnabledProvider), false);
    await tester.pumpAndSettle();
    expect(find.textContaining('preview is off'), findsOneWidget);
    expect(find.byType(PluginCatalogEntry), findsNothing);
    expect(other.reads, 1);
    expect(api.reads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'player catalog preserves inline details across resize and owns Back',
    (tester) async {
      final api = _CatalogApi(_catalog());
      final container = await _container(
        _Proxy({'enabled': true, 'catalog_browsing': true}),
        api,
        player: true,
      );
      await tester.binding.setSurfaceSize(const Size(400, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const MusicPlayerScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ServerChip));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plugins'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('plugin-search')),
        'Jamendo',
      );
      await tester.pumpAndSettle();
      await _expand(tester, 'jamendo');
      final panel = tester.state(find.byType(PluginCatalogScreen));
      for (final size in [const Size(1280, 850), const Size(400, 850)]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pump();
        // Existing outgoing player layout can overflow for one resize frame
        // with test fonts, as in settings_panel_resize_test.dart.
        final exception = tester.takeException();
        if (exception != null) {
          expect('$exception', contains('RenderFlex overflowed'));
        }
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(PluginCatalogScreen)), same(panel));
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('plugin-search')))
              .controller!
              .text,
          'Jamendo',
        );
        expect(
          tester
              .widget<PluginCatalogEntry>(find.byType(PluginCatalogEntry))
              .expanded,
          true,
        );
        expect(tester.takeException(), isNull);
      }
      expect(api.reads, 1);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(PluginCatalogScreen), findsNothing);
      expect(find.byType(MusicPlayerScreen), findsOneWidget);
      // The Settings-style arrow must dismiss the same panel as system Back.
      await tester.tap(find.byType(ServerChip));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plugins'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('catalog-back')));
      await tester.pumpAndSettle();
      expect(find.byType(PluginCatalogScreen), findsNothing);
      expect(find.byType(MusicPlayerScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'device filter and family search show readable controls and model scope',
    (tester) async {
      final container = await _container(
        _Proxy({'enabled': true, 'catalog_browsing': true}),
        _CatalogApi(_catalog()),
      );
      await _screen(tester, container);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Device control'));
      await tester.enterText(
        find.byKey(const ValueKey('plugin-search')),
        'Yamaha',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('plugin-jamendo')), findsNothing);
      expect(find.byKey(const ValueKey('plugin-dummydevice')), findsNothing);
      await _expand(tester, 'musiccast');
      expect(find.text('Supported models'), findsOneWidget);
      expect(find.text('Supported families'), findsOneWidget);
      expect(find.text('Controls and limitations'), findsOneWidget);
      expect(
        find.text('Yamaha MusicCast / Yamaha Extended Control'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(320, 640), const Size(640, 800)]) {
    testWidgets('narrow and tablet panes handle large text at $size', (
      tester,
    ) async {
      final container = await _container(
        _Proxy({'enabled': true, 'catalog_browsing': true}),
        _CatalogApi(_catalog()),
      );
      await _screen(tester, container, size: size, scale: 1.8);
      await _expand(tester, 'jamendo');
      expect(
        tester
            .widget<PluginCatalogEntry>(
              find.byKey(const ValueKey('entry-jamendo')),
            )
            .expanded,
        isTrue,
      );
      expect(
        find.byKey(
          const ValueKey('plugin-details-jamendo'),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('stale feed stays visible with a warning', (tester) async {
    final container = await _container(
      _Proxy({'enabled': true, 'catalog_browsing': true}),
      _CatalogApi(_catalog(status: 'stale')),
    );
    await _screen(tester, container);
    expect(find.textContaining('Showing a cached catalog'), findsOneWidget);
    expect(find.byKey(const ValueKey('plugin-jamendo')), findsOneWidget);
  });

  testWidgets(
    'expanded identity pins within its card; heading and footer stay fixed',
    (tester) async {
      final container = await _container(
        _Proxy({'enabled': true, 'catalog_browsing': true}),
        _CatalogApi(_catalog()),
      );
      await _screen(tester, container, size: const Size(483, 619));
      final heading = tester.getRect(
        find.byKey(const ValueKey('catalog-heading')),
      );
      final footer = tester.getRect(
        find.byKey(const ValueKey('catalog-footer')),
      );
      expect(
        tester.widget<Text>(find.text('Plugins')).style!.fontFamily,
        KalinkaFonts.displayFamily,
      );
      await _expand(tester, 'jamendo');
      final row = find.byKey(const ValueKey('plugin-jamendo'));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      scroll.jumpTo(scroll.offset + 100);
      await tester.pumpAndSettle();
      final viewport = tester.getRect(
        find.byKey(const ValueKey('catalog-scroll')),
      );
      expect(tester.getTopLeft(row).dy, closeTo(viewport.top, 1));
      expect(
        tester.getRect(find.byKey(const ValueKey('catalog-heading'))),
        heading,
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('catalog-footer'))),
        footer,
      );
      expect(find.byType(PinnedHeaderSliver), findsOneWidget);
      expect(find.byType(Scrollable), findsOneWidget);
      // Its collapse control is still hit-testable, not merely painted on top.
      await tester.tap(
        find.descendant(of: row, matching: find.byType(InkWell)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PinnedHeaderSliver), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('model lookup stays inline and never claims verification', (
    tester,
  ) async {
    final container = await _container(
      _Proxy({'enabled': true, 'catalog_browsing': true}),
      _CatalogApi(_catalog()),
    );
    await _screen(tester, container);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Device control'));
    await tester.pumpAndSettle();
    await _expand(tester, 'musiccast');
    final search = find.byKey(const ValueKey('model-search-musiccast'));
    await tester.ensureVisible(search);
    await tester.enterText(search, 'nonexistent model');
    await tester.pumpAndSettle();
    expect(find.text('No catalog match · Not verified'), findsOneWidget);
    expect(find.byType(PluginCatalogScreen), findsOneWidget);
    expect(find.text('Check connected device'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(PinnedHeaderSliver), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'phone sheet shows Plugins only after opt-in and returns its action',
    (tester) async {
      final proxy = _Proxy({'enabled': false, 'catalog_browsing': true});
      final container = await _container(proxy, _CatalogApi(_catalog()));
      ServerSheetAction? action;
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.8)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    action = await showKalinkaBottomSheet<ServerSheetAction>(
                      context: context,
                      contentBuilder: (_) => const ServerSheetContent(),
                    );
                  },
                  child: const Text('Open menu'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open menu'));
      await tester.pumpAndSettle();
      expect(find.text('Plugins'), findsNothing);
      proxy.capabilities['enabled'] = true;
      container.invalidate(serverInfoProvider);
      await tester.pumpAndSettle();
      expect(find.text('Plugins'), findsOneWidget);
      await tester.ensureVisible(find.text('Plugins'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plugins'));
      await tester.pumpAndSettle();
      expect(action, ServerSheetAction.openPlugins);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tablet sheet closes before opening Plugins', (tester) async {
    final container = await _container(
      _Proxy({'enabled': true, 'catalog_browsing': true}),
      _CatalogApi(_catalog()),
    );
    final actions = <String>[];
    await tester.binding.setSurfaceSize(const Size(640, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.8)),
            child: child!,
          ),
          home: Scaffold(
            body: ServerSheet(
              onClose: () => actions.add('close'),
              onOpenSettings: () {},
              onOpenDiscovery: () {},
              onOpenPlugins: () => actions.add('plugins'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Plugins'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plugins'));
    await tester.pumpAndSettle();
    expect(actions, ['close', 'plugins']);
    expect(tester.takeException(), isNull);
  });
}
