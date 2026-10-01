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
      final api = ref.read(kalinkaProxyProvider);
      return api.browse(
        request.id,
        limit: request.limit,
        filter: request.filter,
      );
    });
