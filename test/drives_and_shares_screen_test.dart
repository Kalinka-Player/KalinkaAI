import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/data_model/storage.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/demo_mode.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/storage_devices_provider.dart';
import 'package:kalinka/providers/toast_provider.dart';
import 'package:kalinka/providers/wire_event_provider.dart'
    show playQueueEventBusProvider;
import 'package:kalinka/screens/drives_and_shares_screen.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/demo_read_only_dialog.dart';
import 'package:kalinka/widgets/kalinka_button.dart';
import 'package:kalinka/widgets/kalinka_dialog.dart';

import 'support/server_answer.dart';

const _music = 'nfs-3f9a1c0b7e21';
const _video = 'nfs-0a1b2c3d4e5f';
const _flac = 'nfs-flac';
const _spare = '1111-2222';
const _stick = '3A1F-9C2B';

const _refused =
    'RASPBERRYPI does not let this streamer in. Add 192.168.1.50 to the '
    "share's NFS exports.";
const _said =
    'mount.nfs4: access denied by server while mounting 192.168.1.30:/flac';

Map<String, dynamic> _device(
  String id,
  String medium,
  String label, {
  String summary = '',
  String state = 'unmounted',
  Map<String, Object?> extra = const {},
}) => {
  'id': id,
  'medium': medium,
  'label': label,
  'summary': summary,
  'state': state,
  'managed_by': 'kalinka',
  'saved': false,
  'at_start': null,
  'connected': true,
  ...extra,
};

Map<String, dynamic> _listing({
  bool scanning = false,
  bool found = true,
  bool libraryHolds = false,
  bool canMount = true,
  Map<String, Map<String, Object?>> changed = const {},
}) => {
  'devices': [
    for (final device in _devices(found: found, libraryHolds: libraryHolds))
      {...device, ...?changed[device['id']], if (!canMount) 'can_mount': false},
  ],
  'scan': {'running': scanning, 'finished_at': scanning ? null : 1762171200.0},
  'mounting_available': canMount,
};

/// [_spare] as it is once mounted and kept.
const _spareMounted = {
  'state': 'mounted',
  'saved': true,
  'at_start': true,
  'can_mount': false,
  'can_unmount': true,
  'can_forget': true,
};

List<Map<String, dynamic>> _devices({
  required bool found,
  required bool libraryHolds,
}) => [
  _device(
    'internal',
    'internal',
    'Internal storage',
    summary: '212 GB free',
    state: 'mounted',
  ),
  _device(
    'aaaa-bbbb',
    'disk',
    'Archive',
    summary: 'Disk · 2 TB',
    state: 'mounted',
    extra: {'managed_by': 'system'},
  ),
  _device(
    _spare,
    'disk',
    'Samsung 980',
    summary: 'Disk · 1 TB',
    extra: {
      'at_start': true,
      'can_mount': true,
      'can_set_at_start': true,
      'can_edit': true,
    },
  ),
  _device(
    _stick,
    'usb',
    'SanDisk Ultra',
    summary: 'USB drive · 31 GB',
    state: 'mounted',
    extra: {
      'at_start': false,
      'can_unmount': true,
      'can_eject': true,
      'can_set_at_start': true,
      'can_edit': true,
    },
  ),
  _device(
    'AB12-CD34',
    'usb',
    'Travel',
    summary: 'USB drive',
    extra: {
      'saved': true,
      'at_start': true,
      'connected': false,
      'can_set_at_start': true,
      'can_edit': true,
      'can_forget': true,
    },
  ),
  _device(
    _music,
    'network',
    'Music',
    summary: 'NFS · nas.local',
    state: 'mounted',
    extra: {
      'saved': true,
      'at_start': true,
      'found': true,
      'read_only': true,
      'nfs': {'host': 'nas.local', 'export': '/volume1/music', 'version': '4'},
      'library': {
        'module': 'localfiles',
        'title': 'My Library',
        'holds': libraryHolds,
        'library_empty': false,
      },
      'can_unmount': true,
      'can_set_at_start': true,
      'can_edit': true,
      'can_forget': true,
    },
  ),
  _device(
    _flac,
    'network',
    'flac',
    summary: 'NFS · RASPBERRYPI',
    state: 'failed',
    extra: {
      'saved': true,
      'at_start': true,
      'read_only': true,
      'error': _refused,
      'error_detail': _said,
      'nfs': {'host': '192.168.1.30', 'export': '/flac', 'version': '4'},
      'can_mount': true,
      'can_set_at_start': true,
      'can_edit': true,
      'can_forget': true,
    },
  ),
  if (found)
    _device(
      _video,
      'network',
      'video',
      summary: 'NFS · DS920',
      extra: {
        'at_start': true,
        'found': true,
        'server': 'DS920',
        'clients': ['192.168.1.0/24'],
        'nfs': {'host': '192.168.1.20', 'export': '/volume1/video'},
        'can_mount': true,
        'can_set_at_start': true,
        'can_edit': true,
      },
    ),
];

class _Api implements KalinkaPlayerProxy {
  Map<String, dynamic> listing = _listing();
  ShareProbe probe = const ShareProbe(host: 'nas', reachable: true);
  final calls = <String>[];
  int fetches = 0;

  /// What a mount is answered with; a refusal where unset.
  Completer<DeviceAnswer>? mounting;

  /// Why adding a share is refused, where it is.
  String? addRefusal;

  /// What adding a share is answered with.
  DeviceAnswer added = const DeviceAnswer(
    id: 'nfs-new',
    state: VolumeState.mounted,
  );

  @override
  Future<StorageDeviceList> listStorageDevices() async {
    fetches++;
    return StorageDeviceList.fromJson(listing);
  }

  @override
  Future<DeviceAnswer> mountStorageDevice(
    String deviceId, {
    bool? atStart,
    String? label,
    bool? readOnly,
    String? version,
  }) async {
    calls.add(
      'mount $deviceId ${{'at_start': ?atStart, 'label': ?label, 'read_only': ?readOnly, 'version': ?version}}',
    );
    return mounting?.future ??
        DeviceAnswer(id: deviceId, state: VolumeState.failed, error: 'No');
  }

  @override
  Future<void> unmountStorageDevice(String deviceId) async =>
      calls.add('unmount $deviceId');

  @override
  Future<void> ejectVolume(String volumeId) async =>
      calls.add('eject $volumeId');

  @override
  Future<void> updateStorageDevice(
    String deviceId, {
    bool? atStart,
    String? label,
    bool? readOnly,
    String? version,
  }) async => calls.add(
    'update $deviceId ${{'at_start': ?atStart, 'label': ?label, 'read_only': ?readOnly, 'version': ?version}}',
  );

  @override
  Future<void> forgetStorageDevice(String deviceId) async =>
      calls.add('forget $deviceId');

  @override
  Future<ShareProbe> probeShareHost(String host) async {
    calls.add('probe $host');
    return probe;
  }

  @override
  Future<void> rescanShares() async => calls.add('rescan');

  @override
  Future<DeviceAnswer> addShare({
    required String host,
    required String export,
    required String version,
    required bool atStart,
    required bool readOnly,
  }) async {
    calls.add(
      'add $host:$export ${{'version': version, 'at_start': atStart, 'read_only': readOnly}}',
    );
    if (addRefusal case final refusal?) throw Exception(refusal);
    return added;
  }

  @override
  Future<void> dismissStorageFailure(String deviceId) async =>
      calls.add('dismiss $deviceId');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// The toasts shown, without the timers that put them away.
class _Toasts extends ToastNotifier {
  final shown = <String>[];

  @override
  void show(
    String message, {
    bool isError = false,
    bool inPanel = false,
    ToastAction? action,
  }) => shown.add(message);
}

class _Connected extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

class _Host extends StatefulWidget {
  final bool open;

  const _Host({required this.open});

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late bool _open = widget.open;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: _open
        ? DrivesAndSharesScreen(onClose: () => setState(() => _open = false))
        : const SizedBox.shrink(),
  );
}

Future<_Toasts> _pump(
  WidgetTester tester,
  _Api api, {
  bool demo = false,
  Stream<PlayQueueEvent>? events,
  Size size = const Size(420, 1800),
}) async {
  final toasts = _Toasts();
  SharedPreferences.setMockInitialValues({
    'Kalinka.host': 'localhost',
    'Kalinka.port': 8080,
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      connectionStateProvider.overrideWith(_Connected.new),
      kalinkaProxyProvider.overrideWithValue(api),
      demoModeProvider.overrideWithValue(demo),
      serverAnswering('box-1'),
      toastProvider.overrideWith(() => toasts),
      playQueueEventBusProvider.overrideWith(
        (ref) => events ?? const Stream.empty(),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.dark(), home: const _Host(open: true)),
    ),
  );
  await tester.pumpAndSettle();
  return toasts;
}

/// Taps [finder] once it is scrolled into view.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _in(String id, Finder matching) =>
    find.descendant(of: find.byKey(ValueKey('device-$id')), matching: matching);

Finder _status(String id) => find.byKey(ValueKey('status-$id'));

/// The words of [id]'s status beside its name, null where it has none.
String? _statusOf(WidgetTester tester, String id) {
  final badge = _status(id);
  if (badge.evaluate().isEmpty) return null;
  return tester
      .widget<Text>(find.descendant(of: badge, matching: find.byType(Text)))
      .data;
}

/// Opens the settings of [id] by tapping its name.
Future<void> _openSettings(WidgetTester tester, String id, String name) =>
    _tap(tester, _in(id, find.text(name)));

/// Opens [id]'s dialog and mounts it as the dialog stands.
Future<void> _mountFromDialog(
  WidgetTester tester,
  String id,
  String name,
) async {
  await _openSettings(tester, id, name);
  await _tap(tester, find.byKey(const ValueKey('device-mount')));
}

KalinkaDialog _dialog(WidgetTester tester) =>
    tester.widget<KalinkaDialog>(find.byType(KalinkaDialog));

Future<void> _type(WidgetTester tester, String field, String text) =>
    tester.enterText(
      find.descendant(
        of: find.byKey(ValueKey(field)),
        matching: find.byType(TextField),
      ),
      text,
    );

/// Lets a list asked for now arrive, and its rows draw.
Future<void> _listed(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

double _top(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

void main() {
  test('a device is read as the server lists it', () {
    final devices = StorageDeviceList.fromJson(_listing()).devices;
    final music = devices.firstWhere((d) => d.id == _music);
    final flac = devices.firstWhere((d) => d.id == _flac);

    expect(music.medium, StorageMedium.network);
    expect((music.saved, music.atStart, music.found), (true, true, true));
    expect(music.nfs?.address, 'nas.local:/volume1/music');
    expect(music.library?.title, 'My Library');
    expect((music.isFoundShare, music.canEdit), (false, true));
    expect((flac.error, flac.errorDetail), (_refused, _said));
    expect(
      StorageDevice.fromJson({'id': 'x', 'medium': 'robot'}).medium,
      StorageMedium.disk,
    );
  });

  test('an answer to a mount is read as the server sends it', () {
    final answer = DeviceAnswer.fromJson({
      'id': _spare,
      'state': 'failed',
      'error': 'No such filesystem',
    });

    expect(
      (answer.id, answer.state, answer.error),
      (_spare, VolumeState.failed, 'No such filesystem'),
    );
    expect(StorageDeviceList.fromJson(_listing()).mountingAvailable, isTrue);
    expect(
      StorageDeviceList.fromJson(_listing(canMount: false)).mountingAvailable,
      isFalse,
    );
    expect(StorageDeviceList.fromJson({}).mountingAvailable, isTrue);
  });

  test('two lists read from the same answer are equal', () {
    expect(
      StorageDeviceList.fromJson(_listing()),
      StorageDeviceList.fromJson(_listing()),
    );
    expect(
      StorageDeviceList.fromJson(_listing()),
      isNot(StorageDeviceList.fromJson(_listing(scanning: true))),
    );
  });

  testWidgets('each device is listed under where it is, with its state', (
    tester,
  ) async {
    await _pump(tester, _Api());

    final streamer = _top(tester, find.text('ON THIS STREAMER'));
    final usb = _top(tester, find.text('USB'));
    final saved = _top(tester, find.text('SAVED NETWORK SHARES'));
    final found = _top(tester, find.text('FOUND ON YOUR NETWORK'));
    expect(streamer < _top(tester, find.text('Samsung 980')), isTrue);
    expect(_top(tester, find.text('Samsung 980')) < usb, isTrue);
    expect(usb < _top(tester, find.text('SanDisk Ultra')), isTrue);
    expect(_top(tester, find.text('Travel')) < saved, isTrue);
    expect(saved < _top(tester, find.text('flac')), isTrue);
    expect(_top(tester, find.text('flac')) < found, isTrue);
    expect(found < _top(tester, find.text('video')), isTrue);

    expect(find.text('212 GB free'), findsOneWidget);
    expect(find.byKey(const ValueKey('no-mount-helper')), findsNothing);
    expect(_statusOf(tester, 'internal'), isNull);
    expect(_statusOf(tester, 'aaaa-bbbb'), 'Mounted by the system');
    expect(_statusOf(tester, _spare), isNull);
    expect(_statusOf(tester, _stick), 'Mounted');
    expect(_statusOf(tester, 'AB12-CD34'), 'Not connected');
    expect(_statusOf(tester, _music), 'Mounted');
    expect(_statusOf(tester, _flac), 'Failed');
    expect(_statusOf(tester, _video), isNull);
    expect(_in(_music, find.text('NFS · nas.local')), findsOneWidget);
    expect(_in(_video, find.text('NFS · DS920')), findsOneWidget);
    expect(find.textContaining('192.168.1.0/24'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('only a mounted device has a button; Mount is in the dialog', (
    tester,
  ) async {
    await _pump(tester, _Api());

    expect(find.byKey(const ValueKey('eject-$_stick')), findsOneWidget);
    expect(find.byKey(const ValueKey('unmount-$_stick')), findsNothing);
    expect(find.byKey(const ValueKey('unmount-$_music')), findsOneWidget);
    for (final id in [
      'internal',
      'aaaa-bbbb',
      _spare,
      'AB12-CD34',
      _flac,
      _video,
    ]) {
      expect(_in(id, find.byType(KalinkaButton)), findsNothing);
    }
    // Only a device with settings opens them.
    for (final id in [_spare, _stick, 'AB12-CD34', _music, _flac, _video]) {
      expect(find.byKey(ValueKey('settings-$id')), findsOneWidget);
    }
    for (final id in ['internal', 'aaaa-bbbb']) {
      expect(find.byKey(ValueKey('settings-$id')), findsNothing);
    }
  });

  testWidgets('on a phone the button goes under the name', (tester) async {
    await _pump(tester, _Api());

    expect(
      _top(tester, find.byKey(const ValueKey('unmount-$_music'))) >
          _top(tester, find.text('NFS · nas.local')),
      isTrue,
    );
  });

  testWidgets('on a wide panel the button goes beside the name', (
    tester,
  ) async {
    await _pump(tester, _Api(), size: const Size(1000, 1800));

    expect(
      _top(tester, find.byKey(const ValueKey('unmount-$_music'))) <
          _top(tester, find.text('NFS · nas.local')),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Mount says the mount is under way, then that it is mounted', (
    tester,
  ) async {
    final api = _Api()..mounting = Completer();
    await _pump(tester, api);

    await _openSettings(tester, _spare, 'Samsung 980');
    expect(find.byKey(const ValueKey('device-save')), findsNothing);
    await _tap(tester, find.byKey(const ValueKey('device-mount')));
    expect(find.byType(KalinkaDialog), findsNothing);
    expect(api.calls, ['mount $_spare {}']);
    expect(_statusOf(tester, _spare), 'Mounting…');

    api.listing = _listing(changed: {_spare: _spareMounted});
    api.mounting!.complete(
      const DeviceAnswer(id: _spare, state: VolumeState.mounted),
    );
    await tester.pumpAndSettle();
    expect(_statusOf(tester, _spare), 'Mounted');
    expect(find.byKey(const ValueKey('unmount-$_spare')), findsOneWidget);
  });

  testWidgets('a mount still under way when answered settles as listed', (
    tester,
  ) async {
    final api = _Api()..mounting = Completer();
    await _pump(tester, api);

    await _mountFromDialog(tester, _spare, 'Samsung 980');
    api.mounting!.complete(
      const DeviceAnswer(id: _spare, state: VolumeState.mounting),
    );
    await tester.pumpAndSettle();
    expect(_statusOf(tester, _spare), 'Mounting…');

    api.listing = _listing(
      changed: {
        _spare: {'state': 'failed', 'error': 'Check the drive.'},
      },
    );
    await tester.pump(storageDevicesPollInterval);
    await tester.pumpAndSettle();
    expect(_statusOf(tester, _spare), 'Failed');
    expect(_in(_spare, find.text('Check the drive.')), findsOneWidget);
    expect(find.byKey(const ValueKey('details-$_spare')), findsNothing);
  });

  testWidgets('a mount that failed says what to do, and the mount its words', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final api = _Api();
    final toasts = await _pump(tester, api);

    expect(_in(_flac, find.text(_refused)), findsOneWidget);
    expect(_in(_flac, find.text(_said)), findsNothing);
    await _tap(tester, find.byKey(const ValueKey('details-$_flac')));
    expect(
      tester
          .widget<SelectableText>(
            find.byKey(const ValueKey('technical-details')),
          )
          .data,
      _said,
    );
    await _tap(tester, find.byKey(const ValueKey('copy-details')));
    expect(copied, _said);
    expect(toasts.shown, ['Copied']);
    await _tap(tester, find.text('Close'));

    await _mountFromDialog(tester, _flac, 'flac');
    expect(api.calls, ['mount $_flac {}']);
  });

  testWidgets('a share found shows Mounting… once kept, in its new place', (
    tester,
  ) async {
    final api = _Api()..mounting = Completer();
    await _pump(tester, api);

    await _mountFromDialog(tester, _video, 'video');
    expect(_statusOf(tester, _video), 'Mounting…');

    api.listing = _listing(
      changed: {
        _video: {
          'saved': true,
          'at_start': true,
          'state': 'mounting',
          'can_mount': false,
          'can_forget': true,
        },
      },
    );
    await tester.pump(storageDevicesPollInterval);
    await tester.pumpAndSettle();
    expect(
      _top(tester, find.text('video')) <
          _top(tester, find.text('FOUND ON YOUR NETWORK')),
      isTrue,
    );
    expect(_statusOf(tester, _video), 'Mounting…');

    api.listing = _listing(
      changed: {
        _video: {
          'saved': true,
          'at_start': true,
          'state': 'mounted',
          'can_mount': false,
          'can_unmount': true,
          'can_forget': true,
        },
      },
    );
    api.mounting!.complete(
      const DeviceAnswer(id: _video, state: VolumeState.mounted),
    );
    await tester.pumpAndSettle();
    expect(_statusOf(tester, _video), 'Mounted');
    expect(find.byKey(const ValueKey('unmount-$_video')), findsOneWidget);
  });

  testWidgets('a server without the mount helper offers no mount', (
    tester,
  ) async {
    final api = _Api()..listing = _listing(canMount: false);
    await _pump(tester, api);

    final note = find.byKey(const ValueKey('no-mount-helper'));
    expect(
      find.descendant(
        of: note,
        matching: find.textContaining(
          'This server cannot mount drives or shares',
        ),
      ),
      findsOneWidget,
    );
    // It stays put while the list scrolls under it.
    expect(
      find.ancestor(of: note, matching: find.byType(Scrollable)),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('add-share')), findsNothing);
    expect(find.byKey(const ValueKey('eject-$_stick')), findsOneWidget);
    await _openSettings(tester, _spare, 'Samsung 980');
    expect(
      tester
          .widget<KalinkaButton>(find.byKey(const ValueKey('device-mount')))
          .enabled,
      isFalse,
    );
    expect(find.text('It cannot be mounted now.'), findsOneWidget);
  });

  testWidgets('a dialog mounts with what was changed in it', (tester) async {
    final api = _Api()..mounting = Completer();
    await _pump(tester, api);

    await _openSettings(tester, _video, 'video');
    expect(find.byKey(const ValueKey('device-forget')), findsNothing);
    await _type(tester, 'device-name', 'Films');
    await _tap(tester, find.byKey(const ValueKey('at-start')));
    await _tap(tester, find.byKey(const ValueKey('advanced-settings')));
    await _tap(tester, find.byKey(const ValueKey('read-only')));
    await _tap(tester, find.byKey(const ValueKey('device-mount')));

    expect(api.calls, [
      'mount $_video {at_start: false, label: Films, read_only: false}',
    ]);
  });

  testWidgets(
    'the dialog of a mounted device saves, of one not mounted mounts',
    (tester) async {
      await _pump(tester, _Api());

      await _openSettings(tester, _music, 'Music');
      expect(find.byKey(const ValueKey('device-save')), findsOneWidget);
      expect(find.byKey(const ValueKey('device-mount')), findsNothing);
      // In the middle of the pane, the device named beside its icon.
      expect(
        (_dialog(tester).centered, _dialog(tester).iconBeside),
        (true, true),
      );
      expect(
        find.text('NFS · nas.local\nnas.local:/volume1/music'),
        findsOneWidget,
      );
      await _tap(tester, find.text('Cancel'));

      await _openSettings(tester, _flac, 'flac');
      expect(find.byKey(const ValueKey('device-mount')), findsOneWidget);
      expect(find.byKey(const ValueKey('device-save')), findsNothing);
      expect(find.byKey(const ValueKey('device-forget')), findsOneWidget);
    },
  );

  testWidgets('a drive that is not plugged in says so instead of mounting', (
    tester,
  ) async {
    final api = _Api();
    await _pump(tester, api);

    await _openSettings(tester, 'AB12-CD34', 'Travel');

    expect(
      tester
          .widget<KalinkaButton>(find.byKey(const ValueKey('device-mount')))
          .enabled,
      isFalse,
    );
    expect(find.text('Plug it in to mount it.'), findsOneWidget);
    expect(find.text('Mount when plugged in'), findsOneWidget);
  });

  testWidgets('a drive ejected can be unplugged', (tester) async {
    final api = _Api();
    final toasts = await _pump(tester, api);

    await _tap(tester, find.byKey(const ValueKey('eject-$_stick')));

    expect(api.calls, ['eject $_stick']);
    expect(toasts.shown, contains('SanDisk Ultra can be unplugged'));
  });

  testWidgets('Unmount asks first, and says a share comes back at restart', (
    tester,
  ) async {
    final api = _Api();
    await _pump(tester, api);

    await _tap(tester, find.byKey(const ValueKey('unmount-$_music')));
    expect(find.text('Unmount “Music”?'), findsOneWidget);
    expect(
      find.text(
        'Music from this share will be unavailable. Your files and saved '
        'connection will be kept. It will mount again after the streamer '
        'restarts.',
      ),
      findsOneWidget,
    );
    await _tap(tester, find.text('Cancel'));
    expect(api.calls, isEmpty);

    await _tap(tester, find.byKey(const ValueKey('unmount-$_music')));
    await _tap(tester, find.byKey(const ValueKey('confirm-unmount')));
    expect(api.calls, ['unmount $_music']);
  });

  testWidgets('Unmount promises nothing back where the switch is off', (
    tester,
  ) async {
    final api = _Api()
      ..listing = _listing(
        changed: {
          _spare: {..._spareMounted, 'at_start': false},
        },
      );
    await _pump(tester, api);

    await _tap(tester, find.byKey(const ValueKey('unmount-$_spare')));

    expect(
      find.text(
        'Music from this drive will be unavailable. Your files will be kept.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a row opens its settings, which save what changed at once', (
    tester,
  ) async {
    final api = _Api()..listing = _listing(libraryHolds: true);
    await _pump(tester, api);

    await _openSettings(tester, _music, 'Music');
    expect(find.textContaining('My Library keeps its music'), findsNothing);
    await _type(tester, 'device-name', 'Records');
    await _tap(tester, find.byKey(const ValueKey('at-start')));
    expect(find.textContaining('My Library keeps its music'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('device-save')));

    expect(api.calls, ['update $_music {at_start: false, label: Records}']);
    expect(find.byKey(const ValueKey('device-save')), findsNothing);
  });

  testWidgets('settings left as they were save nothing', (tester) async {
    final api = _Api();
    await _pump(tester, api);

    await _openSettings(tester, _music, 'Music');
    await _tap(tester, find.byKey(const ValueKey('device-save')));

    expect(api.calls, isEmpty);
    expect(find.byKey(const ValueKey('device-save')), findsNothing);
  });

  testWidgets('read-only and the NFS version fold under Advanced settings', (
    tester,
  ) async {
    final api = _Api();
    await _pump(tester, api);

    await _openSettings(tester, _music, 'Music');
    expect(find.text('Read-only · NFS 4'), findsOneWidget);
    expect(find.byKey(const ValueKey('read-only')), findsNothing);
    await _tap(tester, find.byKey(const ValueKey('advanced-settings')));
    await _tap(tester, find.byKey(const ValueKey('read-only')));
    await _tap(
      tester,
      find.descendant(
        of: find.byKey(const ValueKey('nfs-version')),
        matching: find.text('3'),
      ),
    );
    expect(find.text('Writable · NFS 3'), findsOneWidget);
    expect(find.text('A change here mounts it again.'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('device-save')));

    expect(api.calls, ['update $_music {read_only: false, version: 3}']);
  });

  testWidgets(
    'a drive has no NFS version, and one not kept nothing to forget',
    (tester) async {
      final api = _Api();
      await _pump(tester, api);

      await _openSettings(tester, _spare, 'Samsung 980');
      await _tap(tester, find.byKey(const ValueKey('advanced-settings')));
      expect(find.byKey(const ValueKey('nfs-version')), findsNothing);
      expect(find.byKey(const ValueKey('device-forget')), findsNothing);
      await _tap(tester, find.text('Cancel'));

      expect(api.calls, isEmpty);
    },
  );

  testWidgets('Forget share asks first, then forgets it', (tester) async {
    final api = _Api();
    await _pump(tester, api);

    await _openSettings(tester, _music, 'Music');
    await _tap(tester, find.byKey(const ValueKey('device-forget')));
    expect(find.text('Forget “Music”?'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('confirm-forget')));

    expect(api.calls, ['forget $_music']);
    expect(find.byKey(const ValueKey('device-save')), findsNothing);
  });

  testWidgets('a share is added by its server and folder, mounted as set', (
    tester,
  ) async {
    final api = _Api()
      ..probe = const ShareProbe(
        host: 'nas',
        reachable: true,
        exports: ['/volume1/music'],
      );
    await _pump(tester, api);

    await _tap(tester, find.byKey(const ValueKey('add-share')));
    expect(
      tester
          .widget<KalinkaButton>(find.byKey(const ValueKey('share-go')))
          .enabled,
      isFalse,
    );
    await _type(tester, 'share-host', 'nas');
    await tester.pump(shareLookupDelay);
    await tester.pumpAndSettle();
    expect(
      find.text('It shares one folder: Browse to pick it.'),
      findsOneWidget,
    );
    await _tap(tester, find.byIcon(Icons.travel_explore));
    await _tap(tester, find.text('/volume1/music').last);
    await _tap(tester, find.byKey(const ValueKey('share-at-start')));
    await _tap(tester, find.byKey(const ValueKey('share-go')));

    expect(api.calls, [
      'probe nas',
      'add nas:/volume1/music {version: 4, at_start: false, read_only: true}',
    ]);
    expect(find.byKey(const ValueKey('share-go')), findsNothing);
  });

  testWidgets('a failed try of a device not kept is put away from its note', (
    tester,
  ) async {
    final api = _Api()
      ..listing = _listing(
        changed: {
          _video: {
            'state': 'failed',
            'error': 'DS920 did not answer.',
            'error_detail': 'mount.nfs4: Connection timed out',
            'can_dismiss': true,
          },
        },
      );
    await _pump(tester, api);

    expect(_statusOf(tester, _video), 'Failed');
    expect(_in(_video, find.text('DS920 did not answer.')), findsOneWidget);
    // A kept share that failed stays kept, and is forgotten from its dialog.
    expect(find.byKey(const ValueKey('dismiss-$_flac')), findsNothing);
    await _tap(tester, find.byKey(const ValueKey('dismiss-$_video')));

    expect(api.calls, ['dismiss $_video']);
  });

  testWidgets('a share that fails to mount is put right in its dialog', (
    tester,
  ) async {
    final api = _Api()
      ..added = const DeviceAnswer(
        id: 'nfs-new',
        state: VolumeState.failed,
        error: 'nas does not let this streamer in.',
        errorDetail: 'mount.nfs4: access denied by server',
      );
    await _pump(tester, api);

    await _tap(tester, find.byKey(const ValueKey('add-share')));
    await _type(tester, 'share-host', 'nas');
    await _type(tester, 'share-export', '/music');
    await _tap(tester, find.byKey(const ValueKey('share-go')));

    expect(find.byKey(const ValueKey('share-go')), findsOneWidget);
    expect(find.text('nas does not let this streamer in.'), findsOneWidget);
    expect(find.byKey(const ValueKey('details-nfs-new')), findsOneWidget);
    await _tap(tester, find.text('Cancel'));

    expect(find.byKey(const ValueKey('share-go')), findsNothing);
    expect(api.calls.last, 'dismiss nfs-new');
  });

  testWidgets(
    'a share refused says why, and the dialog stays to put it right',
    (tester) async {
      final api = _Api()
        ..addRefusal = 'An export is a path, such as /volume1/music';
      await _pump(tester, api);

      await _tap(tester, find.byKey(const ValueKey('add-share')));
      await _type(tester, 'share-host', 'nas');
      await _type(tester, 'share-export', 'music');
      await _tap(tester, find.byKey(const ValueKey('share-go')));

      expect(
        find.text('An export is a path, such as /volume1/music'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('share-go')), findsOneWidget);
    },
  );

  testWidgets('Refresh asks the network again, and says while it looks', (
    tester,
  ) async {
    final api = _Api();
    await _pump(tester, api);

    api.listing = _listing(scanning: true);
    await _tap(tester, find.byKey(const ValueKey('refresh-shares')));

    expect(api.calls, ['rescan']);
    expect(find.text('Looking…'), findsOneWidget);
    expect(find.byKey(const ValueKey('refresh-shares')), findsNothing);
  });

  testWidgets('the search says while it looks and when it found nothing', (
    tester,
  ) async {
    final api = _Api()..listing = _listing(scanning: true, found: false);
    await _pump(tester, api);
    expect(find.text('Looking for shares…'), findsOneWidget);
    expect(find.text('No shares found on your network.'), findsNothing);

    api.listing = _listing(found: false);
    await tester.pump(storageDevicesPollInterval);
    await tester.pumpAndSettle();

    expect(find.text('Looking…'), findsNothing);
    expect(find.text('No shares found on your network.'), findsOneWidget);
    expect(find.byKey(const ValueKey('add-share')), findsOneWidget);
  });

  testWidgets(
    'it asks again while open, and as volumes change, and not after',
    (tester) async {
      final api = _Api();
      final events = StreamController<PlayQueueEvent>();
      addTearDown(events.close);
      await _pump(tester, api, events: events.stream);
      final opened = api.fetches;

      await tester.pump(storageDevicesPollInterval);
      await tester.pump();
      expect(api.fetches, opened + 1);

      events.add(
        PlayQueueEvent.fromJson({
          'event_type': 'volumes_changed',
          'seq': 2,
          'volumes': [],
        }),
      );
      await _listed(tester);
      expect(api.fetches, opened + 2);

      await _tap(tester, find.byTooltip('Back').first);
      final closed = api.fetches;
      await tester.pump(storageDevicesPollInterval * 3);
      expect(api.fetches, closed);
    },
  );

  testWidgets('a demo server changes nothing', (tester) async {
    final api = _Api();
    await _pump(tester, api, demo: true);

    await _tap(tester, find.byKey(const ValueKey('unmount-$_music')));
    expect(find.byType(DemoReadOnlyDialog), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await _openSettings(tester, _spare, 'Samsung 980');
    expect(find.byType(DemoReadOnlyDialog), findsOneWidget);
    expect(find.byKey(const ValueKey('device-mount')), findsNothing);
    expect(api.calls, isEmpty);
  });
}
