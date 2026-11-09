import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart';
import 'catalog_section_provider.dart';
import 'kalinka_player_api_provider.dart';
import 'home_preview_cache.dart';

class HomePinContent {
  final BrowseItemsList listing;
  final BrowseItem? folderAlbum;
  const HomePinContent(this.listing, {this.folderAlbum});
}

typedef HomePinRequest = ({CatalogSectionRequest listing, bool folder});

/// Folder recognition uses complete, unfiltered membership and the library's
/// canonical album, never a shared title, cover or the first few tracks. The
/// budget deliberately leaves large/unknown/incomplete folders as ordered rows.
const homeAlbumVerificationLimit = 200;

final homePinContentProvider = FutureProvider.autoDispose
    .family<HomePinContent, HomePinRequest>((ref, request) async {
      final listing = await ref.watch(
        pinnedPreviewProvider(request.listing).future,
      );
      BrowseItem? album;
      if (ref.mounted &&
          request.folder &&
          request.listing.id.startsWith('kalinka:localfiles:')) {
        try {
          album = await ref.watch(
            homeFolderAlbumProvider((
              id: request.listing.id,
              revision: request.listing.revision,
            )).future,
          );
        } catch (_) {
          // Optional metadata must not prevent browsing the loaded rows.
        }
      }
      // The data providers cache successes. This wrapper must release its
      // subscriptions when a width/filter changes or the pin leaves Home.
      return HomePinContent(listing, folderAlbum: album);
    });

typedef HomeFolderRequest = ({String id, int revision});

/// Canonical verification is independent of the displayed limit and filter.
/// Grouping, resized shelves and filtered pins all share one bounded probe.
final homeFolderAlbumProvider = FutureProvider.autoDispose
    .family<BrowseItem?, HomeFolderRequest>((ref, request) async {
      final release = retainHomePreview(ref);
      final api = ref.watch(kalinkaProxyProvider);
      late BrowseItemsList initial;
      try {
        initial = await ref.watch(
          pinnedPreviewProvider((
            id: request.id,
            filter: null,
            limit: 8,
            revision: request.revision,
          )).future,
        );
      } catch (_) {
        release();
        rethrow;
      }
      try {
        final albumId = _singleAlbumId(initial.items);
        if (albumId == null ||
            initial.offset != 0 ||
            initial.total <= 0 ||
            initial.total > homeAlbumVerificationLimit) {
          return null;
        }
        final complete = await _complete(api, request.id, initial);
        if (complete == null || _singleAlbumId(complete) != albumId) {
          return null;
        }
        final metadata = await api.getMetadata(albumId);
        if (metadata.album?.id != albumId ||
            !metadata.canBrowse ||
            metadata.album!.title.trim().isEmpty) {
          return null;
        }
        final members = await api.browse(
          albumId,
          limit: homeAlbumVerificationLimit,
        );
        final tracks = await _complete(api, albumId, members);
        final ids = complete.map((item) => item.id).toSet();
        if (tracks != null &&
            tracks.length == complete.length &&
            ids.length == complete.length &&
            tracks.every((item) => item.track != null) &&
            tracks.map((item) => item.id).toSet().length == ids.length &&
            tracks.every((item) => ids.contains(item.id))) {
          return metadata;
        }
      } catch (_) {
        // Metadata is optional; old servers and transient failures stay rows.
      }
      return null;
    });

String? _singleAlbumId(List<BrowseItem> items) {
  if (items.isEmpty ||
      items.any((item) => item.track == null || item.canBrowse)) {
    return null;
  }
  final id = items.first.track?.album?.id;
  if (id == null || !items.every((item) => item.track?.album?.id == id)) {
    return null;
  }
  try {
    final entity = EntityId.fromString(id);
    // The library's unknown bucket is not an album, even if it has artwork.
    if (entity.type != EntityType.album ||
        !id.startsWith('kalinka:localfiles:album:') ||
        id.endsWith(':unknown_album')) {
      return null;
    }
  } catch (_) {
    return null;
  }
  return id;
}

Future<List<BrowseItem>?> _complete(
  KalinkaPlayerProxy api,
  String id,
  BrowseItemsList initial,
) async {
  final total = initial.total;
  if (initial.offset != 0 || total <= 0 || total > homeAlbumVerificationLimit) {
    return null;
  }
  final items = [...initial.items];
  // Bound requests too: a source returning one item per page cannot make Home
  // perform hundreds of requests. Leave it as rows if completeness is unknown.
  for (var page = 0; items.length < total && page < 3; page++) {
    final more = await api.browse(
      id,
      offset: items.length,
      limit: total - items.length,
    );
    if (more.offset != items.length ||
        more.total != total ||
        more.items.isEmpty) {
      return null;
    }
    items.addAll(more.items);
  }
  return items.length == total ? items : null;
}
