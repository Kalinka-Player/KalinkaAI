// A credential the server holds is shown as set, never as what it is: the
// server does not send it, and the field starts a new value on the first
// edit rather than revealing or appending to one it does not have.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/data_model/presentation_schema.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/settings_provider.dart';
import 'package:kalinka/widgets/onboarding/onboarding_fields.dart';
import 'package:kalinka/widgets/settings_controls/settings_password_input.dart';

const _password = 'input_modules.localfiles.smb.password';
const _token = 'input_modules.qobuz.user_auth_token';

class _Field extends StatefulWidget {
  const _Field({required this.hidden, required this.committed});

  final bool hidden;
  final List<String> committed;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  late bool hidden = widget.hidden;
  String value = '';

  void discard() => setState(() {
    hidden = widget.hidden;
    value = '';
  });

  @override
  Widget build(BuildContext context) => SettingsPasswordInput(
    value: value,
    hidden: hidden,
    onChanged: (v) {
      widget.committed.add(v);
      setState(() {
        hidden = false;
        value = v;
      });
    },
  );
}

Future<List<String>> _pump(WidgetTester tester, {required bool hidden}) async {
  final committed = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: _Field(hidden: hidden, committed: committed),
      ),
    ),
  );
  return committed;
}

TextField _textField(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField));

String _shown(WidgetTester tester) => _textField(tester).controller!.text;

Future<void> _type(WidgetTester tester, String text) async {
  await tester.showKeyboard(find.byType(TextField));
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
}

Future<void> _submit(WidgetTester tester) async {
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump();
}

class _FakeApi implements KalinkaPlayerProxy {
  _FakeApi(this.envelope, this.schema);

  final Map<String, dynamic> envelope;
  final PresentationSchema schema;

  @override
  Future<Map<String, dynamic>> getSettings() async => envelope;

  @override
  Future<PresentationSchema> getSettingsSchema() async => schema;

  @override
  Future<Set<String>?> saveSettings({
    required String schemaVersion,
    required Map<String, dynamic> changes,
  }) async => null;

  @override
  Future<List<ConfigIssue>> validateSettings({
    required String schemaVersion,
    required Map<String, dynamic> changes,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

const _schema = PresentationSchema(
  schemaVersion: 'v1',
  pages: [],
  expertFields: [
    FieldSpec(
      path: _password,
      label: 'SMB password',
      widget: WidgetKind.password,
      type: 'str',
    ),
    FieldSpec(
      path: 'base_config.server.port',
      label: 'Port',
      widget: WidgetKind.numberInput,
      type: 'int',
    ),
  ],
);

Future<SettingsNotifier> _loaded(ProviderContainer container) async {
  final notifier = container.read(settingsProvider.notifier);
  await notifier.loadConfig();
  return notifier;
}

ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [
      kalinkaProxyProvider.overrideWithValue(
        _FakeApi({
          'schema_version': 'v1',
          'values': {'base_config.server.port': 8000},
          'secrets_set': [_password],
        }, _schema),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('the field', () {
    testWidgets('a held credential shows as set and reveals nothing', (
      tester,
    ) async {
      await _pump(tester, hidden: true);

      expect(_shown(tester), isNotEmpty);
      expect(_textField(tester).obscureText, isTrue);

      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pump();

      expect(_textField(tester).obscureText, isTrue);
    });

    testWidgets('typing replaces the mask rather than adding to it', (
      tester,
    ) async {
      final committed = await _pump(tester, hidden: true);

      await _type(tester, '${_shown(tester)}n');

      expect(_shown(tester), 'n');

      await _type(tester, 'new-pass');
      await _submit(tester);

      expect(committed.toSet(), {'new-pass'});
    });

    testWidgets('once typed, the value can be revealed', (tester) async {
      await _pump(tester, hidden: true);

      await _type(tester, '${_shown(tester)}n');
      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pump();

      expect(_textField(tester).obscureText, isFalse);
    });

    testWidgets('deleting from the mask clears the credential', (tester) async {
      final committed = await _pump(tester, hidden: true);

      final mask = _shown(tester);
      await _type(tester, mask.substring(0, mask.length - 1));
      await _submit(tester);

      expect(_shown(tester), isEmpty);
      expect(committed.toSet(), {''});
    });

    testWidgets('leaving it untouched commits nothing', (tester) async {
      final committed = await _pump(tester, hidden: true);

      await tester.showKeyboard(find.byType(TextField));
      await _submit(tester);

      expect(committed, isEmpty);
    });

    testWidgets('discarding an edit puts the mask back', (tester) async {
      await _pump(tester, hidden: true);
      final mask = _shown(tester);

      await _type(tester, 'new-pass');
      await _submit(tester);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      tester.state<_FieldState>(find.byType(_Field)).discard();
      await tester.pump();

      expect(_shown(tester), mask);
    });

    testWidgets('a value saved while focused is not staged again on blur', (
      tester,
    ) async {
      final committed = await _pump(tester, hidden: true);
      final mask = _shown(tester);

      await _type(tester, 'new-pass');
      await _submit(tester);
      committed.clear();
      tester.state<_FieldState>(find.byType(_Field)).discard();
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      expect(committed, isEmpty);
      expect(_shown(tester), mask);
    });

    testWidgets(
      'undoing back to the mask keeps the held credential',
      (tester) async {
        final committed = await _pump(tester, hidden: true);
        final mask = _shown(tester);

        await tester.tap(find.byType(TextField));
        await tester.pump(const Duration(seconds: 1));
        await _type(tester, '${mask}n');
        await tester.pump(const Duration(seconds: 1));
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump(const Duration(seconds: 1));
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();

        expect(_shown(tester), mask);
        expect(committed, isEmpty);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

    testWidgets('with nothing held it is an ordinary password field', (
      tester,
    ) async {
      final committed = await _pump(tester, hidden: false);

      expect(_shown(tester), isEmpty);

      await _type(tester, 'guest-pass');
      await _submit(tester);

      expect(committed.toSet(), {'guest-pass'});
    });
  });

  group('the settings state', () {
    test('knows which credentials are set without holding them', () async {
      final container = _container();
      await _loaded(container);
      final state = container.read(settingsProvider);

      expect(state.hasHiddenSecret(_password), isTrue);
      expect(state.getEffective(_password), isNull);
    });

    test('an edit replaces the held credential until it is saved', () async {
      final container = _container();
      final notifier = await _loaded(container);

      notifier.stageChange(_password, 'new-pass');

      expect(
        container.read(settingsProvider).hasHiddenSecret(_password),
        false,
      );
    });

    test('a saved credential is kept only as set', () async {
      final container = _container();
      final notifier = await _loaded(container);

      notifier.stageChange(_password, 'new-pass');
      notifier.stageChange('base_config.server.port', 9001);
      await notifier.applyChanges();
      final state = container.read(settingsProvider);

      expect(state.values.containsKey(_password), isFalse);
      expect(state.hasHiddenSecret(_password), isTrue);
      expect(state.values['base_config.server.port'], 9001);
    });

    test('typing an unset credential back to empty unstages it', () async {
      final container = _container();
      final notifier = await _loaded(container);
      notifier.stageChange(_password, '');
      await notifier.applyChanges();

      notifier.stageChange(_password, 'new-pass');
      notifier.stageChange(_password, '');

      expect(container.read(settingsProvider).hasPendingChanges, isFalse);
    });

    test('a cleared credential is no longer set', () async {
      final container = _container();
      final notifier = await _loaded(container);

      notifier.stageChange(_password, '');
      await notifier.applyChanges();

      expect(
        container.read(settingsProvider).hasHiddenSecret(_password),
        false,
      );
    });
  });

  test('a required credential the server holds counts as answered', () {
    const module = ModuleSpec(
      id: 'qobuz',
      kind: 'input_module',
      title: 'Qobuz',
      fields: [
        FieldSpec(
          path: 'input_modules.qobuz.enabled',
          label: 'Enabled',
          widget: WidgetKind.toggle,
          type: 'bool',
        ),
      ],
    );
    const schema = PresentationSchema(
      schemaVersion: 'v1',
      pages: [
        PageSpec(id: 'sources', title: 'Sources', modules: [module]),
      ],
      expertFields: [
        FieldSpec(
          path: _token,
          label: 'User auth token',
          widget: WidgetKind.password,
          type: 'str',
          setup: Setup.required,
        ),
      ],
    );
    const held = SettingsState(
      schema: schema,
      values: {'input_modules.qobuz.enabled': true},
      secretsSet: {_token},
    );
    const missing = SettingsState(
      schema: schema,
      values: {'input_modules.qobuz.enabled': true},
    );

    expect(moduleMissingFields(held, module), isEmpty);
    expect(moduleMissingFields(missing, module), ['User auth token']);
  });
}
