import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data_model/data_model.dart';
import 'collections_provider.dart';
import 'kalinka_player_api_provider.dart';
import 'source_modules_provider.dart';

/// Fetches browse details (album tracks, artist albums) for inline expansion.
///
/// A collection changes under the app's own writes, each of which bumps the
/// revision, so an unrolled one follows it. A source's album keeps its first
/// answer.
final browseDetailProvider = FutureProvider.family<BrowseItemsList, String>((
  ref,
  id,
) async {
  if (ownedByServer(ref.watch(builtinSourcesProvider), id)) {
    ref.watch(collectionsRevisionProvider);
  }
  final api = ref.watch(kalinkaProxyProvider);
  return api.browse(id, limit: 50);
});
