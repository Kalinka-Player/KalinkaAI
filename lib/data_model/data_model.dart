import '../utils/html_unescape.dart';

enum PlayerStateType { stopped, playing, paused, buffering, error }

enum BrowseType { album, artist, playlist, catalog, track, unknown }

extension PlayerStateTypeExtension on PlayerStateType {
  String toValue() {
    switch (this) {
      case PlayerStateType.stopped:
        return 'STOPPED';
      case PlayerStateType.playing:
        return 'PLAYING';
      case PlayerStateType.paused:
        return 'PAUSED';
      case PlayerStateType.buffering:
        return 'BUFFERING';
      case PlayerStateType.error:
        return 'ERROR';
    }
  }

  static PlayerStateType fromValue(String value) {
    switch (value) {
      case 'STOPPED':
        return PlayerStateType.stopped;
      case 'PLAYING':
        return PlayerStateType.playing;
      case 'PAUSED':
        return PlayerStateType.paused;
      case 'BUFFERING':
        return PlayerStateType.buffering;
      case 'ERROR':
        return PlayerStateType.error;
      default:
        throw Exception('Invalid PlayerStateType value: $value');
    }
  }
}

/// How a renderer holds its output device. Shared is not proof that anything
/// alters the samples, only that nothing rules it out.
enum DeviceAccess {
  unknown,
  exclusive,
  shared;

  static DeviceAccess fromJson(Object? value) => switch (value) {
    'exclusive' => DeviceAccess.exclusive,
    'shared' => DeviceAccess.shared,
    _ => DeviceAccess.unknown,
  };
}

/// What the output device runs at, against the stream decoded for it.
class OutputInfo {
  final int sampleRate;
  final int bitsPerSample;
  final int channels;
  final DeviceAccess access;

  /// Whether the decoded samples reach the device unaltered. Only half of
  /// bit-perfection: the volume is reported with the device that applies it.
  final bool losslessPath;

  const OutputInfo({
    this.sampleRate = 0,
    this.bitsPerSample = 0,
    this.channels = 0,
    this.access = DeviceAccess.unknown,
    this.losslessPath = false,
  });

  factory OutputInfo.fromJson(Map<String, dynamic> json) => OutputInfo(
    sampleRate: json["sample_rate"] ?? 0,
    bitsPerSample: json["bits_per_sample"] ?? 0,
    channels: json["channels"] ?? 0,
    access: DeviceAccess.fromJson(json["access"]),
    losslessPath: json["lossless_path"] ?? false,
  );

  Map<String, dynamic> toJson() => {
    "sample_rate": sampleRate,
    "bits_per_sample": bitsPerSample,
    "channels": channels,
    "access": access.name,
    "lossless_path": losslessPath,
  };
}

class AudioInfo {
  int sampleRate;
  int bitsPerSample;
  int channels;
  int durationMs;

  /// The device the stream is played out of; null on a server that does not
  /// report one, or a renderer with none open.
  OutputInfo? output;

  AudioInfo({
    this.sampleRate = 0,
    this.bitsPerSample = 0,
    this.channels = 0,
    this.durationMs = 0,
    this.output,
  });

  factory AudioInfo.fromJson(Map<String, dynamic> json) => AudioInfo(
    sampleRate: json["sample_rate"],
    bitsPerSample: json["bits_per_sample"],
    channels: json["channels"],
    durationMs: json["duration_ms"],
    output: json["output"] == null ? null : OutputInfo.fromJson(json["output"]),
  );

  Map<String, dynamic> toJson() => {
    "sample_rate": sampleRate,
    "bits_per_sample": bitsPerSample,
    "channels": channels,
    "duration_ms": durationMs,
    "output": output?.toJson(),
  };
}

class PlaybackMode {
  final bool repeatAll;
  final bool repeatSingle;
  final bool shuffle;

  PlaybackMode({
    required this.repeatAll,
    required this.repeatSingle,
    required this.shuffle,
  });

  static final empty = PlaybackMode(
    repeatAll: false,
    repeatSingle: false,
    shuffle: false,
  );

  factory PlaybackMode.fromJson(Map<String, dynamic> json) => PlaybackMode(
    repeatAll: json["repeat_all"],
    repeatSingle: json["repeat_single"],
    shuffle: json["shuffle"],
  );

  Map<String, dynamic> toJson() => {
    "repeat_all": repeatAll,
    "repeat_single": repeatSingle,
    "shuffle": shuffle,
  };
}

class PlaybackState {
  PlayerStateType? state;
  Track? currentTrack;
  int? index;
  int? position;
  String? message;
  AudioInfo? audioInfo;
  String? mimeType;

  /// Where the renderer is fetching the current stream from. Null on a server
  /// that does not report it, and while nothing is loaded.
  String? streamUrl;
  int timestampNs = 0;

  PlaybackState({
    this.state,
    this.currentTrack,
    this.index = 0,
    this.position = 0,
    this.message,
    this.audioInfo,
    this.mimeType,
    this.streamUrl,
    this.timestampNs = 0,
  });

  static final PlaybackState empty = PlaybackState();

  factory PlaybackState.fromJson(Map<String, dynamic> json) => PlaybackState(
    state: json.containsKey('state')
        ? PlayerStateTypeExtension.fromValue(json["state"])
        : null,
    currentTrack: json["current_track"] == null
        ? null
        : Track.fromJson(json["current_track"]),
    index: json["index"],
    position: json["position"],
    message: json["message"],
    audioInfo: json["audio_info"] == null
        ? null
        : AudioInfo.fromJson(json["audio_info"]),
    mimeType: json["mime_type"],
    streamUrl: json["stream_url"],
    timestampNs: json["timestamp_ns"] ?? 0,
  );

  Map<String, dynamic> toJson() => {
    "state": state?.toValue(),
    "current_track": currentTrack?.toJson(),
    "index": index,
    "position": position,
    "message": message,
    "audio_info": audioInfo?.toJson(),
    "mime_type": mimeType,
    "stream_url": streamUrl,
    "timestamp_ns": timestampNs,
  };

  PlaybackState copyWith(PlaybackState other) {
    return PlaybackState(
      state: other.state ?? state,
      currentTrack: other.currentTrack ?? currentTrack,
      index: other.index ?? index,
      position: other.position ?? position,
      message: other.message ?? message,
      audioInfo: other.audioInfo ?? audioInfo,
      mimeType: other.mimeType ?? mimeType,
      // Replaced, not merged: the URL is only true while the renderer holds
      // that stream, so a state reporting none must clear the last one rather
      // than leave a link to something that stopped playing.
      streamUrl: other.streamUrl,
      timestampNs: other.timestampNs != 0 ? other.timestampNs : timestampNs,
    );
  }

  PlaybackState copyWithFields({
    PlayerStateType? state,
    Track? currentTrack,
    int? index,
    int? position,
    String? message,
    AudioInfo? audioInfo,
    String? mimeType,
    String? streamUrl,
    int? timestampNs,
  }) {
    return PlaybackState(
      state: state ?? this.state,
      currentTrack: currentTrack ?? this.currentTrack,
      index: index ?? this.index,
      position: position ?? this.position,
      message: message ?? this.message,
      audioInfo: audioInfo ?? this.audioInfo,
      mimeType: mimeType ?? this.mimeType,
      streamUrl: streamUrl ?? this.streamUrl,
      timestampNs: timestampNs ?? this.timestampNs,
    );
  }
}

/// Where a device applies its volume, and so whether it touches the samples.
/// Only [software] does, and only below unity.
enum VolumeBackend {
  unknown,
  none,
  hardware,
  software;

  static VolumeBackend fromJson(Object? value) => switch (value) {
    'none' => VolumeBackend.none,
    'hardware' => VolumeBackend.hardware,
    'software' => VolumeBackend.software,
    _ => VolumeBackend.unknown,
  };
}

class DeviceVolume {
  final int currentVolume;
  final int maxVolume;
  final int volumeGain;
  final bool supported;
  final VolumeBackend backend;

  DeviceVolume({
    required this.currentVolume,
    required this.maxVolume,
    required this.volumeGain,
    required this.supported,
    this.backend = VolumeBackend.unknown,
  });

  factory DeviceVolume.fromJson(Map<String, dynamic> json) => DeviceVolume(
    currentVolume: json["current_volume"],
    maxVolume: json["max_volume"],
    volumeGain: json["volume_gain"],
    supported: json["supported"],
    backend: VolumeBackend.fromJson(json["backend"]),
  );

  static final empty = DeviceVolume(
    currentVolume: 0,
    maxVolume: 0,
    volumeGain: 0,
    supported: false,
  );

  Map<String, dynamic> toJson() => {
    "volume": currentVolume,
    "max_volume": maxVolume,
    "volume_gain": volumeGain,
    "supported": supported,
    "backend": backend.name,
  };

  DeviceVolume copyWith({
    int? currentVolume,
    int? maxVolume,
    int? volumeGain,
    bool? supported,
    VolumeBackend? backend,
  }) {
    return DeviceVolume(
      currentVolume: currentVolume ?? this.currentVolume,
      maxVolume: maxVolume ?? this.maxVolume,
      volumeGain: volumeGain ?? this.volumeGain,
      supported: supported ?? this.supported,
      backend: backend ?? this.backend,
    );
  }
}

class Track {
  String id;
  String title;
  int duration;
  Artist? performer;
  Album? album;
  String? playlistTrackId;

  /// True when the backend could not retrieve a stream URL for this track and
  /// skipped it during playback. Surfaced as a warning indicator in the queue.
  bool unavailable;

  /// User-presentable cause the server sent with [unavailable]. Event-borne:
  /// a replay after reconnect restores the flag but not the reason.
  String? unavailableReason;

  Track({
    required this.id,
    required this.title,
    required this.duration,
    this.performer,
    this.album,
    this.playlistTrackId,
    this.unavailable = false,
    this.unavailableReason,
  });

  factory Track.fromJson(Map<String, dynamic> json) => Track(
    id: json["id"],
    title: unescapeHtml(json["title"]),
    duration: json["duration"],
    performer: json["performer"] == null
        ? null
        : Artist.fromJson(json["performer"]),
    album: json["album"] == null ? null : Album.fromJson(json["album"]),
    playlistTrackId: json["playlist_track_id"],
    unavailable: json["unavailable"] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    "id": id,
    "title": title,
    "duration": duration,
    "performer": performer?.toJson(),
    "album": album?.toJson(),
    "playlist_track_id": playlistTrackId,
    "unavailable": unavailable,
  };

  /// Changing [unavailable] also replaces [unavailableReason], so a track
  /// that becomes available again drops the stale cause.
  Track copyWith({bool? unavailable, String? unavailableReason}) => Track(
    id: id,
    title: title,
    duration: duration,
    performer: performer,
    album: album,
    playlistTrackId: playlistTrackId,
    unavailable: unavailable ?? this.unavailable,
    unavailableReason: unavailable == null
        ? this.unavailableReason
        : unavailableReason,
  );
}

class Album {
  final String id;
  final String title;
  final int? duration;
  final int? trackCount;
  final int? year;
  final AlbumImage? image;
  final List<Genre> genres;
  final Artist? artist;

  Album({
    required this.id,
    required this.title,
    this.duration,
    this.trackCount,
    this.year,
    this.image,
    this.genres = const [],
    this.artist,
  });

  factory Album.fromJson(Map<String, dynamic> json) => Album(
    id: json["id"],
    title: unescapeHtml(json["title"]),
    duration: json["duration"],
    trackCount: json["track_count"],
    year: json["year"],
    image: json["image"] == null ? null : AlbumImage.fromJson(json["image"]),
    genres: json["genres"] == null
        ? const []
        : List<Genre>.from(json["genres"].map((x) => Genre.fromJson(x))),
    artist: json["artist"] == null ? null : Artist.fromJson(json["artist"]),
  );

  Map<String, dynamic> toJson() => {
    "id": id,
    "title": title,
    "duration": duration,
    "track_count": trackCount,
    "year": year,
    "image": image?.toJson(),
    "genres": genres.map((genre) => genre.toJson()).toList(),
    "artist": artist?.toJson(),
  };
}

class AlbumImage {
  final String? small;
  final String? thumbnail;
  final String? large;

  AlbumImage({this.small, this.thumbnail, this.large});

  factory AlbumImage.fromJson(Map<String, dynamic> json) => AlbumImage(
    small: json["small"],
    thumbnail: json["thumbnail"],
    large: json["large"],
  );

  Map<String, dynamic> toJson() => {
    "small": small,
    "thumbnail": thumbnail,
    "large": large,
  };
}

class Artist {
  final String id;
  final String name;
  final AlbumImage? image;
  final int? albumCount;

  Artist({required this.id, required this.name, this.image, this.albumCount});

  factory Artist.fromJson(Map<String, dynamic> json) => Artist(
    id: json["id"],
    name: unescapeHtml(json["name"]),
    image: json["image"] == null ? null : AlbumImage.fromJson(json["image"]),
    albumCount: json["album_count"],
  );

  Map<String, dynamic> toJson() => {
    "id": id,
    "name": name,
    "image": image?.toJson(),
    "album_count": albumCount,
  };
}

class Owner {
  final String name;
  final String id;

  Owner({required this.name, required this.id});

  factory Owner.fromJson(Map<String, dynamic> json) =>
      Owner(name: json["name"], id: json["id"]);

  Map<String, dynamic> toJson() => {"name": name, "id": id};
}

class Playlist {
  final String id;
  final String name;
  final Owner? owner;
  final AlbumImage? image;
  final String? description;
  final int? trackCount;

  /// Total playing time in seconds, where the source knew it without
  /// loading the tracks.
  final int? duration;

  Playlist({
    required this.id,
    required this.name,
    this.owner,
    this.image,
    this.description,
    this.trackCount,
    this.duration,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
    id: json["id"],
    name: unescapeHtml(json["name"]),
    owner: json["owner"] == null ? null : Owner.fromJson(json["owner"]),
    image: json["image"] == null ? null : AlbumImage.fromJson(json["image"]),
    description: json["description"],
    trackCount: json["track_count"],
    duration: json["duration"],
  );

  Map<String, dynamic> toJson() => {
    "id": id,
    "name": name,
    "owner": owner?.toJson(),
    "image": image?.toJson(),
    "description": description,
    "track_count": trackCount,
    "duration": duration,
  };
}

enum PreviewType {
  imageText,
  textOnly,
  carousel,
  tile,
  tileNumbered,
  card,
  none,
}

extension PreviewTypeExtension on PreviewType {
  String toValue() {
    switch (this) {
      case PreviewType.imageText:
        return 'image';
      case PreviewType.textOnly:
        return 'text';
      case PreviewType.carousel:
        return 'carousel';
      case PreviewType.tile:
        return 'tile';
      case PreviewType.tileNumbered:
        return 'tile_numbered';
      case PreviewType.card:
        return 'card';
      case PreviewType.none:
        return 'none';
    }
  }

  static PreviewType fromValue(String value) {
    switch (value) {
      case 'image':
        return PreviewType.imageText;
      case 'text':
        return PreviewType.textOnly;
      case 'carousel':
        return PreviewType.carousel;
      case 'tile':
        return PreviewType.tile;
      case 'tile_numbered':
        return PreviewType.tileNumbered;
      case 'card':
        return PreviewType.card;
      case 'none':
        return PreviewType.none;
      default:
        // Tolerate unknown/newer server layout types instead of throwing:
        // the section still renders as a plain tile list.
        return PreviewType.tile;
    }
  }
}

enum CardSize { small, large }

extension CardSizeExtension on CardSize {
  String toValue() {
    switch (this) {
      case CardSize.small:
        return 'small';
      case CardSize.large:
        return 'large';
    }
  }

  static CardSize fromValue(String value) {
    switch (value) {
      case 'small':
        return CardSize.small;
      case 'large':
        return CardSize.large;
      default:
        throw Exception('Invalid CardSize value: $value');
    }
  }
}

enum PreviewContentType { catalog, album, artist, playlist, track, unknown }

extension PreviewContentTypeExtension on PreviewContentType {
  String toValue() {
    switch (this) {
      case PreviewContentType.catalog:
        return 'catalog';
      case PreviewContentType.album:
        return 'album';
      case PreviewContentType.artist:
        return 'artist';
      case PreviewContentType.playlist:
        return 'playlist';
      case PreviewContentType.track:
        return 'track';
      case PreviewContentType.unknown:
        return 'unknown';
    }
  }

  static PreviewContentType fromValue(String value) {
    switch (value) {
      case 'catalog':
        return PreviewContentType.catalog;
      case 'album':
        return PreviewContentType.album;
      case 'artist':
        return PreviewContentType.artist;
      case 'playlist':
        return PreviewContentType.playlist;
      case 'track':
        return PreviewContentType.track;
      default:
        throw Exception('Invalid PreviewContentType value: $value');
    }
  }

  static PreviewContentType fromBrowseType(BrowseType type) {
    switch (type) {
      case BrowseType.album:
        return PreviewContentType.album;
      case BrowseType.artist:
        return PreviewContentType.artist;
      case BrowseType.playlist:
        return PreviewContentType.playlist;
      case BrowseType.catalog:
        return PreviewContentType.catalog;
      case BrowseType.track:
        return PreviewContentType.track;
      default:
        return PreviewContentType.unknown;
    }
  }

  static PreviewContentType fromSearchType(SearchType type) {
    switch (type) {
      case SearchType.album:
        return PreviewContentType.album;
      case SearchType.artist:
        return PreviewContentType.artist;
      case SearchType.playlist:
        return PreviewContentType.playlist;
      case SearchType.track:
        return PreviewContentType.track;
      default:
        return PreviewContentType.unknown; // Default for invalid search type
    }
  }
}

class Preview {
  final int? itemsCount;
  final PreviewType type;
  final PreviewContentType? contentType;

  /// Semantic icon id for the section header (e.g. "best_match",
  /// "ai_suggestions", "album", "artist"); mapped to a concrete icon by the UI.
  final String? icon;
  final int? rowsCount;
  final CardSize? cardSize;

  Preview({
    this.itemsCount,
    required this.type,
    this.contentType,
    this.icon,
    this.rowsCount,
    this.cardSize,
  });

  factory Preview.fromJson(Map<String, dynamic> json) => Preview(
    itemsCount: json["items_count"],
    type: PreviewTypeExtension.fromValue(json["type"]),
    contentType: json["content_type"] == null
        ? null
        : PreviewContentTypeExtension.fromValue(json["content_type"]),
    icon: json["icon"],
    rowsCount: json["rows_count"],
    cardSize: json["card_size"] == null
        ? null
        : CardSizeExtension.fromValue(json["card_size"]),
  );

  Map<String, dynamic> toJson() => {
    "items_count": itemsCount,
    "type": type.toValue(),
    "content_type": contentType?.toValue(),
    "icon": icon,
    "rows_count": rowsCount,
    "card_size": cardSize?.toValue(),
  };

  Preview copyWith({
    int? itemsCount,
    PreviewType? type,
    PreviewContentType? contentType,
    String? icon,
    int? rowsCount,
    CardSize? cardSize,
  }) {
    return Preview(
      itemsCount: itemsCount ?? this.itemsCount,
      type: type ?? this.type,
      contentType: contentType ?? this.contentType,
      icon: icon ?? this.icon,
      rowsCount: rowsCount ?? this.rowsCount,
      cardSize: cardSize ?? this.cardSize,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Preview &&
        other.itemsCount == itemsCount &&
        other.type == type &&
        other.contentType == contentType &&
        other.icon == icon &&
        other.rowsCount == rowsCount &&
        other.cardSize == cardSize;
  }

  @override
  int get hashCode =>
      Object.hash(itemsCount, type, contentType, icon, rowsCount, cardSize);
}

enum CatalogRole { featured, discovery, library, indexNode, hideOnHome }

extension CatalogRoleExtension on CatalogRole {
  String toValue() {
    switch (this) {
      case CatalogRole.featured:
        return 'featured';
      case CatalogRole.discovery:
        return 'discovery';
      case CatalogRole.library:
        return 'library';
      case CatalogRole.indexNode:
        return 'index';
      case CatalogRole.hideOnHome:
        return 'hide_on_home';
    }
  }

  static CatalogRole? fromValue(String? value) {
    switch (value) {
      case 'featured':
        return CatalogRole.featured;
      case 'discovery':
        return CatalogRole.discovery;
      case 'library':
        return CatalogRole.library;
      case 'index':
        return CatalogRole.indexNode;
      case 'hide_on_home':
        return CatalogRole.hideOnHome;
      default:
        return null;
    }
  }
}

class Catalog {
  final String id;
  final String title;
  final AlbumImage? image;
  final String? description;

  /// The fields this catalog can be filtered by, declared by its source.
  /// Empty means it offers no filtering; a field absent here must never be
  /// sent, because the module answers such a request with 422.
  final List<FilterSpec> filters;

  final Preview? previewConfig;
  final CatalogRole? role;

  /// Source name(s) whose entities this catalog holds — one for a per-source
  /// section, several for a cross-source one (e.g. Related Albums), empty when
  /// not applicable.
  final List<String> sources;

  Catalog({
    required this.id,
    required this.title,
    this.filters = const [],
    this.image,
    this.description,
    this.previewConfig,
    this.role,
    this.sources = const [],
  });

  static final empty = Catalog(
    id: '',
    title: '',
    filters: const [],
    image: null,
    description: null,
    previewConfig: null,
    role: null,
    sources: const [],
  );

  factory Catalog.fromJson(Map<String, dynamic> json) => Catalog(
    id: json["id"],
    title: unescapeHtml(json["title"]),
    image: json["image"] == null ? null : AlbumImage.fromJson(json["image"]),
    description: json["description"],
    filters: FilterSpec.parseList(json["filters"]),
    previewConfig: json["preview_config"] == null
        ? null
        : Preview.fromJson(json["preview_config"]),
    role: CatalogRoleExtension.fromValue(json["role"] as String?),
    sources: json["sources"] == null
        ? const []
        : List<String>.from(json["sources"]),
  );

  Map<String, dynamic> toJson() => {
    "id": id,
    "title": title,
    "image": image?.toJson(),
    "description": description,
    "filters": filters.map((x) => x.toJson()).toList(),
    "preview_config": previewConfig?.toJson(),
    "role": role?.toValue(),
    "sources": sources,
  };

  Catalog copyWith({
    String? id,
    String? title,
    AlbumImage? image,
    String? description,
    List<FilterSpec>? filters,
    Preview? previewConfig,
    CatalogRole? role,
    List<String>? sources,
  }) {
    return Catalog(
      id: id ?? this.id,
      title: title ?? this.title,
      image: image ?? this.image,
      description: description ?? this.description,
      filters: filters ?? this.filters,
      previewConfig: previewConfig ?? this.previewConfig,
      role: role ?? this.role,
      sources: sources ?? this.sources,
    );
  }
}

class BrowseItemsList {
  int offset;
  int limit;
  int total;
  List<BrowseItem> items;

  BrowseItemsList(this.offset, this.limit, this.total, this.items);

  factory BrowseItemsList.fromJson(Map<String, dynamic> json) =>
      BrowseItemsList(
        json["offset"],
        json["limit"],
        json["total"],
        List<BrowseItem>.from(json["items"].map((x) => BrowseItem.fromJson(x))),
      );

  factory BrowseItemsList.empty() => BrowseItemsList(0, 0, 0, []);
}

class TrackList {
  int offset;
  int limit;
  int total;
  List<Track> items;

  TrackList(this.offset, this.limit, this.total, this.items);

  factory TrackList.fromJson(Map<String, dynamic> json) => TrackList(
    json["offset"],
    json["limit"],
    json["total"],
    List<Track>.from(json["items"].map((x) => Track.fromJson(x))),
  );

  Map<String, dynamic> toJson() => {
    "offset": offset,
    "limit": limit,
    "total": total,
    "items": List<dynamic>.from(items.map((x) => x.toJson())),
  };
}

enum EntityType { catalog, album, artist, playlist, track, label, genre, user }

extension EntityTypeExtension on EntityType {
  String toValue() {
    switch (this) {
      case EntityType.catalog:
        return 'catalog';
      case EntityType.album:
        return 'album';
      case EntityType.artist:
        return 'artist';
      case EntityType.playlist:
        return 'playlist';
      case EntityType.track:
        return 'track';
      case EntityType.label:
        return 'label';
      case EntityType.genre:
        return 'genre';
      case EntityType.user:
        return 'user';
    }
  }

  static EntityType fromValue(String value) {
    switch (value) {
      case 'catalog':
        return EntityType.catalog;
      case 'album':
        return EntityType.album;
      case 'artist':
        return EntityType.artist;
      case 'playlist':
        return EntityType.playlist;
      case 'track':
        return EntityType.track;
      case 'label':
        return EntityType.label;
      case 'genre':
        return EntityType.genre;
      case 'user':
        return EntityType.user;
      default:
        throw Exception('Invalid EntityType value: $value');
    }
  }
}

class EntityId {
  final String id;
  final EntityType type;
  final String source;

  EntityId({required this.id, required this.type, required this.source});

  factory EntityId.fromString(String fullId) {
    final parts = fullId.split(':');
    if (parts.length != 4 || parts[0] != 'kalinka') {
      throw Exception('Invalid full_id format: $fullId');
    }
    return EntityId(
      id: parts[3],
      type: EntityTypeExtension.fromValue(parts[2]),
      source: parts[1],
    );
  }
}

/// How closely a search hit's name answers the query, best first — the order
/// hits from several sources merge in, without the app ranking anything.
enum MatchTier { exact, equivalent, close, partial, contextual, weak }

/// Why a search hit stands where it does in its listing, as the server's name
/// ranking decided it.
class NameMatch {
  final MatchTier tier;

  /// Whole-string similarity to the query, 0..100. Orders hits within a tier
  /// and means nothing across tiers.
  final double score;

  const NameMatch({required this.tier, required this.score});

  /// Null for a tier this build does not know: such a hit merges last rather
  /// than somewhere made up.
  static NameMatch? tryFromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final tier = MatchTier.values.asNameMap()[json["tier"]];
    if (tier == null) return null;
    return NameMatch(tier: tier, score: (json["score"] as num).toDouble());
  }

  Map<String, dynamic> toJson() => {"tier": tier.name, "score": score};
}

class BrowseItem {
  final String id;
  final String? name;
  final String? subname;
  final bool canBrowse;
  final bool canAdd;

  /// The server accepts writes that change what this item holds — a
  /// collection's tracks, or which collections exist. Advisory: it lets a
  /// client offer editing without knowing which source owns the item, and the
  /// write API is the authority.
  final bool canEdit;
  final int timestamp;

  final Track? track;
  final Album? album;
  final Artist? artist;
  final Playlist? playlist;
  final Catalog? catalog;

  /// How this item answers the query it was searched for; only a search
  /// hit carries one.
  final NameMatch? match;
  final List<BrowseItem>? sections;

  const BrowseItem({
    required this.id,
    this.name,
    this.subname,
    required this.canBrowse,
    required this.canAdd,
    this.canEdit = false,
    this.timestamp = 0,
    this.track,
    this.album,
    this.artist,
    this.playlist,
    this.catalog,
    this.match,
    this.sections,
  });

  static final empty = BrowseItem(
    id: '',
    name: null,
    subname: null,
    canBrowse: false,
    canAdd: false,
    timestamp: 0,
    track: null,
    album: null,
    artist: null,
    playlist: null,
    catalog: null,
    sections: null,
  );

  BrowseItem copyWith({
    String? id,
    String? name,
    String? subname,
    bool? canBrowse,
    bool? canAdd,
    bool? canEdit,
    int? timestamp,
    Track? track,
    Album? album,
    Artist? artist,
    Playlist? playlist,
    Catalog? catalog,
    List<BrowseItem>? sections,
  }) {
    return BrowseItem(
      id: id ?? this.id,
      name: name ?? this.name,
      subname: subname ?? this.subname,
      canBrowse: canBrowse ?? this.canBrowse,
      canAdd: canAdd ?? this.canAdd,
      canEdit: canEdit ?? this.canEdit,
      timestamp: timestamp ?? this.timestamp,
      track: track ?? this.track,
      album: album ?? this.album,
      artist: artist ?? this.artist,
      playlist: playlist ?? this.playlist,
      catalog: catalog ?? this.catalog,
      sections: sections ?? this.sections,
    );
  }

  AlbumImage? get image {
    if (album != null) {
      return album?.image;
    } else if (artist != null) {
      return artist?.image;
    } else if (playlist != null) {
      return playlist?.image;
    } else if (catalog != null) {
      return catalog?.image;
    } else if (track != null) {
      return track?.album?.image;
    }
    return null;
  }

  int? get duration {
    if (track != null) {
      return track?.duration;
    } else if (album != null) {
      return album?.duration;
    }
    return null;
  }

  int? get trackCount {
    if (album != null) {
      return album?.trackCount;
    } else if (playlist != null) {
      return playlist?.trackCount;
    }
    return null;
  }

  bool get canFavorite {
    return album != null || track != null || artist != null || playlist != null;
  }

  BrowseType get browseType {
    if (album != null) {
      return BrowseType.album;
    } else if (artist != null) {
      return BrowseType.artist;
    } else if (playlist != null) {
      return BrowseType.playlist;
    } else if (catalog != null) {
      return BrowseType.catalog;
    } else if (track != null) {
      return BrowseType.track;
    }
    return BrowseType.unknown;
  }

  String? get description {
    if (catalog != null) {
      return catalog?.description;
    } else if (playlist != null) {
      return playlist?.description;
    }

    return null;
  }

  factory BrowseItem.fromJson(Map<String, dynamic> json) => BrowseItem(
    id: json["id"],
    name: unescapeHtmlOrNull(json["name"]),
    subname: unescapeHtmlOrNull(json["subname"]),
    canBrowse: json["can_browse"],
    canAdd: json["can_add"],
    canEdit: json["can_edit"] ?? false,
    timestamp: json["timestamp"] ?? 0,
    track: json["track"] == null ? null : Track.fromJson(json["track"]),
    album: json["album"] == null ? null : Album.fromJson(json["album"]),
    artist: json["artist"] == null ? null : Artist.fromJson(json["artist"]),
    playlist: json["playlist"] == null
        ? null
        : Playlist.fromJson(json["playlist"]),
    catalog: json["catalog"] == null ? null : Catalog.fromJson(json["catalog"]),
    match: NameMatch.tryFromJson(json["match"]),
    sections: json["sections"] == null
        ? null
        : List<BrowseItem>.from(
            json["sections"].map((x) => BrowseItem.fromJson(x)),
          ),
  );

  Map<String, dynamic> toJson() => {
    "id": id,
    "name": name,
    "subname": subname,
    "can_browse": canBrowse,
    "can_add": canAdd,
    "can_edit": canEdit,
    "timestamp": timestamp,
    "track": track?.toJson(),
    "album": album?.toJson(),
    "artist": artist?.toJson(),
    "playlist": playlist?.toJson(),
    "catalog": catalog?.toJson(),
    "match": match?.toJson(),
    "sections": sections == null
        ? null
        : List<dynamic>.from(sections!.map((x) => x.toJson())),
  };
}

enum SearchType { invalid, track, album, artist, playlist }

extension SearchTypeExtension on SearchType {
  String toStringValue() {
    switch (this) {
      case SearchType.track:
        return 'track';
      case SearchType.album:
        return 'album';
      case SearchType.artist:
        return 'artist';
      case SearchType.playlist:
        return 'playlist';
      default:
        throw Exception('Invalid SearchType');
    }
  }

  static SearchType fromStringValue(String value) {
    switch (value) {
      case 'track':
        return SearchType.track;
      case 'album':
        return SearchType.album;
      case 'artist':
        return SearchType.artist;
      case 'playlist':
        return SearchType.playlist;
      default:
        throw Exception('Invalid SearchType value: $value');
    }
  }

  static SearchType fromBrowseType(BrowseType value) {
    switch (value) {
      case BrowseType.track:
        return SearchType.track;
      case BrowseType.album:
        return SearchType.album;
      case BrowseType.artist:
        return SearchType.artist;
      case BrowseType.playlist:
        return SearchType.playlist;
      default:
        throw Exception('Invalid SearchType value: $value');
    }
  }
}

class Volume {
  final int maxVolume;
  int currentVolume;

  Volume({this.maxVolume = 0, this.currentVolume = 0});

  factory Volume.fromJson(Map<String, dynamic> json) => Volume(
    maxVolume: json["max_volume"],
    currentVolume: json["current_volume"],
  );

  Map<String, dynamic> toJson() => {
    "max_volume": maxVolume,
    "current_volume": currentVolume,
  };
}

class FavoriteIds {
  List<String> albums;
  List<String> tracks;
  List<String> artists;
  List<String> playlists;

  FavoriteIds({
    required this.albums,
    required this.tracks,
    required this.artists,
    required this.playlists,
  });

  factory FavoriteIds.fromJson(Map<String, dynamic> json) => FavoriteIds(
    albums: json["albums"] == null
        ? []
        : List<String>.from(json["albums"]!.map((x) => x)),
    tracks: json["tracks"] == null
        ? []
        : List<String>.from(json["tracks"]!.map((x) => x)),
    artists: json["artists"] == null
        ? []
        : List<String>.from(json["artists"]!.map((x) => x)),
    playlists: json["playlists"] == null
        ? []
        : List<String>.from(json["playlists"]!.map((x) => x)),
  );

  Map<String, dynamic> toJson() => {
    "albums": List<dynamic>.from(albums.map((x) => x)),
    "tracks": List<dynamic>.from(tracks.map((x) => x)),
    "artists": List<dynamic>.from(artists.map((x) => x)),
    "playlists": List<dynamic>.from(playlists.map((x) => x)),
  };
}

class Genre {
  final String id;
  final String name;

  const Genre({required this.id, required this.name});

  factory Genre.fromJson(Map<String, dynamic> json) =>
      Genre(id: json["id"], name: json["name"]);

  Map<String, dynamic> toJson() => {"id": id, "name": name};
}

/// Which selector shape a filter field takes. The set is closed; the field
/// ids that use them are not.
///
/// [choice] is the wire's `values` — Dart reserves that name on an enum. The
/// contract also has a `range` kind, which no source declares yet and this app
/// therefore does not draw: [FilterSpec.parseList] drops a spec carrying it
/// rather than rendering an empty gap.
enum FilterKind {
  text,
  choice;

  static const _wireNames = {
    "text": FilterKind.text,
    "values": FilterKind.choice,
  };

  static FilterKind? fromWire(Object? name) => _wireNames[name];

  String get wireName =>
      _wireNames.entries.firstWhere((entry) => entry.value == this).key;
}

/// How a source combines several values of one field. It is the source's
/// answer, not the UI's assumption: Qobuz unions its genre ids, Jamendo
/// intersects its tags.
enum FilterOp { any, all, none }

/// One field a catalog can be filtered by.
class FilterSpec {
  final String id;
  final FilterKind kind;

  /// Shown above the control. For a text field this is also where the source
  /// says what it matches ("Search track names").
  final String label;

  /// [FilterKind.choice] only — the combinations this source honours.
  final List<FilterOp> ops;

  const FilterSpec({
    required this.id,
    required this.kind,
    required this.label,
    this.ops = const [],
  });

  /// The operation to send for a multi-value selection. A source that offers
  /// several is asked for a union, the reading a chip row implies.
  FilterOp get defaultOp => ops.contains(FilterOp.any)
      ? FilterOp.any
      : (ops.firstOrNull ?? FilterOp.any);

  /// Every spec this build can render, skipping any whose kind or operations
  /// it does not know. A control it cannot draw would hide a filter the source
  /// offers, so an older app shows fewer fields rather than a broken one.
  static List<FilterSpec> parseList(dynamic json) {
    if (json is! List) return const [];
    return json
        .map((entry) => tryFromJson(entry as Map<String, dynamic>))
        .whereType<FilterSpec>()
        .toList();
  }

  static FilterSpec? tryFromJson(Map<String, dynamic> json) {
    final kind = FilterKind.fromWire(json["kind"]);
    if (kind == null) return null;

    return FilterSpec(
      id: json["id"],
      kind: kind,
      label: json["label"] ?? json["id"],
      ops: json["ops"] == null
          ? const []
          : List<FilterOp>.from(
              (json["ops"] as List)
                  .map((x) => FilterOp.values.asNameMap()[x])
                  .whereType<FilterOp>(),
            ),
    );
  }

  Map<String, dynamic> toJson() => {
    "id": id,
    "kind": kind.wireName,
    "label": label,
    "ops": ops.map((op) => op.name).toList(),
  };
}

/// One entry of a values field's vocabulary.
class FilterValue {
  final String id;
  final String name;

  /// How many items the value covers, where the source can say.
  final int? count;

  const FilterValue({required this.id, required this.name, this.count});

  factory FilterValue.fromJson(Map<String, dynamic> json) => FilterValue(
    id: json["id"],
    name: json["name"],
    count: (json["count"] as num?)?.toInt(),
  );

  Map<String, dynamic> toJson() => {"id": id, "name": name, "count": count};
}

class FilterValueList {
  final int offset;
  final int limit;
  final int total;
  final List<FilterValue> items;

  const FilterValueList({
    required this.offset,
    required this.limit,
    required this.total,
    required this.items,
  });

  factory FilterValueList.fromJson(Map<String, dynamic> json) =>
      FilterValueList(
        offset: json["offset"],
        limit: json["limit"],
        total: json["total"],
        items: json["items"] == null
            ? const []
            : List<FilterValue>.from(
                json["items"]!.map((x) => FilterValue.fromJson(x)),
              ),
      );

  Map<String, dynamic> toJson() => {
    "offset": offset,
    "limit": limit,
    "total": total,
    "items": items.map((x) => x.toJson()).toList(),
  };
}

class StatusMessage {
  final String? message;

  /// Tracks the server acted on, when reported (`/queue/add` returns this after
  /// expanding albums/playlists).
  final int? count;

  StatusMessage({this.message, this.count});

  factory StatusMessage.fromJson(Map<String, dynamic> json) => StatusMessage(
    message: json["message"],
    count: (json["count"] as num?)?.toInt(),
  );

  Map<String, dynamic> toJson() => {"message": message, "count": count};
}

class SeekStatusMessage extends StatusMessage {
  final int? positionMs;

  SeekStatusMessage({this.positionMs, super.message});

  factory SeekStatusMessage.fromJson(Map<String, dynamic> json) =>
      SeekStatusMessage(
        positionMs: json["position_ms"],
        message: json["message"],
      );

  @override
  Map<String, dynamic> toJson() => {
    "position_ms": positionMs,
    "message": message,
  };
}

/// Server-reported health of a plugin.
///
/// `warning` means the plugin is enabled and partially functional but one
/// or more internal sub-features have failed (e.g. an optional package
/// isn't installed). `message` carries the human-readable reason.
enum ModuleState { ready, warning, disabled, error }

class ModuleStateExtension {
  static String toValue(ModuleState state) {
    switch (state) {
      case ModuleState.ready:
        return 'ready';
      case ModuleState.warning:
        return 'warning';
      case ModuleState.disabled:
        return 'disabled';
      case ModuleState.error:
        return 'error';
    }
  }

  static ModuleState fromValue(String value) {
    switch (value) {
      case 'ready':
        return ModuleState.ready;
      case 'warning':
        return ModuleState.warning;
      case 'disabled':
        return ModuleState.disabled;
      case 'error':
        return ModuleState.error;
      default:
        throw Exception('Invalid ModuleState value: $value');
    }
  }
}

/// Capability names as the server spells them, for [ModuleInfo.can].
abstract final class ModuleCapability {
  /// Natural-language search over the source's own audio — the `/ai_search`
  /// leg. A source without it has nothing of its own to suggest, so asking
  /// would only buy an empty answer and a row that waits for it.
  static const aiSearch = 'ai_search';
}

class ModuleInfo {
  final String name;
  final String title;

  /// The material icon name the module's config declares for it, drawn on
  /// its badge in place of its letter; null where it declares none.
  final String? icon;
  final bool enabled;
  final ModuleState state;

  /// Human-readable summary of *why* the module is in [state]. Plain
  /// markdown (currently `**bold**` and `` `code` ``); render via
  /// the inline-markdown helpers in `widgets/inline_markdown.dart`.
  final String? message;

  /// Optional-package keys this module would benefit from but cannot
  /// currently import. Pass these straight to `restartServer(install: …)`
  /// to queue a bootstrap-time install on next restart.
  final List<String> missingPackages;

  /// Provided by the server itself rather than a plugin — collections. Has no
  /// config, no packages, and is the user's own, so it goes unbadged like the
  /// local library and its shelves are not catalogs to explore.
  final bool builtin;

  /// The optional calls this source answers, by name — `ai_search` so far.
  /// Browsing and matching a name are what make a source a source and are
  /// not listed. Read it to decide what to ask for rather than asking and
  /// reading an empty answer.
  final List<String> capabilities;

  ModuleInfo({
    required this.name,
    required this.title,
    this.icon,
    required this.enabled,
    required this.state,
    this.message,
    this.missingPackages = const [],
    this.builtin = false,
    this.capabilities = const [],
  });

  bool can(String capability) => capabilities.contains(capability);

  factory ModuleInfo.fromJson(Map<String, dynamic> json) => ModuleInfo(
    name: json["name"],
    title: json["title"],
    icon: json["icon"] as String?,
    enabled: json["enabled"],
    state: ModuleStateExtension.fromValue(json["state"]),
    message: json["error_message"] as String?,
    missingPackages:
        (json["missing_packages"] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const [],
    builtin: json["builtin"] ?? false,
    capabilities:
        (json["capabilities"] as List?)?.map((e) => e.toString()).toList() ??
        const [],
  );

  Map<String, dynamic> toJson() => {
    "name": name,
    "title": title,
    if (icon != null) "icon": icon,
    "enabled": enabled,
    "state": ModuleStateExtension.toValue(state),
    if (message != null) "error_message": message,
    "missing_packages": missingPackages,
    "builtin": builtin,
    "capabilities": capabilities,
  };
}

class ModulesAndDevices {
  final List<ModuleInfo> inputModules;
  final List<ModuleInfo> devices;

  ModulesAndDevices({required this.inputModules, required this.devices});

  factory ModulesAndDevices.fromJson(Map<String, dynamic> json) =>
      ModulesAndDevices(
        inputModules: json["input_modules"] == null
            ? []
            : List<ModuleInfo>.from(
                json["input_modules"].map((x) => ModuleInfo.fromJson(x)),
              ),
        devices: json["devices"] == null
            ? []
            : List<ModuleInfo>.from(
                json["devices"].map((x) => ModuleInfo.fromJson(x)),
              ),
      );

  Map<String, dynamic> toJson() => {
    "input_modules": List<dynamic>.from(inputModules.map((x) => x.toJson())),
    "devices": List<dynamic>.from(devices.map((x) => x.toJson())),
  };

  ModulesAndDevices copyWith({
    List<ModuleInfo>? inputModules,
    List<ModuleInfo>? devices,
  }) {
    ModuleInfo clone(ModuleInfo m) => ModuleInfo(
      name: m.name,
      title: m.title,
      icon: m.icon,
      enabled: m.enabled,
      state: m.state,
      message: m.message,
      missingPackages: List<String>.from(m.missingPackages),
      builtin: m.builtin,
      capabilities: List<String>.from(m.capabilities),
    );
    return ModulesAndDevices(
      inputModules: (inputModules ?? this.inputModules).map(clone).toList(),
      devices: (devices ?? this.devices).map(clone).toList(),
    );
  }
}

class StageStatus {
  final int total;
  final int done;
  final int pending;
  final int inProgress;
  final int failed;
  final double coveragePct;

  const StageStatus({
    required this.total,
    required this.done,
    required this.pending,
    required this.inProgress,
    required this.failed,
    required this.coveragePct,
  });

  factory StageStatus.fromJson(Map<String, dynamic> json) => StageStatus(
    total: (json['total'] ?? 0) as int,
    done: (json['done'] ?? 0) as int,
    pending: (json['pending'] ?? 0) as int,
    inProgress: (json['in_progress'] ?? 0) as int,
    failed: (json['failed'] ?? 0) as int,
    coveragePct: ((json['coverage_pct'] ?? 0) as num).toDouble(),
  );
}

class IndexerStatus {
  final Map<String, Map<String, StageStatus>> modules;

  const IndexerStatus(this.modules);

  factory IndexerStatus.fromJson(Map<String, dynamic> json) => IndexerStatus({
    for (final m in json.entries)
      m.key: {
        for (final s in (m.value as Map).entries)
          s.key as String: StageStatus.fromJson(
            Map<String, dynamic>.from(s.value as Map),
          ),
      },
  });
}

/// One ready-to-run AI search query from `/ai_search/suggestions`, matched to
/// the current moment (time of day, in-window holidays) and validated against
/// the local library on the server side.
class SearchSuggestion {
  final String query;

  /// Context that produced it: a daypart ("morning", "evening", …) or
  /// `holiday:<name>`.
  final String context;

  /// True when the suggestion is NOT validated against the library — the
  /// server's per-response serendipity slot.
  final bool experimental;

  const SearchSuggestion({
    required this.query,
    this.context = '',
    this.experimental = false,
  });

  factory SearchSuggestion.fromJson(Map<String, dynamic> json) =>
      SearchSuggestion(
        query: (json['query'] ?? '') as String,
        context: (json['context'] ?? '') as String,
        experimental: (json['experimental'] ?? false) as bool,
      );
}

/// Response of `/ai_search/suggestions`.
class SearchSuggestionList {
  final List<SearchSuggestion> suggestions;

  /// True when the non-experimental entries reflect a completed validation
  /// run against the library (false on a cold server or an unindexed one).
  final bool attested;

  const SearchSuggestionList({
    required this.suggestions,
    this.attested = false,
  });

  factory SearchSuggestionList.fromJson(Map<String, dynamic> json) =>
      SearchSuggestionList(
        suggestions: [
          for (final s in (json['suggestions'] ?? const []) as List)
            SearchSuggestion.fromJson(Map<String, dynamic>.from(s as Map)),
        ],
        attested: (json['attested'] ?? false) as bool,
      );
}

/// One playback endpoint known to the server, from `/renderer/list`.
class RendererInfo {
  /// Stable id — what `PUT /renderer/active` takes. Never the name.
  final String rendererId;
  final String friendlyName;

  /// `connected` while the renderer holds a live socket; `offline` for one
  /// that dropped and hasn't been reaped yet.
  final String status;

  /// True for the renderer playback actually runs on — the pinned one while
  /// it is connected, otherwise the first connected.
  final bool active;

  /// True for the renderer pinned by `PUT /renderer/active`. No renderer
  /// carries it while selection is automatic.
  final bool selected;

  /// Host the renderer runs on, from its `platform` block. Empty when the
  /// renderer reported none — it's what tells two outputs apart when their
  /// friendly names don't.
  final String hostname;

  /// The renderer build's own version, or empty for one that reported none.
  final String softwareVersion;

  /// Audio backend it plays through (`alsa`, `pipewire`, …), or empty.
  final String audioBackend;

  /// `native` for a device renderer, `web` for a browser one.
  final String kind;

  /// False when the server speaks no protocol version this renderer does. It
  /// stays listed — that listing is the handle on it — but it cannot play or
  /// be configured until one side is upgraded.
  final bool compatible;

  /// True when a published release would bring this renderer forward and it
  /// can install one — the two conditions for offering the upgrade button.
  final bool updateAvailable;

  const RendererInfo({
    required this.rendererId,
    required this.friendlyName,
    required this.status,
    this.active = false,
    this.selected = false,
    this.hostname = '',
    this.softwareVersion = '',
    this.audioBackend = '',
    this.kind = '',
    this.compatible = true,
    this.updateAvailable = false,
  });

  bool get isConnected => status == 'connected';

  RendererInfo copyWith({bool? active, bool? selected}) => RendererInfo(
    rendererId: rendererId,
    friendlyName: friendlyName,
    status: status,
    active: active ?? this.active,
    selected: selected ?? this.selected,
    hostname: hostname,
    softwareVersion: softwareVersion,
    audioBackend: audioBackend,
    kind: kind,
    compatible: compatible,
    updateAvailable: updateAvailable,
  );

  factory RendererInfo.fromJson(Map<String, dynamic> json) {
    final platform = json['platform'] is Map
        ? Map<String, dynamic>.from(json['platform'] as Map)
        : const <String, dynamic>{};
    return RendererInfo(
      rendererId: (json['renderer_id'] ?? '') as String,
      friendlyName: (json['friendly_name'] ?? '') as String,
      status: (json['status'] ?? 'offline') as String,
      active: (json['active'] ?? false) as bool,
      selected: (json['selected'] ?? false) as bool,
      hostname: platform['hostname']?.toString() ?? '',
      softwareVersion: (json['software_version'] ?? '') as String,
      audioBackend: platform['audio_backend']?.toString() ?? '',
      kind: (json['kind'] ?? '') as String,
      compatible: (json['compatible'] ?? true) as bool,
      updateAvailable: (json['update_available'] ?? false) as bool,
    );
  }
}
