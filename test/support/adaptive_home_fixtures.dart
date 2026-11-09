import 'package:kalinka/data_model/browse_filters.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/pinned_catalogs_provider.dart';
import 'package:kalinka/providers/search_session_provider.dart';

import 'home_shell.dart';

const library = 'localfiles';
const folderId = 'kalinka:localfiles:catalog:folder-new';
const albumFolderId = 'kalinka:localfiles:catalog:folder-oxygene';
const artistId = 'kalinka:localfiles:artist:jarre';
const awardsId = 'kalinka:qobuz:catalog:press-awards';

BrowseItem demoAlbum(
  String key,
  String title,
  String artist, {
  String source = library,
  bool art = false,
}) {
  final id = 'kalinka:$source:album:$key';
  return BrowseItem(
    id: id,
    name: title,
    canBrowse: true,
    canAdd: true,
    album: Album(
      id: id,
      title: title,
      artist: Artist(id: 'kalinka:$source:artist:$artist', name: artist),
      image: art
          ? AlbumImage(
              small: 'https://review.invalid/$key.jpg',
              large: 'https://review.invalid/$key.jpg',
              aspectRatio: 1,
            )
          : null,
    ),
  );
}

BrowseItem demoTrack(String key, String title, String artist, {Album? album}) {
  final id = 'kalinka:localfiles:track:$key';
  return BrowseItem(
    id: id,
    name: title,
    canBrowse: false,
    canAdd: true,
    track: Track(
      id: id,
      title: title,
      duration: 237,
      performer: Artist(id: 'kalinka:localfiles:artist:$artist', name: artist),
      album: album,
    ),
  );
}

PinnedCatalog folderPin({bool album = false}) => PinnedCatalog(
  page: CatalogPage.category(
    id: album ? albumFolderId : folderId,
    title: album ? '01 - Oxygene (1976)' : 'My new music',
    provider: 'My Library',
    folderLayout: true,
    canAdd: true,
    preview: Preview(type: PreviewType.folder),
  ),
  homeName: album ? 'Sunday listening' : null,
  filter: const BrowseFilterQuery(),
  preview: HomePreviewType.automatic,
);

final awardsPin = PinnedCatalog(
  page: CatalogPage.category(
    id: awardsId,
    title: 'Press Awards',
    provider: 'Qobuz',
    description: 'Albums honoured by the music press',
    preview: Preview(
      type: PreviewType.imageText,
      contentType: PreviewContentType.album,
      cardSize: CardSize.large,
    ),
  ),
  filter: const BrowseFilterQuery(),
  preview: HomePreviewType.automatic,
);

const artistPin = PinnedCatalog(
  page: CatalogPage.category(
    id: artistId,
    title: 'Jean-Michel Jarre',
    provider: 'My Library',
  ),
  filter: BrowseFilterQuery(),
  preview: HomePreviewType.automatic,
);

List<PinnedCatalog> get threePins => [folderPin(), awardsPin, artistPin];

List<ModuleInfo> get demoSources => [
  ModuleInfo(
    name: library,
    title: 'My Library',
    icon: 'folder_outlined',
    enabled: true,
    state: ModuleState.ready,
    capabilities: [ModuleCapability.catalogs],
  ),
  ModuleInfo(
    name: 'qobuz',
    title: 'Qobuz',
    icon: 'album_outlined',
    enabled: true,
    state: ModuleState.ready,
    capabilities: [ModuleCapability.catalogs],
  ),
];

/// Representative library/plugin responses, exercised through the real Home,
/// saved pin notifier, browse navigation, artwork resolver and track actions.
class AdaptiveHomeApi extends HomeApi {
  AdaptiveHomeApi({bool art = false}) {
    albums = [
      demoAlbum('oxygene', 'Oxygène', 'Jean-Michel Jarre', art: art),
      demoAlbum('equinoxe', 'Équinoxe', 'Jean-Michel Jarre', art: art),
      demoAlbum('rendezvous', 'Rendez-Vous', 'Jean-Michel Jarre', art: art),
    ];
    awards = [
      demoAlbum('newseason', 'New Season', 'Sylvie', source: 'qobuz', art: art),
      demoAlbum(
        'bluetrain',
        'Blue Train',
        'John Coltrane',
        source: 'qobuz',
        art: art,
      ),
      demoAlbum(
        'backtoblack',
        'Back To Black',
        'Amy Winehouse',
        source: 'qobuz',
        art: art,
      ),
    ];
    albumTracks = [
      for (var i = 1; i <= 6; i++)
        demoTrack(
          'oxygene-$i',
          'Oxygène, Pt. $i',
          'Jean-Michel Jarre',
          album: albums.first.album,
        ),
    ];
    looseTracks = [
      demoTrack(
        'walk',
        'A Walk',
        'Tycho',
        album: demoAlbum('dive', 'Dive', 'Tycho', art: art).album,
      ),
      demoTrack(
        'roygbiv',
        'Roygbiv',
        'Boards of Canada',
        album: demoAlbum(
          'music',
          'Music Has the Right to Children',
          'Boards of Canada',
          art: art,
        ).album,
      ),
      demoTrack(
        'femme',
        'La femme d’argent',
        'Air',
        album: demoAlbum('moon', 'Moon Safari', 'Air', art: art).album,
      ),
      demoTrack('fourth', 'A fourth track stays in the folder', 'Someone'),
    ];
    listings = {
      '': [
        for (final source in demoSources)
          BrowseItem(
            id: 'kalinka:${source.name}:catalog:root',
            name: source.title,
            canBrowse: true,
            canAdd: false,
            catalog: Catalog(
              id: 'kalinka:${source.name}:catalog:root',
              title: source.title,
            ),
          ),
      ],
      folderId: looseTracks,
      albumFolderId: albumTracks,
      artistId: albums,
      awardsId: awards,
      albums.first.id: albumTracks,
    };
  }

  late List<BrowseItem> albums, awards, albumTracks, looseTracks;
  late Map<String, List<BrowseItem>> listings;
  final totals = <String, int>{};
  final calls = <({String id, int offset, int limit, String? filter})>[];
  final metadataCalls = <String>[];
  final replaced = <List<String>>[];
  final played = <int?>[];
  bool metadataFails = false;
  int? pageSize;

  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async {
    calls.add((id: id, offset: offset, limit: limit, filter: filter));
    final items = listings[id] ?? const <BrowseItem>[];
    return BrowseItemsList(
      offset,
      limit,
      totals[id] ?? items.length,
      items
          .skip(offset)
          .take(pageSize == null ? limit : limit.clamp(0, pageSize!))
          .toList(),
    );
  }

  @override
  Future<BrowseItem> getMetadata(String id) async {
    metadataCalls.add(id);
    if (metadataFails) throw StateError('Metadata unavailable');
    return [...albums, ...awards].firstWhere((item) => item.id == id);
  }

  @override
  Future<StatusMessage> replace(List<String> ids) async {
    replaced.add(ids);
    return StatusMessage(count: ids.length);
  }

  @override
  Future<StatusMessage> play([int? index]) async {
    played.add(index);
    return StatusMessage();
  }
}
