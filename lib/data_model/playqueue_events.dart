import 'package:freezed_annotation/freezed_annotation.dart';
import '../data_model/data_model.dart';

part 'playqueue_events.freezed.dart';
part 'playqueue_events.g.dart';

// To regenerate code, run:
// dart run build_runner build --delete-conflicting-outputs

/// Custom converter for EntityId that handles string serialization
class EntityIdConverter implements JsonConverter<EntityId, String> {
  const EntityIdConverter();

  @override
  EntityId fromJson(String json) {
    return EntityId.fromString(json);
  }

  @override
  String toJson(EntityId object) {
    return 'kalinka:${object.source}:${object.type.toValue()}:${object.id}';
  }
}

/// Immutable state for a play queue.
@JsonSerializable()
class PlayQueueState {
  final PlaybackState playbackState;
  final List<Track> trackList;
  final PlaybackMode playbackMode;
  final int seq;

  /// Renderer topology as the replay reported it. Null on a server that
  /// predates the renderer events — distinct from [], which is a server
  /// saying "no renderers".
  @JsonKey(includeToJson: false)
  final List<RendererInfo>? renderers;
  @JsonKey(includeToJson: false)
  final String? currentRendererId;
  @JsonKey(includeToJson: false)
  final String? selectedRendererId;

  /// Whether the queue drives the output, or a plugin plays exclusively.
  @JsonKey(includeToJson: false, fromJson: PlaybackControl.fromJson)
  final PlaybackControl playbackControl;

  const PlayQueueState({
    required this.playbackState,
    required this.trackList,
    required this.playbackMode,
    required this.seq,
    this.renderers,
    this.currentRendererId,
    this.selectedRendererId,
    this.playbackControl = const PlaybackControl.queue(),
  });

  static final PlayQueueState empty = PlayQueueState(
    playbackState: PlaybackState.empty,
    trackList: <Track>[],
    playbackMode: PlaybackMode.empty,
    seq: 0,
  );

  PlayQueueState copyWith({
    PlaybackState? playbackState,
    List<Track>? trackList,
    PlaybackMode? playbackMode,
    required int seq,
  }) => PlayQueueState(
    playbackState: playbackState ?? this.playbackState,
    trackList: trackList ?? this.trackList,
    playbackMode: playbackMode ?? this.playbackMode,
    seq: seq,
    renderers: renderers,
    currentRendererId: currentRendererId,
    selectedRendererId: selectedRendererId,
    playbackControl: playbackControl,
  );

  /// Apply an event to produce a new state (immutable pattern).
  PlayQueueState apply(PlayQueueEvent event, int timestamp) {
    switch (event) {
      case PlaybackStateChangedEvent(:final state, :final seq):
        final nextPlaybackState = playbackState.copyWith(state)
          ..timestampNs = timestamp;
        return copyWith(
          playbackState: _normalizePlaybackIndex(
            nextPlaybackState,
            trackList.length,
          ),
          seq: seq,
        );
      case TracksAddedEvent(:final tracks, :final seq, :final index):
        final insertAt = _clampInsertionIndex(
          index ?? trackList.length,
          trackList.length,
        );
        final nextTrackList = [...trackList]..insertAll(insertAt, tracks);
        final nextPlaybackState = _remapPlaybackIndexForInsertion(
          playbackState,
          insertAt,
          tracks.length,
        );
        return copyWith(
          trackList: nextTrackList,
          playbackState: _normalizePlaybackIndex(
            nextPlaybackState,
            nextTrackList.length,
          ),
          seq: seq,
        );
      case TracksRemovedEvent(:final indices, :final seq):
        final nextTrackList = [
          for (var i = 0; i < trackList.length; i++)
            if (!indices.contains(i)) trackList[i],
        ];
        return copyWith(
          trackList: nextTrackList,
          playbackState: _normalizePlaybackIndex(
            playbackState,
            nextTrackList.length,
          ),
          seq: seq,
        );
      case PlaybackModeChangedEvent(:final mode, :final seq):
        return copyWith(playbackMode: mode, seq: seq);
      case RequestMoreTracksEvent():
        // Ignore - no state change.
        return this;
      case TrackMovedEvent(:final fromIndex, :final toIndex, :final seq):
        final list = [...trackList];
        final item = list.removeAt(fromIndex);
        list.insert(toIndex, item);
        final oldPlaybackIndex = playbackState.index ?? 0;
        final newPlaybackIndex = _remapIndex(
          oldPlaybackIndex,
          fromIndex,
          toIndex,
        );
        final newPlaybackState = newPlaybackIndex != oldPlaybackIndex
            ? playbackState.copyWithFields(index: newPlaybackIndex)
            : playbackState;
        return copyWith(
          trackList: list,
          playbackState: _normalizePlaybackIndex(newPlaybackState, list.length),
          seq: seq,
        );
      case TrackUnavailableEvent(
        :final index,
        :final unavailable,
        :final reason,
        :final seq,
      ):
        if (index < 0 || index >= trackList.length) {
          return this;
        }
        final nextTrackList = [...trackList];
        nextTrackList[index] = nextTrackList[index].copyWith(
          unavailable: unavailable,
          unavailableReason: unavailable ? reason : null,
        );
        return copyWith(trackList: nextTrackList, seq: seq);
      case PlaybackErrorEvent():
        // Ignore - no state change.
        return this;
      case RenderersChangedEvent(:final renderers, :final seq):
        return PlayQueueState(
          playbackState: playbackState,
          trackList: trackList,
          playbackMode: playbackMode,
          seq: seq,
          renderers: renderers,
          currentRendererId: currentRendererId,
          selectedRendererId: selectedRendererId,
          playbackControl: playbackControl,
        );
      case CurrentRendererChangedEvent(
        :final rendererId,
        :final selectedRendererId,
        :final seq,
      ):
        // Not copyWith: a null id here means "nothing", not "keep".
        return PlayQueueState(
          playbackState: playbackState,
          trackList: trackList,
          playbackMode: playbackMode,
          seq: seq,
          renderers: renderers,
          currentRendererId: rendererId,
          selectedRendererId: selectedRendererId,
          playbackControl: playbackControl,
        );
      case PlaybackControlChangedEvent(:final control, :final seq):
        // Back to the queue, the plugin's track goes with it; the queue's own
        // state follows and brings its track back.
        return PlayQueueState(
          playbackState: control.isExclusive
              ? playbackState
              : playbackState.withoutTrack(),
          trackList: trackList,
          playbackMode: playbackMode,
          seq: seq,
          renderers: renderers,
          currentRendererId: currentRendererId,
          selectedRendererId: selectedRendererId,
          playbackControl: control,
        );
      case ReplayPlayQueueEvent(:final state, :final serverTimeNs, :final seq):
        final nextPlaybackState =
            state.playbackState.copyWith(state.playbackState)
              ..timestampNs = timestamp
              ..position = _estimatePosition(state.playbackState, serverTimeNs);
        return PlayQueueState(
          playbackState: _normalizePlaybackIndex(
            nextPlaybackState,
            state.trackList.length,
          ),
          trackList: state.trackList,
          playbackMode: state.playbackMode,
          seq: seq,
          renderers: state.renderers,
          currentRendererId: state.currentRendererId,
          selectedRendererId: state.selectedRendererId,
          playbackControl: state.playbackControl,
        );
    }
  }

  PlaybackState _normalizePlaybackIndex(
    PlaybackState nextPlaybackState,
    int trackCount,
  ) {
    final currentIndex = nextPlaybackState.index;
    if (currentIndex == null) {
      return nextPlaybackState;
    }

    final normalizedIndex = _clampPlaybackIndex(currentIndex, trackCount);
    if (normalizedIndex == currentIndex) {
      return nextPlaybackState;
    }

    return nextPlaybackState.copyWithFields(index: normalizedIndex);
  }

  int _clampPlaybackIndex(int index, int trackCount) {
    if (trackCount <= 0) {
      return 0;
    }
    if (index < 0) {
      return 0;
    }
    final maxIndex = trackCount - 1;
    if (index > maxIndex) {
      return maxIndex;
    }
    return index;
  }

  int _clampInsertionIndex(int index, int trackCount) {
    if (index < 0) {
      return 0;
    }
    if (index > trackCount) {
      return trackCount;
    }
    return index;
  }

  PlaybackState _remapPlaybackIndexForInsertion(
    PlaybackState state,
    int insertionIndex,
    int insertedCount,
  ) {
    if (insertedCount <= 0) {
      return state;
    }

    final currentIndex = state.index;
    if (currentIndex == null || insertionIndex > currentIndex) {
      return state;
    }

    return state.copyWithFields(index: currentIndex + insertedCount);
  }

  /// Mirrors the server-side `_remap_index` logic.
  /// Returns the new position of [idx] after an item is moved from
  /// [fromIndex] to [toIndex] in the list.
  int _remapIndex(int idx, int fromIndex, int toIndex) {
    if (idx == fromIndex) return toIndex;
    if (fromIndex < toIndex) {
      // Item moved forward: everything in (fromIndex, toIndex] shifts back by 1
      if (fromIndex < idx && idx <= toIndex) return idx - 1;
    } else {
      // Item moved backward: everything in [toIndex, fromIndex) shifts forward by 1
      if (toIndex <= idx && idx < fromIndex) return idx + 1;
    }
    return idx;
  }

  int _estimatePosition(PlaybackState playbackState, int serverTimeNs) {
    if (playbackState.state == PlayerStateType.playing) {
      final delta = (serverTimeNs - playbackState.timestampNs) / 1_000_000;
      return (playbackState.position ?? 0) + delta.toInt();
    } else {
      return playbackState.position ?? 0;
    }
  }

  factory PlayQueueState.fromJson(Map<String, dynamic> json) =>
      _$PlayQueueStateFromJson(json);

  Map<String, dynamic> toJson() => _$PlayQueueStateToJson(this);
}

/// Wire event types matching PlayQueueEventType from backend.
@JsonEnum(fieldRename: FieldRename.snake, alwaysCreate: true)
enum PlayQueueEventType {
  playbackStateChanged,
  requestMoreTracks,
  tracksAdded,
  tracksRemoved,
  trackUnavailable,
  playbackError,
  playbackModeChanged,
  renderersChanged,
  currentRendererChanged,
  playbackControlChanged;

  String toJson() => _$PlayQueueEventTypeEnumMap[this]!;

  factory PlayQueueEventType.fromJson(String json) =>
      _$PlayQueueEventTypeEnumMap.map(
        (key, value) => MapEntry(value, key),
      )[json]!;
}

/// Base class for PlayQueue events with event_type and seq.
@freezed
sealed class PlayQueueEvent with _$PlayQueueEvent {
  const factory PlayQueueEvent.playbackStateChanged({
    required PlaybackState state,
    required int seq,
  }) = PlaybackStateChangedEvent;

  const factory PlayQueueEvent.requestMoreTracks({required int seq}) =
      RequestMoreTracksEvent;

  const factory PlayQueueEvent.tracksAdded({
    required List<Track> tracks,
    required int seq,
    int? index,
  }) = TracksAddedEvent;

  const factory PlayQueueEvent.tracksRemoved({
    required List<int> indices,
    required int seq,
  }) = TracksRemovedEvent;

  const factory PlayQueueEvent.trackMoved({
    required int fromIndex,
    required int toIndex,
    required int seq,
  }) = TrackMovedEvent;

  const factory PlayQueueEvent.trackUnavailable({
    required int index,
    required bool unavailable,
    required int seq,
    String? reason,
  }) = TrackUnavailableEvent;

  const factory PlayQueueEvent.playbackError({
    required String message,
    required int seq,
  }) = PlaybackErrorEvent;

  const factory PlayQueueEvent.playbackModeChanged({
    required PlaybackMode mode,
    required int seq,
  }) = PlaybackModeChangedEvent;

  const factory PlayQueueEvent.replayEvent({
    required PlayQueueState state,
    required int serverTimeNs,
    required int seq,
  }) = ReplayPlayQueueEvent;

  /// Full renderer snapshot; rows carry no current/selected marker — that is
  /// [CurrentRendererChangedEvent]'s fact alone.
  const factory PlayQueueEvent.renderersChanged({
    required List<RendererInfo> renderers,
    required int seq,
  }) = RenderersChangedEvent;

  const factory PlayQueueEvent.currentRendererChanged({
    String? rendererId,
    String? selectedRendererId,
    required int seq,
  }) = CurrentRendererChangedEvent;

  /// Who drives the output changed: the queue, or a plugin playing
  /// exclusively. A state change describing the new controller's playback
  /// always follows.
  const factory PlayQueueEvent.playbackControlChanged({
    required PlaybackControl control,
    required int seq,
  }) = PlaybackControlChangedEvent;

  factory PlayQueueEvent.fromJson(Map<String, dynamic> json) {
    final eventTypeStr = json['event_type'] as String;
    final seq = json['seq'] as int? ?? 0;

    switch (eventTypeStr) {
      case 'state_changed':
        return PlayQueueEvent.playbackStateChanged(
          state: PlaybackState.fromJson(json['state'] as Map<String, dynamic>),
          seq: seq,
        );
      case 'request_more_tracks':
        return PlayQueueEvent.requestMoreTracks(seq: seq);
      case 'tracks_added':
        final rawIndex = json['index'];
        final insertionIndex = rawIndex is int
            ? rawIndex
            : rawIndex is num
            ? rawIndex.toInt()
            : null;
        return PlayQueueEvent.tracksAdded(
          tracks: (json['tracks'] as List)
              .map((e) => Track.fromJson(e))
              .toList(),
          seq: seq,
          index: insertionIndex,
        );
      case 'tracks_removed':
        return PlayQueueEvent.tracksRemoved(
          indices: List<int>.from(json['indices'] as List),
          seq: seq,
        );
      case 'track_moved':
        return PlayQueueEvent.trackMoved(
          fromIndex: json['from_index'] as int,
          toIndex: json['to_index'] as int,
          seq: seq,
        );
      case 'track_unavailable':
        final reason = json['reason'] as String?;
        final rawIndex = json['index'];
        final index = rawIndex is int
            ? rawIndex
            : rawIndex is num
            ? rawIndex.toInt()
            : throw ArgumentError(
                'track_unavailable event missing valid index: $rawIndex',
              );
        return PlayQueueEvent.trackUnavailable(
          index: index,
          unavailable: json['unavailable'] as bool? ?? true,
          seq: seq,
          // Blank reasons count as absent — an empty Tooltip message asserts.
          reason: (reason == null || reason.trim().isEmpty) ? null : reason,
        );
      case 'playback_error':
        return PlayQueueEvent.playbackError(
          message: json['message'] as String,
          seq: seq,
        );
      case 'playback_mode_changed':
        return PlayQueueEvent.playbackModeChanged(
          mode: PlaybackMode.fromJson(json['mode'] as Map<String, dynamic>),
          seq: seq,
        );
      case 'replay_event':
        if (json['state_type'] == 'PlayQueueState') {
          return PlayQueueEvent.replayEvent(
            state: PlayQueueState.fromJson(
              json['state'] as Map<String, dynamic>,
            ),
            serverTimeNs: json['server_time_ns'] as int,
            seq: seq,
          );
        } else {
          throw ArgumentError(
            'Unknown state_type for replay_event: ${json['state_type']}',
          );
        }
      case 'renderers_changed':
        return PlayQueueEvent.renderersChanged(
          renderers: [
            for (final r in (json['renderers'] ?? const []) as List)
              RendererInfo.fromJson(Map<String, dynamic>.from(r as Map)),
          ],
          seq: seq,
        );
      case 'current_renderer_changed':
        return PlayQueueEvent.currentRendererChanged(
          rendererId: json['renderer_id'] as String?,
          selectedRendererId: json['selected_renderer_id'] as String?,
          seq: seq,
        );
      case 'playback_control_changed':
        return PlayQueueEvent.playbackControlChanged(
          control: PlaybackControl.fromJson(json['control']),
          seq: seq,
        );
      default:
        throw ArgumentError('Unknown event_type: $eventTypeStr');
    }
  }
}
