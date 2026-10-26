import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/providers/catalog_sources_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/modules_state_provider.dart';
import 'package:kalinka/providers/wire_event_provider.dart'
    show playQueueEventBusProvider;

ModulesAndDevices _listing(ModuleState qobuz) => ModulesAndDevices(
  inputModules: [
    ModuleInfo(
      name: 'qobuz',
      title: 'Qobuz',
      enabled: true,
      state: qobuz,
      capabilities: const [ModuleCapability.catalogs],
    ),
  ],
  devices: const [],
);

ModuleState? _qobuz(ProviderContainer container) =>
    container.read(modulesStateProvider).value?.inputModules.single.state;

PlayQueueEvent _replay(ModulesAndDevices? modules) =>
    PlayQueueEvent.replayEvent(
      state: PlayQueueState(
        playbackState: PlaybackState.empty,
        trackList: const [],
        playbackMode: PlaybackMode.empty,
        seq: 1,
        modules: modules,
      ),
      serverTimeNs: 0,
      seq: 1,
    );

PlayQueueEvent _changed(ModuleState qobuz, int seq) =>
    PlayQueueEvent.modulesChanged(modules: _listing(qobuz), seq: seq);

/// Answers `/server/modules` and the browse root as a server would; only the
/// sources in [serving] are on the root.
class _Api implements KalinkaPlayerProxy {
  _Api(this.modules);

  ModulesAndDevices modules;
  Completer<ModulesAndDevices>? pending;
  int reads = 0;
  Set<String> serving = {'qobuz'};

  @override
  Future<ModulesAndDevices> listModules() {
    reads++;
    return pending?.future ?? Future.value(modules);
  }

  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async {
    final roots = [
      for (final name in serving)
        BrowseItem(
          id: 'kalinka:$name:catalog:root',
          name: name,
          canBrowse: true,
          canAdd: false,
          catalog: Catalog(id: 'kalinka:$name:catalog:root', title: name),
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

/// Watched, as the screens showing it watch it.
ProviderSubscription<AsyncValue<ModulesAndDevices>> _watch(
  ProviderContainer container,
) => container.listen(modulesStateProvider, (_, _) {});

void main() {
  late StreamController<PlayQueueEvent> events;

  setUp(() => events = StreamController<PlayQueueEvent>());
  tearDown(() => events.close());

  test('a replay without modules leaves the GET\'s answer in place', () async {
    final api = _Api(_listing(ModuleState.error));
    final container = await _container(api, events);
    _watch(container);
    await container.read(modulesStateProvider.future);

    events.add(_replay(null));
    await pumpEventQueue();

    expect(_qobuz(container), ModuleState.error);
    expect(api.reads, 1);
  });

  test(
    'the replay\'s modules and each change replace it, asking nothing',
    () async {
      final api = _Api(_listing(ModuleState.error));
      final container = await _container(api, events);
      _watch(container);
      await container.read(modulesStateProvider.future);

      events.add(_replay(_listing(ModuleState.warning)));
      await pumpEventQueue();
      expect(_qobuz(container), ModuleState.warning);

      events.add(_changed(ModuleState.ready, 2));
      await pumpEventQueue();
      expect(_qobuz(container), ModuleState.ready);
      expect(api.reads, 1);
    },
  );

  test('a change pushed while the GET is out outlives its answer', () async {
    final api = _Api(_listing(ModuleState.error))..pending = Completer();
    final container = await _container(api, events);
    _watch(container);
    await pumpEventQueue();

    events.add(_changed(ModuleState.ready, 2));
    await pumpEventQueue();
    api.pending!.complete(_listing(ModuleState.error));
    await pumpEventQueue();

    expect(_qobuz(container), ModuleState.ready);
  });

  test('invalidating asks the GET again', () async {
    final api = _Api(_listing(ModuleState.error));
    final container = await _container(api, events);
    _watch(container);
    await container.read(modulesStateProvider.future);
    events.add(_changed(ModuleState.ready, 2));
    await pumpEventQueue();

    api.modules = _listing(ModuleState.warning);
    container.invalidate(modulesStateProvider);
    await container.read(modulesStateProvider.future);

    expect(_qobuz(container), ModuleState.warning);
    expect(api.reads, 2);
  });

  test(
    'a source that fails leaves the browse root, and returns once ready',
    () async {
      final api = _Api(_listing(ModuleState.ready));
      final container = await _container(api, events);
      container.listen(catalogSourcesProvider, (_, _) {});
      Future<List<String>> sources() async => [
        for (final s in await container.read(catalogSourcesProvider.future))
          s.module.name,
      ];
      expect(await sources(), ['qobuz']);

      api.serving = {};
      events.add(_changed(ModuleState.error, 2));
      await pumpEventQueue();
      expect(await sources(), isEmpty);

      api.serving = {'qobuz'};
      events.add(_changed(ModuleState.ready, 3));
      await pumpEventQueue();
      expect(await sources(), ['qobuz']);
      expect(api.reads, 1);
    },
  );
}
