import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kalinka/data_model/browse_filters.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/pinned_catalogs_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';

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

void main() {
  late SharedPreferences prefs;
  late ProviderContainer container;
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'Kalinka.host': 'first',
      'Kalinka.port': 8000,
    });
    prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    );
  });
  tearDown(() => container.dispose());

  test('pins, filter variants, order and previews survive a restart', () async {
    final notifier = container.read(pinnedCatalogsProvider.notifier);
    await notifier.pin(pin('one', genres: ['jazz']));
    await notifier.pin(pin('two'));
    await notifier.pin(pin('one', genres: ['rock']));
    await notifier.reorder(2, 0);
    await notifier.setPreview(pin('two').key, HomePreviewType.artwork);
    final restarted = ProviderContainer(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    );
    addTearDown(restarted.dispose);
    final saved = restarted.read(pinnedCatalogsProvider);
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
      final notifier = container.read(pinnedCatalogsProvider.notifier);
      await notifier.pin(
        pin('one', genres: ['jazz', 'rock'], preview: HomePreviewType.artwork),
      );
      await notifier.pin(pin('one', genres: ['rock', 'jazz']));
      expect(container.read(pinnedCatalogsProvider), hasLength(1));
      expect(
        container.read(pinnedCatalogsProvider).single.preview,
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
        'Kalinka.pinnedCatalogs.v1:http://first:8000',
        jsonEncode([
          for (final mode in legacyModes)
            pin(mode, genres: ['jazz']).toJson()
              ..remove('previewVersion')
              ..['preview'] = mode,
        ]),
      );
      final migrated = container.read(pinnedCatalogsProvider);
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
      final restored = container.read(pinnedCatalogsProvider);
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
        container.read(pinnedCatalogsProvider)[1].preview,
        HomePreviewType.artwork,
      );
    },
  );

  test(
    'pins are isolated per server and a switch back restores them',
    () async {
      await container.read(pinnedCatalogsProvider.notifier).pin(pin('one'));
      final connection = container.read(connectionSettingsProvider.notifier);
      connection.setDeviceEphemeral('Second', 'second', 8000);
      expect(container.read(pinnedCatalogsProvider), isEmpty);
      await container.read(pinnedCatalogsProvider.notifier).pin(pin('two'));
      connection.setDeviceEphemeral('First', 'first', 8000);
      expect(
        container.read(pinnedCatalogsProvider).single.page.provider,
        'one',
      );
    },
  );

  test('invalid saved entries do not discard valid pins', () async {
    await prefs.setString(
      'Kalinka.pinnedCatalogs.v1:http://first:8000',
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
    expect(container.read(pinnedCatalogsProvider).single.page.provider, 'one');
  });

  test('rapid edits persist in their final order', () async {
    final notifier = container.read(pinnedCatalogsProvider.notifier);
    await Future.wait([
      notifier.pin(pin('one')),
      notifier.pin(pin('two')),
      notifier.reorder(1, 0),
    ]);
    container.invalidate(pinnedCatalogsProvider);
    expect(container.read(pinnedCatalogsProvider).map((p) => p.page.provider), [
      'two',
      'one',
    ]);
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
