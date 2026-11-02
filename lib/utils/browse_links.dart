import '../data_model/data_model.dart';

/// Metadata links use the source's full entity id, never a name lookup.
bool _hasType(String id, EntityType type) {
  try {
    final entity = EntityId.fromString(id);
    return entity.type == type &&
        entity.source.isNotEmpty &&
        entity.id.isNotEmpty;
  } catch (_) {
    return false;
  }
}

BrowseItem? artistBrowseLink(Artist? artist) {
  if (artist == null || !_hasType(artist.id, EntityType.artist)) return null;
  return BrowseItem(
    id: artist.id,
    name: artist.name,
    canBrowse: true,
    canAdd: false,
    artist: artist,
  );
}

BrowseItem? albumBrowseLink(Album? album) {
  if (album == null || !_hasType(album.id, EntityType.album)) return null;
  return BrowseItem(
    id: album.id,
    name: album.title,
    canBrowse: true,
    canAdd: true,
    album: album,
  );
}
