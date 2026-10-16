import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/catalog_cards_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/recently_added_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/widgets/home/preview_shelf.dart';
import 'package:kalinka/widgets/home/recently_added_section.dart';

const _rootId = 'kalinka:localfiles:catalog:root';
const _recentId = 'kalinka:localfiles:catalog:recent';

BrowseItem _catalog(
  String id,
  String title, {
  List<BrowseItem>? sections,
  int count = 10,
}) => BrowseItem(
  id: id,
  name: title,
  canBrowse: true,
  canAdd: false,
  sections: sections,
  catalog: Catalog(
    id: id,
    title: title,
    role: CatalogRole.library,
    image: AlbumImage(large: '/catalog.png'),
    previewConfig: Preview(
      type: PreviewType.imageText,
      icon: id == _recentId ? 'recent' : null,
      itemsCount: count,
    ),
  ),
);

BrowseItem _album(String title, {String? art}) => BrowseItem(
  id: 'kalinka:localfiles:album:$title',
  name: title,
  canBrowse: true,
  canAdd: true,
  album: Album(
    id: 'kalinka:localfiles:album:$title',
    title: title,
    image: art == null ? null : AlbumImage(large: art),
  ),
);

class _Api implements KalinkaPlayerProxy {
  final BrowseItem recent;
  final Map<String, List<BrowseItem>> items;
  final calls = <({String id, int limit})>[];
  final previewStarted = Completer<void>();
  Completer<void>? gate;
  Completer<void>? catalogGate;
  bool failPreview = false;

  _Api(
    List<BrowseItem> recentItems, {
    List<BrowseItem>? sections,
    int count = 10,
  }) : recent = _catalog(
         _recentId,
         'Recently added',
         sections: sections,
         count: count,
       ),
       items = {_recentId: recentItems};

  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async {
    calls.add((id: id, limit: limit));
    if (id == _rootId) await catalogGate?.future;
    if (id != '' && id != _rootId) {
      if (!previewStarted.isCompleted) previewStarted.complete();
      await gate?.future;
      if (failPreview) throw StateError('Server unavailable');
    }
    final result = switch (id) {
      '' => [_catalog(_rootId, 'Local Library')],
      _rootId => [recent],
      _ => items[id] ?? const <BrowseItem>[],
    };
    return BrowseItemsList(
      offset,
      limit,
      result.length,
      result.take(limit).toList(),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'Kalinka.host': 'first.test',
      'Kalinka.port': 80,
    });
    prefs = await SharedPreferences.getInstance();
  });

  ProviderContainer containerFor(_Api first, [_Api? second]) {
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        sourceModulesProvider.overrideWith((ref) => <ModuleInfo>[]),
        kalinkaProxyProvider.overrideWith((ref) {
          final address = ref.watch(
            connectionSettingsProvider.select((s) => s.address),
          );
          return address == (scheme: 'http', host: 'first.test', port: 80)
              ? first
              : second ?? first;
        }),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test(
    'keeps flat catalogs compatible and respects the preview limit',
    () async {
      final api = _Api([
        _album('One'),
        _album('Two'),
        _album('Three'),
      ], count: 2);
      final container = containerFor(api);

      final shelf = await container.read(recentlyAddedProvider.future);

      expect(shelf!.items.map((item) => item.name), ['One', 'Two']);
      expect(shelf.plan.id, _recentId);
      expect(api.calls, contains((id: _recentId, limit: 2)));
    },
  );

  for (final declared in [true, false]) {
    test(
      'interleaves sub-catalog previews (declared sections: $declared)',
      () async {
        final sections = [
          _catalog('recent-albums', 'Albums', count: 3),
          _catalog('recent-artists', 'Artists', count: 1),
          _catalog('recent-tracks', 'Tracks', count: 2),
        ];
        final artist = BrowseItem(
          id: 'artist',
          name: 'Artist',
          canBrowse: true,
          canAdd: true,
          artist: Artist(id: 'artist', name: 'Artist'),
        );
        final track = BrowseItem(
          id: 'track',
          name: 'Track',
          canBrowse: false,
          canAdd: true,
          track: Track(id: 'track', title: 'Track', duration: 10),
        );
        final api =
            _Api(sections, sections: declared ? sections : null, count: 5)
              ..items.addAll({
                'recent-albums': [
                  _album('Album 1'),
                  _album('Album 2'),
                  _album('Album 3'),
                ],
                'recent-artists': [artist],
                'recent-tracks': [track],
              });
        final container = containerFor(api);

        final shelf = await container.read(recentlyAddedProvider.future);

        expect(shelf!.items.map((item) => item.name), [
          'Album 1',
          'Artist',
          'Track',
          'Album 2',
          'Album 3',
        ]);
        expect(shelf.plan.id, _recentId);
        expect(
          api.calls,
          containsAll([
            (id: 'recent-albums', limit: 3),
            (id: 'recent-artists', limit: 1),
            (id: 'recent-tracks', limit: 2),
          ]),
        );
      },
    );
  }

  test('catalog art refreshes do not refetch the recent items', () async {
    final api = _Api([_album('One')]);
    final container = containerFor(api);
    final shelf = await container.read(recentlyAddedProvider.future);
    container.invalidate(catalogCardGroupsProvider);
    await container.read(catalogCardGroupsProvider.future);
    expect(await container.read(recentlyAddedProvider.future), same(shelf));
    expect(api.calls.where((call) => call.id == _recentId), hasLength(1));
  });

  for (final address in [
    (scheme: 'http', host: 'second.test', port: 80),
    (scheme: 'http', host: 'first.test', port: 8080),
    (scheme: 'https', host: 'first.test', port: 80),
  ]) {
    test('reloads identical catalog IDs after switching to $address', () async {
      final first = _Api([_album('First', art: '/first.png')]);
      final second = _Api([_album('Second', art: '/second.png')]);
      final container = containerFor(first, second);
      await container.read(recentlyAddedProvider.future);

      container
          .read(connectionSettingsProvider.notifier)
          .setDeviceEphemeral(
            'Second',
            address.host,
            address.port,
            scheme: address.scheme,
          );
      final shelf = await container.read(recentlyAddedProvider.future);

      expect(shelf!.items.single.name, 'Second');
      expect(shelf.items.single.image!.large, '/second.png');
      expect(second.calls, contains((id: _recentId, limit: 10)));
    });
  }

  test(
    'waits for the new server catalogs before fetching its previews',
    () async {
      final first = _Api([_album('First')]);
      final second = _Api([_album('Second')])..catalogGate = Completer<void>();
      final container = containerFor(first, second);
      await container.read(recentlyAddedProvider.future);

      container
          .read(connectionSettingsProvider.notifier)
          .setDeviceEphemeral('Second', 'second.test', 80);
      final pending = container.read(recentlyAddedProvider.future);
      await container.pump();
      expect(second.calls.where((call) => call.id == _recentId), isEmpty);

      second.catalogGate!.complete();
      expect((await pending)!.items.single.name, 'Second');
    },
  );

  test(
    'a late response from the previous server cannot replace the new shelf',
    () async {
      final gate = Completer<void>();
      final first = _Api([_album('First')])..gate = gate;
      final second = _Api([_album('Second')]);
      final container = containerFor(first, second);
      container.listen(recentlyAddedProvider, (_, _) {});
      await first.previewStarted.future;
      expect(first.calls, contains((id: _recentId, limit: 10)));

      container
          .read(connectionSettingsProvider.notifier)
          .setDeviceEphemeral('Second', 'second.test', 80);
      expect(
        (await container.read(recentlyAddedProvider.future))!.items.single.name,
        'Second',
      );
      gate.complete();
      await container.pump();
      expect(
        container.read(recentlyAddedProvider).value!.items.single.name,
        'Second',
      );
    },
  );

  for (final fails in [false, true]) {
    testWidgets(
      'drops old previews on server switch (new preview fails: $fails)',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final firstFrame = (await tester.runAsync(
          () => createTestImage(width: 20),
        ))!;
        final secondFrame = (await tester.runAsync(
          () => createTestImage(width: 40),
        ))!;
        addTearDown(firstFrame.dispose);
        addTearDown(secondFrame.dispose);
        addTearDown(() {
          imageCache.clear();
          imageCache.clearLiveImages();
        });
        for (final entry in [
          ('http://first.test/first.png', firstFrame),
          ('http://second.test/second.png', secondFrame),
        ]) {
          final key = await ResizeImage(
            NetworkImage(entry.$1),
            width: 128,
          ).obtainKey(ImageConfiguration.empty);
          imageCache.putIfAbsent(
            key,
            () => OneFrameImageStreamCompleter(
              Future.value(ImageInfo(image: entry.$2.clone())),
            ),
          );
        }
        final first = _Api([_album('First', art: '/first.png')]);
        final second = _Api([_album('Second', art: '/second.png')])
          ..gate = Completer<void>()
          ..failPreview = fails;
        final container = containerFor(first, second);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: ListView(
                  children: [
                    RecentlyAddedSection(
                      onOpenCatalog: (_, _, {focusItemId}) {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('First'), findsOneWidget);
        expect(
          tester
              .widget<RawImage>(find.byType(RawImage))
              .image!
              .isCloneOf(firstFrame),
          isTrue,
        );

        container
            .read(connectionSettingsProvider.notifier)
            .setDeviceEphemeral('Second', 'second.test', 80);
        await tester.pump();
        await tester.pump();
        expect(find.text('First'), findsNothing);
        expect(find.byType(PreviewShelf), findsNothing);
        expect(find.byType(Image), findsNothing);

        second.gate!.complete();
        await tester.pumpAndSettle();
        if (fails) {
          expect(container.read(recentlyAddedProvider).hasError, isTrue);
          expect(find.byType(PreviewShelf), findsNothing);
          expect(find.byType(Image), findsNothing);
        } else {
          expect(find.text('Second'), findsOneWidget);
          expect(
            tester
                .widget<RawImage>(find.byType(RawImage))
                .image!
                .isCloneOf(secondFrame),
            isTrue,
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      },
    );
  }
}
