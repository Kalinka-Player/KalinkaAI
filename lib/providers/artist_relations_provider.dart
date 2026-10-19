import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart';
import '../providers/search_session_provider.dart';
import 'kalinka_player_api_provider.dart';

/// How far into an artist's listing the page looks for what it holds.
const _probe = 100;

/// Which of an artist's relations their listing holds, in the order the page
/// offers them: releases (anything that opens) before loose tracks. Read off
/// what the source returned, so a relation with nothing in it gets no tab.
final artistRelationsProvider =
    FutureProvider.family<List<ArtistRelation>, String>((ref, id) async {
      final api = ref.watch(kalinkaProxyProvider);
      final list = await api.browse(id, limit: _probe);
      return [
        if (list.items.any(isArtistRelease)) ArtistRelation.albums,
        if (list.items.any((item) => !isArtistRelease(item)))
          ArtistRelation.tracks,
      ];
    });

/// A release on an artist's page: something with a page of its own. Loose
/// tracks are the rest.
bool isArtistRelease(BrowseItem item) => item.canBrowse;

/// The artist's portrait, asked of the source for a page that was opened
/// without one — from an album's artist line, say.
final artistPortraitProvider = FutureProvider.family<String?, String>((
  ref,
  id,
) async {
  final item = await ref.watch(kalinkaProxyProvider).getMetadata(id);
  return imagePathOf(item.image);
});

String? imagePathOf(AlbumImage? image) =>
    image?.large ?? image?.small ?? image?.thumbnail;
