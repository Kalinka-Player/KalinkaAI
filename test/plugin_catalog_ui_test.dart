import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/playqueue_events.dart' show PlayQueueEvent;
import 'package:kalinka/data_model/plugin_catalog.dart';
import 'package:kalinka/data_model/presentation_schema.dart';
import 'package:kalinka/data_model/configuration_sections.dart';
import 'package:kalinka/widgets/settings_controls/settings_toggle.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/box_control_provider.dart';
import 'package:kalinka/providers/supervisor_api.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/log_export_provider.dart';
import 'package:kalinka/providers/modules_state_provider.dart';
import 'package:kalinka/providers/plugin_catalog_provider.dart';
import 'package:kalinka/providers/onboarding_provider.dart';
import 'package:kalinka/providers/renderer_settings_route_provider.dart';
import 'package:kalinka/providers/server_info_provider.dart';
import 'package:kalinka/providers/server_update_provider.dart';
import 'package:kalinka/providers/settings_provider.dart';
import 'package:kalinka/providers/restart_provider.dart';
import 'package:kalinka/providers/plugin_state.dart';
import 'package:kalinka/screens/server_configuration_screen.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/providers/toast_provider.dart';
import 'package:kalinka/providers/websocket_provider.dart';
import 'package:kalinka/providers/wire_event_provider.dart'
    show playQueueEventBusProvider;
import 'package:kalinka/screens/music_player_screen.dart';
import 'package:kalinka/screens/log_export_screen.dart';
import 'package:kalinka/screens/plugin_about_screen.dart';
import 'package:kalinka/screens/plugin_catalog_screen.dart';
import 'package:kalinka/screens/plugin_settings_screen.dart';
import 'package:kalinka/screens/settings_screen.dart';
import 'package:kalinka/screens/renderer_settings_screen.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/server_sheet.dart';
import 'package:kalinka/widgets/breadcrumb_crumb.dart';
import 'package:kalinka/widgets/kalinka_bottom_sheet.dart';
import 'package:kalinka/widgets/kalinka_button.dart';
import 'package:kalinka/widgets/kalinka_dialog.dart';
import 'package:kalinka/widgets/mini_player.dart';
import 'package:kalinka/widgets/page_banner.dart';
import 'package:kalinka/widgets/pending_changes_banner.dart';
import 'package:kalinka/widgets/configuration_appearance.dart';
import 'package:kalinka/widgets/settings_controls/settings_action_row.dart';
import 'package:kalinka/screens/configuration_review_screen.dart';
import 'package:kalinka/widgets/settings_top_bar.dart';
import 'package:kalinka/widgets/settings_page_intro.dart';
import 'package:kalinka/widgets/server_chip.dart';
import 'package:kalinka/widgets/plugin_catalog_entry.dart';
import 'package:kalinka/widgets/restart_overlay.dart';
import 'package:kalinka/widgets/now_playing_content.dart';
import 'package:kalinka/widgets/search/search_session_view.dart';
import 'package:kalinka/widgets/renderer_switcher.dart';
import 'package:kalinka/widgets/sheet_anchor.dart';
import 'package:kalinka/widgets/settings_controls/inline_markdown.dart';
import 'package:kalinka/widgets/expert_settings_screen.dart';
import 'package:kalinka/widgets/settings_controls/module_header_row.dart';
import 'package:kalinka/widgets/settings_controls/settings_row.dart';
import 'package:kalinka/widgets/settings_controls/settings_text_input.dart';

import 'support/server_answer.dart';
import 'support/soundcard_fakes.dart' show FakeBox;

PluginCatalog _catalog({
  String status = 'available',
  Map<String, dynamic>? qobuzCompatibility,
}) {
  final json = jsonDecode(
    File('test/fixtures/plugin_catalog.json').readAsStringSync(),
  ) as Map<String, dynamic>;
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
  final SettingsState initial;
  _Settings([this.initial = const SettingsState()]);
  int loads = 0;
  int saves = 0;
  @override
  Future<void> applyChanges() async {
    saves++;
    state = state.copyWith(
      values: {...state.values, ...state.stagedChanges},
      stagedChanges: {},
    );
  }

  @override
  SettingsState build() => initial;
  @override
  Future<void> loadConfig() async {
    loads++;
  }

  void saved(bool enabled) =>
      state = state.copyWith(values: {pluginCatalogSettingPath: enabled});
}

class _Restart extends RestartNotifier {
  final bool fail;
  _Restart({this.fail = false});
  int calls = 0;
  final followed = <String>[];

  /// What the next followed restart ends in: done, abandoned or an error.
  String follow = 'done';
  @override
  RestartState build() => const RestartState();
  @override
  Future<void> executeRestart() async {
    calls++;
    if (fail) {
      state = const RestartState(
        isRestarting: true,
        error: 'Could not save settings',
      );
      return;
    }
    await ref.read(settingsProvider.notifier).applyChanges();
    state = const RestartState(isRestarting: true, isDone: true);
  }

  @override
  Future<void> followRestart({String subtitle = ''}) async {
    followed.add(subtitle);
    // Each restart begins afresh, as the real one does once dismissed, and
    // takes a moment, as the real one does.
    state = const RestartState();
    state = RestartState(
      isRestarting: true,
      currentStep: RestartStep.starting,
      subtitle: subtitle,
    );
    await Future<void>.delayed(const Duration(seconds: 1));
    state = switch (follow) {
      'error' => RestartState(
        isRestarting: true,
        error: 'Server did not come back after restart.',
        subtitle: subtitle,
      ),
      'abandoned' => const RestartState(),
      _ => RestartState(isRestarting: true, isDone: true, subtitle: subtitle),
    };
    // Done puts itself away a moment later, as the real one does.
    if (state.isDone) {
      Timer(const Duration(milliseconds: 2200), () {
        if (ref.mounted) state = const RestartState();
      });
    }
  }
}

class _Proxy implements KalinkaPlayerProxy {
  Map<String, dynamic> capabilities;
  Map<String, dynamic>? updateInfo;
  int reads = 0;
  _Live live = _Live();
  _Proxy(this.capabilities);
  @override
  Future<ModulesAndDevices> listModules() async => live.value;
  @override
  Future<List<RendererInfo>> listRenderers() async => [];
  @override
  Future<Map<String, dynamic>?> getServerUpdateInfo() async => updateInfo;
  @override
  Future<Map<String, dynamic>> getServerVersion() async {
    reads++;
    return {'server_version': '5.5.0', 'plugin_management': capabilities};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _Logs extends LogExportController {
  @override
  LogExportView build() => const LogExportView(unsupported: true);
}

class _CatalogApi implements PluginCatalogApi {
  PluginCatalog result;
  int reads = 0;
  Completer<PluginCatalog>? pending;
  _CatalogApi(this.result);

  /// Thrown by the next reads, as a server that cannot answer would.
  PluginCatalogException? failure;

  @override
  Future<PluginCatalog> read() async {
    reads++;
    if (failure case final failure?) throw failure;
    return pending == null ? result : pending!.future;
  }

  List<PluginUpdate> available = const [];
  final runs = <(String, PluginOperation)>[];
  Completer<void>? running;
  String? refusal;

  /// Whether the server restarts to carry an accepted operation out, and
  /// what its helper then has to say about it.
  bool restarts = false;
  PluginOperationRecord? record;
  int recordReads = 0;

  @override
  Future<List<PluginUpdate>> updates() async => available;

  @override
  Future<bool> run(String pluginId, PluginOperation operation) async {
    runs.add((pluginId, operation));
    await running?.future;
    if (refusal case final refusal?) throw PluginCatalogException(refusal);
    return restarts;
  }

  @override
  Future<PluginOperationRecord?> lastOperation() async {
    recordReads++;
    return record;
  }
}

/// What `/server/modules` answers; tests change it as the server would.
class _Live {
  ModulesAndDevices value;
  _Live([ModulesAndDevices? value])
    : value = value ?? ModulesAndDevices(inputModules: [], devices: []);
}

ModuleInfo _module(
  String name, {
  bool enabled = true,
  String state = 'ready',
  String? summary,
  String? message,
}) => ModuleInfo.fromJson({
  'name': name,
  'title': name,
  'enabled': enabled,
  'state': state,
  'summary': ?summary,
  'error_message': ?message,
});

Map<String, dynamic> _moduleSpec(String id, {bool device = false}) {
  final prefix = device ? 'devices' : 'input_modules';
  return {
    'id': id,
    'kind': device ? 'device' : 'input_module',
    'title': id,
    'fields': [
      {
        'path': '$prefix.$id.enabled',
        'label': 'Module enabled',
        'widget': 'toggle',
        'type': 'bool',
        'default': true,
      },
      {
        'path': '$prefix.$id.region',
        'label': 'Store region',
        'widget': 'text_input',
        'type': 'str',
      },
    ],
  };
}

/// Settings whose schema carries a switch and one field for each plugin.
SettingsState _settingsWith(Map<String, bool> enabled) => SettingsState(
  schema: PresentationSchema.fromJson({
    'schema_version': '1',
    'pages': [
      {
        'id': 'input_modules',
        'title': 'Modules',
        'modules': [
          for (final id in enabled.keys)
            if (id != 'musiccast') _moduleSpec(id),
        ],
      },
      {
        'id': 'devices',
        'title': 'Devices',
        'modules': [
          if (enabled.containsKey('musiccast'))
            _moduleSpec('musiccast', device: true),
        ],
      },
    ],
  }),
  values: {
    for (final MapEntry(key: id, value: on) in enabled.entries)
      '${id == 'musiccast' ? 'devices' : 'input_modules'}.$id.enabled': on,
  },
);

SettingsState _serverSettings({bool details = false}) {
  final plugins = _settingsWith({'localfiles': true});
  return plugins.copyWith(
    schema: PresentationSchema(
      schemaVersion: '1',
      pages: [
        PageSpec(
          id: 'base_config',
          title: 'Server',
          sections: [
            SectionSpec(
              id: 'base_config.server',
              title: 'Server',
              fields: [
                FieldSpec(
                  path: 'base_config.server.service_name',
                  label: 'Service name',
                  help: 'How this server appears in the app when found on your network',
                  widget: WidgetKind.text,
                  type: 'str',
                ),
                if (details) ...const [
                  FieldSpec(
                    path: 'base_config.server.auto_upgrade',
                    label: 'Auto upgrade',
                    widget: WidgetKind.toggle,
                    type: 'bool',
                    defaultValue: false,
                  ),
                  FieldSpec(
                    path: 'base_config.server.supervisor_status',
                    label: 'Supervisor status',
                    widget: WidgetKind.text,
                    type: 'str',
                    readonly: true,
                    defaultValue: 'Not installed',
                    help: 'Detailed service information.',
                  ),
                ],
              ],
            ),
            SectionSpec(
              id: 'base_config.device_automation',
              title: 'Device automation',
              fields: [
                FieldSpec(
                  path: 'base_config.device_automation.auto_power_on',
                  label: 'Auto power on',
                  widget: WidgetKind.toggle,
                  type: 'bool',
                  defaultValue: false,
                ),
                FieldSpec(
                  path: 'base_config.device_automation.auto_power_off',
                  label: 'Auto power off',
                  widget: WidgetKind.toggle,
                  type: 'bool',
                  defaultValue: false,
                ),
                FieldSpec(
                  path: ConfigurationSections.timeoutPath,
                  label: 'Pause timeout',
                  widget: WidgetKind.numberInput,
                  type: 'int',
                  defaultValue: 0,
                  constraints: Constraints(ge: 0),
                ),
              ],
            ),
            SectionSpec(
              id: 'base_config.new_feature',
              title: 'Future feature',
              fields: [
                FieldSpec(
                  path: 'base_config.new_feature.value',
                  label: 'Future setting',
                  widget: WidgetKind.text,
                  type: 'str',
                ),
              ],
            ),
          ],
        ),
        ...plugins.schema!.pages,
      ],
    ),
  );
}

Future<ProviderContainer> _container(
  _Proxy proxy,
  _CatalogApi api, {
  bool player = false,
  _Proxy? otherServer,
  _Live? live,
  SettingsState settings = const SettingsState(),
  String? name,
  _Restart? restart,
  FakeBox? box,
  Stream<PlayQueueEvent>? events,
}) async {
  live ??= _Live();
  proxy.live = live;
  SharedPreferences.setMockInitialValues({
    'Kalinka.name': ?name,
    if (events != null) ...{'Kalinka.host': 'localhost', 'Kalinka.port': 8080},
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
      if (box != null) ...[
        supervisorApiProvider.overrideWithValue(box),
        serverIdentityProvider.overrideWith((ref) async => 'box-1'),
      ],
      if (restart != null) restartProvider.overrideWith(() => restart),
      connectionStateProvider.overrideWith(_Connected.new),
      serverAnswering('box-1'),
      settingsProvider.overrideWith(() => _Settings(settings)),
      // With events, the real module state reads the proxy and follows them.
      if (events != null)
        playQueueEventBusProvider.overrideWith((ref) => events)
      else
        modulesStateProvider.overrideWithBuild((ref, _) async => live!.value),
      kalinkaProxyProvider.overrideWith(
        (ref) =>
            ref.watch(connectionSettingsProvider).host == 'other' &&
                otherServer != null
            ? otherServer
            : proxy,
      ),
      pluginCatalogApiProvider.overrideWithValue(api),
      if (player) ...[
        logExportProvider.overrideWith(_Logs.new),
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
  VoidCallback? onClose,
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
          child: Scaffold(body: PluginCatalogScreen(onClose: onClose)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _scrollable => find
    .descendant(
      of: find.byKey(const ValueKey('catalog-scroll')),
      matching: find.byType(Scrollable),
    )
    .first;

/// Taps a plugin's row: an installed one opens its configuration page, one
/// the server lacks its About page.
Future<void> _open(WidgetTester tester, String id) async {
  final row = find.byKey(ValueKey('plugin-$id'));
  // From the top, so a row scrolled past is found too.
  tester
      .widget<CustomScrollView>(find.byKey(const ValueKey('catalog-scroll')))
      .controller!
      .jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(row, 150, scrollable: _scrollable);
  await Scrollable.ensureVisible(tester.element(row), alignment: 0.5);
  await tester.pumpAndSettle();
  expect(row.hitTestable(), findsOneWidget);
  await tester.tap(row);
  await tester.pumpAndSettle();
}

/// Opens a plugin's About page, from its configuration page where it has one.
Future<void> _about(WidgetTester tester, String id) async {
  final about = find.byKey(ValueKey('plugin-about-$id'));
  if (about.evaluate().isEmpty) await _open(tester, id);
  if (find.byType(PluginAboutScreen).evaluate().isEmpty) {
    await tester.tap(about);
    await tester.pumpAndSettle();
  }
  expect(find.byType(PluginAboutScreen), findsOneWidget);
}

Future<void> _tapTab(WidgetTester tester, PluginTab tab) async {
  final button = find.byKey(ValueKey('catalog-tab-${tab.name}'));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void _expectTab(WidgetTester tester, PluginTab selected) {
  for (final tab in [PluginTab.sources, PluginTab.server, PluginTab.devices]) {
    final button = find.byKey(ValueKey('catalog-tab-${tab.name}'));
    final box = tester.widget<Container>(
      find.descendant(of: button, matching: find.byType(Container)).first,
    );
    final underline = (box.decoration! as BoxDecoration).border!.bottom;
    final label = tester.widget<Text>(
      find.descendant(of: button, matching: find.byType(Text)),
    );
    expect(
      underline.color,
      tab == selected ? KalinkaColors.accent : Colors.transparent,
    );
    expect(underline.width, 2);
    expect(
      label.style!.color,
      tab == selected ? KalinkaColors.textPrimary : KalinkaColors.textSecondary,
    );
    expect(
      tester.getSemantics(button),
      isSemantics(isSelected: tab == selected, isButton: true),
    );
  }
}

/// The plugins listed, top to bottom, built or not.
List<String> _listed(WidgetTester tester) => tester
    .widgetList<PluginRow>(find.byType(PluginRow, skipOffstage: false))
    .map((row) => row.plugin.id)
    .toList();

String _statusOf(WidgetTester tester, String id) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(ValueKey('plugin-$id')),
        matching: find.byKey(const ValueKey('plugin-status')),
      ),
    )
    .data!;

/// The word a row's badge says, as Server settings says it.
ModuleStatusBadge? _badgeOf(WidgetTester tester, String id) {
  final badge = find.descendant(
    of: find.byKey(ValueKey('plugin-$id')),
    matching: find.byKey(const ValueKey('plugin-badge')),
  );
  return badge.evaluate().isEmpty
      ? null
      : tester.widget<ModuleStatusBadge>(badge);
}

List<double> _opacitiesOf(WidgetTester tester, String id) => tester
    .widgetList<Opacity>(
      find.descendant(
        of: find.byKey(ValueKey('plugin-$id')),
        matching: find.byType(Opacity),
      ),
    )
    .map((o) => o.opacity)
    .toList();

/// A section heading's spans: its name, then its count.
List<InlineSpan> _headingSpans(WidgetTester tester, String text) =>
    (tester.widget<Text>(find.textContaining(text).first).textSpan! as TextSpan)
        .children!;

Finder _onPage<T>(Finder matching) =>
    find.descendant(of: find.byType(T), matching: matching);

/// Configuration's changes bar, under every page it opens.
final _changesBar = find.byKey(const ValueKey('configuration-changes'));

void main() {
  for (final withSettings in [true, false]) {
    testWidgets(
      'live plugin errors stay with status and appear once, settings: $withSettings',
      (tester) async {
        final live = _Live(
          ModulesAndDevices(inputModules: [_module('localfiles')], devices: []),
        );
        final container = await _container(
          _Proxy({'enabled': true, 'catalog_browsing': true}),
          _CatalogApi(_catalog()),
          live: live,
          settings: withSettings
              ? _settingsWith({'localfiles': true})
              : const SettingsState(),
        );
        await _screen(
          tester,
          container,
          size: withSettings ? const Size(375, 812) : const Size(320, 850),
          scale: withSettings ? 1 : 2,
          disableAnimations: true,
        );
        await _open(tester, 'localfiles');
        final status = _onPage<PluginSettingsScreen>(
          find.byType(PluginStatusSummary),
        );
        expect(
          find.descendant(of: status, matching: find.text('Ready')),
          findsOneWidget,
        );
        const message =
            'Cannot open **Music library**. Check the server folder permissions.';
        live.value = ModulesAndDevices(
          inputModules: [
            _module('localfiles', state: 'error', message: message),
          ],
          devices: [],
        );
        container.invalidate(modulesStateProvider);
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: status, matching: find.text('Error')),
          findsOneWidget,
        );
        final messages = _onPage<PluginSettingsScreen>(
          find.byWidgetPredicate(
            (w) => w is InlineMarkdown && w.text == message,
          ),
        );
        expect(messages, findsOneWidget);
        expect(find.descendant(of: status, matching: messages), findsOneWidget);
        expect(
          tester
              .widget<Text>(
                find.descendant(of: status, matching: find.text('Error')),
              )
              .style!
              .color,
          KalinkaColors.statusError,
        );
        live.value = ModulesAndDevices(
          inputModules: [_module('localfiles', summary: '2 folders connected')],
          devices: [],
        );
        container.invalidate(modulesStateProvider);
        await tester.pumpAndSettle();
        expect(messages, findsNothing);
        expect(
          find.descendant(of: status, matching: find.text('Ready')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: status,
            matching: find.text('2 folders connected'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'software status and automatic updates share one card and stage edits',
    (tester) async {
      final proxy = _Proxy({'enabled': true, 'catalog_browsing': true})
        ..updateInfo = {
          'current_version': '5.5.0',
          'latest_version': '5.5.0',
          'update_available': false,
          'upgrade_supported': true,
        };
      final container = await _container(
        proxy,
        _CatalogApi(_catalog()),
        settings: _serverSettings(details: true),
      );
      await _screen(tester, container);
      await _tapTab(tester, PluginTab.server);
      await container.read(serverUpdateProvider.future);
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('server-software-updates'));
      expect(
        find.descendant(of: card, matching: find.text('Up to date')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Automatic updates')),
        findsOneWidget,
      );
      final toggle = find.descendant(of: card, matching: find.byType(Switch));
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      expect(tester.getSize(toggle).height, greaterThanOrEqualTo(48));
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).stagedChanges, {
        ConfigurationSections.updatePath: true,
      });
      expect(
        find.descendant(of: card, matching: find.text('Changed')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Streamer orders sections and edits the name from the server card',
    (tester) async {
      final container = await _container(
        _Proxy({'enabled': true, 'catalog_browsing': true}),
        _CatalogApi(_catalog()),
        settings: _serverSettings(details: true),
        box: FakeBox(),
      );
      await container
          .read(connectionSettingsProvider.notifier)
          .setDevice('RPi 4B', '192.168.1.42', 8000);
      await _screen(tester, container, size: const Size(400, 700));
      await _tapTab(tester, PluginTab.server);
      expect(find.text('Server address').hitTestable(), findsOneWidget);
      expect(
        find.text('http://192.168.1.42:8000').hitTestable(),
        findsOneWidget,
      );
      expect(find.text('Server version').hitTestable(), findsOneWidget);
      expect(find.text('5.5.0').hitTestable(), findsOneWidget);
      expect(find.text('Supervisor status'), findsOneWidget);
      expect(find.text('Not installed'), findsOneWidget);
      expect(find.text('RPi 4B'), findsOneWidget);
      expect(find.byTooltip('Edit server name'), findsOneWidget);
      expect(find.text('Service name'), findsNothing);
      expect(find.text('Automatic updates'), findsOneWidget);
      expect(find.text('Detailed service information.'), findsNothing);
      expect(find.text('Maintenance'), findsNothing);
      expect(find.text('System details'), findsNothing);
      expect(find.text('Sound card'), findsNothing);
      expect(find.byType(BreadcrumbCrumb), findsNothing);
      for (final label in [
        'Restart Kalinka',
        'Streamer dashboard',
        'Restart streamer',
        'Power off streamer',
        'Download server logs',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      // Expert is the tab's own switch, not a page of its own.
      expect(find.text('Advanced settings'), findsNothing);
      expect(find.byKey(const ValueKey('expert-mode-toggle')), findsOneWidget);
      final summary = find.byKey(const ValueKey('server-summary'));
      final summaryRect = tester.getRect(summary);
      expect(
        summaryRect.bottom,
        lessThan(tester.getRect(find.text('MANAGEMENT')).top),
      );
      final headings = ['SERVER', 'SOFTWARE UPDATES', 'MANAGEMENT', 'SUPPORT'];
      for (var i = 1; i < headings.length; i++) {
        expect(
          tester.getRect(find.text(headings[i - 1])).bottom,
          lessThan(tester.getRect(find.text(headings[i])).top),
        );
      }
      expect(
        find.descendant(of: summary, matching: find.text('RPi 4B')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: summary, matching: find.byType(TextField)),
        findsNothing,
      );
      final titleBar = find.byType(SettingsTopBar).last;
      final barRect = tester.getRect(titleBar);
      final card = tester.widget<Container>(
        find.descendant(of: summary, matching: find.byType(Container)).first,
      );
      expect(card.margin, const EdgeInsets.fromLTRB(20, 0, 20, 12));
      await tester.drag(
        find.byKey(const ValueKey('catalog-scroll')),
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(summary).top, lessThan(summaryRect.top));
      expect(tester.getRect(titleBar), barRect);
      await tester.ensureVisible(find.text('Restart streamer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restart streamer'));
      await tester.pumpAndSettle();
      expect(find.text('Restart streamer?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Edit server name'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit server name'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(
        find.descendant(of: summary, matching: find.byType(TextField)),
        findsNothing,
      );
      final nameInput = find.byKey(const ValueKey('server-name-input'));
      expect(tester.widget<TextField>(nameInput).controller!.text, 'RPi 4B');
      expect(tester.widget<TextField>(nameInput).focusNode!.hasFocus, isTrue);
      await tester.enterText(nameInput, 'Cancelled name');
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).hasPendingChanges, isFalse);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('RPi 4B'), findsOneWidget);
      await tester.tap(find.byTooltip('Edit server name'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(nameInput).controller!.text, 'RPi 4B');
      await tester.enterText(nameInput, '   ');
      await tester.pumpAndSettle();
      final done = find.widgetWithText(KalinkaButton, 'Done');
      expect(tester.widget<KalinkaButton>(done).enabled, isFalse);
      await tester.enterText(nameInput, 'Living room');
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).hasPendingChanges, isFalse);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Living room'), findsOneWidget);
      expect(nameInput, findsNothing);
      expect(container.read(settingsProvider).stagedChanges, {
        ConfigurationSections.namePath: 'Living room',
      });
      await tester.tap(find.byTooltip('Edit server name'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(nameInput).controller!.text,
        'Living room',
      );
      await tester.enterText(nameInput, 'Abandoned edit');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(ServerSettingsBody), findsOneWidget);
      expect(container.read(settingsProvider).stagedChanges, {
        ConfigurationSections.namePath: 'Living room',
      });
      await tester.tap(find.byKey(const ValueKey('pending-changes-discard')));
      await tester.pumpAndSettle();
      expect(find.text('RPi 4B'), findsOneWidget);
      expect(container.read(settingsProvider).hasPendingChanges, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  for (final loading in [true, false]) {
    testWidgets(
      'server summary and management survive missing schema, loading: $loading',
      (tester) async {
        final container = await _container(
          _Proxy({'enabled': true, 'catalog_browsing': true}),
          _CatalogApi(_catalog()),
          settings: SettingsState(
            isLoading: loading,
            error: loading ? null : 'Unavailable',
          ),
          box: FakeBox(),
        );
        await _screen(tester, container);
        // A loading spinner never settles, so only advance frames for this case.
        final tab = find.byKey(const ValueKey('catalog-tab-server'));
        await tester.tap(tab);
        await tester.pump();
        await container.read(boxControlProvider.future);
        await tester.pump();
        expect(find.text('Server address'), findsOneWidget);
        expect(find.text('Server version'), findsOneWidget);
        expect(find.text('Restart Kalinka'), findsOneWidget);
        expect(find.text('Power off streamer'), findsOneWidget);
        expect(find.text('Retry'), loading ? findsNothing : findsOneWidget);
        expect(find.byTooltip('Edit server name'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'review opens the named invalid settings and preserves edits on Back',
    (tester) async {
      const path = 'base_config.server.service_name';
      final settings = _serverSettings().copyWith(
        stagedChanges: {path: ''},
        issues: {
          path: [
            const ConfigIssue(path: path, message: 'Enter a player name.'),
          ],
        },
      );
      final container = await _container(
        _Proxy({'enabled': true, 'catalog_browsing': true}),
        _CatalogApi(_catalog()),
        settings: settings,
      );
      await _screen(tester, container);
      expect(find.text('1 change staged · check Service name'), findsOneWidget);
      await tester.tap(find.text('REVIEW'));
      await tester.pumpAndSettle();
      expect(find.byType(ConfigurationReviewScreen), findsOneWidget);
      expect(
        find.byKey(const ValueKey('review-base_config.server.service_name')),
        findsOneWidget,
      );
      expect(find.text('Enter a player name.'), findsOneWidget);
      expect(find.byType(ChangedSettingLabel), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Listening room');
      await tester.pumpAndSettle();
      expect(
        container.read(settingsProvider).stagedChanges[path],
        'Listening room',
      );
      expect(find.byType(TextField), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ConfigurationReviewScreen), findsNothing);
      expect(container.read(settingsProvider).hasPendingChanges, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'changes bar wraps at large text and retains generous action targets',
    (tester) async {
      final container = await _container(
        _Proxy({'enabled': true, 'catalog_browsing': true}),
        _CatalogApi(_catalog()),
        settings: _serverSettings().copyWith(
          stagedChanges: {'base_config.server.service_name': 'Room'},
        ),
      );
      await _screen(tester, container, size: const Size(320, 640), scale: 1.8);
      final summary = tester.widget<Text>(
        find.text('1 change staged · restart required'),
      );
      expect(summary.maxLines, isNull);
      for (final key in ['pending-changes-discard', 'pending-changes-apply']) {
        expect(
          tester.getSize(find.byKey(ValueKey(key))).height,
          greaterThanOrEqualTo(48),
        );
        expect(find.byKey(ValueKey(key)).hitTestable(), findsOneWidget);
      }
      expect(tester.getRect(_changesBar).bottom, 640);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ready status uses the brighter text without changing its subtle fill',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: const Scaffold(
            body: ModuleStatusBadge(
              label: 'READY',
              color: KalinkaColors.statusOnline,
            ),
          ),
        ),
      );
      final text = tester.widget<Text>(find.text('READY'));
      expect(text.style!.color, KalinkaColors.statusOnlineLight);
      expect(text.style!.fontSize, greaterThanOrEqualTo(12));
      final badge = tester.widget<Container>(
        find.descendant(
          of: find.byType(ModuleStatusBadge),
          matching: find.byType(Container),
        ),
      );
      expect(
        (badge.decoration as BoxDecoration).color,
        KalinkaColors.statusOnline.withValues(alpha: .1),
      );
    },
  );

  testWidgets(
    'plugin descriptions sit below the settings title and ordinary edits stay pending on return',
    (tester) async {
      final catalog = _catalog();
      final plugin = catalog.plugins.singleWhere((p) => p.id == 'localfiles');
      final container = await _container(
        _Proxy({'enabled': true, 'catalog_browsing': true}),
        _CatalogApi(catalog),
        settings: _settingsWith({'localfiles': true}),
        live: _Live(
          ModulesAndDevices(inputModules: [_module('localfiles')], devices: []),
        ),
      );
      await _screen(tester, container);
      expect(find.text(plugin.description), findsNothing);
      await _open(tester, 'localfiles');
      final intro = _onPage<PluginSettingsScreen>(
        find.byType(SettingsPageIntro),
      );
      final description = find.descendant(
        of: intro,
        matching: find.text(plugin.description),
      );
      expect(description, findsOneWidget);
      expect(tester.widget<Text>(description).maxLines, isNull);
      expect(
        tester.getRect(description).top,
        greaterThan(
          tester
              .getRect(
                find.descendant(
                  of: _onPage<PluginSettingsScreen>(
                    find.byType(SettingsTopBar),
                  ),
                  matching: find.text('Folders & NAS settings'),
                ),
              )
              .bottom,
        ),
      );
      final field = _onPage<PluginSettingsScreen>(find.byType(TextField));
      await tester.ensureVisible(field);
      await tester.enterText(field, 'GB');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(KalinkaDialog), findsNothing);
      expect(container.read(settingsProvider).stagedChanges, {
        'input_modules.localfiles.region': 'GB',
      });
      expect(_statusOf(tester, 'localfiles'), 'Changes pending');
      expect(_badgeOf(tester, 'localfiles')!.label, 'READY');
      container.read(settingsProvider.notifier).discardAll();
      await tester.pumpAndSettle();
      expect(find.text('Changes pending'), findsNothing);
    },
  );

  test('pending changes include nested and collection settings, and stay with their plugin', () {
    final settings = _settingsWith({'localfiles': true, 'qobuz': true})
        .copyWith(
          stagedChanges: {
            'input_modules.localfiles.folders': [
              {'path': '/music'},
            ],
            'input_modules.localfiles.indexer.enabled': true,
          },
        );
    final modules = ModulesAndDevices(
      inputModules: [_module('localfiles'), _module('qobuz')],
      devices: [],
    );
    PluginState state(String id) => PluginState.of(
      _catalog().plugins.singleWhere((p) => p.id == id),
      modules: modules,
      settings: settings,
    );
    expect(state('localfiles').hasPendingChanges, isTrue);
    expect(state('qobuz').hasPendingChanges, isFalse);
  });

  for (final systemBack in [false, true]) {
    testWidgets(
      'leaving Configuration asks before discarding, system back: $systemBack',
      (tester) async {
        var closes = 0;
        final container = await _container(
          _Proxy({'enabled': true, 'catalog_browsing': true}),
          _CatalogApi(_catalog()),
          settings: _serverSettings(),
        );
        await _screen(tester, container, onClose: () => closes++);
        container
            .read(settingsProvider.notifier)
            .stageChange('base_config.server.service_name', 'Listening room');
        await tester.pumpAndSettle();
        Future<void> back() async {
          if (systemBack) {
            await tester.binding.handlePopRoute();
          } else {
            await tester.tap(find.byKey(const ValueKey('settings-back')));
          }
          await tester.pumpAndSettle();
        }

        await back();
        expect(find.text('Apply your changes?'), findsOneWidget);
        expect(closes, 0);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(container.read(settingsProvider).hasPendingChanges, isTrue);
        await back();
        await tester.tap(find.byKey(const ValueKey('configuration-discard')));
        await tester.pumpAndSettle();
        expect(closes, 1);
        expect(container.read(settingsProvider).hasPendingChanges, isFalse);
      },
    );
  }

  for (final result in ['success', 'validation', 'failure']) {
    testWidgets('apply on exit handles $result without losing changes', (
      tester,
    ) async {
      var closes = 0;
      final restart = _Restart(fail: result == 'failure');
      final container = await _container(
        _Proxy({'enabled': true, 'catalog_browsing': true}),
        _CatalogApi(_catalog()),
        restart: restart,
        settings: _serverSettings().copyWith(
          stagedChanges: {'base_config.server.service_name': 'Listening room'},
          issues: result == 'validation'
              ? {
                  'base_config.server.service_name': [
                    const ConfigIssue(
                      path: 'base_config.server.service_name',
                      message: 'Choose a name',
                      severity: IssueSeverity.error,
                    ),
                  ],
                }
              : {},
        ),
      );
      await _screen(tester, container, onClose: () => closes++);
      await tester.tap(find.byKey(const ValueKey('settings-back')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('configuration-apply')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      if (result == 'failure') {
        expect(find.text('Could not save settings'), findsOneWidget);
        await tester.tap(find.text('Dismiss'));
      }
      await tester.pumpAndSettle();
      expect(closes, result == 'success' ? 1 : 0);
      expect(
        container.read(settingsProvider).hasPendingChanges,
        result != 'success',
      );
      expect(restart.calls, result == 'validation' ? 0 : 1);
      expect(
        (container.read(settingsProvider.notifier) as _Settings).saves,
        result == 'success' ? 1 : 0,
      );
    });
  }

  testWidgets('device automation is editable only in expert settings', (
    tester,
  ) async {
    final api = _CatalogApi(_catalog())
      ..failure = const PluginCatalogException('Catalog unavailable');
    final settings = _serverSettings();
    final container = await _container(
      _Proxy({'enabled': true, 'catalog_browsing': true}),
      api,
      settings: settings.copyWith(
        schema: PresentationSchema(
          schemaVersion: settings.schema!.schemaVersion,
          pages: settings.schema!.pages,
          expertFields: configurationFields(settings.schema).toList(),
        ),
      ),
    );
    await _screen(tester, container);
    await _tapTab(tester, PluginTab.server);
    expect(find.byTooltip('Edit server name'), findsOneWidget);
    expect(find.text('Future setting'), findsOneWidget);
    for (final label in [
      'DEVICE AUTOMATION',
      'Auto power on',
      'Auto power off',
      'Pause timeout',
    ]) {
      expect(find.text(label), findsNothing);
    }
    await tester.tap(find.byTooltip('Edit server name'));
    await tester.pumpAndSettle();
    final name = find.byKey(const ValueKey('server-name-input'));
    await tester.enterText(name, 'Listening room');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expert-mode-toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(
      _onPage<ExpertSettingsScreen>(find.byType(TextField)).first,
      'device_automation',
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    for (final label in ['Auto power on', 'Auto power off', 'Pause timeout']) {
      expect(find.text(label), findsOneWidget);
    }
    final power = find.byKey(
      const ValueKey('base_config.device_automation.auto_power_on'),
    );
    await tester.ensureVisible(power);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: power, matching: find.byType(SettingsToggle)),
    );
    await tester.pumpAndSettle();
    final timeout = find.descendant(
      of: find.byKey(const ValueKey(ConfigurationSections.timeoutPath)),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(timeout);
    await tester.pumpAndSettle();
    await tester.enterText(timeout, '60');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expert-mode-toggle')));
    await tester.pumpAndSettle();
    expect(find.byType(ExpertSettingsScreen), findsNothing);
    expect(find.text('Auto power on'), findsNothing);
    expect(find.text('Pause timeout'), findsNothing);
    await _tapTab(tester, PluginTab.devices);
    await _tapTab(tester, PluginTab.server);
    expect(container.read(settingsProvider).stagedChanges, {
      'base_config.server.service_name': 'Listening room',
      'base_config.device_automation.auto_power_on': true,
      ConfigurationSections.timeoutPath: 60,
    });
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Apply your changes?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('configuration-discard')));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).hasPendingChanges, false);
    expect(tester.takeException(), isNull);
  });

  for (final (size, scale) in [
    (const Size(375, 812), 1.0),
    (const Size(320, 850), 2.0),
    (const Size(812, 375), 1.0),
    (const Size(1024, 768), 1.0),
  ]) {
    testWidgets('Streamer fits $size at text scale $scale', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final container = await _container(
        _Proxy({'enabled': true, 'catalog_browsing': true}),
        _CatalogApi(_catalog()),
        settings: _serverSettings(details: true),
        box: FakeBox(),
      );
      await container
          .read(connectionSettingsProvider.notifier)
          .setDevice(
            'Listening room',
            'kalinka-long-server-address.local',
            8000,
          );
      await _screen(
        tester,
        container,
        size: size,
        scale: scale,
        disableAnimations: true,
      );
      await _tapTab(tester, PluginTab.server);
      for (final label in [
        'Server address',
        'Server version',
        'Power off streamer',
        'Listening room',
        'Automatic updates',
      ]) {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        expect(find.text(label).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.ensureVisible(find.byTooltip('Edit server name'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit server name'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = FakeViewPadding(
        bottom: size.height < 500 ? 140 : 300,
      );
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      final nameInput = find.byKey(const ValueKey('server-name-input'));
      await tester.ensureVisible(nameInput);
      await tester.pumpAndSettle();
      expect(nameInput.hitTestable(), findsOneWidget);
      await tester.enterText(nameInput, 'Living room');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Done').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        container
            .read(settingsProvider)
            .stagedChanges[ConfigurationSections.namePath],
        'Living room',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Streamer support rows lead with their icons, and expert swaps the body',
    (tester) async {
      final container = await _container(
        _Proxy({'enabled': true, 'catalog_browsing': true}),
        _CatalogApi(_catalog()),
        settings: _serverSettings(),
      );
      await _screen(tester, container);
      await _tapTab(tester, PluginTab.server);
      expect(find.text('Restart Kalinka'), findsOneWidget);
      expect(find.text('Now-playing display'), findsNothing);
      for (final (label, icon, navigates) in [
        ('Restart Kalinka', Icons.restart_alt, false),
        ('Download server logs', Icons.description_outlined, true),
      ]) {
        final text = find.text(label);
        final row = find.ancestor(
          of: text,
          matching: find.byType(SettingsActionRow),
        );
        final leading = find.descendant(of: row, matching: find.byIcon(icon));
        expect(
          tester.getRect(leading).right,
          lessThan(tester.getRect(text).left),
        );
        expect(
          find.descendant(of: row, matching: find.byIcon(Icons.chevron_right)),
          navigates ? findsOneWidget : findsNothing,
        );
      }
      // Expert swaps the tab's body for the flat list, and back.
      await tester.tap(find.byKey(const ValueKey('expert-mode-toggle')));
      await tester.pumpAndSettle();
      expect(find.byType(ExpertSettingsScreen), findsOneWidget);
      expect(find.byType(ServerSettingsBody), findsNothing);
      await tester.tap(find.byKey(const ValueKey('expert-mode-toggle')));
      await tester.pumpAndSettle();
      expect(find.byType(ServerSettingsBody), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the exit question stays usable with large text on a narrow screen',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final container = await _container(
        _Proxy({'enabled': true, 'catalog_browsing': true}),
        _CatalogApi(_catalog()),
        settings: _serverSettings(),
      );
      await _screen(
        tester,
        container,
        size: const Size(320, 850),
        scale: 1.8,
        onClose: () {},
      );
      container
          .read(settingsProvider.notifier)
          .stageChange('base_config.server.service_name', 'Listening room');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-back')));
      await tester.pumpAndSettle();
      expect(find.text('Apply your changes?'), findsOneWidget);
      await tester.ensureVisible(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).hasPendingChanges, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

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

    final container = await _container(
      _Proxy({'enabled': true, 'catalog_browsing': true}),
      _CatalogApi(_catalog()),
    );
    await _screen(tester, container);
    final tabStyle = tester.widget<Text>(find.text('MUSIC SOURCES')).style!;
    expect(tabStyle.fontFamily, KalinkaFonts.monoFamily);
    expect(tabStyle.letterSpacing, 1);
    expect(tabStyle.color, KalinkaColors.textPrimary);
    // Section names are set as the shelves over tracks and albums.
    expect(
      _headingSpans(tester, 'MORE SOURCES').first.style,
      KalinkaTextStyles.sectionLabel.copyWith(color: KalinkaColors.textPrimary),
    );
    final row = find.byKey(const ValueKey('plugin-jamendo'));
    final text = tester
        .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
        .toList();
    expect(text[0].style, labelStyle);
    expect(text[1].style, explanationStyle);
    expect(
      text[2].style,
      explanationStyle!.copyWith(color: KalinkaColors.textMuted),
    );
    await _about(tester, 'jamendo');
    expect(
      tester.widget<Text>(find.text('Created by')).style,
      explanationStyle,
    );
    expect(
      tester.widget<Text>(find.text('Managed with Kalinka Player')).style,
      labelStyle!.copyWith(color: KalinkaColors.textPrimary),
    );
    expect(
      _onPage<PluginAboutScreen>(find.text('Included with Kalinka Player')),
      findsOneWidget,
    );
    expect(find.text('Included with Kalinka'), findsNothing);
    expect(find.text('Managed with Kalinka'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tabs underline only the selected section in berry', (
    tester,
  ) async {
    final container = await _container(
      _Proxy({'enabled': true, 'catalog_browsing': true}),
      _CatalogApi(_catalog()),
    );
    await _screen(tester, container);
    _expectTab(tester, PluginTab.sources);
    // Updates head each list rather than having a tab of their own.
    expect(find.text('UPDATES'), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
    // The berry line sits on the grey rule that runs the whole width.
    final tabs = tester.getRect(find.byKey(const ValueKey('catalog-tabs')));
    expect(tabs.height, 44);
    final hifi = tester.getRect(
      find.byKey(const ValueKey('catalog-tab-devices')),
    );
    final sources = tester.getRect(
      find.byKey(const ValueKey('catalog-tab-sources')),
    );
    // From the content's inset, an even gap apart.
    final server = tester.getRect(
      find.byKey(const ValueKey('catalog-tab-server')),
    );
    expect(sources.left, closeTo(tabs.left + 20, 0.1));
    expect(server.left - hifi.right, closeTo(hifi.left - sources.right, 0.1));
    expect(server.right, lessThanOrEqualTo(tabs.right - 20 + 0.1));
    expect(hifi.width / 12, closeTo(sources.width / 13, 0.1));
    expect(
      tester.getRect(find.byKey(const ValueKey('catalog-tab-sources'))).bottom,
      tabs.bottom,
    );
    for (final tab in [
      PluginTab.devices,
      PluginTab.server,
      PluginTab.sources,
      PluginTab.sources,
    ]) {
      await _tapTab(tester, tab);
      _expectTab(tester, tab);
      final description = find.byKey(const ValueKey('catalog-description'));
      if (tab == PluginTab.devices) {
        expect(
          tester
              .widget<Text>(
                find.descendant(of: description, matching: find.byType(Text)),
              )
              .data,
          'Let Kalinka adjust your amplifier’s volume and switch inputs.',
        );
      } else {
        expect(description, findsNothing);
      }
      expect(find.byType(PageBanner), findsNothing);
      expect(find.text('HIFI CONTROL'), findsOneWidget);
      expect(find.text('Configuration'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'installed plugins come first, then the rest, counted, in either tab',
    (tester) async {
      final container = await _container(
        _Proxy({'enabled': true, 'catalog_browsing': true}),
        _CatalogApi(_catalog()),
        live: _Live(
          ModulesAndDevices(
            inputModules: [
              _module('upnp'),
              // Switched off is still installed.
              _module('jamendo', enabled: false, state: 'disabled'),
              _module('localfiles'),
            ],
            devices: [_module('musiccast')],
          ),
        ),
        settings: _settingsWith({'jamendo': false}),
      );
      await _screen(tester, container, size: const Size(400, 1400));
      // Official and stable first within each, else as the catalog lists
      // them.
      expect(_listed(tester), [
        'jamendo',
        'localfiles',
        'upnp',
        'qobuz',
        'spotify',
      ]);
      expect(find.text('YOUR SOURCES · 3'), findsOneWidget);
      expect(find.text('MORE SOURCES · 2'), findsOneWidget);
      expect(find.bySemanticsLabel('Your sources, 3'), findsOneWidget);
      expect(find.bySemanticsLabel('More sources, 2'), findsOneWidget);
      expect(
        _headingSpans(tester, 'YOUR SOURCES · 3').last.style!.color,
        KalinkaColors.textMuted,
      );
      expect(
        tester.getRect(find.textContaining('MORE SOURCES')).top,
        greaterThan(
          tester.getRect(find.byKey(const ValueKey('entry-upnp'))).bottom,
        ),
      );
      // The two sections stand further apart than rows do.
      final gap =
          tester.getRect(find.textContaining('MORE SOURCES')).top -
          tester.getRect(find.byKey(const ValueKey('entry-upnp'))).bottom;
      expect(gap, greaterThanOrEqualTo(32));
      // Every row ends in one chevron, installed or not.
      for (final id in ['jamendo', 'localfiles', 'upnp', 'qobuz', 'spotify']) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey('entry-$id')),
            matching: find.byIcon(Icons.chevron_right),
          ),
          findsOneWidget,
        );
      }

      await _tapTab(tester, PluginTab.devices);
      expect(_listed(tester), ['musiccast', 'dummydevice']);
      expect(find.bySemanticsLabel('Your controls, 1'), findsOneWidget);
      expect(find.bySemanticsLabel('More controls, 1'), findsOneWidget);
      // It comes with the server, so there is nothing to install.
      expect(_statusOf(tester, 'dummydevice'), 'Included with Kalinka Player');
      expect(
        find.byKey(const ValueKey('plugin-install-dummydevice')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('badges and what a plugin does come from the catalog', (
    tester,
  ) async {
    final container = await _container(
      _Proxy({'enabled': true, 'catalog_browsing': true}),
      _CatalogApi(_catalog()),
      live: _Live(
        ModulesAndDevices(
          inputModules: [_module('localfiles', summary: '2 folders connected')],
          devices: [],
        ),
      ),
      name: 'Living room',
    );
    // Wide enough for the test font to set a status and pill on one line.
    await _screen(tester, container, size: const Size(900, 1400));
    Finder inRow(String id, Finder matching) => find.descendant(
      of: find.byKey(ValueKey('plugin-$id')),
      matching: matching,
    );

    expect(inRow('localfiles', find.text('Folders & NAS')), findsOneWidget);
    expect(
      inRow(
        'localfiles',
        find.text('Music from USB drives, this device or network storage.'),
      ),
      findsOneWidget,
    );
    // Its state as Server settings words it, then the module's own words.
    expect(_badgeOf(tester, 'localfiles')!.label, 'READY');
    expect(_badgeOf(tester, 'localfiles')!.color, KalinkaColors.statusOnline);
    expect(_statusOf(tester, 'localfiles'), '2 folders connected');
    expect(
      find.bySemanticsLabel(
        RegExp(r'^Folders & NAS\. Ready\. 2 folders connected$'),
      ),
      findsOneWidget,
    );
    expect(
      inRow(
        'upnp',
        find.text('Send music to Living room from compatible apps.'),
      ),
      findsOneWidget,
    );
    // Publisher and maturity are separate facts; a plugin may carry both.
    expect(inRow('qobuz', find.text('Unofficial')), findsOneWidget);
    expect(inRow('qobuz', find.text('Experimental')), findsOneWidget);
    expect(inRow('upnp', find.text('Unofficial')), findsOneWidget);
    expect(inRow('upnp', find.text('Experimental')), findsNothing);
    expect(inRow('jamendo', find.text('Unofficial')), findsNothing);
    final experimental = tester.widget<Text>(
      inRow('qobuz', find.text('Experimental')),
    );
    expect(experimental.style!.color, KalinkaColors.statusPendingLight);
    final unofficial = tester.widget<Text>(
      inRow('qobuz', find.text('Unofficial')),
    );
    expect(unofficial.style!.color, KalinkaColors.textSecondary);

    expect(inRow('qobuz', find.text('Browse in Kalinka')), findsNothing);
    expect(inRow('qobuz', find.text('Play from another app')), findsNothing);
    expect(
      find.bySemanticsLabel('Qobuz. Unofficial. Experimental'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a row not yet installed is one target, Install apart', (
    tester,
  ) async {
    final api = _CatalogApi(_catalog());
    final container = await _container(
      _Proxy({'enabled': true, 'catalog_browsing': true, 'installation': true}),
      api,
    );
    await _screen(tester, container, size: const Size(400, 1400));
    final row = find.byKey(const ValueKey('entry-qobuz'));
    final chevron = find.descendant(
      of: row,
      matching: find.byIcon(Icons.chevron_right),
    );
    final install = find.byKey(const ValueKey('plugin-install-qobuz'));
    // The highlight takes in the whole row: the tile, Install and the
    // chevron.
    final ink = tester.getRect(
      find.ancestor(of: chevron, matching: find.byType(InkWell)).first,
    );
    expect(ink.left, tester.getRect(row).left);
    expect(ink.right, tester.getRect(row).right);
    expect(ink.contains(tester.getRect(install).center), isTrue);
    // The chevron opens About, like the rest of the row.
    await tester.tap(chevron);
    await tester.pumpAndSettle();
    expect(find.byType(PluginAboutScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    // Install installs, and opens nothing.
    await tester.tap(install);
    await tester.pumpAndSettle();
    expect(api.runs, [('qobuz', PluginOperation.install)]);
    expect(find.byType(PluginAboutScreen), findsNothing);
    // Its own button, within the row's.
    expect(
      tester.getSemantics(install),
      isSemantics(isButton: true, label: 'Add'),
    );
    await tester.pump(const Duration(seconds: 10));
    expect(tester.takeException(), isNull);
  });

  testWidgets('pulling the list down rereads the catalog', (tester) async {
    final api = _CatalogApi(_catalog());
    final container = await _container(
      _Proxy({'enabled': true, 'catalog_browsing': true}),
      api,
    );
    await _screen(tester, container);
    expect(find.byKey(const ValueKey('catalog-reload')), findsNothing);
    await tester.fling(
      find.byKey(const ValueKey('catalog-scroll')),
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();
    expect(api.reads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a catalog the server cannot read offers Try again', (
    tester,
  ) async {
    final api = _CatalogApi(_catalog())
      ..failure = const PluginCatalogException('The feed is down.');
    final container = await _container(
      _Proxy({'enabled': true, 'catalog_browsing': true}),
      api,
    );
    await _screen(tester, container);
    expect(find.text('The feed is down.'), findsOneWidget);
    api.failure = null;
    await tester.tap(find.byKey(const ValueKey('catalog-retry')));
    await tester.pumpAndSettle();
    expect(api.reads, 2);
    expect(find.text('The feed is down.'), findsNothing);
    expect(find.byKey(const ValueKey('plugin-jamendo')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'title bar shows Configuration, the streamer and its connection',
    (tester) async {
      final container = await _container(
        _Proxy({'enabled': true, 'catalog_browsing': true}),
        _CatalogApi(_catalog()),
        name: 'Living room',
      );
      await _screen(tester, container);
      expect(find.byIcon(Icons.more_vert), findsNothing);
      expect(find.byTooltip('Catalog options'), findsNothing);
      final back = tester.widget<Icon>(find.byIcon(Icons.arrow_back));
      expect(back.size, 22);
      expect(back.color, KalinkaColors.textPrimary);
      expect(
        tester.getSize(find.byKey(const ValueKey('settings-back'))),
        const Size(48, 48),
      );
      // A quiet sans-serif title above the uppercase tab navigation.
      final bar = find.byType(SettingsTopBar);
      final title = tester.widget<Text>(
        find.descendant(of: bar, matching: find.text('Configuration')),
      );
      expect(title.style!.fontFamily, KalinkaFonts.sansFamily);
      expect(title.style!.fontSize, greaterThan(13));
      expect(find.byType(BreadcrumbCrumb), findsNothing);
      expect(
        find.descendant(of: bar, matching: find.text('Living room')),
        findsNothing,
      );
      expect(
        tester.getSize(
          find.byKey(const ValueKey('settings-connection-status')),
        ),
        const Size(8, 8),
      );
      expect(find.byKey(const ValueKey('catalog-description')), findsNothing);
      expect(find.byType(PageBanner), findsNothing);
      expect(find.text('Music sources'), findsNothing);
      expect(find.text('Configuration'), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const ValueKey('catalog-tabs'))).top,
        tester.getRect(bar).bottom,
      );
      expect(
        tester.getRect(find.text('MORE SOURCES · 5')).top -
            tester.getRect(find.byKey(const ValueKey('catalog-tabs'))).bottom,
        24,
      );
      expect(find.byKey(const ValueKey('catalog-art')), findsNothing);
      for (final (status, color, label) in [
        (
          ConnectionStatus.connected,
          KalinkaColors.statusOnline,
          'Server online',
        ),
        (
          ConnectionStatus.reconnecting,
          KalinkaColors.statusPending,
          'Reconnecting',
        ),
        (
          ConnectionStatus.offline,
          KalinkaColors.statusOffline,
          'Server offline',
        ),
        (
          ConnectionStatus.connecting,
          KalinkaColors.statusPending,
          'Connecting',
        ),
        (ConnectionStatus.none, KalinkaColors.textMuted, 'Not connected'),
        (
          ConnectionStatus.connected,
          KalinkaColors.statusOnline,
          'Server online',
        ),
      ]) {
        (container.read(connectionStateProvider.notifier) as _Connected)
            .setStatus(status);
        // Reconnecting deliberately has a continuously pulsing banner.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final dot = tester.widget<DecoratedBox>(
          find.byKey(const ValueKey('settings-connection-status')),
        );
        expect((dot.decoration as BoxDecoration).color, color);
        expect(find.byTooltip(label), findsOneWidget);
        expect(find.bySemanticsLabel('Living room, $label'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );

  for (final (size, appWidth, scale) in [
    (const Size(390, 730), 390.0, 1.0),
    (const Size(483, 619), 1024.0, 1.0),
    (const Size(320, 640), 320.0, 1.8),
    (const Size(483, 619), 1024.0, 1.8),
  ]) {
    testWidgets(
      'description scrolls away under a fixed title bar and pinned tabs at $size, '
      'text scale $scale',
      (tester) async {
        final catalog = PluginCatalog(
          status: 'available',
          plugins: [
            ..._catalog().plugins,
            // Enough controls to exercise scrolling even on the wider panel.
            for (var i = 0; i < 4; i++)
              CatalogPlugin.fromJson({
                'id': 'amplifier_$i',
                'name': 'Amplifier $i',
                'description': 'Control a compatible amplifier.',
                'type': 'output_device',
                'tier': 'official',
                'maturity': 'stable',
                'delivery': 'bundle',
              }),
          ],
        );
        final container = await _container(
          _Proxy({
            'enabled': true,
            'catalog_browsing': true,
            'update_checks': true,
          }),
          _CatalogApi(catalog)
            ..available = const [
              PluginUpdate(pluginId: 'spotify', version: '0.4.0'),
            ],
          live: _Live(
            ModulesAndDevices(inputModules: [_module('spotify')], devices: []),
          ),
          name: 'A streamer with a long name',
        );
        await _screen(
          tester,
          container,
          size: size,
          appWidth: appWidth,
          scale: scale,
          disableAnimations: scale > 1,
        );
        expect(find.byKey(const ValueKey('catalog-description')), findsNothing);
        await _tapTab(tester, PluginTab.devices);
        final description = find.byKey(const ValueKey('catalog-description'));
        final tabs = find.byKey(const ValueKey('catalog-tabs'));
        final viewport = tester.getRect(
          find.byKey(const ValueKey('catalog-scroll')),
        );
        final bar = tester.getRect(find.byType(SettingsTopBar));
        final scroll = tester
            .widget<CustomScrollView>(
              find.byKey(const ValueKey('catalog-scroll')),
            )
            .controller!;
        expect(bar.bottom, viewport.top);
        expect(tester.getRect(tabs).top, viewport.top);
        expect(tester.getRect(description).top, tester.getRect(tabs).bottom);
        expect(find.byType(PageBanner), findsNothing);
        final descriptionText = tester.widget<Text>(
          find.descendant(of: description, matching: find.byType(Text)),
        );
        expect(descriptionText.maxLines, isNull);
        expect(descriptionText.softWrap, isTrue);
        expect(descriptionText.overflow, TextOverflow.clip);
        expect(
          tester.getSize(description).width,
          lessThanOrEqualTo(size.width),
        );
        final resting = tester.getRect(tabs);
        final tabScroll = find.descendant(
          of: tabs,
          matching: find.byType(SingleChildScrollView),
        );
        expect(tabScroll, findsNothing);
        final hifi = tester.getRect(
          find.byKey(const ValueKey('catalog-tab-devices')),
        );
        final streamer = tester.getRect(
          find.byKey(const ValueKey('catalog-tab-server')),
        );
        final sources = tester.getRect(
          find.byKey(const ValueKey('catalog-tab-sources')),
        );
        // The content's inset: wider from the tablet breakpoint.
        final inset = appWidth < 900 ? 20.0 : 25.0;
        expect(sources.left, closeTo(resting.left + inset, 0.1));
        expect(streamer.right, lessThanOrEqualTo(resting.right - inset + 0.1));
        expect(sources.right, lessThan(hifi.left));
        expect(hifi.right, lessThan(streamer.left));
        expect(hifi.width / 12, closeTo(streamer.width / 8, 0.1));
        expect(sources.width / 13, closeTo(streamer.width / 8, 0.1));
        for (final (tab, name) in [
          (PluginTab.sources, 'Music sources'),
          (PluginTab.devices, 'HiFi control'),
          (PluginTab.server, 'Streamer'),
        ]) {
          final button = find.byKey(ValueKey('catalog-tab-${tab.name}'));
          final bounds = tester.getRect(button);
          expect(bounds.left, greaterThanOrEqualTo(resting.left));
          expect(bounds.right, lessThanOrEqualTo(resting.right));
          expect(button.hitTestable(), findsOneWidget);
          expect(find.byTooltip(name), findsOneWidget);
          final label = tester.widget<Text>(
            find.descendant(
              of: button,
              matching: find.text(name.toUpperCase()),
            ),
          );
          expect(label.maxLines, 1);
          expect(label.overflow, TextOverflow.ellipsis);
          expect(tester.getSemantics(button), isSemantics(label: name));
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(tester.getSemantics(button), isSemantics(isSelected: true));
          expect(tester.takeException(), isNull);
        }
        await tester.tap(find.byKey(const ValueKey('catalog-tab-devices')));
        await tester.pumpAndSettle();
        for (var pass = 0; pass < 2; pass++) {
          scroll.jumpTo(tester.getSize(description).height + 200);
          await tester.pumpAndSettle();
          expect(description.hitTestable(), findsNothing);
          expect(tester.getRect(tabs).top, viewport.top);
          expect(tester.getRect(find.byType(SettingsTopBar)), bar);
          for (final key in ['settings-back', 'catalog-tab-sources']) {
            expect(find.byKey(ValueKey(key)).hitTestable(), findsOneWidget);
          }
          expect(find.byTooltip('Server online').hitTestable(), findsOneWidget);
          scroll.jumpTo(0);
          await tester.pumpAndSettle();
          expect(tester.getRect(tabs), resting);
          expect(find.byKey(const ValueKey('catalog-art')), findsNothing);
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

  test('staged settings never enable the feature; a saved flag refreshes capabilities', () async {
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
  });

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
    'a row opens a page rather than unfolding, and nothing installs from a URL',
    (tester) async {
      final api = _CatalogApi(_catalog());
      final container = await _container(
        _Proxy({'enabled': true, 'catalog_browsing': true}),
        api,
        live: _Live(
          ModulesAndDevices(inputModules: [_module('localfiles')], devices: []),
        ),
        settings: _settingsWith({'localfiles': true}),
      );
      await _screen(tester, container);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
      expect(find.text('Manage folders'), findsNothing);
      expect(find.text('Configuration'), findsWidgets);
      expect(find.text('Browse other plugins'), findsNothing);
      await _open(tester, 'localfiles');
      expect(find.byType(PluginSettingsScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await _open(tester, 'qobuz');
      expect(find.byType(PluginAboutScreen), findsOneWidget);
      expect(find.byType(PluginSettingsScreen), findsNothing);
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
    expect(find.byType(PluginRow), findsNothing);
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
    expect(find.byType(PluginRow), findsNothing);
    // The new streamer's name, at once.
    expect(
      find.descendant(
        of: find.byType(SettingsTopBar),
        matching: find.text('Other server'),
      ),
      findsNothing,
    );
    expect(other.reads, 1);
    expect(api.reads, 1);
    expect(tester.takeException(), isNull);
  });

  for (final bottomInset in [0.0, 34.0]) {
    testWidgets(
      'Configuration pages leave the mini-player usable with inset $bottomInset',
      (tester) async {
        final container = await _container(
          _Proxy({'enabled': true, 'catalog_browsing': true}),
          _CatalogApi(_catalog()),
          player: true,
          settings: _serverSettings(),
          live: _Live(
            ModulesAndDevices(
              inputModules: [_module('localfiles')],
              devices: [],
            ),
          ),
        );
        await tester.binding.setSurfaceSize(const Size(480, 850));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: MediaQuery(
                data: MediaQueryData(
                  size: const Size(480, 850),
                  padding: EdgeInsets.only(top: 24, bottom: bottomInset),
                  viewPadding: EdgeInsets.only(top: 24, bottom: bottomInset),
                ),
                child: const MusicPlayerScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final miniPlayer = find.byType(MiniPlayer);
        final playerRect = tester.getRect(miniPlayer);
        final playerState = tester.state(miniPlayer);
        expect(playerRect.bottom, 850);

        void expectAbovePlayer(Finder page) {
          expect(tester.getRect(page).bottom, playerRect.top);
          expect(tester.getRect(miniPlayer), playerRect);
          expect(tester.state(miniPlayer), same(playerState));
          expect(miniPlayer.hitTestable(), findsOneWidget);
          expect(MediaQuery.of(tester.element(page)).padding.bottom, 0);
          expect(tester.takeException(), isNull);
        }

        await tester.tap(find.byType(ServerChip));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Configuration'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 160));
        expectAbovePlayer(find.byType(PluginCatalogScreen));
        await tester.pumpAndSettle();
        expectAbovePlayer(find.byType(PluginCatalogScreen));

        await _open(tester, 'localfiles');
        expectAbovePlayer(find.byType(PluginSettingsScreen));
        container
            .read(settingsProvider.notifier)
            .stageChange('input_modules.localfiles.region', 'gb');
        await tester.pumpAndSettle();
        final changes = _changesBar;
        final footerRect = tester.getRect(changes);
        expect(footerRect.bottom, playerRect.top);
        expect(
          tester.getRect(find.byType(PluginSettingsScreen)).bottom,
          footerRect.top,
        );
        await _about(tester, 'localfiles');
        expect(changes, findsOneWidget);
        expect(
          tester.getRect(find.byType(PluginAboutScreen)).bottom,
          footerRect.top,
        );
        expect(tester.getRect(miniPlayer), playerRect);
        await tester.tap(find.byKey(const ValueKey('pending-changes-discard')));
        await tester.pumpAndSettle();
        expect(container.read(settingsProvider).hasPendingChanges, isFalse);
        expectAbovePlayer(find.byType(PluginAboutScreen));

        // Playback can be opened without losing the current configuration page.
        await tester.tap(miniPlayer);
        await tester.pumpAndSettle();
        expect(find.byType(NowPlayingContent), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(NowPlayingContent), findsNothing);
        expectAbovePlayer(find.byType(PluginAboutScreen));
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        await _tapTab(tester, PluginTab.server);
        for (final label in ['Download server logs']) {
          final row = find.text(label);
          await tester.ensureVisible(row);
          await tester.pumpAndSettle();
          await tester.tap(row);
          await tester.pumpAndSettle();
          expectAbovePlayer(find.byType(LogExportScreen));
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(find.byType(ServerSettingsBody), findsOneWidget);
        }

        container
            .read(rendererSettingsRouteProvider.notifier)
            .open('living-room', 'Living Room');
        await tester.pumpAndSettle();
        expectAbovePlayer(find.byType(RendererSettingsScreen));
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expectAbovePlayer(find.byType(PluginCatalogScreen));
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(PluginCatalogScreen), findsNothing);
        expect(tester.getRect(miniPlayer), playerRect);
        expect(miniPlayer.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'player catalog keeps an open page across resize and Back closes it first',
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
      await tester.tap(find.text('Configuration').hitTestable());
      await tester.pumpAndSettle();
      await _open(tester, 'jamendo');
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
        expect(find.byType(PluginAboutScreen), findsOneWidget);
        if (size.width == 400) {
          final miniPlayer = find.byType(MiniPlayer);
          expect(miniPlayer.hitTestable(), findsOneWidget);
          expect(
            tester.getRect(find.byType(PluginAboutScreen)).bottom,
            tester.getRect(miniPlayer).top,
          );
        }
        expect(tester.takeException(), isNull);
      }
      expect(api.reads, 1);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(PluginAboutScreen), findsNothing);
      expect(find.byType(PluginCatalogScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(PluginCatalogScreen), findsNothing);
      expect(find.byType(MusicPlayerScreen), findsOneWidget);
      // The Settings-style arrow must dismiss the same panel as system Back.
      await tester.tap(find.byType(ServerChip));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Configuration').hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-back')));
      await tester.pumpAndSettle();
      expect(find.byType(PluginCatalogScreen), findsNothing);
      expect(find.byType(MusicPlayerScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('device control lists device plugins with their model scope', (
    tester,
  ) async {
    final container = await _container(
      _Proxy({'enabled': true, 'catalog_browsing': true}),
      _CatalogApi(_catalog()),
    );
    await _screen(tester, container);
    await _tapTab(tester, PluginTab.devices);
    expect(find.byKey(const ValueKey('plugin-jamendo')), findsNothing);
    expect(find.byKey(const ValueKey('plugin-musiccast')), findsOneWidget);
    expect(find.byKey(const ValueKey('plugin-dummydevice')), findsOneWidget);
    await _about(tester, 'musiccast');
    expect(find.text('Supported models'), findsOneWidget);
    expect(find.text('Supported families'), findsOneWidget);
    expect(find.text('Controls and limitations'), findsOneWidget);
    expect(
      find.text('Yamaha MusicCast / Yamaha Extended Control'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 640), const Size(640, 800)]) {
    testWidgets('narrow and tablet panes handle large text at $size', (
      tester,
    ) async {
      final container = await _container(
        _Proxy({'enabled': true, 'catalog_browsing': true}),
        _CatalogApi(_catalog()),
        live: _Live(
          ModulesAndDevices(
            inputModules: [
              _module('localfiles', summary: '2 folders connected'),
              _module('upnp'),
            ],
            devices: [],
          ),
        ),
        settings: _settingsWith({'localfiles': true, 'upnp': true}),
        name: 'Living room',
      );
      await _screen(tester, container, size: size, scale: 1.8);
      // Chevrons line up at the edge; Install stays on screen and easy to
      // hit.
      final chevrons = <Rect>[];
      for (final id in ['localfiles', 'upnp', 'qobuz']) {
        final chevron = find.descendant(
          of: find.byKey(ValueKey('entry-$id')),
          matching: find.byIcon(Icons.chevron_right),
        );
        await tester.scrollUntilVisible(chevron, 150, scrollable: _scrollable);
        await tester.pumpAndSettle();
        chevrons.add(tester.getRect(chevron));
      }
      expect(chevrons[0].right, chevrons[1].right);
      expect(chevrons[0].right, chevrons[2].right);
      expect(chevrons[0].right, lessThanOrEqualTo(size.width));
      final install = find.byKey(const ValueKey('plugin-install-qobuz'));
      await tester.scrollUntilVisible(install, 150, scrollable: _scrollable);
      await tester.pumpAndSettle();
      expect(tester.getRect(install).right, lessThanOrEqualTo(size.width));
      expect(tester.getSize(install).height, greaterThanOrEqualTo(40));
      await _open(tester, 'localfiles');
      expect(find.byType(PluginSettingsScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await _about(tester, 'jamendo');
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

  for (final (status, heading, detail) in [
    (
      'metadata_compatible',
      'Requirements met',
      'Version 5.0.1 (stable) matches this server.',
    ),
    ('blocked', 'Requirements not met', 'SDK 1.0 does not meet >=2.'),
    (
      'unknown_future_status',
      'Requirements not checked',
      'has not reported a compatibility check',
    ),
    (
      'missing',
      'Requirements not checked',
      'has not reported a compatibility check',
    ),
  ]) {
    testWidgets(
      'shows server compatibility $status without install permission',
      (tester) async {
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
        await _screen(
          tester,
          container,
          size: const Size(320, 640),
          scale: 1.8,
        );
        await _about(tester, 'qobuz');
        final details = find.byKey(
          const ValueKey('plugin-details-qobuz'),
          skipOffstage: false,
        );
        // Long descriptions remain fully readable at large text sizes; the
        // requirements follow them in the same scroll.
        await tester.scrollUntilVisible(
          details,
          160,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('plugin-page-about')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
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
        expect(text, contains(detail));
        // Said once, at the top, with its reasons; nothing below repeats it,
        // and each release states what it requires as a plain fact.
        expect('\n$text\n'.split('\n$heading\n'), hasLength(2));
        for (final repeat in [
          'Server check',
          'Declared requirements',
          'No release meets',
          'Compatibility with this server has not been checked',
        ]) {
          expect(text, isNot(contains(repeat)));
        }
        expect(
          text,
          contains('Server >=5.2,<6 · SDK >=3.4,<4 · Python >=3.10'),
        );
        final qobuz = api.result.plugins.singleWhere((p) => p.id == 'qobuz');
        expect(
          tester.getRect(find.text(heading, skipOffstage: false)).top,
          greaterThan(
            tester
                .getRect(find.text(qobuz.description, skipOffstage: false))
                .bottom,
          ),
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
        expect(text, contains('Catalog signatures are not verified'));
        expect(
          text,
          contains(
            'Package dependencies and actual device support have not been checked',
          ),
        );
        for (final key in ['plugin-install-qobuz', 'about-install-qobuz']) {
          final install = tester.widget<KalinkaButton>(
            find.byKey(ValueKey(key), skipOffstage: false),
          );
          expect(install.label, 'Add');
          expect(install.enabled, isFalse);
        }
        expect(
          text,
          contains('This server cannot install, remove or update plugins yet.'),
        );
        expect(api.runs, isEmpty);
        expect(api.reads, 1);
        expect(tester.takeException(), isNull);
      },
    );
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
    await _about(tester, 'qobuz');
    // Both in the one banner, the match and what it leaves out.
    final banner = find.textContaining(
      'Version 5.0.1 (stable) matches this server.',
      skipOffstage: false,
    );
    expect(banner, findsOneWidget);
    expect(tester.widget<Text>(banner).data, contains('Version 6.0 does not.'));
  });

  testWidgets(
    'an installed row opens its page: the switch, About and upkeep at the top',
    (tester) async {
      final container = await _container(
        _Proxy({'enabled': true, 'catalog_browsing': true}),
        _CatalogApi(_catalog()),
        live: _Live(
          ModulesAndDevices(
            inputModules: [
              _module('jamendo', enabled: false, state: 'disabled'),
              _module('spotify'),
            ],
            devices: [],
          ),
        ),
        settings: _settingsWith({'jamendo': false, 'spotify': true}),
      );
      await _screen(tester, container, size: const Size(483, 619));
      // Nothing on the overview acts on an installed plugin.
      for (final key in [
        'plugin-enabled-jamendo',
        'plugin-about-jamendo',
        'plugin-uninstall-spotify',
        'plugin-settings-jamendo',
      ]) {
        expect(find.byKey(ValueKey(key)), findsNothing);
      }
      expect(find.text('Configuration'), findsWidgets);

      await _open(tester, 'jamendo');
      final page = find.byType(PluginSettingsScreen);
      expect(page, findsOneWidget);
      expect(
        _onPage<PluginSettingsScreen>(
          find.byKey(const ValueKey('plugin-enabled-jamendo')),
        ),
        findsOneWidget,
      );
      // Bundled with the server, so nothing to uninstall; and what the
      // catalog says waits behind About.
      expect(
        find.byKey(const ValueKey('plugin-uninstall-jamendo')),
        findsNothing,
      );
      expect(find.text('Created by'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await _open(tester, 'spotify');
      final about = find.byKey(const ValueKey('plugin-about-spotify'));
      expect(
        find.descendant(of: about, matching: find.byIcon(Icons.info_outline)),
        findsOneWidget,
      );
      expect(find.byTooltip('About Spotify Connect'), findsOneWidget);
      expect(tester.getSize(about), const Size(48, 48));
      // At the top right, level with the title, never beside Uninstall.
      final title = tester.getRect(
        _onPage<PluginSettingsScreen>(
          find.descendant(
            of: find.byType(SettingsTopBar),
            matching: find.text('Spotify Connect settings'),
          ),
        ),
      );
      final aboutRect = tester.getRect(about);
      expect(aboutRect.top, lessThan(title.bottom));
      expect(aboutRect.right, 483 - 16 - 8 - 12);
      final uninstall = tester.getRect(
        find.byKey(const ValueKey('plugin-uninstall-spotify')),
      );
      expect(uninstall.top, greaterThan(aboutRect.bottom));
      expect(
        tester
            .widget<KalinkaButton>(
              find.byKey(const ValueKey('plugin-uninstall-spotify')),
            )
            .variant,
        KalinkaButtonVariant.neutral,
      );
      expect(find.text('About'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  // Each is offered only on its side of the server's catalog opt-in.
  for (final (label, panelType, catalog) in [
    ('Server settings', SettingsScreen, false),
    ('Configuration', PluginCatalogScreen, true),
  ]) {
    testWidgets(
      '$label covers only the tablet content pane and preserves state across resize',
      (tester) async {
        final container = await _container(
          _Proxy({'enabled': catalog, 'catalog_browsing': true}),
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
        final queue = tester.getRect(find.byType(SearchSessionView));
        final nowPlaying = tester.getRect(find.byType(NowPlayingContent));
        await tester.tap(find.byType(ServerChip));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(ServerSheet),
            matching: find.text(label),
          ),
        );
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
        expect(panelRect.right, lessThan(nowPlaying.left));
        expect(tester.getRect(find.byType(NowPlayingContent)), nowPlaying);
        expect(
          find.byType(RendererSwitcherDropdown).hitTestable(),
          findsOneWidget,
        );
        expect(find.byType(ServerChip).hitTestable(), findsNothing);
        final anchor = SheetAnchor.elementOf(tester.element(panel));
        expect(SheetAnchor.paddingFor(anchor, 1280).left, panelRect.left);
        expect(
          SheetAnchor.paddingFor(anchor, 1280).right,
          1280 - panelRect.right,
        );

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
          expect(rect.right, size.width == 400 ? size.width : queue.right);
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
        if (panelType == PluginCatalogScreen) {
          await tester.tap(find.byKey(const ValueKey('configuration-discard')));
          await tester.pumpAndSettle();
        }
        expect(panel, findsNothing);
        expect(find.byType(ServerChip).hitTestable(), findsOneWidget);
        expect(
          find.byType(RendererSwitcherDropdown).hitTestable(),
          findsOneWidget,
        );
        expect(tester.getRect(find.byType(SearchSessionView)), queue);
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
    await _tapTab(tester, PluginTab.devices);
    await _about(tester, 'musiccast');
    final search = find.byKey(const ValueKey('model-search-musiccast'));
    await tester.ensureVisible(search);
    await tester.enterText(search, 'nonexistent model');
    await tester.pumpAndSettle();
    expect(find.text('No catalog match · Not verified'), findsOneWidget);
    expect(find.byType(PluginCatalogScreen), findsOneWidget);
    expect(find.text('Check connected device'), findsNothing);
    // System Back closes only the About page.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(PluginAboutScreen), findsNothing);
    expect(find.byKey(const ValueKey('plugin-musiccast')), findsOneWidget);
    _expectTab(tester, PluginTab.devices);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'phone sheet swaps Server settings for Configuration after opt-in',
    (tester) async {
      final proxy = _Proxy({'enabled': false, 'catalog_browsing': true});
      final container = await _container(
        proxy,
        _CatalogApi(_catalog()),
        settings: const SettingsState(
          values: {pluginCatalogSettingPath: false},
        ),
      );
      final settings = container.read(settingsProvider.notifier) as _Settings;
      ServerSheetAction? action;
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.8)),
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
      expect(find.text('Configuration'), findsNothing);
      expect(find.text('Server settings'), findsOneWidget);
      expect(find.text('Now-playing display'), findsNothing);
      expect(find.text('THIS APP'), findsNothing);
      settings.stageChange(pluginCatalogSettingPath, true);
      await tester.pumpAndSettle();
      expect(find.text('Configuration'), findsNothing);
      expect(find.text('Server settings'), findsOneWidget);
      proxy.capabilities['enabled'] = true;
      await settings.applyChanges();
      await tester.pumpAndSettle();
      expect(find.text('Configuration'), findsWidgets);
      expect(find.text('Server settings'), findsNothing);
      expect(find.text('Now-playing display'), findsNothing);
      expect(find.text('THIS APP'), findsNothing);
      await tester.ensureVisible(find.text('Configuration'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Configuration'));
      await tester.pumpAndSettle();
      expect(action, ServerSheetAction.openPlugins);

      proxy.capabilities['enabled'] = false;
      settings.saved(false);
      await tester.tap(find.text('Open menu'));
      await tester.pumpAndSettle();
      expect(find.text('Configuration'), findsNothing);
      expect(find.text('Server settings'), findsOneWidget);
      await tester.tap(find.text('Server settings'));
      await tester.pumpAndSettle();
      expect(action, ServerSheetAction.openSettings);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tablet sheet closes before opening Configuration', (
    tester,
  ) async {
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
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.8)),
            child: child!,
          ),
          home: Scaffold(
            body: ServerSheet(
              onClose: () => actions.add('close'),
              onOpenSettings: () {},
              onOpenDiscovery: () {},
              onOpenPlugins: () => actions.add('plugins'),
              onPowerOff: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Server settings'), findsNothing);
    await tester.ensureVisible(find.text('Configuration'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Configuration'));
    await tester.pumpAndSettle();
    expect(actions, ['close', 'plugins']);
    expect(tester.takeException(), isNull);
  });

  test(
    'installing and update checks need browsing and their own flags',
    () async {
      for (final (capabilities, installs, checks) in [
        (
          <String, dynamic>{'enabled': true, 'catalog_browsing': true},
          false,
          false,
        ),
        (
          {
            'enabled': true,
            'catalog_browsing': true,
            'installation': true,
            'update_checks': true,
          },
          true,
          true,
        ),
        (
          {
            'enabled': false,
            'catalog_browsing': true,
            'installation': true,
            'update_checks': true,
          },
          false,
          false,
        ),
      ]) {
        final container = await _container(
          _Proxy(capabilities),
          _CatalogApi(_catalog()),
        );
        final subscription = container.listen(serverInfoProvider, (_, _) {});
        await container.read(serverInfoProvider.future);
        expect(container.read(pluginInstallationProvider), installs);
        expect(container.read(pluginUpdateChecksProvider), checks);
        subscription.close();
      }
    },
  );

  testWidgets(
    'each row says how its plugin stands and switched-off ones stay readable',
    (tester) async {
      final container = await _container(
        _Proxy({'enabled': true, 'catalog_browsing': true}),
        _CatalogApi(_catalog()),
        live: _Live(
          ModulesAndDevices(
            inputModules: [
              _module('localfiles'),
              _module('jamendo', enabled: false, state: 'disabled'),
              _module('upnp', state: 'warning'),
              _module('spotify', state: 'error'),
            ],
            devices: [],
          ),
        ),
        settings: _settingsWith({
          'localfiles': true,
          'jamendo': false,
          'upnp': true,
          'spotify': true,
        }),
      );
      await _screen(tester, container, size: const Size(400, 1400));
      // The words and colours of Server settings' cards.
      for (final (id, label, color) in [
        ('localfiles', 'READY', KalinkaColors.statusOnline),
        ('jamendo', 'DISABLED', KalinkaColors.textMuted),
        ('upnp', 'WARNING', KalinkaColors.statusPending),
        ('spotify', 'ERROR', KalinkaColors.statusError),
      ]) {
        expect(_badgeOf(tester, id)!.label, label);
        expect(_badgeOf(tester, id)!.color, color);
      }
      // Ready, with nothing of its own to say.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('plugin-localfiles')),
          matching: find.byKey(const ValueKey('plugin-status')),
        ),
        findsNothing,
      );
      // Not installed says itself in the heading above.
      expect(_badgeOf(tester, 'qobuz'), isNull);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('plugin-qobuz')),
          matching: find.byKey(const ValueKey('plugin-status')),
        ),
        findsNothing,
      );
      expect(_opacitiesOf(tester, 'jamendo'), isEmpty);
      expect(_opacitiesOf(tester, 'localfiles'), isEmpty);
      expect(_opacitiesOf(tester, 'qobuz'), isEmpty);
      expect(find.bySemanticsLabel('Jamendo. Disabled'), findsOneWidget);
      await _open(tester, 'jamendo');
      expect(find.byType(PluginSettingsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a row follows its plugin\'s status as the server reports it', (
    tester,
  ) async {
    final events = StreamController<PlayQueueEvent>.broadcast();
    addTearDown(events.close);
    ModulesAndDevices qobuz(String state) => ModulesAndDevices(
      inputModules: [
        _module('localfiles'),
        _module(
          'qobuz',
          state: state,
          message: state == 'error' ? 'Not paired yet.' : null,
        ),
      ],
      devices: [],
    );
    final container = await _container(
      _Proxy({'enabled': true, 'catalog_browsing': true}),
      _CatalogApi(_catalog()),
      live: _Live(qobuz('error')),
      settings: _settingsWith({'localfiles': true, 'qobuz': true}),
      events: events.stream,
    );
    await _screen(tester, container, size: const Size(400, 1400));
    expect(_badgeOf(tester, 'qobuz')!.label, 'ERROR');

    events.add(PlayQueueEvent.modulesChanged(modules: qobuz('ready'), seq: 2));
    await tester.pumpAndSettle();
    expect(_badgeOf(tester, 'qobuz')!.label, 'READY');
    expect(_badgeOf(tester, 'qobuz')!.color, KalinkaColors.statusOnline);

    events.add(PlayQueueEvent.modulesChanged(modules: qobuz('error'), seq: 3));
    await tester.pumpAndSettle();
    expect(_badgeOf(tester, 'qobuz')!.label, 'ERROR');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the switch on its page stages a plugin on or off for the restart',
    (tester) async {
      final container = await _container(
        _Proxy({'enabled': true, 'catalog_browsing': true}),
        _CatalogApi(_catalog()),
        live: _Live(
          ModulesAndDevices(
            inputModules: [
              _module('localfiles'),
              _module('jamendo', enabled: false, state: 'disabled'),
            ],
            devices: [],
          ),
        ),
        settings: _settingsWith({'localfiles': true, 'jamendo': false}),
      );
      await _screen(tester, container);
      int pending() =>
          tester.widget<PendingChangesBanner>(_changesBar).pendingCount;
      expect(pending(), 0);

      await _open(tester, 'jamendo');
      final toggle = find.byKey(const ValueKey('plugin-enabled-jamendo'));
      expect(tester.getSemantics(toggle), isSemantics(isToggled: false));
      expect(tester.getSize(toggle).height, greaterThanOrEqualTo(48));
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).stagedChanges, {
        'input_modules.jamendo.enabled': true,
      });
      expect(
        _onPage<PluginSettingsScreen>(find.text('Turns on after restart')),
        findsOneWidget,
      );
      final banner = tester.widget<PendingChangesBanner>(_changesBar);
      expect(banner.pendingCount, 1);
      expect(find.text('APPLY'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      // Off as it runs now, on once restarted.
      expect(_badgeOf(tester, 'jamendo')!.label, 'DISABLED');
      expect(_statusOf(tester, 'jamendo'), 'Turns on after restart');
      expect(_opacitiesOf(tester, 'jamendo'), isEmpty);
      expect(pending(), 1);

      await _open(tester, 'jamendo');
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).stagedChanges, isEmpty);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_badgeOf(tester, 'jamendo')!.label, 'DISABLED');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('plugin-jamendo')),
          matching: find.byKey(const ValueKey('plugin-status')),
        ),
        findsNothing,
      );
      expect(pending(), 0);

      // A plugin the server does not have has nothing to switch.
      await _open(tester, 'qobuz');
      expect(find.byType(PluginAboutScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('plugin-enabled-qobuz')), findsNothing);
      expect(
        find.byKey(const ValueKey('plugin-uninstall-qobuz')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an installed row opens its settings with a page title and Back',
    (tester) async {
      final container = await _container(
        _Proxy({'enabled': true, 'catalog_browsing': true}),
        _CatalogApi(_catalog()),
        live: _Live(
          ModulesAndDevices(
            inputModules: [_module('localfiles'), _module('upnp')],
            devices: [],
          ),
        ),
        settings: _settingsWith({'localfiles': true}),
      );
      await _screen(tester, container);

      await _open(tester, 'localfiles');
      final page = find.byType(PluginSettingsScreen);
      expect(find.byType(BreadcrumbCrumb), findsNothing);
      expect(
        tester
            .widget<SettingsTopBar>(
              find.descendant(of: page, matching: find.byType(SettingsTopBar)),
            )
            .title,
        'Folders & NAS settings',
      );
      final title = find.descendant(
        of: find.descendant(of: page, matching: find.byType(SettingsTopBar)),
        matching: find.text('Folders & NAS settings'),
      );
      expect(
        tester.widget<Text>(title).style!.fontFamily,
        KalinkaFonts.sansFamily,
      );
      expect(
        find.descendant(of: page, matching: find.byType(PageBanner)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: page,
          matching: find.text('Folders & NAS settings'),
        ),
        findsOneWidget,
      );
      // The badge its row shows, under the title.
      expect(
        tester
            .widget<ModuleStatusBadge>(
              find.descendant(
                of: page,
                matching: find.byKey(const ValueKey('plugin-badge')),
              ),
            )
            .label,
        'READY',
      );
      // The page's own switch stands in for the schema's.
      expect(find.text('Module enabled'), findsNothing);
      expect(
        find.descendant(of: page, matching: find.text('Store region')),
        findsOneWidget,
      );
      await tester.enterText(
        find.descendant(of: page, matching: find.byType(TextField)),
        'nl',
      );
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).stagedChanges, {
        'input_modules.localfiles.region': 'nl',
      });
      expect(tester.widget<PendingChangesBanner>(_changesBar).pendingCount, 1);

      // The Back button returns to the overview and keeps staged edits.
      await tester.tap(find.byKey(const ValueKey('settings-back')).last);
      await tester.pumpAndSettle();
      expect(find.byType(PluginSettingsScreen), findsNothing);

      // System Back closes only the settings page.
      await _open(tester, 'localfiles');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(PluginSettingsScreen), findsNothing);
      expect(find.byType(PluginCatalogScreen), findsOneWidget);
      expect(container.read(settingsProvider).stagedChanges, {
        'input_modules.localfiles.region': 'nl',
      });

      // UPnP is installed, but the settings schema has nothing for it: its
      // page says so, and has no switch to offer.
      await _open(tester, 'upnp');
      expect(
        find.text('The server lists no other settings for this plugin.'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.byKey(const ValueKey('plugin-enabled-upnp'))),
        isSemantics(isEnabled: false),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'About returns to the plugin settings with both system and button Back',
    (tester) async {
      final container = await _container(
        _Proxy({'enabled': true, 'catalog_browsing': true}),
        _CatalogApi(_catalog()),
        live: _Live(
          ModulesAndDevices(inputModules: [_module('localfiles')], devices: []),
        ),
        settings: _settingsWith({'localfiles': true}),
      );
      await _screen(tester, container);
      await _about(tester, 'localfiles');
      expect(find.byType(BreadcrumbCrumb), findsNothing);
      expect(
        tester.widget<SettingsTopBar>(find.byType(SettingsTopBar).last).title,
        'About Folders & NAS',
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(PluginAboutScreen), findsNothing);
      expect(find.byType(PluginSettingsScreen), findsOneWidget);

      await _about(tester, 'localfiles');
      await tester.tap(
        find.descendant(
          of: find.byType(PluginAboutScreen),
          matching: find.byKey(const ValueKey('settings-back')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PluginAboutScreen), findsNothing);
      expect(find.byType(PluginSettingsScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('settings-back')).last);
      await tester.pumpAndSettle();
      expect(find.byType(PluginSettingsScreen), findsNothing);
      expect(find.byType(PluginCatalogScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Install and Uninstall run on a server that manages its plugins',
    (tester) async {
      final api = _CatalogApi(_catalog());
      final live = _Live(
        ModulesAndDevices(
          inputModules: [_module('localfiles'), _module('spotify')],
          devices: [],
        ),
      );
      final container = await _container(
        _Proxy({
          'enabled': true,
          'catalog_browsing': true,
          'installation': true,
        }),
        api,
        live: live,
      );
      await _screen(tester, container);
      List<String> toasts() =>
          container.read(toastProvider).map((t) => t.message).toList();

      // Part of the server install, so nothing to remove on its own.
      await _open(tester, 'localfiles');
      expect(
        find.byKey(const ValueKey('plugin-uninstall-localfiles')),
        findsNothing,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Solid berry, at the row's right edge.
      final install = find.byKey(const ValueKey('plugin-install-qobuz'));
      await tester.scrollUntilVisible(install, 150, scrollable: _scrollable);
      await tester.pumpAndSettle();
      expect(tester.widget<KalinkaButton>(install).enabled, isTrue);
      expect(
        tester.widget<KalinkaButton>(install).variant,
        KalinkaButtonVariant.accent,
      );
      // Before the chevron every row ends in.
      final chevron = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('entry-qobuz')),
          matching: find.byIcon(Icons.chevron_right),
        ),
      );
      expect(chevron.right, 400 - 20);
      expect(tester.getRect(install).right, lessThan(chevron.left));
      // About keeps its action beside the status, below the fixed title
      // and above what the catalog says.
      await _about(tester, 'qobuz');
      final top = tester.getRect(
        find.byKey(const ValueKey('about-install-qobuz')),
      );
      final title = tester.getRect(
        find.descendant(
          of: find.descendant(
            of: find.byType(PluginAboutScreen),
            matching: find.byType(SettingsTopBar),
          ),
          matching: find.text('About Qobuz'),
        ),
      );
      expect(top.right, 400 - 20);
      expect(top.top, greaterThan(title.bottom));
      expect(top.bottom, lessThan(tester.getRect(find.text('Created by')).top));
      // No second Install at the foot.
      expect(find.text('Add'), findsNWidgets(2));
      await tester.tap(find.byKey(const ValueKey('settings-back')).last);
      await tester.pumpAndSettle();

      api.running = Completer<void>();
      await tester.tap(install);
      await tester.pump();
      expect(api.runs, [('qobuz', PluginOperation.install)]);
      // Busy, not dimmed, and deaf to a second tap.
      expect(tester.widget<KalinkaButton>(install).label, 'Adding…');
      expect(tester.widget<KalinkaButton>(install).onTap, isNull);
      expect(tester.widget<KalinkaButton>(install).leading, isNotNull);
      expect(_badgeOf(tester, 'qobuz')!.label, 'INSTALLING');
      live.value = ModulesAndDevices(
        inputModules: [..._liveInputs(live), _module('qobuz')],
        devices: [],
      );
      api.running!.complete();
      api.running = null;
      await tester.pumpAndSettle();
      expect(toasts(), contains('Qobuz installed'));
      // Moved up among the installed, opening its configuration.
      expect(install, findsNothing);
      expect(
        _listed(tester).indexOf('qobuz'),
        lessThan(_listed(tester).indexOf('jamendo')),
      );
      expect(_badgeOf(tester, 'qobuz')!.label, 'READY');
      await _open(tester, 'qobuz');
      expect(find.byType(PluginSettingsScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Uninstall is grey, on the plugin's page, and asks first.
      await _open(tester, 'spotify');
      final uninstall = find.byKey(const ValueKey('plugin-uninstall-spotify'));
      expect(
        tester.widget<KalinkaButton>(uninstall).variant,
        KalinkaButtonVariant.neutral,
      );
      await tester.tap(uninstall);
      await tester.pumpAndSettle();
      expect(find.text('Uninstall Spotify Connect?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(api.runs, hasLength(1));

      Future<void> confirmUninstall() async {
        await tester.tap(uninstall);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(KalinkaDialog),
            matching: find.text('Uninstall'),
          ),
        );
        await tester.pumpAndSettle();
      }

      api.refusal = 'Spotify Connect is playing. Stop playback first.';
      await confirmUninstall();
      expect(api.runs.last, ('spotify', PluginOperation.uninstall));
      // The refusal stays on the plugin's page, in the server's words.
      expect(container.read(toastProvider).where((t) => t.isError), isEmpty);
      final note = _onPage<PluginSettingsScreen>(
        find.byKey(const ValueKey('plugin-failure')),
      );
      expect(
        tester.widget<Text>(note).textSpan!.toPlainText(),
        'Uninstall failed. ${api.refusal}',
      );
      expect(find.byType(PluginSettingsScreen), findsOneWidget);
      // About shows it too, under the Uninstall it carries.
      await _about(tester, 'spotify');
      final failed = _onPage<PluginAboutScreen>(
        find.byKey(const ValueKey('plugin-failure')),
      );
      expect(failed, findsOneWidget);
      final aboutUninstall = find.byKey(
        const ValueKey('about-uninstall-spotify'),
      );
      expect(
        tester.getRect(failed).top,
        greaterThan(tester.getRect(aboutUninstall).bottom),
      );
      expect(
        tester.getRect(failed).bottom,
        lessThan(tester.getRect(find.text('Created by')).top),
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      // Put away by hand.
      await tester.tap(
        _onPage<PluginSettingsScreen>(
          find.byKey(const ValueKey('plugin-failure-dismiss')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('plugin-failure')), findsNothing);

      // Done: its page goes with it, and it waits among the rest.
      api.refusal = null;
      live.value = ModulesAndDevices(
        inputModules: [
          for (final m in _liveInputs(live))
            if (m.name != 'spotify') m,
        ],
        devices: [],
      );
      await confirmUninstall();
      expect(find.byType(PluginSettingsScreen), findsNothing);
      expect(toasts(), contains('Spotify Connect uninstalled'));
      expect(
        find.byKey(const ValueKey('plugin-install-spotify')),
        findsOneWidget,
      );
      // Let the toasts time out.
      await tester.pump(const Duration(seconds: 10));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a failed install stays in its row until put away', (
    tester,
  ) async {
    final api = _CatalogApi(_catalog())
      ..refusal = 'No space left on the server for this package.';
    final container = await _container(
      _Proxy({'enabled': true, 'catalog_browsing': true, 'installation': true}),
      api,
    );
    await _screen(tester, container, size: const Size(400, 1400));
    await tester.tap(find.byKey(const ValueKey('plugin-install-qobuz')));
    await tester.pumpAndSettle();
    final note = find.descendant(
      of: find.byKey(const ValueKey('entry-qobuz')),
      matching: find.byKey(const ValueKey('plugin-failure')),
    );
    expect(
      tester.widget<Text>(note).textSpan!.toPlainText(),
      'Install failed. ${api.refusal}',
    );
    expect(container.read(toastProvider), isEmpty);
    // Never claimed: it stays among those not installed.
    expect(find.byKey(const ValueKey('plugin-install-qobuz')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('plugin-failure-dismiss')));
    await tester.pumpAndSettle();
    expect(note, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'updates head each list, with Update beside the row until it is done',
    (tester) async {
      final api = _CatalogApi(_catalog())
        ..available = const [
          PluginUpdate(pluginId: 'spotify', version: '0.4.0'),
          PluginUpdate(pluginId: 'musiccast', version: '1.1.0'),
          // Not installed here: nothing to update.
          PluginUpdate(pluginId: 'qobuz', version: '6.0.0'),
        ];
      final container = await _container(
        _Proxy({
          'enabled': true,
          'catalog_browsing': true,
          'installation': true,
          'update_checks': true,
        }),
        api,
        live: _Live(
          ModulesAndDevices(
            inputModules: [_module('spotify'), _module('jamendo')],
            devices: [_module('musiccast')],
          ),
        ),
      );
      await _screen(tester, container, size: const Size(900, 1400));
      expect(find.byKey(const ValueKey('catalog-tab-updates')), findsNothing);
      // Listed once, above the plugins already up to date.
      expect(_listed(tester).first, 'spotify');
      expect(find.text('UPDATE AVAILABLE · 1'), findsOneWidget);
      expect(find.bySemanticsLabel('Update available, 1'), findsOneWidget);
      expect(find.text('YOUR SOURCES · 1'), findsOneWidget);
      expect(
        tester.getRect(find.text('UPDATE AVAILABLE · 1')).bottom,
        lessThan(
          tester.getRect(find.byKey(const ValueKey('entry-spotify'))).top,
        ),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('entry-spotify'))).bottom,
        lessThan(tester.getRect(find.text('YOUR SOURCES · 1')).top),
      );
      expect(_statusOf(tester, 'spotify'), 'Update available · 0.4.0');
      final update = find.byKey(const ValueKey('plugin-row-update-spotify'));
      expect(tester.widget<KalinkaButton>(update).label, 'Update');
      // Before the chevron, as Add is.
      final row = find.byKey(const ValueKey('entry-spotify'));
      expect(
        tester.getRect(update).right,
        lessThan(
          tester
              .getRect(
                find.descendant(
                  of: row,
                  matching: find.byKey(const ValueKey('plugin-chevron')),
                ),
              )
              .left,
        ),
      );
      expect(
        find.byKey(const ValueKey('plugin-row-update-jamendo')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('plugin-install-qobuz')),
        findsOneWidget,
      );

      api.running = Completer<void>();
      api.available = const [
        PluginUpdate(pluginId: 'musiccast', version: '1.1.0'),
      ];
      await tester.tap(update);
      await tester.pump();
      expect(api.runs, [('spotify', PluginOperation.update)]);
      final busy = tester.widget<KalinkaButton>(update);
      expect(busy.label, 'Updating…');
      expect(busy.onTap, isNull);
      expect(_badgeOf(tester, 'spotify')!.label, 'UPDATING');
      api.running!.complete();
      await tester.pumpAndSettle();
      // Done: back among the others, with nothing to offer.
      expect(update, findsNothing);
      expect(find.textContaining('UPDATE AVAILABLE'), findsNothing);
      expect(find.text('YOUR SOURCES · 2'), findsOneWidget);
      expect(_badgeOf(tester, 'spotify')!.label, 'READY');

      await _tapTab(tester, PluginTab.devices);
      expect(_listed(tester).first, 'musiccast');
      expect(find.text('UPDATE AVAILABLE · 1'), findsOneWidget);
      expect(
        tester
            .widget<KalinkaButton>(
              find.byKey(const ValueKey('plugin-row-update-musiccast')),
            )
            .label,
        'Update',
      );
      // Nothing left to update: the section goes.
      api.available = const [];
      container.invalidate(pluginUpdatesProvider);
      await tester.pumpAndSettle();
      expect(find.textContaining('UPDATE AVAILABLE'), findsNothing);
      expect(find.text('YOUR CONTROLS · 1'), findsOneWidget);
      // Let the toast time out.
      await tester.pump(const Duration(seconds: 10));
      expect(tester.takeException(), isNull);
    },
  );

  for (final (size, scale) in [
    (const Size(900, 1400), 1.0),
    (const Size(320, 900), 1.8),
  ]) {
    testWidgets('the configuration page offers a short Update before Uninstall '
        'at ${size.width.round()} px, ${scale}x text', (tester) async {
      final api = _CatalogApi(_catalog())
        ..available = const [
          PluginUpdate(pluginId: 'spotify', version: '0.4.0'),
        ];
      final container = await _container(
        _Proxy({
          'enabled': true,
          'catalog_browsing': true,
          'installation': true,
          'update_checks': true,
        }),
        api,
        live: _Live(
          ModulesAndDevices(inputModules: [_module('spotify')], devices: []),
        ),
      );
      await _screen(
        tester,
        container,
        size: size,
        scale: scale,
        disableAnimations: scale > 1,
      );
      // By its name: on a narrow phone the row's own Update sits mid-row.
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('entry-spotify')),
          matching: find.text('Spotify Connect'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PluginSettingsScreen), findsOneWidget);
      final update = find.byKey(const ValueKey('plugin-update-spotify'));
      await tester.scrollUntilVisible(
        update,
        100,
        scrollable: _onPage<PluginSettingsScreen>(find.byType(Scrollable))
            .first,
      );
      await tester.pumpAndSettle();
      final button = tester.widget<KalinkaButton>(update);
      expect(button.label, 'Update');
      expect(button.size, KalinkaButtonSize.compact);
      expect(button.fullWidth, isFalse);
      final updateRect = tester.getRect(update);
      final uninstall = tester.getRect(
        find.byKey(const ValueKey('plugin-uninstall-spotify')),
      );
      if (scale == 1) {
        // Side by side, Update first.
        expect(updateRect.right, lessThan(uninstall.left));
        expect(updateRect.center.dy, closeTo(uninstall.center.dy, 0.5));
      } else {
        expect(updateRect.top, lessThanOrEqualTo(uninstall.top));
      }
      expect(updateRect.right, lessThanOrEqualTo(size.width));
      expect(uninstall.right, lessThanOrEqualTo(size.width));

      api.running = Completer<void>();
      await tester.tap(update);
      await tester.pump();
      expect(api.runs, [('spotify', PluginOperation.update)]);
      expect(tester.widget<KalinkaButton>(update).label, 'Updating…');
      expect(tester.widget<KalinkaButton>(update).enabled, isFalse);
      api.available = const [];
      api.running!.complete();
      await tester.pumpAndSettle();
      expect(update, findsNothing);
      await tester.pump(const Duration(seconds: 10));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a server that checks but cannot update says so once', (
    tester,
  ) async {
    final api = _CatalogApi(_catalog())
      ..available = const [PluginUpdate(pluginId: 'spotify', version: '0.4.0')];
    final container = await _container(
      _Proxy({
        'enabled': true,
        'catalog_browsing': true,
        'update_checks': true,
      }),
      api,
      live: _Live(
        ModulesAndDevices(inputModules: [_module('spotify')], devices: []),
      ),
    );
    await _screen(tester, container, size: const Size(400, 1400));
    final update = tester.widget<KalinkaButton>(
      find.byKey(const ValueKey('plugin-row-update-spotify')),
    );
    expect(update.enabled, isFalse);
    final note = find.byKey(const ValueKey('catalog-manage-note'));
    expect(note, findsOneWidget);
    expect(
      tester.getRect(note).top,
      greaterThan(tester.getRect(find.text('UPDATE AVAILABLE · 1')).bottom),
    );
    expect(
      tester.getRect(note).bottom,
      lessThan(tester.getRect(find.byKey(const ValueKey('entry-spotify'))).top),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a server without update checks never offers an update', (
    tester,
  ) async {
    final api = _CatalogApi(_catalog())
      ..available = const [PluginUpdate(pluginId: 'spotify', version: '0.4.0')];
    final container = await _container(
      _Proxy({'enabled': true, 'catalog_browsing': true}),
      api,
      live: _Live(
        ModulesAndDevices(inputModules: [_module('spotify')], devices: []),
      ),
    );
    await _screen(tester, container, size: const Size(400, 1400));
    expect(find.textContaining('UPDATE AVAILABLE'), findsNothing);
    expect(
      find.byKey(const ValueKey('plugin-row-update-spotify')),
      findsNothing,
    );
    expect(_badgeOf(tester, 'spotify')!.label, 'READY');
    await _open(tester, 'spotify');
    expect(find.byKey(const ValueKey('plugin-update-spotify')), findsNothing);
    // Uninstall is offered, but out of reach on this server, which says so.
    final uninstall = tester.widget<KalinkaButton>(
      find.byKey(const ValueKey('plugin-uninstall-spotify')),
    );
    expect(uninstall.enabled, isFalse);
    expect(
      find.byTooltip('This server cannot remove plugins yet'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('plugin-manage-note')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a server that cannot install says so once, under More sources', (
    tester,
  ) async {
    final container = await _container(
      _Proxy({'enabled': true, 'catalog_browsing': true}),
      _CatalogApi(_catalog()),
    );
    await _screen(tester, container, size: const Size(400, 1400));
    final note = find.byKey(const ValueKey('catalog-manage-note'));
    expect(note, findsOneWidget);
    expect(
      find.descendant(
        of: note,
        matching: find.text(
          'This server cannot install, remove or update plugins yet.',
        ),
      ),
      findsOneWidget,
    );
    // Under the heading it holds back, not under each plugin.
    expect(
      tester.getRect(note).top,
      greaterThan(tester.getRect(find.textContaining('MORE SOURCES')).bottom),
    );
    expect(
      tester.getRect(note).bottom,
      lessThan(tester.getRect(find.byKey(const ValueKey('entry-jamendo'))).top),
    );
    // Out of reach, and looks it.
    final install = tester.widget<KalinkaButton>(
      find.byKey(const ValueKey('plugin-install-qobuz')),
    );
    expect(install.enabled, isFalse);
    expect(find.textContaining('cannot install or update'), findsNothing);
    // Every device plugin here comes with the server: nothing to say.
    await _tapTab(tester, PluginTab.devices);
    expect(note, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a server that installs says nothing over the list', (
    tester,
  ) async {
    final container = await _container(
      _Proxy({'enabled': true, 'catalog_browsing': true, 'installation': true}),
      _CatalogApi(_catalog()),
    );
    await _screen(tester, container);
    expect(find.byKey(const ValueKey('catalog-manage-note')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'plugin summaries wrap on tiles and full descriptions appear on About',
    (tester) async {
      final container = await _container(
        _Proxy({'enabled': true, 'catalog_browsing': true}),
        _CatalogApi(_catalog()),
      );
      await _screen(tester, container, size: const Size(320, 1400));
      final qobuz = _catalog().plugins.singleWhere((p) => p.id == 'qobuz');
      final short = find.descendant(
        of: find.byKey(const ValueKey('plugin-qobuz')),
        matching: find.text(qobuz.summary!),
      );
      expect(short, findsOneWidget);
      expect(tester.widget<Text>(short).maxLines, isNull);
      expect(tester.widget<Text>(short).softWrap, isTrue);
      expect(
        tester.getSemantics(find.byKey(const ValueKey('plugin-qobuz'))).value,
        qobuz.summary,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('plugin-qobuz')),
          matching: find.text(qobuz.description),
        ),
        findsNothing,
      );
      // HiFi controls use the same catalog summary and description fallback.
      await _tapTab(tester, PluginTab.devices);
      final musiccast = _catalog().plugins.singleWhere(
        (p) => p.id == 'musiccast',
      );
      final deviceSummary = find.descendant(
        of: find.byKey(const ValueKey('plugin-musiccast')),
        matching: find.byKey(const ValueKey('plugin-summary')),
      );
      expect(
        tester.widget<Text>(deviceSummary).data,
        musiccast.blurb('your player'),
      );
      expect(tester.widget<Text>(deviceSummary).maxLines, isNull);
      expect(tester.widget<Text>(deviceSummary).softWrap, isTrue);
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('plugin-musiccast')))
            .value,
        musiccast.blurb('your player'),
      );
      await _tapTab(tester, PluginTab.sources);
      await _about(tester, 'qobuz');
      expect(find.text(qobuz.description), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'an accepted operation follows the server\'s restart and reports what the helper left behind',
    (tester) async {
      final api = _CatalogApi(_catalog())..restarts = true;
      final live = _Live(
        ModulesAndDevices(
          inputModules: [_module('localfiles'), _module('spotify')],
          devices: [],
        ),
      );
      final restart = _Restart();
      final container = await _container(
        _Proxy({
          'enabled': true,
          'catalog_browsing': true,
          'installation': true,
        }),
        api,
        live: live,
        restart: restart,
      );
      await _screen(tester, container);
      List<String> toasts() =>
          container.read(toastProvider).map((t) => t.message).toList();

      final install = find.byKey(const ValueKey('plugin-install-qobuz'));
      await tester.scrollUntilVisible(install, 150, scrollable: _scrollable);
      await tester.pumpAndSettle();
      api.running = Completer<void>();
      await tester.tap(install);
      await tester.pump();
      expect(restart.followed, isEmpty);
      expect(find.byType(RestartOverlay), findsNothing);

      // Accepted: the server restarts, and that shows here as Apply's does,
      // naming the plugin. Nothing is claimed until it is back.
      live.value = ModulesAndDevices(
        inputModules: [..._liveInputs(live), _module('qobuz')],
        devices: [],
      );
      api.running!.complete();
      api.running = null;
      await tester.pump();
      await tester.pump();
      expect(restart.followed, ['Adding Qobuz\u2026']);
      expect(find.byType(RestartOverlay), findsOneWidget);
      expect(find.text('Adding Qobuz\u2026'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(toasts(), contains('Qobuz installed'));
      // The overlay puts itself away a moment after the server is back.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byType(RestartOverlay), findsNothing);
      expect(api.recordReads, 1);
      expect(_badgeOf(tester, 'qobuz')!.label, 'READY');

      // The helper's failure is the plugin's, in the server's words, and
      // nothing is toasted as done.
      api.record = const PluginOperationRecord(
        pluginId: 'spotify',
        operation: PluginOperation.uninstall,
        status: 'failed',
        error: 'apt-get did not complete; see the restart service\'s log.',
      );
      Future<void> confirmUninstall() async {
        await tester.tap(
          find.byKey(const ValueKey('plugin-uninstall-spotify')),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('The server restarts without it'),
          findsOneWidget,
        );
        await tester.tap(
          find.descendant(
            of: find.byType(KalinkaDialog),
            matching: find.text('Uninstall'),
          ),
        );
        // Through the followed restart, which takes a moment, and the overlay
        // putting itself away a moment after; one left showing an error stays
        // until dismissed, spinner and all.
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 3));
        final dismiss = find.descendant(
          of: find.byType(RestartOverlay),
          matching: find.text('Dismiss'),
        );
        if (dismiss.evaluate().isNotEmpty) await tester.tap(dismiss);
        await tester.pumpAndSettle();
      }

      await _open(tester, 'spotify');
      await confirmUninstall();
      expect(restart.followed.last, 'Uninstalling Spotify Connect\u2026');
      expect(toasts(), isNot(contains('Spotify Connect uninstalled')));
      Finder failure() => _onPage<PluginSettingsScreen>(
        find.byKey(const ValueKey('plugin-failure')),
      );
      expect(
        tester.widget<Text>(failure()).textSpan!.toPlainText(),
        'Uninstall failed. ${api.record!.error}',
      );

      // A record about another plugin says nothing about this one, and a
      // wait given up claims nothing either way.
      api.record = const PluginOperationRecord(
        pluginId: 'other',
        status: 'failed',
        error: 'Unrelated.',
      );
      restart.follow = 'abandoned';
      await confirmUninstall();
      expect(toasts(), isNot(contains('Spotify Connect uninstalled')));
      expect(failure(), findsNothing);
      expect(api.recordReads, 2);

      // A server that never came back leaves the outcome unknown, and says so.
      restart.follow = 'error';
      await confirmUninstall();
      expect(
        tester.widget<Text>(failure()).textSpan!.toPlainText(),
        contains('did not come back'),
      );
      expect(api.recordReads, 2);
    },
  );
}

List<ModuleInfo> _liveInputs(_Live live) => live.value.inputModules;
