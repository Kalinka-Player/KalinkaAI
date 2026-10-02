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
import 'package:kalinka/providers/renderer_settings_route_provider.dart';
import 'package:kalinka/providers/server_info_provider.dart';
import 'package:kalinka/providers/settings_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/providers/websocket_provider.dart';
import 'package:kalinka/screens/music_player_screen.dart';
import 'package:kalinka/screens/plugin_catalog_screen.dart';
import 'package:kalinka/screens/settings_screen.dart';
import 'package:kalinka/screens/renderer_settings_screen.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/server_sheet.dart';
import 'package:kalinka/widgets/kalinka_bottom_sheet.dart';
import 'package:kalinka/widgets/server_chip.dart';
import 'package:kalinka/widgets/plugin_catalog_entry.dart';
import 'package:kalinka/widgets/now_playing_content.dart';
import 'package:kalinka/widgets/queue_zone.dart';
import 'package:kalinka/widgets/renderer_switcher.dart';
import 'package:kalinka/widgets/sheet_anchor.dart';
import 'package:kalinka/widgets/settings_controls/inline_markdown.dart';
import 'package:kalinka/widgets/settings_controls/settings_row.dart';
import 'package:kalinka/widgets/settings_controls/settings_text_input.dart';

PluginCatalog _catalog({
  String status = 'available',
  Map<String, dynamic>? qobuzCompatibility,
}) {
  final json =
      jsonDecode(File('test/fixtures/plugin_catalog.json').readAsStringSync())
          as Map<String, dynamic>;
  json['status'] = status;
  if (qobuzCompatibility != null) {
    (json['plugins'] as List).singleWhere(
      (p) => p['id'] == 'qobuz',
    )['compatibility'] = qobuzCompatibility;
  }
  return PluginCatalog.fromJson(json);
}

class _Connected extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
  void setStatus(ConnectionStatus value) => state = value;
}

class _Settings extends SettingsNotifier {
  int loads = 0;
  @override
  SettingsState build() => const SettingsState();
  @override
  Future<void> loadConfig() async {
    loads++;
  }

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
  Future<Map<String, dynamic>?> getServerUpdateInfo() async => null;
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
  double? appWidth,
  bool disableAnimations = false,
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
            size: Size(appWidth ?? size.width, size.height),
            textScaler: TextScaler.linear(scale),
            disableAnimations: disableAnimations,
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
      tester.widget<Text>(find.text('Managed with Kalinka Player')).style,
      labelStyle!.copyWith(color: KalinkaColors.textPrimary),
    );
    expect(find.text('Included with Kalinka Player'), findsNWidgets(2));
    expect(find.text('Included with Kalinka'), findsNothing);
    expect(find.text('Managed with Kalinka'), findsNothing);
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

  for (final (label, type) in [
    ('All', 'all'),
    ('Input sources', 'input_module'),
    ('Device control', 'output_device'),
  ]) {
    testWidgets(
      'clear search restores all $label without changing the type filter',
      (tester) async {
        final catalog = _catalog();
        final api = _CatalogApi(catalog);
        final container = await _container(
          _Proxy({'enabled': true, 'catalog_browsing': true}),
          api,
        );
        await _screen(
          tester,
          container,
          size: const Size(320, 640),
          scale: 1.8,
        );
        await tester.tap(find.widgetWithText(ChoiceChip, label));
        await tester.pumpAndSettle();
        final search = find.byKey(const ValueKey('plugin-search'));
        final clear = find.byKey(const ValueKey('plugin-search-clear'));
        expect(clear, findsNothing);
        await tester.ensureVisible(search);
        await tester.enterText(search, 'no plugin matches this');
        await tester.pumpAndSettle();
        expect(find.textContaining('No matching plugins'), findsOneWidget);
        expect(find.byTooltip('Clear search'), findsOneWidget);
        expect(find.descendant(of: search, matching: clear), findsOneWidget);
        expect(tester.getSize(clear).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(clear).height, greaterThanOrEqualTo(48));

        await tester.tap(clear);
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(search).controller!.text, isEmpty);
        expect(clear, findsNothing);
        expect(find.textContaining('No matching plugins'), findsNothing);
        expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label))
              .selected,
          isTrue,
        );
        expect(
          tester
              .widgetList<PluginCatalogEntry>(
                find.byType(PluginCatalogEntry, skipOffstage: false),
              )
              .map((entry) => entry.plugin.id)
              .toSet(),
          catalog.plugins
              .where((plugin) => type == 'all' || plugin.type == type)
              .map((plugin) => plugin.id)
              .toSet(),
        );
        expect(api.reads, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Reload sits to the right of Browse and disables while reading', (
    tester,
  ) async {
    final api = _CatalogApi(_catalog());
    final container = await _container(
      _Proxy({'enabled': true, 'catalog_browsing': true}),
      api,
    );
    await _screen(tester, container, size: const Size(320, 640), scale: 1.8);
    final browseBar = find.byKey(const ValueKey('catalog-browse-bar'));
    final reload = find.byKey(const ValueKey('catalog-reload'));
    expect(find.descendant(of: browseBar, matching: reload), findsOneWidget);
    // The Browse bar's outer bounds include its 20px phone gutters.
    expect(tester.getRect(reload).right, tester.getRect(browseBar).right - 20);
    expect(
      tester.getRect(reload).left,
      greaterThan(tester.getRect(find.text('BROWSE')).right),
    );
    expect(
      tester.getRect(reload).center.dy,
      closeTo(tester.getRect(browseBar).center.dy, 1),
    );
    expect(find.byKey(const ValueKey('catalog-footer')), findsNothing);
    expect(
      tester.getRect(find.byKey(const ValueKey('catalog-scroll'))).bottom,
      640,
    );

    final pending = api.pending = Completer<PluginCatalog>();
    await tester.tap(reload);
    await tester.pump();
    await tester.pump();
    expect(api.reads, 2);
    expect(tester.widget<TextButton>(reload).onPressed, isNull);
    pending.complete(_catalog(status: 'stale'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(reload).onPressed, isNotNull);
    expect(find.textContaining('Showing a cached catalog'), findsOneWidget);
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
      find.descendant(
        of: heading,
        matching: find.text('Kalinka Player server'),
      ),
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

  for (final (size, appWidth, scale) in [
    (const Size(390, 730), 390.0, 1.0),
    (const Size(483, 619), 1024.0, 1.0),
    (const Size(320, 640), 320.0, 1.8),
    (const Size(483, 619), 1024.0, 1.8),
  ]) {
    testWidgets(
      'header shrinks, fades and restores at $size with text scale $scale',
      (tester) async {
        final container = await _container(
          _Proxy({'enabled': true, 'catalog_browsing': true}),
          _CatalogApi(_catalog()),
        );
        await _screen(
          tester,
          container,
          size: size,
          appWidth: appWidth,
          scale: scale,
          disableAnimations: scale > 1,
        );
        final heading = find.byKey(const ValueKey('catalog-heading'));
        final details = find.byKey(const ValueKey('catalog-heading-details'));
        final browse = find.byKey(const ValueKey('catalog-browse-bar'));
        final scroll = tester
            .widget<CustomScrollView>(
              find.byKey(const ValueKey('catalog-scroll')),
            )
            .controller!;
        final delegate = tester
            .widget<SliverPersistentHeader>(find.byType(SliverPersistentHeader))
            .delegate;
        final range = delegate.maxExtent - delegate.minExtent;
        final expandedHeight = tester.getSize(heading).height;
        final expandedFont = tester
            .widget<Text>(find.text('Plugins'))
            .style!
            .fontSize!;
        expect(expandedFont, appWidth < kKalinkaTabletBreakpoint ? 29 : 35);
        expect(tester.widget<Opacity>(details).opacity, 1);
        expect(find.semantics.byLabel(RegExp('Read-only preview')), findsOne);

        // Repeated passes must be deterministic, including reduced-motion mode.
        for (var pass = 0; pass < 2; pass++) {
          scroll.jumpTo(range / 4);
          await tester.pumpAndSettle();
          expect(
            tester.getSize(heading).height,
            closeTo(expandedHeight - range / 4, 0.1),
          );
          expect(tester.widget<Opacity>(details).opacity, closeTo(0.5, 0.01));
          expect(
            tester.widget<Text>(find.text('Plugins')).style!.fontSize!,
            lessThan(expandedFont),
          );
          expect(
            tester.getTopLeft(browse).dy,
            closeTo(tester.getBottomLeft(heading).dy, 0.1),
          );

          scroll.jumpTo(range + 30);
          await tester.pumpAndSettle();
          expect(
            tester.getSize(heading).height,
            closeTo(delegate.minExtent, 0.1),
          );
          expect(
            tester.widget<Text>(find.text('Plugins')).style!.fontSize,
            appWidth < kKalinkaTabletBreakpoint ? 20 : 22,
          );
          expect(tester.widget<Opacity>(details).opacity, 0);
          expect(
            find.semantics.byLabel(RegExp('Read-only preview')),
            findsNothing,
          );
          expect(find.text('Plugins').hitTestable(), findsOneWidget);
          expect(
            find.byKey(const ValueKey('catalog-back')).hitTestable(),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('catalog-reload')).hitTestable(),
            findsOneWidget,
          );
          expect(find.byTooltip('Server online').hitTestable(), findsOneWidget);
          final compactBrowse = tester.getRect(browse);
          scroll.jumpTo(range + 100);
          await tester.pumpAndSettle();
          expect(tester.getRect(browse), compactBrowse);

          scroll.jumpTo(0);
          await tester.pumpAndSettle();
          expect(tester.getSize(heading).height, expandedHeight);
          expect(tester.widget<Opacity>(details).opacity, 1);
          expect(
            tester.widget<Text>(find.text('Plugins')).style!.fontSize,
            expandedFont,
          );
          expect(find.semantics.byLabel(RegExp('Read-only preview')), findsOne);
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

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
              .widget<TextField>(
                find.byKey(
                  const ValueKey('plugin-search'),
                  skipOffstage: false,
                ),
              )
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

  for (final (status, heading, releaseText) in [
    (
      'metadata_compatible',
      'Declared requirements match',
      'Server check: declared requirements match.',
    ),
    ('blocked', 'Requirements not met', 'Server check: requirements not met.'),
    (
      'unknown_future_status',
      'Compatibility unavailable',
      'Server check: result unavailable.',
    ),
    (
      'missing',
      'Compatibility unavailable',
      'Server check: result unavailable.',
    ),
  ]) {
    testWidgets('shows server compatibility $status without install permission', (
      tester,
    ) async {
      final result = status == 'missing'
          ? null
          : <String, dynamic>{
              'status': status,
              'channel': 'stable',
              'latest_compatible_version': status == 'metadata_compatible'
                  ? '5.0.1'
                  : null,
              'installation_allowed': false,
              'releases': [
                {
                  'version': '5.0.1',
                  'channel': 'stable',
                  'status': status,
                  'reasons': status == 'blocked'
                      ? [
                          {
                            'code': 'incompatible_sdk',
                            'installed': '1.0',
                            'required': '>=2',
                          },
                          {
                            'code': 'renderer_unavailable',
                            'renderer_id': 'living-room',
                          },
                          {'code': 'no_compatible_artifact'},
                        ]
                      : [],
                  'artifacts': status == 'blocked'
                      ? [
                          {
                            'filename': 'qobuz.deb',
                            'status': 'blocked',
                            'reasons': [
                              {
                                'code': 'unsupported_distribution',
                                'id': 'debian',
                                'version': '12',
                              },
                            ],
                          },
                        ]
                      : [],
                },
              ],
            };
      final api = _CatalogApi(_catalog(qobuzCompatibility: result));
      final container = await _container(
        _Proxy({'enabled': true, 'catalog_browsing': true}),
        api,
      );
      await _screen(tester, container, size: const Size(320, 640), scale: 1.8);
      await _expand(tester, 'qobuz');
      final details = find.byKey(
        const ValueKey('plugin-details-qobuz'),
        skipOffstage: false,
      );
      final text = tester
          .widgetList<Text>(
            find.descendant(
              of: details,
              matching: find.byType(Text, skipOffstage: false),
            ),
          )
          .map((text) => text.data ?? '')
          .join('\n');
      expect(text, contains(heading));
      expect(text, contains(releaseText));
      expect(
        text,
        isNot(contains('Compatibility with this server has not been checked')),
      );
      if (status == 'blocked') {
        expect(text, contains('SDK 1.0 does not meet >=2.'));
        expect(
          text,
          contains('Renderer is not connected. (renderer living-room)'),
        );
        expect(
          text,
          contains(
            'qobuz.deb: Server distribution debian 12 is not supported.',
          ),
        );
      }
      if (status == 'metadata_compatible') {
        expect(text, contains('version 5.0.1 (stable channel)'));
      }
      expect(text, contains('Catalog signatures are not verified'));
      expect(
        text,
        contains(
          'Package dependencies and actual device support have not been checked',
        ),
      );
      expect(find.text('Install'), findsNothing);
      expect(api.reads, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('older matching release does not hide a newer blocked version', (
    tester,
  ) async {
    final container = await _container(
      _Proxy({'enabled': true, 'catalog_browsing': true}),
      _CatalogApi(
        _catalog(
          qobuzCompatibility: {
            'status': 'metadata_compatible',
            'channel': 'stable',
            'latest_available_version': '6.0',
            'latest_compatible_version': '5.0.1',
            'newer_blocked_release': {
              'version': '6.0',
              'channel': 'stable',
              'status': 'blocked',
            },
          },
        ),
      ),
    );
    await _screen(tester, container);
    await _expand(tester, 'qobuz');
    expect(
      find.textContaining(
        'version 5.0.1 (stable channel)',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Newer version 6.0 does not meet the requirements',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'opening another entry reveals its beginning after the old header scrolls away',
    (tester) async {
      final container = await _container(
        _Proxy({'enabled': true, 'catalog_browsing': true}),
        _CatalogApi(_catalog()),
      );
      await _screen(tester, container, size: const Size(483, 619));
      await _expand(tester, 'jamendo');
      for (final id in ['localfiles', 'qobuz', 'spotify', 'jamendo']) {
        final row = find.byKey(ValueKey('plugin-$id'), skipOffstage: false);
        await Scrollable.ensureVisible(tester.element(row), alignment: 0);
        await tester.pumpAndSettle();
        if (id == 'localfiles') {
          expect(
            find.byKey(const ValueKey('plugin-jamendo')).hitTestable(),
            findsNothing,
          );
        }
        await tester.tap(
          find.descendant(of: row, matching: find.byType(Text)).first,
        );
        await tester.pumpAndSettle();
        final viewport = tester.getRect(
          find.byKey(const ValueKey('catalog-scroll')),
        );
        final header = tester.getRect(row);
        final details = tester.getRect(
          find.byKey(ValueKey('plugin-details-$id')),
        );
        final browseBottom = tester
            .getBottomLeft(find.byKey(const ValueKey('catalog-browse-bar')))
            .dy;
        expect(header.top, inInclusiveRange(browseBottom, browseBottom + 5));
        expect(details.top, closeTo(header.bottom, 1));
        expect(details.top, lessThan(viewport.bottom));
        expect(
          find.descendant(
            of: find.byType(PluginCatalogEntry),
            matching: find.byType(PinnedHeaderSliver),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'expanded identity pins below the compact heading and Browse bar',
    (tester) async {
      final container = await _container(
        _Proxy({'enabled': true, 'catalog_browsing': true}),
        _CatalogApi(_catalog()),
      );
      await _screen(tester, container, size: const Size(483, 619));
      final expandedHeading = tester.getRect(
        find.byKey(const ValueKey('catalog-heading')),
      );
      expect(
        tester.widget<Text>(find.text('Plugins')).style!.fontFamily,
        KalinkaFonts.displayFamily,
      );
      await _expand(tester, 'jamendo');
      final row = find.byKey(const ValueKey('plugin-jamendo'));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      final heading = tester.getRect(
        find.byKey(const ValueKey('catalog-heading')),
      );
      final browseBar = tester.getRect(
        find.byKey(const ValueKey('catalog-browse-bar')),
      );
      expect(heading.height, lessThan(expandedHeading.height));
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      scroll.jumpTo(scroll.offset + 100);
      await tester.pumpAndSettle();
      final viewport = tester.getRect(
        find.byKey(const ValueKey('catalog-scroll')),
      );
      expect(tester.getTopLeft(row).dy, closeTo(browseBar.bottom, 1));
      expect(
        tester.getRect(find.byKey(const ValueKey('catalog-heading'))),
        heading,
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('catalog-browse-bar'))),
        browseBar,
      );
      expect(viewport.bottom, 619);
      expect(find.byKey(const ValueKey('catalog-footer')), findsNothing);
      expect(
        find.byKey(const ValueKey('catalog-reload')).hitTestable(),
        findsOneWidget,
      );
      expect(find.byType(PinnedHeaderSliver), findsNWidgets(2));
      expect(find.byType(Scrollable), findsOneWidget);
      // Its collapse control is still hit-testable, not merely painted on top.
      await tester.tap(
        find.descendant(of: row, matching: find.byType(InkWell)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PinnedHeaderSliver), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (label, panelType) in [
    ('Server settings', SettingsScreen),
    ('Plugins', PluginCatalogScreen),
  ]) {
    testWidgets(
      '$label covers only the tablet queue and preserves state across resize',
      (tester) async {
        final container = await _container(
          _Proxy({'enabled': true, 'catalog_browsing': true}),
          _CatalogApi(_catalog()),
          player: true,
        );
        await tester.binding.setSurfaceSize(const Size(1280, 850));
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
        final queue = tester.getRect(find.byType(QueueZone));
        final nowPlaying = tester.getRect(find.byType(NowPlayingContent));
        await tester.tap(find.byType(ServerChip));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        // The incoming management panel never blocks the left-hand controls.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 160));
        expect(
          find.byType(RendererSwitcherDropdown).hitTestable(),
          findsOneWidget,
        );
        await tester.pumpAndSettle();

        final panel = find.byType(panelType);
        final panelState = tester.state(panel);
        final panelRect = tester.getRect(panel);
        expect(panelRect.left, queue.left);
        expect(panelRect.right, queue.right);
        expect(panelRect.left, greaterThan(nowPlaying.right));
        expect(tester.getRect(find.byType(NowPlayingContent)), nowPlaying);
        expect(
          find.byType(RendererSwitcherDropdown).hitTestable(),
          findsOneWidget,
        );
        expect(find.byType(ServerChip).hitTestable(), findsNothing);
        final anchor = SheetAnchor.elementOf(tester.element(panel));
        expect(SheetAnchor.paddingFor(anchor, 1280).left, panelRect.left);
        expect(SheetAnchor.paddingFor(anchor, 1280).right, 0);

        final settings = container.read(settingsProvider.notifier) as _Settings;
        settings.stageChange('base_config.server.name', 'Staged name');
        final loads = settings.loads;
        // Now Playing can open renderer settings without discarding the panel
        // underneath. System Back must dismiss only that topmost overlay.
        container
            .read(rendererSettingsRouteProvider.notifier)
            .open('living-room', 'Living Room');
        await tester.pumpAndSettle();
        final rendererRect = tester.getRect(
          find.byType(RendererSettingsScreen),
        );
        expect(rendererRect, panelRect);
        expect(
          find.byType(RendererSwitcherDropdown).hitTestable(),
          findsOneWidget,
        );
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(RendererSettingsScreen), findsNothing);
        expect(tester.state(panel), same(panelState));
        expect(find.byType(ServerChip).hitTestable(), findsNothing);

        for (final size in [const Size(400, 850), const Size(1280, 850)]) {
          await tester.binding.setSurfaceSize(size);
          await tester.pump();
          final exception = tester.takeException();
          if (exception != null) {
            expect('$exception', contains('RenderFlex overflowed'));
          }
          await tester.pumpAndSettle();
          expect(tester.state(panel), same(panelState));
          final rect = tester.getRect(panel);
          expect(rect.left, size.width == 400 ? 0 : queue.left);
          expect(rect.right, size.width);
          expect(settings.loads, loads);
          expect(
            container
                .read(settingsProvider)
                .getEffective('base_config.server.name'),
            'Staged name',
          );
          expect(tester.takeException(), isNull);
        }

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(panel, findsNothing);
        expect(find.byType(ServerChip).hitTestable(), findsOneWidget);
        expect(
          find.byType(RendererSwitcherDropdown).hitTestable(),
          findsOneWidget,
        );
        expect(tester.getRect(find.byType(QueueZone)), queue);
        expect(tester.takeException(), isNull);
      },
    );
  }

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
    expect(
      find.descendant(
        of: find.byType(PluginCatalogEntry),
        matching: find.byType(PinnedHeaderSliver),
      ),
      findsNothing,
    );
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
