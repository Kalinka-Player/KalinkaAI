import 'dart:convert';

import 'package:dio/dio.dart' show DioException;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kalinka/data_model/browse_filters.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/box_control_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/pinned_catalogs_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';

import 'support/home_shell.dart' show SettableConnection;
import 'support/server_answer.dart';

const genre = FilterSpec(
  id: 'genre',
  kind: FilterKind.choice,
  label: 'Genre',
  ops: [FilterOp.any],
);
PinnedCatalog pin(
  String source, {
  List<String> genres = const [],
  HomePreviewType preview = HomePreviewType.list,
}) => PinnedCatalog(
  page: CatalogPage.category(
    id: 'kalinka:$source:catalog:new',
    title: 'New releases',
    description: 'The latest albums selected by our editors.',
    provider: source,
    filters: const [genre],
    preview: Preview(type: PreviewType.imageText, aspectRatio: 3),
  ),
  filter: BrowseFilterQuery(genreIds: genres),
  preview: preview,
);

const _firstAddressKey = 'Kalinka.pinnedCatalogs.v1:http://first:8000';
const _firstRecordKey = 'Kalinka.serverIdAt.first:8000';

void main() {
  late SharedPreferences prefs;
  late ServersByHost servers;
  late ProviderContainer container;

  ProviderContainer open() {
    final opened = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        connectionStateProvider.overrideWith(SettableConnection.new),
        servers.client,
      ],
    );
    addTearDown(opened.dispose);
    return opened;
  }

  /// The pins once the server at the current address has answered.
  Future<List<PinnedCatalog>> known(ProviderContainer container) async {
    await container.read(serverAnswerProvider.future);
    // Read on its own: the return type would infer the state as a FutureOr.
    final pins = container.read(pinnedCatalogsProvider);
    return pins!;
  }

  Future<void> reconnect(ProviderContainer container) async {
    final connection =
        container.read(connectionStateProvider.notifier) as SettableConnection;
    connection.set(ConnectionStatus.reconnecting);
    connection.set(ConnectionStatus.connected);
    try {
      await container.read(serverAnswerProvider.future);
    } on DioException {
      // The server did not answer: what is shown stays.
    }
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'Kalinka.host': 'first',
      'Kalinka.port': 8000,
    });
    prefs = await SharedPreferences.getInstance();
    servers = ServersByHost()
      ..ids['first'] = 'box-a'
      ..ids['second'] = 'box-b';
    container = open();
  });

  test('pins, filter variants, order and previews survive a restart', () async {
    await known(container);
    final notifier = container.read(pinnedCatalogsProvider.notifier);
    await notifier.pin(pin('one', genres: ['jazz']));
    await notifier.pin(pin('two'));
    await notifier.pin(pin('one', genres: ['rock']));
    await notifier.reorder(2, 0);
    await notifier.setPreview(pin('two').key, HomePreviewType.artwork);
    final restarted = open();
    final saved = await known(restarted);
    expect(saved.map((p) => p.key), [
      pin('one', genres: ['rock']).key,
      pin('one', genres: ['jazz']).key,
      pin('two').key,
    ]);
    expect(saved.last.preview, HomePreviewType.artwork);
    expect(saved.first.page.filters.single.id, 'genre');
    expect(saved.first.page.preview?.aspectRatio, 3);
    expect(
      saved.first.page.description,
      'The latest albums selected by our editors.',
    );
    await restarted
        .read(pinnedCatalogsProvider.notifier)
        .unpin(saved.first.key);
    expect(restarted.read(pinnedCatalogsProvider), hasLength(2));
  });

  test(
    'equivalent genre sets deduplicate without changing their layout',
    () async {
      await known(container);
      final notifier = container.read(pinnedCatalogsProvider.notifier);
      await notifier.pin(
        pin('one', genres: ['jazz', 'rock'], preview: HomePreviewType.artwork),
      );
      await notifier.pin(pin('one', genres: ['rock', 'jazz']));
      expect(container.read(pinnedCatalogsProvider), hasLength(1));
      expect(
        container.read(pinnedCatalogsProvider)!.single.preview,
        HomePreviewType.artwork,
      );
    },
  );

  test('albums, artists, playlists and malformed IDs cannot be pinned', () {
    for (final id in [
      'kalinka:one:album:a',
      'kalinka:one:artist:a',
      'kalinka:one:playlist:a',
      'unknown',
    ]) {
      expect(
        () => container
            .read(pinnedCatalogsProvider.notifier)
            .pin(
              PinnedCatalog(
                page: CatalogPage.category(id: id, title: 'No'),
                filter: const BrowseFilterQuery(),
                preview: HomePreviewType.list,
              ),
            ),
        throwsArgumentError,
      );
    }
  });

  test(
    'legacy previews migrate and new choices persist after a restart',
    () async {
      const legacyModes = ['artwork', 'compact', 'list'];
      await prefs.setString(
        _firstAddressKey,
        jsonEncode([
          for (final mode in legacyModes)
            pin(mode, genres: ['jazz']).toJson()
              ..remove('previewVersion')
              ..['preview'] = mode,
        ]),
      );
      final migrated = await known(container);
      expect(migrated.map((pin) => pin.preview), [
        HomePreviewType.cards,
        HomePreviewType.compact,
        HomePreviewType.list,
      ]);
      expect(migrated.map((pin) => pin.page.provider), legacyModes);
      expect(
        migrated.every((pin) => pin.filter.genreIds.single == 'jazz'),
        isTrue,
      );
      await container.read(pinnedCatalogsProvider.notifier).reorder(2, 0);
      container.invalidate(pinnedCatalogsProvider);
      final restored = container.read(pinnedCatalogsProvider)!;
      expect(restored.map((pin) => pin.preview), [
        HomePreviewType.list,
        HomePreviewType.cards,
        HomePreviewType.compact,
      ]);
      await container
          .read(pinnedCatalogsProvider.notifier)
          .setPreview(restored[1].key, HomePreviewType.artwork);
      container.invalidate(pinnedCatalogsProvider);
      expect(
        container.read(pinnedCatalogsProvider)![1].preview,
        HomePreviewType.artwork,
      );
    },
  );

  test(
    'pins are isolated per server and a switch back restores them',
    () async {
      await known(container);
      await container.read(pinnedCatalogsProvider.notifier).pin(pin('one'));
      final connection = container.read(connectionSettingsProvider.notifier);
      connection.setDeviceEphemeral('Second', 'second', 8000);
      expect(await known(container), isEmpty);
      await container.read(pinnedCatalogsProvider.notifier).pin(pin('two'));
      connection.setDeviceEphemeral('First', 'first', 8000);
      expect((await known(container)).single.page.provider, 'one');
    },
  );

  test('two servers at one address keep their own pins', () async {
    await known(container);
    await container.read(pinnedCatalogsProvider.notifier).pin(pin('one'));
    servers.ids['first'] = 'box-c';
    await reconnect(container);
    expect(container.read(pinnedCatalogsProvider), isEmpty);
    await container.read(pinnedCatalogsProvider.notifier).pin(pin('two'));
    servers.ids['first'] = 'box-a';
    await reconnect(container);
    expect(container.read(pinnedCatalogsProvider)!.single.page.provider, 'one');
  });

  test('one server reached at two addresses shows the same pins', () async {
    servers.ids['second'] = 'box-a';
    await known(container);
    await container.read(pinnedCatalogsProvider.notifier).pin(pin('one'));
    container
        .read(connectionSettingsProvider.notifier)
        .setDeviceEphemeral('By IP', 'second', 8000);
    expect(container.read(pinnedCatalogsProvider), isNull);
    expect((await known(container)).single.page.provider, 'one');
  });

  test(
    'pins kept under the address move to the server the first time it is known',
    () async {
      await prefs.setString(
        _firstAddressKey,
        jsonEncode([pin('one').toJson()]),
      );
      expect((await known(container)).single.page.provider, 'one');
      await Future<void>.delayed(Duration.zero);
      expect(prefs.getString(_firstAddressKey), isNull);
      expect(prefs.getString('Kalinka.pinnedCatalogs.v1:id:box-a'), isNotNull);

      final restarted = open();
      expect((await known(restarted)).single.page.provider, 'one');
    },
  );

  test('a server without an id keeps its pins under its address', () async {
    servers.ids.remove('first');
    await prefs.setString(_firstAddressKey, jsonEncode([pin('one').toJson()]));
    expect((await known(container)).single.page.provider, 'one');
    await container.read(pinnedCatalogsProvider.notifier).pin(pin('two'));
    expect(jsonDecode(prefs.getString(_firstAddressKey)!), hasLength(2));
    expect(
      prefs.getKeys().where((k) => k.startsWith('Kalinka.pinnedCatalogs')),
      [_firstAddressKey],
    );
  });

  for (final status in [403, 404, 405, 501]) {
    test(
      'a server refusing the route with $status keeps its pins under its address',
      () async {
        servers.statuses['first'] = status;
        await prefs.setString(
          _firstAddressKey,
          jsonEncode([pin('one').toJson()]),
        );
        expect((await known(container)).single.page.provider, 'one');
        expect(prefs.getString(_firstAddressKey), isNotNull);
      },
    );
  }

  test('a server error is asked again, less often each time', () {
    fakeAsync((async) {
      servers.statuses['first'] = 503;
      final asking = open()..listen(pinnedCatalogsProvider, (_, _) {});
      for (final (at, asked) in [(0, 1), (2, 2), (6, 3), (14, 4)]) {
        async.elapse(Duration(seconds: at) - async.elapsed);
        async.elapse(const Duration(milliseconds: 1));
        expect(servers.asked, asked, reason: 'at ${at}s');
        expect(asking.read(pinnedCatalogsProvider), isNull);
      }
      servers.statuses.remove('first');
      async.elapse(const Duration(seconds: 16));
      expect(servers.asked, 5);
      expect(asking.read(pinnedCatalogsProvider), isEmpty);
    });
  });

  test(
    'a server that does not answer, or is not connected, shows no pins',
    () async {
      await prefs.setString(
        _firstAddressKey,
        jsonEncode([pin('one').toJson()]),
      );
      servers.silent.add('first');
      await expectLater(
        container.read(serverAnswerProvider.future),
        throwsA(isA<DioException>()),
      );
      expect(container.read(pinnedCatalogsProvider), isNull);

      final offline = open();
      (offline.read(connectionStateProvider.notifier) as SettableConnection)
          .set(ConnectionStatus.offline);
      expect(offline.read(pinnedCatalogsProvider), isNull);
      expect(servers.asked, 1);
      expect(prefs.getString(_firstAddressKey), isNotNull);
    },
  );

  test(
    'away, the pins stay unchanged; back, none show until the server answers',
    () async {
      await known(container);
      final notifier = container.read(pinnedCatalogsProvider.notifier);
      await notifier.pin(pin('one'));
      final connection = container.read(
        connectionStateProvider.notifier,
      ) as SettableConnection;
      connection.set(ConnectionStatus.reconnecting);
      expect(container.read(pinnedCatalogsProvider), hasLength(1));
      await expectLater(notifier.pin(pin('two')), throwsStateError);

      servers.silent.add('first');
      connection.set(ConnectionStatus.connected);
      expect(container.read(pinnedCatalogsProvider), isNull);
      await expectLater(
        container.read(serverAnswerProvider.future),
        throwsA(isA<DioException>()),
      );
      expect(container.read(pinnedCatalogsProvider), isNull);

      servers.silent.remove('first');
      await reconnect(container);
      expect(container.read(pinnedCatalogsProvider), hasLength(1));
    },
  );

  test(
    'another server at the address shows no pins until it answers',
    () async {
      await known(container);
      await container.read(pinnedCatalogsProvider.notifier).pin(pin('one'));
      servers
        ..ids['first'] = 'box-c'
        ..silent.add('first');
      await reconnect(container);
      expect(container.read(pinnedCatalogsProvider), isNull);
      await expectLater(
        container.read(pinnedCatalogsProvider.notifier).pin(pin('two')),
        throwsStateError,
      );

      servers.silent.clear();
      await reconnect(container);
      expect(container.read(pinnedCatalogsProvider), isEmpty);
      expect(
        jsonDecode(prefs.getString('Kalinka.pinnedCatalogs.v1:id:box-a')!),
        hasLength(1),
      );
    },
  );

  for (final recorded in ['box-a', null]) {
    test(
      'pins kept under the address go to the server answering there when '
      '${recorded == null ? 'none was recorded' : 'it was the one recorded'}',
      () async {
        await prefs.setString(
          _firstAddressKey,
          jsonEncode([pin('one').toJson()]),
        );
        if (recorded != null) {
          await prefs.setString(_firstRecordKey, recorded);
        }
        expect((await known(container)).single.page.provider, 'one');
      },
    );
  }

  test('pins kept under the address go to the server recorded there, not to '
      'another that answers', () async {
    await prefs.setString(_firstAddressKey, jsonEncode([pin('one').toJson()]));
    await prefs.setString(_firstRecordKey, 'box-x');
    container.read(rememberServerIdentityProvider);
    expect(await known(container), isEmpty);
    await Future<void>.delayed(Duration.zero);
    expect(prefs.getString(_firstAddressKey), isNull);
    expect(prefs.getString('Kalinka.pinnedCatalogs.v1:id:box-x'), isNotNull);

    // The record now names box-a, which still does not get them.
    expect(prefs.getString(_firstRecordKey), 'box-a');
    await reconnect(container);
    expect(container.read(pinnedCatalogsProvider), isEmpty);
  });

  test('with the server away from the start, the pins of the one last recorded '
      'at the address show, unchanged until it answers', () async {
    await prefs.setString(_firstAddressKey, jsonEncode([pin('one').toJson()]));
    await prefs.setString(_firstRecordKey, 'box-a');
    servers.silent.add('first');
    final connection =
        container.read(connectionStateProvider.notifier) as SettableConnection;
    connection.set(ConnectionStatus.connecting);
    expect(container.read(pinnedCatalogsProvider), isNull);

    connection.set(ConnectionStatus.reconnecting);
    expect(container.read(pinnedCatalogsProvider)!.single.page.provider, 'one');
    final notifier = container.read(pinnedCatalogsProvider.notifier);
    await expectLater(notifier.pin(pin('two')), throwsStateError);
    connection.set(ConnectionStatus.offline);
    expect(container.read(pinnedCatalogsProvider), hasLength(1));

    servers.silent.clear();
    await reconnect(container);
    await notifier.pin(pin('two'));
    expect(container.read(pinnedCatalogsProvider), hasLength(2));
  });

  test('nothing is pinned before the server is known', () async {
    expect(container.read(pinnedCatalogsProvider), isNull);
    final notifier = container.read(pinnedCatalogsProvider.notifier);
    await expectLater(notifier.pin(pin('one')), throwsStateError);
    await expectLater(notifier.unpin(pin('one').key), throwsStateError);
    await expectLater(notifier.reorder(0, 1), throwsStateError);
    expect(await known(container), isEmpty);
    expect(
      prefs.getKeys().where((k) => k.startsWith('Kalinka.pinnedCatalogs')),
      isEmpty,
    );
  });

  test('invalid saved entries do not discard valid pins', () async {
    await prefs.setString(
      _firstAddressKey,
      jsonEncode([
        {'broken': true},
        pin('one').toJson(),
        pin('one').toJson(),
        {
          'page': {'id': 'kalinka:one:album:a', 'title': 'Album'},
          'filter': {},
        },
      ]),
    );
    expect((await known(container)).single.page.provider, 'one');
  });

  test('rapid edits persist in their final order', () async {
    await known(container);
    final notifier = container.read(pinnedCatalogsProvider.notifier);
    await Future.wait([
      notifier.pin(pin('one')),
      notifier.pin(pin('two')),
      notifier.reorder(1, 0),
    ]);
    container.invalidate(pinnedCatalogsProvider);
    expect(
      container.read(pinnedCatalogsProvider)!.map((p) => p.page.provider),
      ['two', 'one'],
    );
  });

  test('nested navigation restores parent filters and returns to Home', () {
    final nav = container.read(searchSessionProvider.notifier);
    nav.openPage(
      pin('one').page,
      filter: const BrowseFilterQuery(genreIds: ['jazz']),
    );
    nav.openPage(pin('two').page);
    nav.setCatalogFilter(const BrowseFilterQuery(genreIds: ['rock']));
    nav.backFromCatalog();
    expect(
      container.read(searchSessionProvider).catalogPage.id,
      pin('one').page.id,
    );
    expect(container.read(searchSessionProvider).catalogFilter.genreIds, [
      'jazz',
    ]);
    nav.backFromCatalog();
    expect(container.read(searchSessionProvider).catalogPage.isRoot, isTrue);
  });
}
