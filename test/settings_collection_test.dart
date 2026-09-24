// A list of records on the settings page: one card per entry, a sheet per
// card. The sheet edits with the page's own controls, lists what the backend
// suggests under the fields it has suggestions for, and stages the whole list
// as the user types; closing it puts the list back as it was found.
// A collection that replaces older fields is shown instead of them; a server
// that sends no collection has its fields shown as before.
//
// The module below is what the server sends for My Library
// (test/fixtures/localfiles_module.json).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/data_model/collection_entry.dart';
import 'package:kalinka/data_model/data_model.dart' show ModulesAndDevices;
import 'package:kalinka/data_model/presentation_schema.dart';
import 'package:kalinka/providers/collection_entry_binding.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/modules_state_provider.dart';
import 'package:kalinka/providers/settings_provider.dart';
import 'package:kalinka/widgets/kalinka_bottom_sheet.dart' show SheetHeader;
import 'package:kalinka/widgets/kalinka_button.dart';
import 'package:kalinka/widgets/settings_collection.dart';
import 'package:kalinka/widgets/settings_controls/settings_binding.dart';
import 'package:kalinka/widgets/settings_controls/settings_row.dart';
import 'package:kalinka/widgets/settings_renderer.dart' show SchemaModuleCard;

const _path = 'input_modules.localfiles.music_sources';
const _folders = 'input_modules.localfiles.music_folders';

final Map<String, dynamic> _moduleJson =
    (jsonDecode(File('test/fixtures/localfiles_module.json').readAsStringSync())
            as Map)
        .cast<String, dynamic>();

final ModuleSpec _module = ModuleSpec.fromJson(_moduleJson);

final CollectionSpec _sources = _module.collections.single;

Map<String, dynamic> _share({
  String id = 'rec_nas',
  Map<String, dynamic>? authentication,
}) => {
  'id': id,
  'kind': 'smb',
  'location': {'host': 'nas.local', 'port': 445, 'path': 'Music'},
  'authentication': authentication ?? {'mode': 'account', 'username': 'music'},
  'options': {'require_encryption': false},
};

Map<String, dynamic> _folder() => {
  'id': 'rec_usb',
  'kind': 'local',
  'location': {'path': '/mnt/usb/Music'},
};

/// The page's store: values as the server sent them, what is staged, and
/// what the server has said about it.
class _Store {
  _Store(this.values, {this.secrets = const {}});

  final Map<String, dynamic> values;
  final Set<String> secrets;
  final Map<String, dynamic> staged = {};
  final Map<String, List<ConfigIssue>> issues = {};
  final Map<String, List<OptionSpec>> options = {};
  int refreshes = 0;

  List<Map<String, dynamic>> get entries =>
      entriesOf(staged[_path] ?? values[_path]);
}

class _Binding implements SettingsBinding {
  _Binding(this.store, this.onStage);

  final _Store store;
  final VoidCallback onStage;

  @override
  dynamic effectiveValue(String path) =>
      store.staged.containsKey(path) ? store.staged[path] : store.values[path];

  @override
  bool isStaged(String path) => store.staged.containsKey(path);

  @override
  bool hasHiddenSecret(String path) =>
      !store.staged.containsKey(path) && store.secrets.contains(path);

  @override
  List<OptionSpec>? optionsFor(String path) => store.options[path];

  @override
  List<ConfigIssue> issuesFor(String path) => store.issues[path] ?? const [];

  @override
  void stage(String path, dynamic value) {
    store.staged[path] = value;
    onStage();
  }

  @override
  Future<void> refreshOptions() async => store.refreshes++;
}

/// Rebuilds the scope with a new binding on every edit, as the real page does.
class _Page extends StatefulWidget {
  const _Page(this.store, {this.child});

  final _Store store;

  /// What the page shows; the collection alone when null.
  final Widget? child;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  @override
  Widget build(BuildContext context) => SettingsScope(
    binding: _Binding(widget.store, () => setState(() {})),
    child: SingleChildScrollView(
      child: widget.child ?? SchemaCollectionRenderer(collection: _sources),
    ),
  );
}

Future<void> _pump(WidgetTester tester, _Store store, {Widget? child}) async {
  tester.view.physicalSize = const Size(500, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Live module state is not what these tests are about; it never comes.
        modulesStateProvider.overrideWith(
          (ref) => Completer<ModulesAndDevices>().future,
        ),
      ],
      child: MaterialApp(
        home: Scaffold(body: _Page(store, child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _input(String label) => find.descendant(
  of: find.widgetWithText(SettingsRow, label),
  matching: find.byType(TextField),
);

Future<void> _type(WidgetTester tester, String label, String text) async {
  await tester.enterText(_input(label), text);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

void main() {
  group('the schema the server sends', () {
    test('names each shape an entry can take', () {
      expect(
        [for (final v in _sources.variants) (v.key, v.label, v.icon)],
        [
          ('local', 'Folder on the server', 'folder_outlined'),
          ('smb', 'Network share', 'lan_outlined'),
        ],
      );
      expect(_sources.discriminator, 'kind');
      expect(_sources.after, _folders);
      expect(_sources.replaces, [_folders]);
    });

    test('lays a share out in groups, sign-in as a choice of shapes', () {
      final share = _sources.variants[1];
      final signIn = share.groups.firstWhere((g) => g.path == 'authentication');

      expect(
        [for (final g in share.groups) g.title],
        ['Location', 'Sign in', 'Options'],
      );
      expect(signIn.discriminator, 'mode');
      expect(signIn.defaultVariant, 'guest');
      expect(
        [for (final f in signIn.variants[1].fields) f.path],
        ['authentication.username', 'authentication.password'],
      );
    });

    test('keeps the port and encryption for those who look', () {
      final share = _sources.variants[1];
      final expert = share.allFields.where(
        (f) => f.importance == Importance.expert,
      );
      expect(
        [for (final f in expert) f.path],
        ['location.port', 'options.require_encryption'],
      );
    });

    test('is found by path in a page, for the store to fold a save by', () {
      final schema = PresentationSchema(
        schemaVersion: 'v1',
        pages: [
          PageSpec(
            id: 'modules',
            title: 'Input modules',
            modules: [
              ModuleSpec(
                id: 'localfiles',
                kind: 'input_module',
                title: 'My Library',
                collections: [_sources],
              ),
            ],
          ),
        ],
      );
      expect(schema.collection(_path), same(_sources));
      expect(schema.collection('input_modules.localfiles.other'), isNull);
    });
  });

  group('an entry', () {
    test('is read and written by path, groups created on the way', () {
      final entry = <String, dynamic>{'id': 'x'};
      writeEntryPath(entry, 'location.host', 'nas');

      expect(readEntryPath(entry, 'location.host'), 'nas');
      expect(readEntryPath(entry, 'location.path'), isNull);
      expect(entryHasPath(entry, 'location.host'), isTrue);

      removeEntryPath(entry, 'location.host');
      expect(entryHasPath(entry, 'location.host'), isFalse);
    });

    test('takes the shape its discriminator names', () {
      expect(_sources.variantOf(_folder())?.key, 'local');
      expect(_sources.variantOf(_share())?.key, 'smb');
    });

    test('is summarised by where it points', () {
      expect(_sources.variants[1].summaryOf(_share()), 'nas.local · Music');
    });

    test('signs in the default way until told otherwise', () {
      final signIn = _sources.variants[1].groups[1];
      final entry = _share()..remove('authentication');
      expect(signIn.variantOf(entry)?.key, 'guest');
    });

    test('added here gets an id the server accepts', () {
      final ids = {for (var i = 0; i < 20; i++) newRecordId()};
      expect(ids, hasLength(20));
      expect(ids.every(RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch), isTrue);
    });
  });

  group('the binding an entry is edited through', () {
    CollectionEntryBinding bindingFor(
      _Store store,
      Map<String, dynamic> entry,
    ) => CollectionEntryBinding(
      page: _Binding(store, () {}),
      collection: _sources,
      entry: entry,
      before: copyEntry(entry),
      onStage: (_, _) {},
    );

    test('hears the server about this entry by its id', () {
      final store = _Store({});
      store.issues['$_path.rec_nas.location.path'] = const [
        ConfigIssue(path: '$_path.rec_nas.location.path', message: 'name it'),
      ];
      final binding = bindingFor(store, _share());
      expect(binding.issuesFor('location.path').single.message, 'name it');
    });

    test('offers suggestions made for every entry', () {
      final store = _Store({});
      store.options['$_path.location.host'] = const [
        OptionSpec(value: '192.168.1.20', label: 'NAS'),
      ];
      final binding = bindingFor(store, _share());
      expect(binding.optionsFor('location.host')?.single.value, '192.168.1.20');
    });

    test('shows a saved password as set until one is typed', () {
      final store = _Store(
        {},
        secrets: {'$_path.rec_nas.authentication.password'},
      );
      final entry = _share();
      final binding = bindingFor(store, entry);
      expect(binding.hasHiddenSecret('authentication.password'), isTrue);

      writeEntryPath(entry, 'authentication.password', 'typed');
      expect(binding.hasHiddenSecret('authentication.password'), isFalse);
    });

    test('marks what changed since the dialog opened', () {
      final entry = _share();
      final binding = bindingFor(_Store({}), entry);
      writeEntryPath(entry, 'location.path', 'Films');

      expect(binding.isStaged('location.path'), isTrue);
      expect(binding.isStaged('location.host'), isFalse);
    });
  });

  group('the page', () {
    testWidgets('shows a card per entry, with what it is and where', (
      tester,
    ) async {
      await _pump(
        tester,
        _Store({
          _path: [_share(), _folder()],
        }),
      );

      expect(find.text('Music sources'), findsOneWidget);
      expect(find.text('Network share'), findsOneWidget);
      expect(find.text('nas.local · Music'), findsOneWidget);
      expect(find.text('Folder on the server'), findsOneWidget);
      expect(find.text('/mnt/usb/Music'), findsOneWidget);
    });

    testWidgets('puts what the server says about an entry under its card', (
      tester,
    ) async {
      final store = _Store({
        _path: [_share()],
      });
      store.issues['$_path.rec_nas.location.host'] = const [
        ConfigIssue(
          path: '$_path.rec_nas.location.host',
          message: 'nas.local refused the login',
          severity: IssueSeverity.warning,
        ),
      ];
      await _pump(tester, store);

      expect(find.text('nas.local refused the login'), findsOneWidget);
    });

    testWidgets('puts what the server says about the whole list under it', (
      tester,
    ) async {
      final store = _Store({
        _path: [_share()],
      });
      store.issues[_path] = const [
        ConfigIssue(path: _path, message: 'two sources share one place'),
      ];
      await _pump(tester, store);

      expect(find.text('two sources share one place'), findsOneWidget);

      // And in the sheet, where the edit that drew it is being made.
      await _tap(tester, 'nas.local · Music');
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.byType(SheetHeader),
            matching: find.byType(SettingsScope),
          ),
          matching: find.text('two sources share one place'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('stages the whole list as an entry is edited', (tester) async {
      final store = _Store({
        _path: [_share(), _folder()],
      });
      await _pump(tester, store);

      await _tap(tester, 'nas.local · Music');
      await _type(tester, 'Folder', 'Films');
      await _tap(tester, 'KEEP CHANGES');

      final [share, folder] = store.entries;
      expect(readEntryPath(share, 'location.path'), 'Films');
      expect(folder, _folder());
      // Left out, so the server keeps the password it has.
      expect(entryHasPath(share, 'authentication.password'), isFalse);
    });

    testWidgets('cancel puts the list back as the dialog found it', (
      tester,
    ) async {
      final store = _Store({
        _path: [_share()],
      });
      await _pump(tester, store);

      await _tap(tester, 'nas.local · Music');
      await _type(tester, 'Folder', 'Films');
      expect(readEntryPath(store.entries.single, 'location.path'), 'Films');

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(store.entries, [_share()]);
    });

    testWidgets('adds an entry of the shape chosen, with an id of its own', (
      tester,
    ) async {
      final store = _Store({_path: <Map<String, dynamic>>[]});
      await _pump(tester, store);

      await tester.tap(find.widgetWithText(KalinkaButton, 'Add'));
      await tester.pumpAndSettle();
      await _tap(tester, 'Network share');
      await _type(tester, 'Server', '192.168.1.20');
      await _tap(tester, 'ADD');

      final added = store.entries.single;
      expect(added['kind'], 'smb');
      expect(added['id'], startsWith('rec_'));
      expect(readEntryPath(added, 'location.host'), '192.168.1.20');
    });

    testWidgets('removes an entry', (tester) async {
      final store = _Store({
        _path: [_share(), _folder()],
      });
      await _pump(tester, store);

      await _tap(tester, 'nas.local · Music');
      await _tap(tester, 'REMOVE');

      expect(store.entries, [_folder()]);
    });

    testWidgets('switching the sign-in back restores the login it had', (
      tester,
    ) async {
      final store = _Store(
        {
          _path: [_share()],
        },
        secrets: {'$_path.rec_nas.authentication.password'},
      );
      await _pump(tester, store);

      await _tap(tester, 'nas.local · Music');
      await _tap(tester, 'Guest');
      expect(readEntryPath(store.entries.single, 'authentication'), {
        'mode': 'guest',
      });

      await _tap(tester, 'Account');
      expect(readEntryPath(store.entries.single, 'authentication'), {
        'mode': 'account',
        'username': 'music',
      });
    });

    testWidgets('tapping the sign-in it already has keeps what was typed', (
      tester,
    ) async {
      final store = _Store({
        _path: [_share()],
      });
      await _pump(tester, store);

      await _tap(tester, 'nas.local · Music');
      await _type(tester, 'User name', 'jazz');
      await _tap(tester, 'Account');

      expect(
        readEntryPath(store.entries.single, 'authentication.username'),
        'jazz',
      );
    });

    testWidgets('a login still being typed stays behind when it is left', (
      tester,
    ) async {
      final store = _Store({
        _path: [_share()],
      });
      await _pump(tester, store);

      await _tap(tester, 'nas.local · Music');
      await tester.enterText(_input('User name'), 'jazz');
      await _tap(tester, 'Guest');

      expect(readEntryPath(store.entries.single, 'authentication'), {
        'mode': 'guest',
      });
    });
  });

  group('adding one', () {
    Future<_Store> opened(WidgetTester tester) async {
      final store = _Store({_path: <Map<String, dynamic>>[]});
      await _pump(tester, store);
      await tester.tap(find.widgetWithText(KalinkaButton, 'Add'));
      await tester.pumpAndSettle();
      return store;
    }

    testWidgets('starts as the first shape, switched at the top of the sheet', (
      tester,
    ) async {
      final store = await opened(tester);
      expect(_input('Folder'), findsOneWidget);

      await _tap(tester, 'Network share');
      expect(store.entries.single['kind'], 'smb');
      expect(_input('Server'), findsOneWidget);
    });

    testWidgets('switching back finds what was typed for that shape', (
      tester,
    ) async {
      final store = await opened(tester);
      await _type(tester, 'Folder', '/mnt/usb/Music');
      await _tap(tester, 'Network share');
      await _tap(tester, 'Folder on the server');

      expect(
        readEntryPath(store.entries.single, 'location.path'),
        '/mnt/usb/Music',
      );
    });

    testWidgets('a field still being typed in keeps to its own shape', (
      tester,
    ) async {
      final store = await opened(tester);
      await tester.enterText(_input('Folder'), '/mnt/usb/Music');
      await _tap(tester, 'Network share');

      final share = store.entries.single;
      expect(share['kind'], 'smb');
      expect(readEntryPath(share, 'location.path'), isNull);
    });
  });

  group('suggestions', () {
    _Store offering(List<OptionSpec> hosts) {
      final store = _Store({
        _path: [_share()],
      });
      store.options['$_path.location.host'] = hosts;
      return store;
    }

    const nas = OptionSpec(
      value: '192.168.1.20',
      label: 'NAS',
      description: '192.168.1.20 · found over mDNS',
    );
    const studio = OptionSpec(value: '192.168.1.30', label: 'Studio');

    testWidgets('are listed under the field without asking', (tester) async {
      final store = offering([nas, studio]);
      await _pump(tester, store);
      await _tap(tester, 'nas.local · Music');

      expect(find.text('FOUND · 2'), findsOneWidget);
      await _tap(tester, 'NAS');
      expect(
        readEntryPath(store.entries.single, 'location.host'),
        '192.168.1.20',
      );
    });

    testWidgets('narrow to what is typed', (tester) async {
      await _pump(tester, offering([nas, studio]));
      await _tap(tester, 'nas.local · Music');
      await tester.enterText(_input('Server'), 'stu');
      await tester.pump();

      expect(find.text('Studio'), findsOneWidget);
      expect(find.text('NAS'), findsNothing);
    });

    testWidgets(
      'a click takes the one clicked, not the one moved under it',
      (tester) async {
        final store = offering([nas, studio]);
        await _pump(tester, store);
        await _tap(tester, 'nas.local · Music');
        await tester.enterText(_input('Server'), 'stu');
        await tester.pump();

        final click = await tester.startGesture(
          tester.getCenter(find.text('Studio')),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await click.up();
        await tester.pumpAndSettle();

        expect(
          readEntryPath(store.entries.single, 'location.host'),
          '192.168.1.30',
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

    testWidgets('are asked for again while the sheet is open', (tester) async {
      final store = offering([]);
      await _pump(tester, store);
      await _tap(tester, 'nas.local · Music');
      expect(store.refreshes, 1);
      expect(find.textContaining('Nothing found yet'), findsWidgets);

      await tester.pump(const Duration(seconds: 4));
      expect(store.refreshes, 2);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 8));
      expect(store.refreshes, 2);
    });
  });

  group('beside the music folders an older app edits', () {
    _Store library() => _Store({
      _folders: ['/mnt/usb/Music'],
      _path: [_share(), _folder()],
      'input_modules.localfiles.scan_interval_minutes': 15,
    });

    testWidgets('a server with sources shows them in place of the folders', (
      tester,
    ) async {
      await _pump(
        tester,
        library(),
        child: SchemaModuleCard(module: _module, initiallyExpanded: true),
      );

      expect(find.text('Music sources'), findsOneWidget);
      expect(find.text('Music folders'), findsNothing);
      expect(find.text('2 items · 15'), findsOneWidget);
    });

    testWidgets('a server without them shows the folders as before', (
      tester,
    ) async {
      final older = ModuleSpec.fromJson({..._moduleJson, 'collections': []});
      await _pump(
        tester,
        library(),
        child: SchemaModuleCard(module: older, initiallyExpanded: true),
      );

      expect(find.text('Music folders'), findsOneWidget);
      expect(find.text('Music sources'), findsNothing);
      expect(find.text('/mnt/usb/Music · 15'), findsOneWidget);
    });

    test('one source is previewed by where it points', () {
      expect(_sources.previewOf([_share()]), 'nas.local · Music');
      expect(_sources.previewOf([]), '');
    });
  });

  group('saving', () {
    test(
      'keeps a typed password only as set, by the entry it belongs to',
      () async {
        final api = _Api();
        final container = ProviderContainer(
          overrides: [kalinkaProxyProvider.overrideWithValue(api)],
        );
        addTearDown(container.dispose);
        final notifier = container.read(settingsProvider.notifier);
        await notifier.loadConfig();

        notifier.stageChange(_path, [
          _share(
            authentication: {
              'mode': 'account',
              'username': 'music',
              'password': 'hunter2',
            },
          ),
        ]);
        await notifier.applyChanges();

        final state = container.read(settingsProvider);
        expect(jsonEncode(state.values), isNot(contains('hunter2')));
        expect(
          state.secretsSet,
          contains('$_path.rec_nas.authentication.password'),
        );
      },
    );

    test('takes what the server says is saved over its own guess', () async {
      const saved = '$_path.rec_nas.authentication.password';
      final api = _Api(secretsSet: [saved], secretsAfterSave: {});
      final container = ProviderContainer(
        overrides: [kalinkaProxyProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(settingsProvider.notifier);
      await notifier.loadConfig();
      expect(container.read(settingsProvider).secretsSet, contains(saved));

      // The entry goes; left to itself the app would keep its password marked.
      notifier.stageChange(_path, <Map<String, dynamic>>[]);
      await notifier.applyChanges();

      expect(container.read(settingsProvider).secretsSet, isEmpty);
    });
  });
}

class _Api implements KalinkaPlayerProxy {
  /// What the server holds a credential for, as it reads and as a save
  /// leaves it; null after a save is a server that does not say.
  final List<String> secretsSet;
  final Set<String>? secretsAfterSave;

  _Api({this.secretsSet = const [], this.secretsAfterSave});

  @override
  Future<Map<String, dynamic>> getSettings() async => {
    'schema_version': 'v1',
    'values': {
      _path: [_share()],
    },
    'secrets_set': secretsSet,
  };

  @override
  Future<PresentationSchema> getSettingsSchema() async => PresentationSchema(
    schemaVersion: 'v1',
    pages: [
      PageSpec(
        id: 'modules',
        title: 'Input modules',
        modules: [
          ModuleSpec(
            id: 'localfiles',
            kind: 'input_module',
            title: 'My Library',
            collections: [_sources],
          ),
        ],
      ),
    ],
  );

  @override
  Future<Set<String>?> saveSettings({
    required String schemaVersion,
    required Map<String, dynamic> changes,
  }) async => secretsAfterSave;

  @override
  Future<List<ConfigIssue>> validateSettings({
    required String schemaVersion,
    required Map<String, dynamic> changes,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
