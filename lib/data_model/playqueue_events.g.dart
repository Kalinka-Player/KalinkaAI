// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playqueue_events.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PlayQueueState _$PlayQueueStateFromJson(Map<String, dynamic> json) =>
    PlayQueueState(
      playbackState: PlaybackState.fromJson(
        json['playback_state'] as Map<String, dynamic>,
      ),
      trackList: (json['track_list'] as List<dynamic>)
          .map((e) => Track.fromJson(e as Map<String, dynamic>))
          .toList(),
      playbackMode: PlaybackMode.fromJson(
        json['playback_mode'] as Map<String, dynamic>,
      ),
      seq: (json['seq'] as num).toInt(),
      renderers: (json['renderers'] as List<dynamic>?)
          ?.map((e) => RendererInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
      currentRendererId: json['current_renderer_id'] as String?,
      selectedRendererId: json['selected_renderer_id'] as String?,
      playbackControl: json['playback_control'] == null
          ? const PlaybackControl.queue()
          : PlaybackControl.fromJson(json['playback_control']),
    );

Map<String, dynamic> _$PlayQueueStateToJson(PlayQueueState instance) =>
    <String, dynamic>{
      'playback_state': instance.playbackState.toJson(),
      'track_list': instance.trackList.map((e) => e.toJson()).toList(),
      'playback_mode': instance.playbackMode.toJson(),
      'seq': instance.seq,
    };

const _$PlayQueueEventTypeEnumMap = {
  PlayQueueEventType.playbackStateChanged: 'playback_state_changed',
  PlayQueueEventType.requestMoreTracks: 'request_more_tracks',
  PlayQueueEventType.tracksAdded: 'tracks_added',
  PlayQueueEventType.tracksRemoved: 'tracks_removed',
  PlayQueueEventType.trackUnavailable: 'track_unavailable',
  PlayQueueEventType.playbackError: 'playback_error',
  PlayQueueEventType.playbackModeChanged: 'playback_mode_changed',
  PlayQueueEventType.renderersChanged: 'renderers_changed',
  PlayQueueEventType.currentRendererChanged: 'current_renderer_changed',
  PlayQueueEventType.playbackControlChanged: 'playback_control_changed',
};
