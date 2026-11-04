import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/data_model.dart';
import '../providers/search_session_provider.dart';
import 'kalinka_player_api_provider.dart';

/// How far into an artist's listing the page looks for what it holds.
const artistProbe = 100;

/// Which of an artist's relations their listing holds, in the order the page
/// offers them: releases (anything that opens) before loose tracks. Read off
/// what the source returned, so a relation with nothing in it gets no tab.
final artistRelationsProvider =
    FutureProvider.family<List<ArtistRelation>, String>((ref, id) async {
      final api = ref.watch(kalinkaProxyProvider);
      final list = await api.browse(id, limit: artistProbe);
      return [
        if (list.items.any(isArtistRelease)) ArtistRelation.albums,
        if (list.items.any((item) => !isArtistRelease(item)))
          ArtistRelation.tracks,
      ];
    });

/// A release on an artist's page: something with a page of its own. Loose
/// tracks are the rest.
bool isArtistRelease(BrowseItem item) => item.canBrowse;

/// What an artist's pin previews from the first [artistProbe] of their
/// listing: their releases, or their tracks where they have none, as their
/// page opens on. The releases are counted only when that was all of it.
BrowseItemsList artistPreviewOf(BrowseItemsList list) {
  final releases = list.items.where(isArtistRelease).toList();
  if (releases.isEmpty) return list;
  final whole = list.total < 0
      ? list.items.length < artistProbe
      : list.items.length >= list.total;
  return BrowseItemsList(
    0,
    releases.length,
    whole ? releases.length : -1,
    releases,
  );
}

/// The artist's portrait, asked of the source for a page that was opened
/// without one — from an album's artist line, say.
final artistPortraitProvider = FutureProvider.family<String?, String>((
  ref,
  id,
) async {
  final item = await ref.watch(kalinkaProxyProvider).getMetadata(id);
  return imagePathOf(item.image);
});

String? imagePathOf(AlbumImage? image) => image?.largest;
