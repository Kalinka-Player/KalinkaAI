import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/data_model/presentation_schema.dart';
import 'package:kalinka/providers/settings_provider.dart';
import 'package:kalinka/widgets/settings_controls/settings_binding.dart';
import 'package:kalinka/widgets/settings_controls/settings_combo_input.dart';
import 'package:kalinka/widgets/settings_controls/settings_text_input.dart';
import 'package:kalinka/widgets/settings_renderer.dart';

/// One page with a field per widget kind the shared renderer dispatches, so a
/// binding is exercised across the whole control set rather than one row.
const _page = PageSpec(
  id: 'base_config',
  title: 'General',
  sections: [
    SectionSpec(
      id: 'base_config.playback',
      title: 'Playback',
      fields: [
        FieldSpec(
          path: 'base_config.server.service_name',
          label: 'Server name',
          widget: WidgetKind.text,
          type: 'string',
        ),
        FieldSpec(
          path: 'base_config.server.port',
          label: 'Port',
          widget: WidgetKind.numberInput,
          type: 'integer',
        ),
        // An open field the backend may have values to suggest for.
        FieldSpec(
          path: 'base_config.library.root',
          label: 'Library root',
          widget: WidgetKind.path,
          type: 'string',
          dynamicOptions: true,
        ),
        FieldSpec(
          path: 'base_config.server.discoverable',
          label: 'Discoverable',
          widget: WidgetKind.toggle,
          type: 'boolean',
        ),
        FieldSpec(
          path: 'base_config.output.alsa.device',
          label: 'Output device',
          widget: WidgetKind.enumDropdown,
          type: 'string',
        ),
      ],
    ),
  ],
);

/// Minimal in-memory binding — no provider, no network. Proves the schema
/// widgets need nothing but the interface.
class _RecordingBinding implements SettingsBinding {
  _RecordingBinding(this.values, [this.options = const {}]);

  final Map<String, dynamic> values;
  final Map<String, List<OptionSpec>> options;
  final Map<String, dynamic> staged = {};
  final Map<String, List<ConfigIssue>> issues = {};

  @override
  dynamic effectiveValue(String path) =>
      staged.containsKey(path) ? staged[path] : values[path];

  @override
  bool isStaged(String path) => staged.containsKey(path);

  @override
  bool hasHiddenSecret(String path) => false;

  @override
  List<OptionSpec>? optionsFor(String path) => options[path];

  @override
  List<ConfigIssue> issuesFor(String path) => issues[path] ?? const [];

  @override
  void stage(String path, dynamic value) => staged[path] = value;

  @override
  Future<void> refreshOptions() async {}
}

Widget _wrap(SettingsBinding binding) => ProviderScope(
  child: MaterialApp(
    home: Scaffold(
      body: SettingsScope(
        binding: binding,
        child: const SchemaPageRenderer(page: _page),
      ),
    ),
  ),
);

void main() {
  testWidgets('the schema renderer draws a page from any binding', (
    tester,
  ) async {
    final binding = _RecordingBinding(
      {
        'base_config.server.service_name': 'Living Room',
        'base_config.server.port': 8080,
        'base_config.server.discoverable': true,
        'base_config.output.alsa.device': 'hw:CARD=x',
      },
      {
        'base_config.output.alsa.device': [
          OptionSpec(value: 'hw:CARD=x', label: 'HiFiBerry'),
          OptionSpec(value: 'default', label: 'System default'),
        ],
      },
    );

    await tester.pumpWidget(_wrap(binding));
    await tester.pumpAndSettle();

    expect(find.text('PLAYBACK'), findsOneWidget);
    expect(find.text('Server name'), findsOneWidget);
    expect(find.text('Port'), findsOneWidget);
    expect(find.text('Discoverable'), findsOneWidget);
    // Enum dropdowns show the option's *label*, not the stored value.
    expect(find.text('HiFiBerry'), findsOneWidget);
  });

  testWidgets('edits go to the binding, not to any particular provider', (
    tester,
  ) async {
    final binding = _RecordingBinding(
      {
        'base_config.server.service_name': 'Living Room',
        'base_config.server.port': 8080,
        'base_config.server.discoverable': false,
        'base_config.output.alsa.device': 'default',
      },
      {
        'base_config.output.alsa.device': [
          OptionSpec(value: 'default', label: 'System default'),
          OptionSpec(value: 'hw:CARD=x', label: 'HiFiBerry'),
        ],
      },
    );

    await tester.pumpWidget(_wrap(binding));
    await tester.pumpAndSettle();

    await tester.tap(find.text('System default'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HiFiBerry'));
    await tester.pumpAndSettle();

    expect(binding.staged, {'base_config.output.alsa.device': 'hw:CARD=x'});
  });

  testWidgets('ServerSettingsBinding still drives the server settings page', (
    tester,
  ) async {
    // Guards the refactor that moved these widgets off settingsProvider: the
    // server's own page must keep rendering through the shared interface.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(settingsProvider.notifier);
    notifier.stageChange('base_config.server.service_name', 'Renamed');

    final binding = ServerSettingsBinding(
      container.read(settingsProvider),
      notifier,
    );

    expect(
      binding.effectiveValue('base_config.server.service_name'),
      'Renamed',
    );
    expect(binding.isStaged('base_config.server.service_name'), isTrue);
    expect(binding.isStaged('base_config.server.port'), isFalse);

    await tester.pumpWidget(_wrap(binding));
    await tester.pumpAndSettle();

    expect(find.text('Server name'), findsOneWidget);
    // Staged rows carry the amber "Staged" pill.
    expect(find.text('Staged'), findsOneWidget);
  });

  testWidgets('a field that says suggestions exist is drawn as a combo', (
    tester,
  ) async {
    final binding = _RecordingBinding(
      {'base_config.library.root': '/music'},
      {
        'base_config.library.root': [
          OptionSpec(value: '/media/usb0', label: '/media/usb0'),
        ],
      },
    );

    await tester.pumpWidget(_wrap(binding));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsComboInput), findsOneWidget);
    // The plain text field beside it stays plain.
    expect(find.byType(SettingsTextInput), findsNWidgets(2));
  });

  testWidgets('what the binding says is wrong is shown under the field', (
    tester,
  ) async {
    final binding = _RecordingBinding({'base_config.library.root': '/gone'});
    binding.issues['base_config.library.root'] = const [
      ConfigIssue(path: 'base_config.library.root', message: 'no such folder'),
    ];

    await tester.pumpWidget(_wrap(binding));
    await tester.pumpAndSettle();

    expect(find.text('no such folder'), findsOneWidget);
  });
}
