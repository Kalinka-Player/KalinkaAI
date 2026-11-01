import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/data_model/storage.dart';
import 'package:kalinka/providers/catalog_sources_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/modules_state_provider.dart';
import 'package:kalinka/providers/storage_volumes_provider.dart';
import 'package:kalinka/providers/wire_event_provider.dart'
    show playQueueEventBusProvider;

Map<String, dynamic> _stickJson({String state = 'mounted'}) => {
  'id': '3A1F-9C2B',
  'kind': 'removable',
  'label': 'SANDISK',
  'mount_point': '/media/kalinka/3A1F-9C2B',
  'state': state,
  'fs_type': 'exfat',
  'size_bytes': 31000000000,
  'summary': 'USB drive · 31 GB',
  'library': {
    'module': 'localfiles',
    'title': 'My Library',
    'holds': false,
    'library_empty': true,
  },
};

const _internal = StorageVolume(
  id: 'internal',
  kind: VolumeKind.internal,
  label: 'Internal storage',
  mountPoint: '/srv/kalinka/music',
);

class _Api implements KalinkaPlayerProxy {
  List<StorageVolume> volumes = const [];
  ModulesAndDevices modules = ModulesAndDevices(
    inputModules: const [],
    devices: const [],
  );

  @override
  Future<List<StorageVolume>> listStorageVolumes() async => volumes;

  @override
  Future<ModulesAndDevices> listModules() async => modules;

  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async {
    final roots = [
      for (final m in modules.inputModules)
        BrowseItem(
          id: 'kalinka:${m.name}:catalog:root',
          name: m.title,
          canBrowse: true,
          canAdd: false,
          catalog: Catalog(
            id: 'kalinka:${m.name}:catalog:root',
            title: m.title,
          ),
        ),
    ];
    return BrowseItemsList(offset, limit, roots.length, roots);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _Connected extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

Future<ProviderContainer> _container(
  _Api api,
  StreamController<PlayQueueEvent> events,
) async {
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
      playQueueEventBusProvider.overrideWith((ref) => events.stream),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  late StreamController<PlayQueueEvent> events;

  setUp(() => events = StreamController<PlayQueueEvent>());
  tearDown(() {
    events.close();
  });

  test('a volume is read as the server lists it', () {
    final stick = StorageVolume.fromJson(_stickJson());

    expect(stick.kind, VolumeKind.removable);
    expect(stick.isMounted && stick.isRemovable, isTrue);
    expect(stick.library?.title, 'My Library');
    expect(stick.library?.libraryEmpty, isTrue);
    expect(
      StorageVolume.fromJson({..._stickJson(), 'kind': 'robot', 'state': 'x'})
          .kind,
      VolumeKind.mount,
    );
  });

  test('the socket tells of volumes as the listing does', () {
    final event = PlayQueueEvent.fromJson({
      'event_type': 'volumes_changed',
      'seq': 4,
      'volumes': [_stickJson()],
    });

    expect(event, isA<VolumesChangedEvent>());
    expect((event as VolumesChangedEvent).volumes.single.label, 'SANDISK');
  });

  test('a drive is new when it is removable and was not mounted before', () {
    final stick = StorageVolume.fromJson(_stickJson());
    final gone = StorageVolume.fromJson(_stickJson(state: 'unmounted'));

    expect(newlyPlugged([_internal], [_internal, stick]), [stick]);
    expect(newlyPlugged([_internal, stick], [_internal, stick]), isEmpty);
    expect(newlyPlugged([gone], [stick]), [stick]);
    expect(newlyPlugged([], [_internal]), isEmpty);
  });

  test('the volumes mounted are told by id', () {
    final stick = StorageVolume.fromJson(_stickJson());
    final gone = StorageVolume.fromJson(_stickJson(state: 'unmounted'));

    expect(mountedVolumeIds([_internal, stick]), {'internal', stick.id});
    expect(mountedVolumeIds([_internal, gone]), {'internal'});
  });

  test('a volume carries the summary the server gives it', () {
    expect(StorageVolume.fromJson(_stickJson()).summary, 'USB drive · 31 GB');
    expect(_internal.summary, isNull);
  });

  test('the listing follows what the socket pushes', () async {
    final api = _Api()..volumes = const [_internal];
    final container = await _container(api, events);
    container.listen(storageVolumesProvider, (_, _) {});
    expect(await container.read(storageVolumesProvider.future), [_internal]);

    final stick = StorageVolume.fromJson(_stickJson());
    events.add(
      PlayQueueEvent.volumesChanged(volumes: [_internal, stick], seq: 2),
    );
    await pumpEventQueue();

    expect(container.read(storageVolumesProvider).value?.map((v) => v.id), [
      'internal',
      '3A1F-9C2B',
    ]);
  });

  test('Drives is a source on Home while it declares catalogs', () async {
    final api = _Api()
      ..modules = ModulesAndDevices(
        inputModules: [
          ModuleInfo(
            name: 'drives',
            title: 'Drives',
            enabled: true,
            builtin: true,
            state: ModuleState.ready,
            capabilities: const [ModuleCapability.catalogs],
          ),
          ModuleInfo(
            name: 'collections',
            title: 'Collections',
            enabled: true,
            builtin: true,
            state: ModuleState.ready,
          ),
        ],
        devices: const [],
      );
    final container = await _container(api, events);
    container.listen(modulesStateProvider, (_, _) {});

    final sources = await container.read(catalogSourcesProvider.future);

    expect(sources.map((s) => s.module.name), ['drives']);
  });
}
