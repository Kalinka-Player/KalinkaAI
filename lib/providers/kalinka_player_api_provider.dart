import 'dart:async' show Timer;
import 'dart:convert' show jsonEncode;

import 'package:dio/dio.dart'
    show BaseOptions, Dio, DioException, Headers, Options, Response;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/connection_settings_provider.dart'
    show connectionSettingsProvider;
import '../data_model/data_model.dart'
    show
        BrowseItem,
        BrowseItemsList,
        DeviceVolume,
        FavoriteIds,
        FilterValueList,
        IndexerStatus,
        ModulesAndDevices,
        Playlist,
        RendererInfo,
        SearchSuggestionList,
        SearchType,
        SearchTypeExtension,
        SeekStatusMessage,
        StatusMessage,
        TrackList;
import '../data_model/presentation_schema.dart'
    show ConfigIssue, PresentationSchema;
import '../data_model/renderer_config.dart'
    show RendererConfigResult, RendererConfigSnapshot;
import '../utils/renderer_fault_text.dart' show rendererSwitchRefusal;

/// A collection was written to between an edit being staged and being sent,
/// so the server refused the whole edit rather than apply it to a list the
/// user was no longer looking at.
class CollectionChangedException implements Exception {
  final String collectionId;

  const CollectionChangedException(this.collectionId);

  @override
  String toString() => 'Collection $collectionId changed since it was read';
}

abstract class KalinkaPlayerProxy {
  Future<StatusMessage> play([int? index]);
  Future<StatusMessage> next();
  Future<StatusMessage> previous();
  Future<StatusMessage> add(List<String> items, {int? index});
  Future<StatusMessage> remove(int index);
  Future<StatusMessage> move(int fromIndex, int toIndex);
  Future<StatusMessage> pause({bool paused = true});
  Future<StatusMessage> stop();
  Future<TrackList> listTracks({int offset = 0, int limit = 100});
  Future<StatusMessage> setPlaybackMode({
    bool? repeatOne,
    bool? repeatAll,
    bool? shuffle,
  });
  Future<BrowseItemsList> aiSearch(
    String query, {
    int offset = 0,
    int limit = 10,
    List<String>? sources,
  });

  /// Every hit the given sources return for a name, ranked as one list and
  /// annotated with why each stands where it does. Empty [sources] asks
  /// every source.
  Future<BrowseItemsList> searchMatches(String query, {List<String>? sources});

  /// Context-aware, library-validated AI search suggestions.
  /// [tzOffsetMin] is the device's UTC offset in MINUTES (east positive) so
  /// the server resolves "morning"/"evening" in the listener's local time;
  /// when omitted the implementation sends the device's real offset.
  Future<SearchSuggestionList> searchSuggestions({
    int count = 4,
    int? tzOffsetMin,
  });
  Future<IndexerStatus> getIndexerStatus({List<String>? sources});
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  });
  Future<BrowseItemsList> browseItem(
    BrowseItem item, {
    int offset = 0,
    int limit = 10,
    String? filter,
  });
  Future<BrowseItem> getMetadata(String id);

  /// Makes an empty collection and answers with the browse id to go to.
  /// Throws when the server refuses the name or cannot reach its file.
  Future<String> createCollection(String name, {String description = ''});

  /// Gives a collection another name. Throws when the server refuses the
  /// name, cannot reach its file, or knows no such collection.
  Future<void> renameCollection(String id, String name);

  /// Removes a collection and everything in it. Throws when it knows no such
  /// collection or cannot reach its file.
  Future<void> deleteCollection(String id);

  /// Puts [itemIds] — tracks, or anything that holds them — at the end of a
  /// collection, and answers with how many rows landed and how many it
  /// already had. The server expands a container through its own source, so
  /// a caller need not page one out first. With [keepDuplicates] a track the
  /// collection already holds lands again as its own entry rather than being
  /// counted as already there. Throws when it knows no such collection or
  /// cannot reach its file.
  Future<({int added, int alreadyThere})> addToCollection(
    String id,
    List<String> itemIds, {
    bool keepDuplicates = false,
  });

  /// Makes a collection hold exactly [itemIds] and nothing it held before,
  /// answering with what it now has and what was dropped to make room.
  /// Nothing survives to be duplicated, so [keepDuplicates] decides only
  /// whether one batch may name a track twice. Throws on the same terms as
  /// [addToCollection].
  Future<({int added, int dropped})> replaceCollection(
    String id,
    List<String> itemIds, {
    bool keepDuplicates = false,
  });

  /// Commits a staged edit in one write: drops the entries named in [remove]
  /// and lays the rest out in [order], both by entry id, answering with what
  /// went and how many of the rest the user moved. Between them the two lists
  /// must name every entry the collection held when it was read — one that
  /// has changed since throws [CollectionChangedException] rather than losing
  /// what it gained.
  Future<({int removed, int moved})> editCollection(
    String id, {
    required List<String> remove,
    required List<String> order,
  });
  Future<BrowseItemsList> getFavorite(
    SearchType queryType, {
    int offset = 0,
    int limit = 10,
    String filter = '',
  });
  Future<StatusMessage> addFavorite(String id);
  Future<StatusMessage> removeFavorite(String id);
  Future<FavoriteIds> getFavoriteIds();
  Future<void> clear();
  Future<void> setVolume(int volume);
  Future<DeviceVolume> getVolume();

  /// One page of a catalog filter field's vocabulary.
  Future<FilterValueList> getFilterValues(
    String catalogId,
    String field, {
    int offset = 0,
    int limit = 50,
    String query = '',
  });
  Future<SeekStatusMessage> seek(int positionMs);
  Future<Playlist> playlistCreate(String name, String? description);
  Future<void> playlistDelete(String playlistId);
  Future<Playlist> playlistAddTracks(String playlistId, List<String> trackIds);
  Future<BrowseItemsList> playlistUserList(int offset, int limit);

  /// Values only: `{"schema_version": ..., "values": {<flat dotted path>: value}}`.
  Future<Map<String, dynamic>> getSettings();
  Future<PresentationSchema> getSettingsSchema();

  /// `{server_version, api_version, name}` from `/server/version`.
  Future<Map<String, dynamic>> getServerVersion();

  /// Server release-update info from `GET /server/update`, or null when the
  /// server predates the endpoint (404).
  Future<Map<String, dynamic>?> getServerUpdateInfo();

  /// Ask the server to upgrade itself to [version] — the value advertised by
  /// [getServerUpdateInfo]. The server 409s if that no longer matches.
  Future<void> upgradeServer(String version);
  Future<ModulesAndDevices> listModules();

  /// PUT body: `{"schema_version": ..., "changes": {<flat dotted path>: value}}`.
  Future<void> saveSettings({
    required String schemaVersion,
    required Map<String, dynamic> changes,
  });
  Future<List<ConfigIssue>> validateSettings({
    required String schemaVersion,
    required Map<String, dynamic> changes,
  });
  Future<void> restartServer();

  /// Play a short test tone on one channel (`left` / `right`).
  ///
  /// [device] is the ALSA identifier to play through — pass the user's
  /// (possibly not yet applied) selection; the server falls back to its
  /// configured output when omitted. [rendererId] names the renderer the tone
  /// should come out of; without it the server picks the active one. Throws
  /// [TestToneUnsupportedException] when the server predates the
  /// `/server/test_tone` endpoint.
  Future<void> testTone(String channel, {String? device, String? rendererId});

  /// Playback endpoints known to the server, from `GET /renderer/list`.
  /// Throws [RenderersUnsupportedException] on a server that predates the
  /// endpoint.
  Future<List<RendererInfo>> listRenderers();

  /// This renderer's own settings — schema and values together, from
  /// `GET /renderer/{id}/config`. Not part of `/server/config`: the renderer
  /// owns them, so they are fetched from it on demand.
  Future<RendererConfigSnapshot> getRendererConfig(String rendererId);

  /// Apply renderer settings via `PUT /renderer/{id}/config`. [changes] is
  /// path → wire text. The reply says what ended up in effect, which is not
  /// always what was asked.
  Future<RendererConfigResult> updateRendererConfig(
    String rendererId,
    Map<String, String> changes,
  );

  /// Delegate [rendererId]'s volume and power to device module [module] via
  /// `PUT /renderer/{id}/volume-control`; null hands control back to the
  /// renderer itself. The module must be loaded on the server, so a freshly
  /// enabled one can only be attached after the restart that loads it.
  Future<void> setRendererVolumeControl(String rendererId, String? module);

  /// Pin playback to [rendererId] via `PUT /renderer/active`; pass null to
  /// hand selection back to the server (first connected renderer wins).
  ///
  /// Playback moves with the pin, so this can fail on the handover — the
  /// target is busy, gone, or silent. Those come back as
  /// [RendererSwitchException] with a message fit to show the user; playback
  /// stays where it was. Pass [rendererName] — the name the picker showed —
  /// so the failure can name the output the way the user just did.
  Future<void> setActiveRenderer(String? rendererId, {String? rendererName});

  /// Ask a renderer to install the latest published release of itself, via
  /// `POST /renderer/<id>/upgrade`, and return what it said it was doing.
  ///
  /// Returns once the renderer has taken the request on; it then restarts and
  /// re-registers, which is what actually reports the outcome. A refusal — it
  /// is playing, or cannot replace itself — comes back as
  /// [RendererUpgradeException] with a message fit to show the user.
  Future<String> upgradeRenderer(String rendererId);
  void close();
}

/// The connected server has no `/server/test_tone` endpoint (older build).
class TestToneUnsupportedException implements Exception {
  @override
  String toString() => 'Server does not support test tone playback';
}

/// The connected server has no `/renderer/*` endpoints (older build).
class RenderersUnsupportedException implements Exception {
  @override
  String toString() => 'Server does not support renderers';
}

/// The server refused to move playback to the requested renderer.
/// [message] is already phrased for the user.
class RendererSwitchException implements Exception {
  final String message;
  const RendererSwitchException(this.message);

  @override
  String toString() => message;
}

/// The server would not upgrade itself. [message] is already fit to show.
class ServerUpgradeException implements Exception {
  final String message;
  const ServerUpgradeException(this.message);

  @override
  String toString() => message;
}

/// A renderer could not be upgraded. [message] is already fit to show.
class RendererUpgradeException implements Exception {
  final String message;
  const RendererUpgradeException(this.message);

  @override
  String toString() => message;
}

/// A save the server refused, with its verdict per field so the page can
/// mark the rows that have to change.
class SettingsValidationException implements Exception {
  final List<ConfigIssue> issues;
  final String detail;

  const SettingsValidationException(this.issues, this.detail);

  @override
  String toString() => detail;
}

/// A renderer's settings could not be read or written. [message] is already
/// phrased for the user.
class RendererConfigException implements Exception {
  final String message;
  const RendererConfigException(this.message);

  @override
  String toString() => message;
}

class KalinkaPlayerProxyImpl implements KalinkaPlayerProxy {
  KalinkaPlayerProxyImpl({required this.client});
  final Dio client;

  @override
  Future<StatusMessage> play([int? index]) async {
    return client
        .put(
          '/queue/play',
          queryParameters: index != null ? {'index': index} : null,
        )
        .then((response) {
          return statusMessageFromResponse(response);
        });
  }

  @override
  Future<StatusMessage> next() async {
    return client.put('/queue/next').then((response) {
      return statusMessageFromResponse(response);
    });
  }

  @override
  Future<StatusMessage> previous() async {
    return client.put('/queue/prev').then((response) {
      return statusMessageFromResponse(response);
    });
  }

  @override
  Future<StatusMessage> add(List<String> items, {int? index}) async {
    return client
        .post(
          '/queue/add',
          queryParameters: index != null ? {'index': index} : null,
          data: items,
          options: Options(contentType: Headers.jsonContentType),
        )
        .then((response) {
          return statusMessageFromResponse(response);
        });
  }

  @override
  Future<StatusMessage> remove(int index) async {
    return client.post('/queue/remove', queryParameters: {'index': index}).then(
      (response) {
        return statusMessageFromResponse(response);
      },
    );
  }

  @override
  Future<StatusMessage> move(int fromIndex, int toIndex) async {
    return client
        .put(
          '/queue/move',
          queryParameters: {'from_index': fromIndex, 'to_index': toIndex},
        )
        .then((response) {
          return statusMessageFromResponse(response);
        });
  }

  @override
  Future<StatusMessage> pause({bool paused = true}) async {
    return client.put('/queue/pause', queryParameters: {'paused': paused}).then(
      (response) {
        return statusMessageFromResponse(response);
      },
    );
  }

  @override
  Future<StatusMessage> stop() async {
    return client.put('/queue/stop').then((response) {
      return statusMessageFromResponse(response);
    });
  }

  @override
  Future<TrackList> listTracks({int offset = 0, int limit = 100}) async {
    return client
        .get(
          '/queue/list',
          queryParameters: {
            'offset': offset.toString(),
            'limit': limit.toString(),
          },
        )
        .then((response) {
          if (response.statusCode != 200) {
            throw Exception('Failed to list tracks');
          }

          return TrackList.fromJson(response.data);
        });
  }

  @override
  Future<StatusMessage> setPlaybackMode({
    bool? repeatOne,
    bool? repeatAll,
    bool? shuffle,
  }) async {
    return client
        .put(
          '/queue/mode',
          queryParameters: {
            if (repeatOne != null) 'repeat_single': repeatOne,
            if (repeatAll != null) 'repeat_all': repeatAll,
            if (shuffle != null) 'shuffle': shuffle,
          },
        )
        .then((response) {
          return statusMessageFromResponse(response);
        });
  }

  @override
  Future<BrowseItemsList> aiSearch(
    String query, {
    int offset = 0,
    int limit = 10,
    List<String>? sources,
  }) async {
    return client
        .get(
          '/ai_search',
          queryParameters: {
            'query': query,
            'offset': offset.toString(),
            'limit': limit.toString(),
            if (sources != null && sources.isNotEmpty)
              'sources': sources.join(','),
          },
        )
        .then((response) {
          if (response.statusCode != 200) {
            throw Exception('Failed ai_search for "$query"');
          }
          return BrowseItemsList.fromJson(response.data);
        });
  }

  @override
  Future<BrowseItemsList> searchMatches(
    String query, {
    List<String>? sources,
  }) async {
    return client
        .get(
          '/search/matches',
          queryParameters: {
            'query': query,
            if (sources != null && sources.isNotEmpty)
              'sources': sources.join(','),
          },
        )
        .then((response) {
          if (response.statusCode != 200) {
            throw Exception('Failed to match "$query"');
          }
          return BrowseItemsList.fromJson(response.data);
        });
  }

  @override
  Future<SearchSuggestionList> searchSuggestions({
    int count = 4,
    int? tzOffsetMin,
  }) async {
    // The server resolves daypart/holiday context from this offset — send
    // the device's real UTC offset (in minutes, east positive) so "morning"
    // means the listener's morning, not the server's.
    final offset = tzOffsetMin ?? DateTime.now().timeZoneOffset.inMinutes;
    return client
        .get(
          '/ai_search/suggestions',
          queryParameters: {
            'count': count.toString(),
            'tz_offset_min': offset.toString(),
          },
        )
        .then((response) {
          if (response.statusCode != 200) {
            throw Exception(
              'Failed to fetch search suggestions: '
              'HTTP ${response.statusCode} — ${response.data}',
            );
          }
          return SearchSuggestionList.fromJson(
            Map<String, dynamic>.from(response.data as Map),
          );
        });
  }

  @override
  Future<IndexerStatus> getIndexerStatus({List<String>? sources}) async {
    return client
        .get(
          '/indexer/status',
          queryParameters: (sources != null && sources.isNotEmpty)
              ? {'sources': sources.join(',')}
              : null,
        )
        .then((response) {
          if (response.statusCode != 200) {
            throw Exception('Failed to get indexer status');
          }
          return IndexerStatus.fromJson(
            Map<String, dynamic>.from(response.data as Map),
          );
        });
  }

  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async {
    final normalizedId = id.trim();
    final endpoint = (normalizedId.isEmpty || normalizedId == 'root')
        ? '/browse'
        : '/browse/$normalizedId';

    return client
        .get(
          endpoint,
          queryParameters: {
            'offset': offset.toString(),
            'limit': limit.toString(),
            if (filter != null) 'filter': filter,
          },
        )
        .then((response) {
          if (response.statusCode != 200) {
            throw Exception('Failed to browse $id, url=${response.realUri}');
          }

          return BrowseItemsList.fromJson(response.data);
        });
  }

  @override
  Future<BrowseItemsList> browseItem(
    BrowseItem item, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) {
    if (item.canBrowse) {
      return browse(item.id, offset: offset, limit: limit, filter: filter);
    }

    return Future.value(BrowseItemsList(0, 0, 0, []));
  }

  @override
  Future<BrowseItem> getMetadata(String id) async {
    return client.get('/get/$id').then((response) {
      if (response.statusCode != 200) {
        throw Exception(
          'Failed to get metadata for $id, url=${response.realUri}',
        );
      }

      return BrowseItem.fromJson(response.data);
    });
  }

  @override
  Future<String> createCollection(
    String name, {
    String description = '',
  }) async {
    final response = await client.post(
      '/collections',
      data: {'name': name, 'description': description},
      options: Options(contentType: Headers.jsonContentType),
    );
    if (response.statusCode != 201) {
      throw Exception('Failed to create collection, url=${response.realUri}');
    }
    return response.data['id'] as String;
  }

  @override
  Future<void> renameCollection(String id, String name) async {
    final response = await client.patch(
      '/collections/$id',
      data: {'name': name},
      options: Options(contentType: Headers.jsonContentType),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to rename collection, url=${response.realUri}');
    }
  }

  @override
  Future<void> deleteCollection(String id) async {
    final response = await client.delete('/collections/$id');
    if (response.statusCode != 204) {
      throw Exception('Failed to delete collection, url=${response.realUri}');
    }
  }

  @override
  Future<({int added, int alreadyThere})> addToCollection(
    String id,
    List<String> itemIds, {
    bool keepDuplicates = false,
  }) async {
    final response = await client.post(
      '/collections/$id/entries',
      data: {'items': itemIds, 'allow_duplicates': keepDuplicates},
      options: Options(contentType: Headers.jsonContentType),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to add to collection, url=${response.realUri}');
    }
    return (
      added: response.data['added'] as int,
      alreadyThere: response.data['already_there'] as int,
    );
  }

  @override
  Future<({int added, int dropped})> replaceCollection(
    String id,
    List<String> itemIds, {
    bool keepDuplicates = false,
  }) async {
    final response = await client.put(
      '/collections/$id/entries',
      data: {'items': itemIds, 'allow_duplicates': keepDuplicates},
      options: Options(contentType: Headers.jsonContentType),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to replace collection, url=${response.realUri}');
    }
    return (
      added: response.data['added'] as int,
      dropped: response.data['dropped'] as int,
    );
  }

  @override
  Future<({int removed, int moved})> editCollection(
    String id, {
    required List<String> remove,
    required List<String> order,
  }) async {
    final Response response;
    try {
      response = await client.patch(
        '/collections/$id/entries',
        data: {'remove': remove, 'order': order},
        options: Options(contentType: Headers.jsonContentType),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) throw CollectionChangedException(id);
      rethrow;
    }
    if (response.statusCode != 200) {
      throw Exception('Failed to edit collection, url=${response.realUri}');
    }
    return (
      removed: response.data['removed'] as int,
      moved: response.data['moved'] as int,
    );
  }

  @override
  Future<BrowseItemsList> getFavorite(
    SearchType queryType, {
    int offset = 0,
    int limit = 10,
    String filter = '',
  }) async {
    return client
        .get(
          '/favorite/list/${queryType.toStringValue()}',
          queryParameters: {
            'offset': offset.toString(),
            'limit': limit.toString(),
            'filter': filter,
          },
        )
        .then((response) {
          if (response.statusCode != 200) {
            throw Exception(
              'Failed to get favorite ${queryType.toStringValue()}, url=${response.realUri}',
            );
          }

          return BrowseItemsList.fromJson(response.data);
        });
  }

  @override
  Future<StatusMessage> addFavorite(String id) async {
    return client.put('/favorite/add/$id').then((response) {
      return statusMessageFromResponse(response);
    });
  }

  @override
  Future<StatusMessage> removeFavorite(String id) async {
    return client.delete('/favorite/remove/$id').then((response) {
      return statusMessageFromResponse(response);
    });
  }

  @override
  Future<FavoriteIds> getFavoriteIds() async {
    return client.get('/favorite/ids').then((response) {
      if (response.statusCode != 200) {
        throw Exception('Failed to get favorite ids, url=${response.realUri}');
      }

      return FavoriteIds.fromJson(response.data);
    });
  }

  @override
  Future<void> clear() async {
    return client.put('/queue/clear').then((response) {
      if (response.statusCode != 200) {
        throw Exception('Failed to clear queue, url=${response.realUri}');
      }
    });
  }

  @override
  Future<void> setVolume(int volume) async {
    return client
        .put(
          '/device/set_volume',
          queryParameters: {'volume': volume.toString()},
        )
        .then((response) {
          if (response.statusCode != 200) {
            throw Exception(
              'Failed to set volume to $volume, url=${response.realUri}',
            );
          }
        });
  }

  @override
  Future<DeviceVolume> getVolume() async {
    return client.get('/device/get_volume').then((response) {
      if (response.statusCode != 200) {
        throw Exception('Failed to get volume, url=${response.realUri}');
      }
      return DeviceVolume.fromJson(response.data);
    });
  }

  @override
  Future<FilterValueList> getFilterValues(
    String catalogId,
    String field, {
    int offset = 0,
    int limit = 50,
    String query = '',
  }) async {
    return client
        .get(
          '/browse/$catalogId/filter/$field/values',
          queryParameters: {
            'offset': offset.toString(),
            'limit': limit.toString(),
            if (query.isNotEmpty) 'q': query,
          },
        )
        .then((response) {
          if (response.statusCode != 200) {
            throw Exception(
              'Failed to get $field values, url=${response.realUri}',
            );
          }
          return FilterValueList.fromJson(response.data);
        });
  }

  @override
  Future<SeekStatusMessage> seek(int positionMs) async {
    return client
        .put(
          '/queue/current_track/seek',
          queryParameters: {'position_ms': positionMs.toString()},
        )
        .then((response) {
          if (response.statusCode != 200) {
            throw Exception('Request failed, url=${response.realUri}');
          }
          return SeekStatusMessage.fromJson(response.data);
        });
  }

  @override
  Future<Playlist> playlistCreate(String name, String? description) async {
    return client
        .post(
          '/playlist/create',
          queryParameters: {
            'name': name,
            if (description != null) 'description': description,
          },
        )
        .then((response) {
          if (response.statusCode != 200) {
            throw Exception(
              'Failed to create playlist, url=${response.realUri}',
            );
          }
          return Playlist.fromJson(response.data);
        });
  }

  @override
  Future<void> playlistDelete(String playlistId) async {
    return client
        .delete(
          '/playlist/delete',
          queryParameters: {'playlist_id': playlistId},
        )
        .then((response) {
          if (response.statusCode != 200) {
            throw Exception(
              'Failed to delete playlist, url=${response.realUri}, message=${response.statusMessage}',
            );
          }
        });
  }

  @override
  Future<Playlist> playlistAddTracks(
    String playlistId,
    List<String> trackIds,
  ) async {
    return client
        .post(
          '/playlist/add_tracks',
          queryParameters: {'playlist_id': playlistId},
          data: trackIds,
          options: Options(contentType: Headers.jsonContentType),
        )
        .then((response) {
          if (response.statusCode != 200) {
            throw Exception(
              'Failed to add tracks to playlist, url=${response.realUri}',
            );
          }
          return Playlist.fromJson(response.data);
        });
  }

  @override
  Future<BrowseItemsList> playlistUserList(int offset, int limit) async {
    return client
        .get(
          '/playlist/list',
          queryParameters: {'offset': offset, 'limit': limit},
        )
        .then((response) {
          if (response.statusCode != 200) {
            throw Exception(
              'Failed to list user playlists, url=${response.realUri}',
            );
          }
          return BrowseItemsList.fromJson(response.data);
        });
  }

  @override
  Future<Map<String, dynamic>> getSettings() async {
    return client.get('/server/config').then((response) {
      if (response.statusCode != 200) {
        throw Exception('Failed to get settings, url=${response.realUri}');
      }
      return (response.data as Map).cast<String, dynamic>();
    });
  }

  @override
  Future<PresentationSchema> getSettingsSchema() async {
    final response = await client.get('/server/config/schema');
    if (response.statusCode != 200) {
      throw Exception('Failed to get settings schema, url=${response.realUri}');
    }
    return PresentationSchema.fromJson(
      (response.data as Map).cast<String, dynamic>(),
    );
  }

  @override
  Future<Map<String, dynamic>> getServerVersion() async {
    final response = await client.get('/server/version');
    if (response.statusCode != 200) {
      throw Exception('Failed to get server version, url=${response.realUri}');
    }
    return (response.data as Map).cast<String, dynamic>();
  }

  @override
  Future<Map<String, dynamic>?> getServerUpdateInfo() async {
    try {
      final response = await client.get('/server/update');
      return (response.data as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<void> upgradeServer(String version) async {
    try {
      final response = await client.put(
        '/server/upgrade',
        options: Options(contentType: Headers.jsonContentType),
        data: jsonEncode({'version': version}),
      );
      if (response.statusCode != 200) {
        throw const ServerUpgradeException(
          'The server rejected the upgrade request',
        );
      }
    } on DioException catch (e) {
      // The server's own words when it gave any: renderers being brought
      // forward first is a wait, not a failure, and only it can say so.
      final detail = e.response?.data is Map
          ? (e.response?.data['detail'] as String?)
          : null;
      throw ServerUpgradeException(
        detail?.isNotEmpty == true
            ? detail!
            : 'The server rejected the upgrade request',
      );
    }
  }

  @override
  Future<ModulesAndDevices> listModules() async {
    return client.get('/server/modules').then((response) {
      if (response.statusCode != 200) {
        throw Exception('Failed to list modules, url=${response.realUri}');
      }
      return ModulesAndDevices.fromJson(response.data);
    });
  }

  @override
  Future<void> saveSettings({
    required String schemaVersion,
    required Map<String, dynamic> changes,
  }) async {
    final String body = jsonEncode({
      'schema_version': schemaVersion,
      'changes': changes,
    });
    try {
      final response = await client.put(
        '/server/config',
        options: Options(contentType: Headers.jsonContentType),
        data: body,
      );
      if (response.statusCode != 200) {
        throw Exception(
          'Failed to save settings, status: ${response.statusCode}, body: ${response.data}',
        );
      }
    } on DioException catch (e) {
      final refusal = _refusalFrom(e.response?.data);
      if (refusal != null) throw refusal;
      rethrow;
    }
  }

  /// The per-field refusal in an error body, or null if it isn't one.
  SettingsValidationException? _refusalFrom(dynamic body) {
    if (body is! Map || body['issues'] is! List) return null;
    return SettingsValidationException(
      _issuesFrom(body['issues']),
      body['detail'] as String? ?? 'The server refused the change',
    );
  }

  static List<ConfigIssue> _issuesFrom(dynamic raw) => raw is! List
      ? const []
      : raw
            .whereType<Map>()
            .map((e) => ConfigIssue.fromJson(e.cast<String, dynamic>()))
            .toList();

  @override
  Future<List<ConfigIssue>> validateSettings({
    required String schemaVersion,
    required Map<String, dynamic> changes,
  }) async {
    final response = await client.post(
      '/server/config/validate',
      options: Options(contentType: Headers.jsonContentType),
      data: jsonEncode({'schema_version': schemaVersion, 'changes': changes}),
    );
    return _issuesFrom((response.data as Map?)?['issues']);
  }

  @override
  Future<void> restartServer() async {
    return client.put('/server/restart').then((response) {
      if (response.statusCode != 200) {
        throw Exception('Failed to restart server, url=${response.realUri}');
      }
    });
  }

  @override
  Future<void> testTone(
    String channel, {
    String? device,
    String? rendererId,
  }) async {
    try {
      final response = await client.post(
        '/server/test_tone',
        options: Options(contentType: Headers.jsonContentType),
        data: jsonEncode({
          'channel': channel,
          if (device != null && device.isNotEmpty) 'device': device,
          if (rendererId != null && rendererId.isNotEmpty)
            'renderer_id': rendererId,
        }),
      );
      if (response.statusCode != 200) {
        throw Exception('Failed to play test tone, url=${response.realUri}');
      }
    } on DioException catch (e) {
      // 404/405: endpoint not implemented by this server version.
      final status = e.response?.statusCode;
      if (status == 404 || status == 405) {
        throw TestToneUnsupportedException();
      }
      rethrow;
    }
  }

  @override
  Future<List<RendererInfo>> listRenderers() async {
    try {
      final response = await client.get('/renderer/list');
      final list = (response.data as Map)['renderers'] as List? ?? const [];
      return [
        for (final r in list)
          RendererInfo.fromJson(Map<String, dynamic>.from(r as Map)),
      ];
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 404 || status == 405) {
        throw RenderersUnsupportedException();
      }
      rethrow;
    }
  }

  @override
  Future<RendererConfigSnapshot> getRendererConfig(String rendererId) async {
    try {
      final response = await client.get('/renderer/$rendererId/config');
      return RendererConfigSnapshot.fromJson(
        (response.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw RendererConfigException(_configFailure(e));
    }
  }

  @override
  Future<RendererConfigResult> updateRendererConfig(
    String rendererId,
    Map<String, String> changes,
  ) async {
    try {
      final response = await client.put(
        '/renderer/$rendererId/config',
        options: Options(contentType: Headers.jsonContentType),
        data: jsonEncode({'changes': changes}),
      );
      return RendererConfigResult.fromJson(
        (response.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw RendererConfigException(_configFailure(e));
    }
  }

  @override
  Future<void> setRendererVolumeControl(
    String rendererId,
    String? module,
  ) async {
    try {
      await client.put(
        '/renderer/$rendererId/volume-control',
        options: Options(contentType: Headers.jsonContentType),
        data: jsonEncode({'module': module}),
      );
    } on DioException catch (e) {
      throw RendererConfigException(_configFailure(e));
    }
  }

  /// Settings travel to the renderer over its socket, so the failures are
  /// about that hop rather than about the server.
  static String _configFailure(DioException e) =>
      switch (e.response?.statusCode) {
        404 => 'That output is no longer available',
        409 => 'That output isn’t connected',
        504 => 'That output didn’t respond',
        _ => 'Couldn’t reach that output',
      };

  // A 404 here is the server rejecting an unknown renderer id, not a missing
  // endpoint — the switcher only exists once `listRenderers` has succeeded.
  @override
  Future<String> upgradeRenderer(String rendererId) async {
    try {
      final response = await client.post('/renderer/$rendererId/upgrade');
      if (response.statusCode != 200) {
        throw const RendererUpgradeException('Couldn’t start the upgrade');
      }
      return (response.data?['detail'] ?? '') as String;
    } on DioException catch (e) {
      throw RendererUpgradeException(switch (e.response?.statusCode) {
        404 => 'That output is no longer connected',
        // Both a refusal and "no release known yet"; the server's own words
        // are the only thing that tells them apart.
        409 =>
          (e.response?.data?['detail'] as String?) ??
              'That output can’t be upgraded right now',
        504 => 'That output didn’t respond',
        _ => 'Couldn’t start the upgrade',
      });
    }
  }

  @override
  Future<void> setActiveRenderer(
    String? rendererId, {
    String? rendererName,
  }) async {
    try {
      final response = await client.put(
        '/renderer/active',
        options: Options(contentType: Headers.jsonContentType),
        data: jsonEncode({'renderer_id': rendererId}),
      );
      if (response.statusCode != 200) {
        throw const RendererSwitchException('Couldn’t switch output');
      }
    } on DioException catch (e) {
      final data = e.response?.data;
      throw RendererSwitchException(
        rendererSwitchRefusal(
          status: e.response?.statusCode,
          detail: data is Map ? data['detail'] as String? : null,
          rendererId: rendererId,
          rendererName: rendererName,
        ),
      );
    }
  }

  StatusMessage statusMessageFromResponse(Response response) {
    if (response.statusCode != 200) {
      var url = response.realUri.toString();
      throw Exception('Request $url failed, url=$url');
    }
    return StatusMessage.fromJson(response.data);
  }

  @override
  Future<void> close() async {
    return client.close();
  }
}

final httpClientProvider = Provider<Dio>((ref) {
  final settings = ref.watch(connectionSettingsProvider);
  final baseUrl = settings.isSet
      ? settings.baseUrl.toString()
      : 'http://127.0.0.1:0';
  // Bound every request so a dead/blackholed route (e.g. Wi-Fi dropped while
  // backgrounded) fails fast instead of hanging forever. Without this the
  // reconnect reachability probe (listModules) could stall indefinitely,
  // stacking overlapping retry ticks and blocking escalation to `offline`.
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
    ),
  );
  return dio;
});

// The proxy instance itself (constructed once, disposed automatically)
final kalinkaProxyProvider = Provider<KalinkaPlayerProxy>((ref) {
  final httpClient = ref.watch(httpClientProvider);
  final proxy = KalinkaPlayerProxyImpl(client: httpClient);

  ref.onDispose(() async {
    await proxy.close();
  });

  // Keep alive if you navigate across screens frequently
  final link = ref.keepAlive();

  // Optional: release after some idle time
  final keepAliveTimer = Timer(const Duration(minutes: 10), link.close);
  ref.onDispose(keepAliveTimer.cancel);

  return proxy;
});
