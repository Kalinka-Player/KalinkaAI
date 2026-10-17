import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart';
import 'kalinka_player_api_provider.dart';

/// Equal catalog requests share a cached preview. The collections revision
/// invalidates previews after a write.
typedef CatalogSectionRequest = ({
  String id,
  String? filter,
  int limit,
  int revision,
});

/// A preview of one section, fetched only when the shelf is about to show it.
///
/// A sectioned catalog costs one request per shelf, which is what lets each
/// arrive on its own rather than the page waiting on the slowest.
///
/// Auto-disposed: the filter is part of the key, so a page whose filters were
/// edited a few times would otherwise hold every listing it had ever shown.
final catalogSectionProvider = FutureProvider.autoDispose
    .family<BrowseItemsList, CatalogSectionRequest>((ref, request) async {
      final api = ref.watch(kalinkaProxyProvider);
      return api.browse(
        request.id,
        limit: request.limit,
        filter: request.filter,
      );
    });

/// A pinned catalog's preview on Home. Kept between visits, since slow
/// sources would otherwise shimmer each time Home comes back; Home expires it
/// hourly and on pull to refresh.
final pinnedPreviewProvider = FutureProvider.autoDispose
    .family<BrowseItemsList, CatalogSectionRequest>((ref, request) async {
      final api = ref.watch(kalinkaProxyProvider);
      final list = await api.browse(
        request.id,
        limit: request.limit,
        filter: request.filter,
      );
      // Only a success is kept; a failure is retried on the next visit.
      ref.keepAlive();
      return list;
    });
