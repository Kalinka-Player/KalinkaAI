import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/playqueue_events.dart';

PlayQueueState _stateWith(List<Track> tracks) => PlayQueueState(
  playbackState: PlaybackState(state: PlayerStateType.stopped),
  trackList: tracks,
  playbackMode: PlaybackMode.empty,
  seq: 0,
);

const _qobuz = PlaybackControl.exclusive(
  pluginId: 'qobuz',
  title: 'Qobuz Connect',
);

Map<String, dynamic> _replayJson({Object? control}) => {
  'playback_state': {'state': 'PLAYING'},
  'track_list': [],
  'playback_mode': {
    'shuffle': false,
    'repeat_single': false,
    'repeat_all': false,
  },
  'seq': 1,
  'playback_control': ?control,
};

void main() {
  test('source handover clears stale codec, format and message', () {
    final local = PlaybackState(
      state: PlayerStateType.playing,
      mimeType: 'audio/flac',
      audioInfo: AudioInfo(sampleRate: 192000, bitsPerSample: 24, channels: 2),
      message: 'Local playback',
      streamUrl: 'http://server/local.flac',
    );
    final roon = local.copyWith(
      PlaybackState(
        state: PlayerStateType.playing,
        currentTrack: Track(
          id: 'kalinka:roon:track:1',
          title: 'Roon song',
          duration: 240,
        ),
      ),
    );
    expect(roon.mimeType, isNull);
    expect(roon.audioInfo, isNull);
    expect(roon.message, isNull);
    expect(roon.streamUrl, isNull);
    final resumed = roon.copyWith(local);
    expect(resumed.mimeType, 'audio/flac');
    expect(resumed.audioInfo!.sampleRate, 192000);
  });
  group('playback control', () {
    test('parses playback_control_changed for either mode', () {
      final taken = PlayQueueEvent.fromJson({
        'event_type': 'playback_control_changed',
        'control': {
          'mode': 'exclusive',
          'plugin_id': 'qobuz',
          'title': 'Qobuz Connect',
        },
        'seq': 3,
      });
      final given = PlayQueueEvent.fromJson({
        'event_type': 'playback_control_changed',
        'control': {'mode': 'queue', 'plugin_id': null, 'title': null},
        'seq': 4,
      });

      expect((taken as PlaybackControlChangedEvent).control, _qobuz);
      expect(
        (given as PlaybackControlChangedEvent).control,
        const PlaybackControl.queue(),
      );
    });

    test('a mode the app does not know reads as the queue', () {
      expect(
        PlaybackControl.fromJson({'mode': 'something_new', 'plugin_id': 'x'}),
        const PlaybackControl.queue(),
      );
      expect(PlaybackControl.fromJson(null), const PlaybackControl.queue());
    });

    test('a plugin taking the output leaves the playback state as it was', () {
      final queued = Track(id: 'q', title: 'Queued', duration: 10);
      final state = _stateWith([queued]);

      final held = state.apply(
        const PlayQueueEvent.playbackControlChanged(control: _qobuz, seq: 1),
        0,
      );

      expect(held.playbackControl, _qobuz);
      expect(held.playbackControl.isExclusive, isTrue);
      expect(held.trackList, [queued]);
      expect(held.seq, 1);
    });

    test(
      'control returning to the queue takes the plugin\'s track with it',
      () {
        final connect = Track(id: 'c', title: 'Connect song', duration: 240);
        final held = PlayQueueState(
          playbackState: PlaybackState(
            state: PlayerStateType.playing,
            currentTrack: connect,
            index: null,
          ),
          trackList: const [],
          playbackMode: PlaybackMode.empty,
          seq: 1,
          playbackControl: _qobuz,
        );

        final released = held.apply(
          const PlayQueueEvent.playbackControlChanged(
            control: PlaybackControl.queue(),
            seq: 2,
          ),
          0,
        );

        expect(released.playbackControl.isExclusive, isFalse);
        expect(released.playbackState.currentTrack, isNull);
        expect(released.playbackState.state, PlayerStateType.playing);
      },
    );

    test('the queue keeps its place under the plugin\'s playback', () {
      final queued = [
        Track(id: 'a', title: 'A', duration: 10),
        Track(id: 'b', title: 'B', duration: 10),
      ];
      final state = PlayQueueState(
        playbackState: PlaybackState(state: PlayerStateType.paused, index: 1),
        trackList: queued,
        playbackMode: PlaybackMode.empty,
        seq: 0,
      );

      final held = state
          .apply(
            const PlayQueueEvent.playbackControlChanged(
              control: _qobuz,
              seq: 1,
            ),
            0,
          )
          .apply(
            PlayQueueEvent.playbackStateChanged(
              state: PlaybackState(
                state: PlayerStateType.playing,
                currentTrack: Track(id: 'c', title: 'Connect', duration: 240),
                index: null,
              ),
              seq: 2,
            ),
            0,
          );

      expect(held.playbackState.index, 1);
    });

    test('other events keep the control', () {
      final held = _stateWith(const []).apply(
        const PlayQueueEvent.playbackControlChanged(control: _qobuz, seq: 1),
        0,
      );

      final after = held
          .apply(
            PlayQueueEvent.tracksAdded(
              tracks: [Track(id: 'a', title: 'A', duration: 10)],
              seq: 2,
            ),
            0,
          )
          .apply(
            const PlayQueueEvent.currentRendererChanged(
              rendererId: 'r-1',
              seq: 3,
            ),
            0,
          )
          .apply(
            const PlayQueueEvent.renderersChanged(renderers: [], seq: 4),
            0,
          );

      expect(after.playbackControl, _qobuz);
    });

    test('the replay carries the control; absent is the queue', () {
      final replayed = PlayQueueState.fromJson(
        _replayJson(
          control: {
            'mode': 'exclusive',
            'plugin_id': 'qobuz',
            'title': 'Qobuz Connect',
          },
        ),
      );
      final applied = _stateWith(const []).apply(
        PlayQueueEvent.replayEvent(state: replayed, serverTimeNs: 0, seq: 5),
        0,
      );

      expect(applied.playbackControl, _qobuz);
      expect(
        PlayQueueState.fromJson(_replayJson()).playbackControl,
        const PlaybackControl.queue(),
      );
    });
  });

  group('TrackUnavailableEvent apply', () {
    test('marks the targeted track unavailable', () {
      final state = _stateWith([
        Track(id: 'a', title: 'A', duration: 10),
        Track(id: 'b', title: 'B', duration: 10),
      ]);

      final next = state.apply(
        const PlayQueueEvent.trackUnavailable(
          index: 1,
          unavailable: true,
          seq: 1,
        ),
        0,
      );

      expect(next.trackList[1].unavailable, isTrue);
      expect(next.trackList[0].unavailable, isFalse);
      expect(next.seq, 1);
    });

    test('clears the flag when unavailable is false', () {
      final state = _stateWith([
        Track(id: 'a', title: 'A', duration: 10, unavailable: true),
      ]);

      final next = state.apply(
        const PlayQueueEvent.trackUnavailable(
          index: 0,
          unavailable: false,
          seq: 1,
        ),
        0,
      );

      expect(next.trackList[0].unavailable, isFalse);
    });

    test('ignores out-of-range indices', () {
      final state = _stateWith([Track(id: 'a', title: 'A', duration: 10)]);

      final next = state.apply(
        const PlayQueueEvent.trackUnavailable(
          index: 5,
          unavailable: true,
          seq: 1,
        ),
        0,
      );

      expect(next, same(state));
    });

    test('carries the reason onto the track and clears it with the flag', () {
      final state = _stateWith([Track(id: 'a', title: 'A', duration: 10)]);

      final flagged = state.apply(
        const PlayQueueEvent.trackUnavailable(
          index: 0,
          unavailable: true,
          reason: 'Music folder /mnt/nas is not available',
          seq: 1,
        ),
        0,
      );
      expect(
        flagged.trackList[0].unavailableReason,
        'Music folder /mnt/nas is not available',
      );

      final cleared = flagged.apply(
        const PlayQueueEvent.trackUnavailable(
          index: 0,
          unavailable: false,
          seq: 2,
        ),
        0,
      );
      expect(cleared.trackList[0].unavailable, isFalse);
      expect(cleared.trackList[0].unavailableReason, isNull);
    });

    test('parses the wire event', () {
      final event = PlayQueueEvent.fromJson({
        'event_type': 'track_unavailable',
        'index': 2,
        'unavailable': true,
        'seq': 7,
        'reason': 'Music folder /mnt/nas is not available',
      });

      expect(event, isA<TrackUnavailableEvent>());
      final unavailable = event as TrackUnavailableEvent;
      expect(unavailable.index, 2);
      expect(unavailable.unavailable, isTrue);
      expect(unavailable.seq, 7);
      expect(unavailable.reason, 'Music folder /mnt/nas is not available');
    });

    test('parses the wire event without a reason (older server)', () {
      final event = PlayQueueEvent.fromJson({
        'event_type': 'track_unavailable',
        'index': 2,
        'unavailable': true,
        'seq': 7,
      });

      expect((event as TrackUnavailableEvent).reason, isNull);
    });

    test('treats a blank reason as absent', () {
      final event = PlayQueueEvent.fromJson({
        'event_type': 'track_unavailable',
        'index': 2,
        'unavailable': true,
        'seq': 7,
        'reason': '  ',
      });

      expect((event as TrackUnavailableEvent).reason, isNull);
    });

    test('parses a numeric (non-int) index defensively', () {
      final event = PlayQueueEvent.fromJson({
        'event_type': 'track_unavailable',
        'index': 3.0,
        'unavailable': true,
        'seq': 1,
      });

      expect(event, isA<TrackUnavailableEvent>());
      expect((event as TrackUnavailableEvent).index, 3);
    });
  });

  group('renderer topology events', () {
    test('parses renderers_changed with unflagged rows', () {
      final event = PlayQueueEvent.fromJson({
        'event_type': 'renderers_changed',
        'renderers': [
          {
            'renderer_id': 'r-1',
            'friendly_name': 'Kitchen',
            'status': 'connected',
            'platform': {'hostname': 'pi', 'audio_backend': 'alsa'},
          },
        ],
        'seq': 4,
      });

      expect(event, isA<RenderersChangedEvent>());
      final changed = event as RenderersChangedEvent;
      expect(changed.renderers.single.rendererId, 'r-1');
      expect(changed.renderers.single.active, isFalse);
      expect(changed.seq, 4);
    });

    test('parses current_renderer_changed, nulls meaning nothing', () {
      final event = PlayQueueEvent.fromJson({
        'event_type': 'current_renderer_changed',
        'renderer_id': null,
        'selected_renderer_id': 'r-2',
        'seq': 5,
      });

      expect(event, isA<CurrentRendererChangedEvent>());
      final current = event as CurrentRendererChangedEvent;
      expect(current.rendererId, isNull);
      expect(current.selectedRendererId, 'r-2');
    });

    test('replay state carries the topology; absent keys stay null', () {
      final withTopology = PlayQueueState.fromJson({
        'playback_state': {'state': 'STOPPED'},
        'track_list': [],
        'playback_mode': {
          'shuffle': false,
          'repeat_single': false,
          'repeat_all': false,
        },
        'seq': 1,
        'renderers': [],
        'current_renderer_id': 'r-1',
      });
      expect(withTopology.renderers, isEmpty);
      expect(withTopology.currentRendererId, 'r-1');

      final preEvents = PlayQueueState.fromJson({
        'playback_state': {'state': 'STOPPED'},
        'track_list': [],
        'playback_mode': {
          'shuffle': false,
          'repeat_single': false,
          'repeat_all': false,
        },
        'seq': 1,
      });
      expect(preEvents.renderers, isNull);
    });
  });

  group('PlaybackStateChangedEvent apply', () {
    // The server sends a whole state each time, and reports no URL once the
    // renderer is holding nothing — so the last one has to go.
    test('a state reporting no stream URL clears the one before it', () {
      final playing = _stateWith([Track(id: 'a', title: 'A', duration: 10)])
          .apply(
            PlayQueueEvent.playbackStateChanged(
              state: PlaybackState(
                state: PlayerStateType.playing,
                streamUrl: 'http://server/content/localfiles/a',
              ),
              seq: 1,
            ),
            0,
          );
      expect(playing.playbackState.streamUrl, isNotNull);

      final stopped = playing.apply(
        PlayQueueEvent.playbackStateChanged(
          state: PlaybackState(state: PlayerStateType.stopped),
          seq: 2,
        ),
        0,
      );

      expect(stopped.playbackState.streamUrl, isNull);
    });
  });
}
