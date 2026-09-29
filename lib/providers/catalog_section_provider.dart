import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart';
import 'kalinka_player_api_provider.dart';

/// One shelf of a sectioned catalog: which catalog to browse, under which
/// filter document, and how many items the shelf shows.
///
/// The filter is the encoded document rather than the query object so that two
/// visits with the same constraints share one cached fetch.
typedef CatalogSectionRequest = ({String id, String? filter, int limit});

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
