import 'dart:math' show min;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/browse_root.dart';
import 'package:kalinka/providers/catalog_sources_provider.dart';
import 'package:kalinka/providers/collections_provider.dart';
import 'package:kalinka/providers/discover_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';

BrowseItem _catalog(
  String id,
  String title, {
  bool canBrowse = true,
  CatalogRole? role,
  Preview? preview,
}) => BrowseItem(
  id: id,
  name: title,
  canBrowse: canBrowse,
  canAdd: false,
  catalog: Catalog(id: id, title: title, role: role, previewConfig: preview),
);

List<BrowseItem> _roots(int count) => List.generate(
  count,
  (i) => _catalog(
    'kalinka:source_$i:catalog:returned-root-$i',
    'Source $i',
    canBrowse: false,
  ),
);

class _PagedApi implements KalinkaPlayerProxy {
  final List<BrowseItem> roots;
  final Map<String, List<BrowseItem>> children;
  final int? maxPageSize;
  final int? reportedTotal;
  final int? failAtOffset;
  final rootCalls = <({int offset, int limit})>[];

  _PagedApi(
    this.roots, {
    this.children = const {},
    this.maxPageSize,
    this.reportedTotal,
    this.failAtOffset,
  });

  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async {
    if (id.isEmpty) {
      rootCalls.add((offset: offset, limit: limit));
      if (offset == failAtOffset) throw StateError('Root page unavailable');
    }
    final items = id.isEmpty ? roots : children[id] ?? <BrowseItem>[];
    final pageSize = min(limit, maxPageSize ?? limit);
    return BrowseItemsList(
      offset,
      pageSize,
      id.isEmpty ? reportedTotal ?? items.length : items.length,
      items.skip(offset).take(pageSize).toList(),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  group('browseAllRoots', () {
    test(
      'retains every item and its order across several full pages',
      () async {
        final roots = _roots(205);
        final api = _PagedApi(roots);

        expect(await browseAllRoots(api), roots);
        expect(api.rootCalls, [
          (offset: 0, limit: 100),
          (offset: 100, limit: 100),
          (offset: 200, limit: 100),
        ]);
      },
    );

    test('stops at total when the last page is full', () async {
      final api = _PagedApi(_roots(200));

      expect(await browseAllRoots(api), api.roots);
      expect(api.rootCalls.map((call) => call.offset), [0, 100]);
    });

    test('continues after short pages using the number returned', () async {
      final api = _PagedApi(_roots(7), maxPageSize: 2);

      expect(await browseAllRoots(api), api.roots);
      expect(api.rootCalls.map((call) => call.offset), [0, 2, 4, 6]);
    });

    test('stops on an empty page even if total still promises items', () async {
      final api = _PagedApi(_roots(2), reportedTotal: 9);

      expect(await browseAllRoots(api), api.roots);
      expect(api.rootCalls.map((call) => call.offset), [0, 2]);
    });

    test('accepts an empty root listing', () async {
      final api = _PagedApi([]);

      expect(await browseAllRoots(api), isEmpty);
      expect(api.rootCalls.map((call) => call.offset), [0]);
    });

    test(
      'propagates a later page failure instead of returning partial roots',
      () async {
        final api = _PagedApi(_roots(205), failAtOffset: 100);

        await expectLater(browseAllRoots(api), throwsStateError);
        expect(api.rootCalls.map((call) => call.offset), [0, 100]);
      },
    );
  });

  test(
    'all four providers discover sources beyond the first root pages',
    () async {
      final zulu = _catalog('kalinka:zulu:catalog:returned-root', 'Zulu');
      final alpha = _catalog('kalinka:alpha:catalog:returned-root', 'Alpha');
      final library = _catalog(
        'kalinka:library:catalog:returned-root',
        'My music',
      );
      final builtin = _catalog(
        'kalinka:builtin:catalog:returned-root',
        'Lists',
      );
      final receiver = _catalog(
        'kalinka:receiver:catalog:returned-root',
        'Receiver',
      );
      final zuluShelf = _catalog(
        'kalinka:zulu:catalog:new',
        'Zulu discoveries',
      );
      final alphaShelf = _catalog(
        'kalinka:alpha:catalog:new',
        'Alpha discoveries',
      );
      final featured = _catalog(
        'kalinka:alpha:catalog:featured',
        'Featured',
        role: CatalogRole.featured,
      );
      final ownMusic = _catalog(
        'kalinka:library:catalog:all',
        'My music',
        role: CatalogRole.library,
      );
      final lists = _catalog(
        'kalinka:builtin:catalog:lists',
        'Your collections',
        role: CatalogRole.library,
        preview: Preview(
          type: PreviewType.tile,
          contentType: PreviewContentType.playlist,
          itemsCount: 2,
        ),
      );
      final collections = List.generate(
        3,
        (i) => BrowseItem(
          id: 'kalinka:builtin:playlist:$i',
          canBrowse: true,
          canAdd: true,
          playlist: Playlist(id: '$i', name: 'List $i'),
        ),
      );
      final api = _PagedApi(
        [..._roots(200), zulu, alpha, library, builtin, receiver],
        children: {
          zulu.id: [
            zuluShelf,
            _catalog(
              'kalinka:zulu:catalog:hidden',
              'Hidden',
              role: CatalogRole.hideOnHome,
            ),
          ],
          alpha.id: [alphaShelf, featured],
          library.id: [ownMusic],
          builtin.id: [lists],
          lists.id: collections,
        },
      );
      final container = ProviderContainer(
        overrides: [
          kalinkaProxyProvider.overrideWithValue(api),
          builtinSourcesProvider.overrideWithValue({'builtin'}),
          sourceModulesProvider.overrideWith(
            (ref) => [
              for (final root in [zulu, alpha, library, builtin, receiver])
                ModuleInfo(
                  name: sourceOfId(root.id)!,
                  title: root.name!,
                  enabled: true,
                  state: ModuleState.ready,
                  builtin: root == builtin,
                  capabilities: [
                    ModuleCapability.aiSearch,
                    if (root != receiver) ModuleCapability.catalogs,
                  ],
                ),
            ],
          ),
        ],
      );
      addTearDown(container.dispose);

      void expectAllRootPages() {
        expect(api.rootCalls.map((call) => call.offset), [0, 100, 200]);
        api.rootCalls.clear();
      }

      final sources = await container.read(catalogSourcesProvider.future);
      expect(sources.map((source) => source.root.id), [
        alpha.id,
        library.id,
        zulu.id,
      ]);
      expectAllRootPages();

      final shelves = await container.read(discoverShelfPlansProvider.future);
      expect(shelves.map((shelf) => shelf.id), [
        ownMusic.id,
        lists.id,
        featured.id,
        zuluShelf.id,
        alphaShelf.id,
      ]);
      expectAllRootPages();

      final collectionShelf = await container.read(
        collectionsShelfProvider.future,
      );
      expect(collectionShelf?.plan.id, lists.id);
      expect(collectionShelf?.items, collections.take(2).toList());
      expect(collectionShelf?.total, 3);
      expectAllRootPages();
    },
  );
}
