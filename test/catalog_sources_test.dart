import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/catalog_sources_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';

ModuleInfo module(
  String name, {
  bool catalogs = false,
  bool enabled = true,
  bool builtin = false,
}) => ModuleInfo(
  name: name,
  title: name.toUpperCase(),
  enabled: enabled,
  builtin: builtin,
  state: ModuleState.ready,
  capabilities: [if (catalogs) ModuleCapability.catalogs],
);
BrowseItem root(String name) => BrowseItem(
  id: 'kalinka:$name:catalog:actual-root',
  name: name,
  canBrowse: true,
  canAdd: false,
  catalog: Catalog(id: 'kalinka:$name:catalog:actual-root', title: name),
);

class RootApi implements KalinkaPlayerProxy {
  final List<String> calls = [];
  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async {
    calls.add('$id:$offset');
    // Deliberately shorter than requested, so pagination must follow total.
    final items = [
      root('receiver'),
      root('custom'),
      root('builtin'),
      root('disabled'),
    ];
    return BrowseItemsList(
      offset,
      1,
      items.length,
      items.skip(offset).take(1).toList(),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  test(
    'only declared catalogs appear, using backend IDs and all root pages',
    () async {
      final api = RootApi();
      final container = ProviderContainer(
        overrides: [
          kalinkaProxyProvider.overrideWithValue(api),
          sourceModulesProvider.overrideWith(
            (ref) async => [
              module('receiver'),
              module('custom', catalogs: true),
              module('builtin', catalogs: true, builtin: true),
              module('disabled', catalogs: true, enabled: false),
            ],
          ),
        ],
      );
      addTearDown(container.dispose);
      final sources = await container.read(catalogSourcesProvider.future);
      expect(sources.single.module.name, 'custom');
      expect(sources.single.root.id, 'kalinka:custom:catalog:actual-root');
      expect(api.calls, [':0', ':1', ':2', ':3']);
    },
  );
  test('no catalog capabilities means no browse probing', () async {
    final api = RootApi();
    final container = ProviderContainer(
      overrides: [
        kalinkaProxyProvider.overrideWithValue(api),
        sourceModulesProvider.overrideWith(
          (ref) async => [module('qobuz'), module('localfiles')],
        ),
      ],
    );
    addTearDown(container.dispose);
    expect(await container.read(catalogSourcesProvider.future), isEmpty);
    expect(api.calls, isEmpty);
  });
  test('capabilities round trip through server module metadata', () {
    final data = module('arbitrary', catalogs: true).toJson();
    expect(ModuleInfo.fromJson(data).can(ModuleCapability.catalogs), isTrue);
    data.remove('capabilities');
    expect(ModuleInfo.fromJson(data).can(ModuleCapability.catalogs), isFalse);
  });
}
