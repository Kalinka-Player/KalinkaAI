import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/home_pin_content_provider.dart';
import 'package:kalinka/providers/catalog_section_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';

import 'support/adaptive_home_fixtures.dart';

void main() {
  Future<HomePinContent> load(
    AdaptiveHomeApi api, {
    String id = albumFolderId,
    String? filter,
  }) async {
    final container = ProviderContainer(
      overrides: [kalinkaProxyProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    return container.read(
      homePinContentProvider((
        listing: (id: id, filter: filter, limit: 8, revision: 0),
        folder: true,
      )).future,
    );
  }

  test('folder verification is shared across widths, filters and grouping, then refreshed', () async {
    final api = AdaptiveHomeApi();
    final container = ProviderContainer(
      overrides: [kalinkaProxyProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    const canonical = (id: albumFolderId, revision: 0);
    final grouping = container.listen(
      homeFolderAlbumProvider(canonical),
      (_, _) {},
    );
    for (final (limit, filter) in [
      (8, null),
      (16, null),
      (32, 'saved-filter'),
    ]) {
      final request = (
        listing: (id: albumFolderId, filter: filter, limit: limit, revision: 0),
        folder: true,
      );
      final subscription = container.listen(
        homePinContentProvider(request),
        (_, _) {},
      );
      final content = await container.read(
        homePinContentProvider(request).future,
      );
      expect(content.folderAlbum, same(api.albums.first));
      subscription.close();
      await container.pump();
      expect(container.read(homePinContentProvider(request).exists), isFalse);
    }
    expect(api.metadataCalls, [api.albums.first.id]);
    expect(
      api.calls.where((call) => call.id == api.albums.first.id),
      hasLength(1),
    );
    container.invalidate(pinnedPreviewProvider);
    await container.pump();
    await container.read(homeFolderAlbumProvider(canonical).future);
    expect(api.metadataCalls, [api.albums.first.id, api.albums.first.id]);
    grouping.close();
  });

  test(
    'complete folder membership resolves the canonical album metadata',
    () async {
      final api = AdaptiveHomeApi();
      expect((await load(api)).folderAlbum, same(api.albums.first));
      expect(api.calls.any((call) => call.id == api.albums.first.id), isTrue);
    },
  );

  test('loose tracks and mixed children keep their original order', () async {
    final api = AdaptiveHomeApi();
    final folder = BrowseItem(
      id: 'kalinka:localfiles:catalog:sub',
      canBrowse: true,
      canAdd: false,
      catalog: Catalog(
        id: 'kalinka:localfiles:catalog:sub',
        title: 'Subfolder',
        previewConfig: Preview(type: PreviewType.folder),
      ),
    );
    api.listings[folderId] = [
      api.looseTracks.first,
      api.albums.last,
      folder,
      api.looseTracks[1],
    ];
    final content = await load(api, id: folderId);
    expect(content.folderAlbum, isNull);
    expect(content.listing.items, api.listings[folderId]);
  });

  test(
    'matching first eight tracks do not hide a different album later',
    () async {
      final api = AdaptiveHomeApi();
      api.listings[albumFolderId] = [
        for (var i = 0; i < 10; i++)
          demoTrack(
            'same-$i',
            'Same title',
            'Same artist',
            album: api.albums.first.album,
          ),
        api.looseTracks.first,
      ];
      expect((await load(api)).folderAlbum, isNull);
      expect(
        api.calls.any((call) => call.id == albumFolderId && call.offset == 8),
        isTrue,
      );
    },
  );

  test('a subset of a real album remains tracks', () async {
    final api = AdaptiveHomeApi();
    api.listings[albumFolderId] = api.albumTracks.take(3).toList();
    expect((await load(api)).folderAlbum, isNull);
  });

  test('a duplicate does not count as complete album membership', () async {
    final api = AdaptiveHomeApi();
    api.listings[albumFolderId] = [
      ...api.albumTracks.take(5),
      api.albumTracks.first,
    ];
    expect((await load(api)).folderAlbum, isNull);
  });

  for (final total in [-1, 201, 0]) {
    test(
      'unknown, excessive or inconsistent total $total stays as tracks',
      () async {
        final api = AdaptiveHomeApi()..totals[albumFolderId] = total;
        expect((await load(api)).folderAlbum, isNull);
        expect(api.calls, hasLength(1));
      },
    );
  }

  test('complete paginated membership can identify an album', () async {
    final api = AdaptiveHomeApi()..pageSize = 2;
    expect((await load(api)).folderAlbum, same(api.albums.first));
  });

  test('missing metadata preserves a useful track preview', () async {
    final api = AdaptiveHomeApi()..metadataFails = true;
    final content = await load(api);
    expect(content.folderAlbum, isNull);
    expect(content.listing.items, api.albumTracks);
  });

  test(
    'unknown album bucket never collapses, even with shared artwork',
    () async {
      final api = AdaptiveHomeApi();
      final album = Album(
        id: 'kalinka:localfiles:album:unknown_album',
        title: 'Unknown Album',
        image: AlbumImage(large: '/shared.jpg'),
      );
      api.listings[albumFolderId] = [
        for (var i = 0; i < 3; i++)
          demoTrack('$i', 'Track $i', 'Someone', album: album),
      ];
      expect((await load(api)).folderAlbum, isNull);
      expect(api.calls, hasLength(1));
    },
  );
}
