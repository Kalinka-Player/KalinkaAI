// App-hosted renderer protocol behavior.

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/generated/kalinka/renderer/v1/renderer.pb.dart' as pb;
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/renderer_host_provider.dart';
import 'package:kalinka/providers/websocket_provider.dart'
    show rendererSocketRetryEpochProvider;
import 'package:kalinka/renderer/renderer_backend.dart';
import 'package:kalinka/renderer/renderer_connection.dart';
import 'package:kalinka/renderer/renderer_engine.dart';
import 'package:kalinka/renderer/renderer_identity.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Connection extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;

  void set(ConnectionStatus next) => state = next;
}

class FakeBackend implements RendererAudioBackend {
  final _events = StreamController<BackendEvent>.broadcast(sync: true);
  final calls = <String>[];

  @override
  int positionMs = 0;

  @override
  bool isPaused = false;

  String? uri;
  double? volume;
  int generation = 0;

  @override
  Stream<BackendEvent> get events => _events.stream;

  @override
  void play({
    required String uri,
    required int startOffsetMs,
    required int generation,
  }) {
    this.uri = uri;
    this.generation = generation;
    isPaused = false;
    calls.add('play $uri@$startOffsetMs');
  }

  @override
  void pause() {
    isPaused = true;
    calls.add('pause');
  }

  @override
  void resume() {
    isPaused = false;
    calls.add('resume');
  }

  @override
  void stop() {
    uri = null;
    calls.add('stop');
  }

  @override
  void seek(int positionMs) => calls.add('seek $positionMs');

  @override
  void setVolume(double fraction) {
    volume = fraction;
    calls.add('volume $fraction');
  }

  @override
  void dispose() => _events.close();

  void emit(BackendEvent event) => _events.add(event);

  void playing([int? forGeneration]) =>
      emit(BackendPlaying(forGeneration ?? generation));
  void stalled([int? forGeneration]) =>
      emit(BackendStalled(forGeneration ?? generation));
  void paused([int? forGeneration]) =>
      emit(BackendPaused(forGeneration ?? generation));
  void ended([int? forGeneration]) =>
      emit(BackendEnded(forGeneration ?? generation));
  void failed(BackendErrorKind kind, String message, [int? forGeneration]) =>
      emit(BackendFailed(forGeneration ?? generation, kind, message));
  void format({
    int sampleRateHz = 48000,
    int channels = 2,
    int bitsPerSample = 32,
    String sampleFormat = 'FLOAT32',
    int? forGeneration,
  }) => emit(
    BackendDeviceFormat(
      forGeneration ?? generation,
      sampleRateHz: sampleRateHz,
      channels: channels,
      bitsPerSample: bitsPerSample,
      sampleFormat: sampleFormat,
    ),
  );
  void duration({int durationMs = 300000, int? forGeneration}) => emit(
    BackendDuration(forGeneration ?? generation, durationMs: durationMs),
  );
}

const identity = RendererIdentity(
  rendererId: 'r-1',
  instanceId: 'i-1',
  friendlyName: 'Chrome on Linux',
  softwareVersion: '1.2.3',
  os: 'web',
);

class Harness {
  final backend = FakeBackend();
  late final engine = RendererEngine(backend);
  final sent = <pb.Envelope>[];
  StreamController<dynamic> _incoming = StreamController<dynamic>(sync: true);
  late RendererConnection connection;
  int _inId = 0;

  Harness() {
    connection = _connect();
  }

  RendererConnection _connect() => RendererConnection(
    incoming: _incoming.stream,
    send: (frame) => sent.add(pb.Envelope.fromBuffer(frame)),
    engine: engine,
    identity: identity,
  );

  void dropLink() => connection.disconnect();

  void reconnect() {
    dropLink();
    _incoming = StreamController<dynamic>(sync: true);
    connection = _connect();
  }

  void deliver(pb.Envelope envelope) {
    envelope.messageId = Int64(++_inId);
    _incoming.add(envelope.writeToBuffer());
  }

  void welcome({String serverId = 'core-1'}) =>
      deliver(pb.Envelope()..welcome = (pb.Welcome()..serverId = serverId));

  void openSession(String sessionId, {bool forceFixedOutput = false}) {
    final open = pb.SessionOpen()
      ..sessionId = sessionId
      ..forceFixedOutput = forceFixedOutput;
    deliver(pb.Envelope()..sessionOpen = open);
  }

  void command(pb.Command op, {String sessionId = 's1'}) => deliver(
    pb.Envelope()
      ..sessionId = sessionId
      ..command = op,
  );

  void setSource(
    String token, {
    String uri = 'http://media/a',
    int offset = 0,
  }) => command(
    pb.Command()
      ..setSource = (pb.SetSource()..source = _source(token, uri, offset)),
  );

  void enqueue(String token, {String uri = 'http://media/b'}) => command(
    pb.Command()
      ..enqueueSource = (pb.EnqueueSource()..source = _source(token, uri, 0)),
  );

  static pb.Source _source(String token, String uri, int offset) => pb.Source()
    ..uri = uri
    ..mimeType = 'audio/flac'
    ..sourceToken = token
    ..startOffsetMs = Int64(offset);

  List<pb.Envelope> get replies => sent.sublist(1);

  pb.Envelope get last => sent.last;

  void playing(String token) {
    welcome();
    openSession('s1');
    setSource(token);
    backend.playing();
    sent.clear();
    backend.calls.clear();
  }
}

void main() {
  test('hello leads, carries identity and protocol version 2', () {
    final h = Harness();
    final hello = h.sent.first.hello;
    expect(h.sent.first.messageId.toInt(), 1);
    expect(hello.protocolVersions.min, 2);
    expect(hello.protocolVersions.max, 2);
    expect(hello.rendererId, 'r-1');
    expect(hello.instanceId, 'i-1');
    expect(hello.friendlyName, 'Chrome on Linux');
    expect(hello.kind, pb.RendererKind.RENDERER_KIND_WEB);
    expect(hello.platform.os, 'web');
    expect(hello.activeSessionId, isEmpty);
  });

  test('message ids are monotonic per connection', () {
    final h = Harness();
    h.welcome();
    h.openSession('s1');
    expect(
      [for (final e in h.sent) e.messageId.toInt()],
      [for (var i = 1; i <= h.sent.length; i++) i],
    );
  });

  test('playback and config traffic are gated until Welcome', () {
    final h = Harness();
    h.openSession('s1');
    expect(h.last.sessionOpenResult.accepted, isFalse);
    expect(
      h.last.sessionOpenResult.error,
      pb.SessionOpenResult_Error.ERROR_INTERNAL,
    );
    expect(h.engine.activeSessionId, isEmpty);

    h.sent.clear();
    h.command(pb.Command()..pause = pb.Pause());
    expect(h.last.commandRejected.sessionId, 's1');
    expect(h.backend.calls, isEmpty);

    h.sent.clear();
    h.deliver(pb.Envelope()..configRequest = pb.ConfigRequest());
    expect(h.sent, isEmpty);

    h.welcome();
    h.openSession('s1');
    expect(
      h.last.stateSnapshot.playbackState,
      pb.PlaybackState.PLAYBACK_STATE_STOPPED,
    );
  });

  test('session open is accepted, then the snapshot follows', () {
    final h = Harness();
    h.welcome();
    h.openSession('s1');
    final result = h.replies[0];
    expect(result.sessionOpenResult.sessionId, 's1');
    expect(result.sessionOpenResult.accepted, isTrue);
    // Lifecycle replies carry their own session_id, not the envelope's.
    expect(result.sessionId, isEmpty);
    final snapshot = h.replies[1];
    expect(snapshot.sessionId, 's1');
    expect(
      snapshot.stateSnapshot.playbackState,
      pb.PlaybackState.PLAYBACK_STATE_STOPPED,
    );
    expect(snapshot.stateSnapshot.positionValid, isFalse);
    expect(snapshot.stateSnapshot.volume.current, 100);
    expect(
      snapshot.stateSnapshot.volume.backend,
      pb.VolumeBackend.VOLUME_BACKEND_SOFTWARE,
    );
  });

  test('a second session is refused busy, naming the owner', () {
    final h = Harness();
    h.welcome(serverId: 'core-1');
    h.openSession('s1');
    h.openSession('s2');
    final result = h.last.sessionOpenResult;
    expect(result.sessionId, 's2');
    expect(result.accepted, isFalse);
    expect(result.error, pb.SessionOpenResult_Error.ERROR_BUSY);
    expect(result.ownerServerId, 'core-1');
    expect(h.engine.activeSessionId, 's1');
  });

  test('set_source starts playback and reports the start sequence', () {
    final h = Harness();
    h.welcome();
    h.openSession('s1');
    h.sent.clear();
    h.setSource('t1', uri: 'http://media/a', offset: 1500);
    expect(h.backend.calls, ['play http://media/a@1500']);
    expect(h.sent[0].sourceChanged.sourceToken, 't1');
    expect(h.sent[0].sourceChanged.hasPreviousSourceToken(), isFalse);
    final preparing = h.sent[1].playbackStateChanged;
    expect(preparing.state, pb.PlaybackState.PLAYBACK_STATE_PREPARING);
    expect(preparing.positionMs.toInt(), 1500);
    expect(preparing.positionValid, isFalse);

    h.backend.positionMs = 1500;
    h.backend.playing();
    final playing = h.last.playbackStateChanged;
    expect(playing.state, pb.PlaybackState.PLAYBACK_STATE_PLAYING);
    expect(playing.positionValid, isTrue);
    expect(playing.sourceToken, 't1');
  });

  test('set_source displaces the current source and the queue', () {
    final h = Harness()..playing('t1');
    h.enqueue('t2');
    h.setSource('t3', uri: 'http://media/c');
    expect(h.backend.uri, 'http://media/c');
    expect(h.sent.first.sourceChanged.previousSourceToken, 't1');
    // t2 is gone: when t3 ends, playback finishes.
    h.sent.clear();
    h.backend.ended();
    expect(
      h.last.playbackStateChanged.state,
      pb.PlaybackState.PLAYBACK_STATE_FINISHED,
    );
  });

  test('enqueue onto an idle session starts it', () {
    final h = Harness();
    h.welcome();
    h.openSession('s1');
    h.sent.clear();
    h.enqueue('t1');
    expect(h.backend.calls, ['play http://media/b@0']);
    expect(h.sent.first.sourceChanged.sourceToken, 't1');
  });

  test('the queue advances itself when a source ends', () {
    final h = Harness()..playing('t1');
    h.enqueue('t2');
    expect(h.sent, isEmpty); // queued silently, behind the current source
    h.backend.ended();
    final changed = h.sent.first.sourceChanged;
    expect(changed.sourceToken, 't2');
    expect(changed.previousSourceToken, 't1');
    h.backend.playing();

    h.sent.clear();
    h.backend.ended();
    final finished = h.last.playbackStateChanged;
    expect(finished.state, pb.PlaybackState.PLAYBACK_STATE_FINISHED);
    expect(finished.sourceToken, 't2');
    expect(finished.positionValid, isFalse);
  });

  test('removing the current source hands over to the next', () {
    final h = Harness()..playing('t1');
    h.enqueue('t2');
    h.command(
      pb.Command()..removeSource = (pb.RemoveSource()..sourceToken = 't1'),
    );
    expect(h.sent.first.sourceChanged.sourceToken, 't2');

    h.sent.clear();
    h.command(
      pb.Command()..removeSource = (pb.RemoveSource()..sourceToken = 't2'),
    );
    expect(h.backend.calls, contains('stop'));
    final finished = h.last.playbackStateChanged;
    expect(finished.state, pb.PlaybackState.PLAYBACK_STATE_FINISHED);
    expect(finished.sourceToken, 't2');
  });

  test('removing a queued source is silent', () {
    final h = Harness()..playing('t1');
    h.enqueue('t2');
    h.command(
      pb.Command()..removeSource = (pb.RemoveSource()..sourceToken = 't2'),
    );
    expect(h.sent, isEmpty);
    h.backend.ended();
    expect(
      h.last.playbackStateChanged.state,
      pb.PlaybackState.PLAYBACK_STATE_FINISHED,
    );
  });

  test('clear_queue finishes without naming a source', () {
    final h = Harness()..playing('t1');
    h.command(pb.Command()..clearQueue = pb.ClearQueue());
    expect(h.backend.calls, contains('stop'));
    final state = h.last.playbackStateChanged;
    expect(state.state, pb.PlaybackState.PLAYBACK_STATE_FINISHED);
    expect(state.hasSourceToken(), isFalse);
  });

  test('stop closes the device and reports stopped without a source', () {
    final h = Harness()..playing('t1');
    h.command(pb.Command()..stop = pb.Stop());
    expect(h.backend.calls, contains('stop'));
    final state = h.last.playbackStateChanged;
    expect(state.state, pb.PlaybackState.PLAYBACK_STATE_STOPPED);
    expect(state.hasSourceToken(), isFalse);
  });

  test('pause and resume report with valid positions', () {
    final h = Harness()..playing('t1');
    h.backend.positionMs = 42000;
    h.command(pb.Command()..pause = pb.Pause());
    final paused = h.last.playbackStateChanged;
    expect(paused.state, pb.PlaybackState.PLAYBACK_STATE_PAUSED);
    expect(paused.positionMs.toInt(), 42000);
    expect(paused.positionValid, isTrue);

    h.command(pb.Command()..resume = pb.Resume());
    expect(
      h.last.playbackStateChanged.state,
      pb.PlaybackState.PLAYBACK_STATE_PLAYING,
    );
  });

  test('seek re-buffers at the target position', () {
    final h = Harness()..playing('t1');
    h.command(pb.Command()..seek = (pb.Seek()..positionMs = Int64(5000)));
    expect(h.backend.calls, contains('seek 5000'));
    final preparing = h.last.playbackStateChanged;
    expect(preparing.state, pb.PlaybackState.PLAYBACK_STATE_PREPARING);
    expect(preparing.positionMs.toInt(), 5000);
    h.backend.positionMs = 5000;
    h.backend.playing();
    expect(
      h.last.playbackStateChanged.state,
      pb.PlaybackState.PLAYBACK_STATE_PLAYING,
    );
  });

  test('a seek that settles on a paused element reports paused', () {
    final h = Harness()..playing('t1');
    h.command(pb.Command()..pause = pb.Pause());
    h.command(pb.Command()..seek = (pb.Seek()..positionMs = Int64(5000)));
    h.backend.paused();
    expect(
      h.last.playbackStateChanged.state,
      pb.PlaybackState.PLAYBACK_STATE_PAUSED,
    );
  });

  test('a stall while playing reports preparing, recovery playing', () {
    final h = Harness()..playing('t1');
    h.backend.stalled();
    expect(
      h.last.playbackStateChanged.state,
      pb.PlaybackState.PLAYBACK_STATE_PREPARING,
    );
    h.backend.playing();
    expect(
      h.last.playbackStateChanged.state,
      pb.PlaybackState.PLAYBACK_STATE_PLAYING,
    );
  });

  test('set_volume applies software gain and reports it', () {
    final h = Harness()..playing('t1');
    h.command(pb.Command()..setVolume = (pb.SetVolume()..percent = 30));
    expect(h.backend.volume, 0.3);
    final volume = h.last.volumeChanged.volume;
    expect(volume.current, 30);
    expect(volume.supported, isTrue);
    expect(volume.max, 100);
  });

  test('forced fixed output uses unity and restores the previous level', () {
    final h = Harness();
    h.welcome();
    h.openSession('s1');
    h.command(pb.Command()..setVolume = (pb.SetVolume()..percent = 20));
    h.deliver(
      pb.Envelope()..sessionClose = (pb.SessionClose()..sessionId = 's1'),
    );
    expect(h.backend.volume, 0.2);

    h.openSession('s2', forceFixedOutput: true);
    expect(h.backend.volume, 1);
    final fixedVolume = h.last.stateSnapshot.volume;
    expect(fixedVolume.supported, isFalse);
    expect(fixedVolume.current, 100);
    expect(fixedVolume.backend, pb.VolumeBackend.VOLUME_BACKEND_NONE);

    h.command(
      pb.Command()..setVolume = (pb.SetVolume()..percent = 80),
      sessionId: 's2',
    );
    expect(h.backend.volume, 1);
    expect(h.last.volumeChanged.volume.current, 100);

    h.deliver(
      pb.Envelope()..sessionClose = (pb.SessionClose()..sessionId = 's2'),
    );
    expect(h.backend.volume, 0.2);

    h.openSession('s3');
    final restoredVolume = h.last.stateSnapshot.volume;
    expect(restoredVolume.supported, isTrue);
    expect(restoredVolume.current, 20);
    expect(restoredVolume.backend, pb.VolumeBackend.VOLUME_BACKEND_SOFTWARE);
  });

  test('renderer-owned sessions leave browser software gain unchanged', () {
    final h = Harness();
    h.welcome();
    h.openSession('s1');
    expect(h.backend.volume, isNull);
    expect(h.last.stateSnapshot.volume.current, 100);

    h.command(pb.Command()..setVolume = (pb.SetVolume()..percent = 70));
    h.deliver(
      pb.Envelope()..sessionClose = (pb.SessionClose()..sessionId = 's1'),
    );
    h.openSession('s2');
    expect(h.backend.volume, 0.7);
    expect(h.last.stateSnapshot.volume.current, 70);
  });

  test('force_fixed_output uses SessionOpen field 2', () {
    final open = pb.SessionOpen(forceFixedOutput: true);
    expect(open.writeToBuffer(), <int>[16, 1]);
  });

  test('session close stops playback and acks', () {
    final h = Harness()..playing('t1');
    h.deliver(
      pb.Envelope()..sessionClose = (pb.SessionClose()..sessionId = 's1'),
    );
    expect(h.backend.calls, contains('stop'));
    final closed = h.last.sessionClosed;
    expect(closed.sessionId, 's1');
    expect(closed.reason, pb.SessionClosed_Reason.REASON_ACK);
    expect(h.engine.activeSessionId, isEmpty);
  });

  test('a command naming another session is rejected untouched', () {
    final h = Harness()..playing('t1');
    h.command(pb.Command()..pause = pb.Pause(), sessionId: 'stale');
    expect(h.backend.calls, isEmpty);
    final rejected = h.last.commandRejected;
    expect(rejected.sessionId, 'stale');
    expect(rejected.command, pb.ControlKind.CONTROL_KIND_PAUSE);
  });

  test(
    'another Core cannot command or receive state for the owner session',
    () {
      final h = Harness()..playing('t1');
      final incoming = StreamController<dynamic>(sync: true);
      final strangerSent = <pb.Envelope>[];
      final stranger = RendererConnection(
        incoming: incoming.stream,
        send: (frame) => strangerSent.add(pb.Envelope.fromBuffer(frame)),
        engine: h.engine,
        identity: identity,
      );
      incoming.add(
        (pb.Envelope()
              ..messageId = Int64.ONE
              ..welcome = (pb.Welcome()..serverId = 'core-2'))
            .writeToBuffer(),
      );
      strangerSent.clear();

      incoming.add(
        (pb.Envelope()
              ..messageId = Int64(2)
              ..sessionId = 's1'
              ..command = (pb.Command()..pause = pb.Pause()))
            .writeToBuffer(),
      );
      expect(h.backend.calls, isEmpty);
      expect(strangerSent.single.commandRejected.sessionId, 's1');
      expect(h.sent, isEmpty);

      strangerSent.clear();
      h.backend.stalled();
      expect(
        h.sent.single.playbackStateChanged.state,
        pb.PlaybackState.PLAYBACK_STATE_PREPARING,
      );
      expect(strangerSent, isEmpty);
      stranger.close();
    },
  );

  test('a broken stream reports an error naming the source', () {
    final h = Harness()..playing('t1');
    h.backend.failed(BackendErrorKind.network, 'http error');
    final state = h.last.playbackStateChanged;
    expect(state.state, pb.PlaybackState.PLAYBACK_STATE_ERROR);
    expect(state.sourceToken, 't1');
    expect(state.positionValid, isFalse);
    expect(state.error.source, pb.ErrorSource.ERROR_SOURCE_HTTP_STREAM);
    expect(state.error.message, 'http error');
    expect(state.error.sourceToken, 't1');

    h.command(pb.Command()..requestSnapshot = pb.RequestSnapshot());
    final snapshot = h.last.stateSnapshot;
    expect(snapshot.playbackState, pb.PlaybackState.PLAYBACK_STATE_ERROR);
    expect(snapshot.error.message, 'http error');
    expect(snapshot.error.sourceToken, 't1');
  });

  test('an autoplay refusal surfaces as a renderer-internal error', () {
    final h = Harness()..playing('t1');
    h.backend.failed(BackendErrorKind.internal, 'playback refused');
    expect(
      h.last.playbackStateChanged.error.source,
      pb.ErrorSource.ERROR_SOURCE_RENDERER_INTERNAL,
    );
  });

  test('late events from a displaced source are ignored by generation', () {
    final h = Harness()..playing('t1');
    final oldGeneration = h.backend.generation;
    h.setSource('t2');
    h.sent.clear();
    h.backend.calls.clear();

    h.backend.failed(BackendErrorKind.network, 'late failure', oldGeneration);
    h.backend.ended(oldGeneration);
    expect(h.sent, isEmpty);
    expect(h.backend.calls, isEmpty);

    h.command(pb.Command()..requestSnapshot = pb.RequestSnapshot());
    expect(h.last.stateSnapshot.currentSource.sourceToken, 't2');
    expect(
      h.last.stateSnapshot.playbackState,
      pb.PlaybackState.PLAYBACK_STATE_PREPARING,
    );
  });

  test('the browser reports its own output as the device format', () {
    final h = Harness()..playing('t1');
    h.backend.format(sampleRateHz: 48000, channels: 2, bitsPerSample: 32);
    h.backend.duration(durationMs: 123456);
    final changed = h.last.playbackStateChanged;
    expect(changed.state, pb.PlaybackState.PLAYBACK_STATE_PLAYING);
    expect(changed.sourceToken, 't1');
    expect(changed.deviceInfo.format.sampleRateHz, 48000);
    expect(changed.deviceInfo.format.channels, 2);
    expect(changed.deviceInfo.format.bitsPerSample, 32);
    // Web Audio is never the card on its own.
    expect(changed.deviceInfo.access, pb.DeviceAccess.DEVICE_ACCESS_SHARED);
    // HTMLMediaElement never says what it decoded, so there is no stream
    // format to claim — the 48 kHz above is the browser's, not the file's.
    expect(changed.hasFormat(), isFalse);
    // Reported as it is, with no sample rate to divide back out.
    expect(h.last.playbackStateChanged.durationMs.toInt(), 123456);

    // Every later state restates them, so a Core never has to remember one.
    h.backend.paused();
    expect(
      h.last.playbackStateChanged.state,
      pb.PlaybackState.PLAYBACK_STATE_PAUSED,
    );
    expect(h.last.playbackStateChanged.deviceInfo.format.sampleRateHz, 48000);

    h.command(pb.Command()..requestSnapshot = pb.RequestSnapshot());
    expect(h.last.stateSnapshot.deviceInfo.format.sampleRateHz, 48000);
    expect(h.last.stateSnapshot.durationMs.toInt(), 123456);
  });

  test('a stream of unknown length still reports the device', () {
    final h = Harness()..playing('t1');
    h.backend.format(sampleRateHz: 44100, channels: 2, bitsPerSample: 32);

    final changed = h.last.playbackStateChanged;
    expect(changed.deviceInfo.format.sampleRateHz, 44100);
    // A live stream never learns its length; the device is known regardless.
    expect(changed.hasDurationMs(), isFalse);
  });

  test('request_snapshot describes source, queue and position', () {
    final h = Harness()..playing('t1');
    h.enqueue('t2');
    h.enqueue('t3');
    h.backend.positionMs = 9000;
    h.command(pb.Command()..requestSnapshot = pb.RequestSnapshot());
    final snapshot = h.last.stateSnapshot;
    expect(snapshot.playbackState, pb.PlaybackState.PLAYBACK_STATE_PLAYING);
    expect(snapshot.currentSource.sourceToken, 't1');
    expect(snapshot.positionMs.toInt(), 9000);
    expect(snapshot.positionValid, isTrue);
    expect(snapshot.queuedSourceTokens, ['t2', 't3']);
  });

  test('config plane answers promptly with an empty schema', () {
    final h = Harness();
    h.welcome();
    h.deliver(pb.Envelope()..configRequest = pb.ConfigRequest());
    expect(h.last.inReplyTo.toInt(), 2);
    expect(h.last.configSnapshot.sections, isEmpty);

    h.deliver(
      pb.Envelope()
        ..configUpdate = (pb.ConfigUpdate()
          ..settings.add(
            pb.ConfigUpdate_Setting()
              ..path = 'output.device'
              ..value = 'x',
          )),
    );
    expect(h.last.inReplyTo.toInt(), 3);
    final outcome = h.last.configResult.outcomes.single;
    expect(outcome.applied, isFalse);
    expect(outcome.path, 'output.device');
  });

  test('goodbye replaced stops playback: another tab took over', () {
    final h = Harness()..playing('t1');
    h.deliver(
      pb.Envelope()
        ..goodbye = (pb.Goodbye()..reason = pb.Goodbye_Reason.REASON_REPLACED),
    );
    expect(h.backend.calls, contains('stop'));
    expect(h.engine.activeSessionId, isEmpty);
  });

  test('route replacement is unclean; renderer shutdown says Goodbye', () {
    final replaced = Harness();
    replaced.welcome();
    replaced.sent.clear();
    replaced.connection.disconnect();
    expect(replaced.sent, isEmpty);

    final shutdown = Harness();
    shutdown.welcome();
    shutdown.sent.clear();
    shutdown.connection.close();
    expect(
      shutdown.sent.single.goodbye.reason,
      pb.Goodbye_Reason.REASON_SHUTDOWN,
    );
  });

  group('session ownership across reconnects', () {
    test('a link drop leaves playback running', () {
      fakeAsync((async) {
        final h = Harness()..playing('t1');
        h.dropLink();
        expect(h.backend.calls, isNot(contains('stop')));
        expect(h.engine.activeSessionId, 's1');
        async.elapse(const Duration(minutes: 2));
      });
    });

    test('the owner returning within the grace keeps the session', () {
      fakeAsync((async) {
        final h = Harness()..playing('t1');
        h.reconnect();
        async.elapse(const Duration(seconds: 30));
        h.welcome(serverId: 'core-1');
        async.elapse(const Duration(minutes: 5));
        expect(h.backend.calls, isNot(contains('stop')));
        expect(h.engine.activeSessionId, 's1');
        expect(h.engine.sessionOwnerServerId, 'core-1');
      });
    });

    test('an owner that stays away past the grace loses the session', () {
      fakeAsync((async) {
        final h = Harness()..playing('t1');
        h.dropLink();
        async.elapse(const Duration(seconds: 59));
        expect(h.backend.calls, isNot(contains('stop')));
        async.elapse(const Duration(seconds: 2));
        expect(h.backend.calls, contains('stop'));
        expect(h.engine.activeSessionId, isEmpty);
      });
    });

    test('a different Core cannot adopt the session', () {
      fakeAsync((async) {
        final h = Harness()..playing('t1');
        h.reconnect();
        h.welcome(serverId: 'core-2');
        h.openSession('s2');
        final result = h.last.sessionOpenResult;
        expect(result.accepted, isFalse);
        expect(result.error, pb.SessionOpenResult_Error.ERROR_BUSY);
        expect(result.ownerServerId, 'core-1');
        expect(h.backend.calls, isNot(contains('stop')));
        async.elapse(const Duration(seconds: 61));
        expect(h.backend.calls, contains('stop'));
        expect(h.engine.activeSessionId, isEmpty);
      });
    });

    test('the owner\'s session id replayed by another Core is refused', () {
      fakeAsync((async) {
        final h = Harness()..playing('t1');
        h.reconnect();
        h.welcome(serverId: 'core-2');
        h.openSession('s1');
        expect(h.last.sessionOpenResult.accepted, isFalse);
        expect(h.engine.sessionOwnerServerId, 'core-1');
        async.elapse(const Duration(minutes: 2));
      });
    });

    test('a close from a Core that is not the owner changes nothing', () {
      fakeAsync((async) {
        final h = Harness()..playing('t1');
        h.reconnect();
        h.welcome(serverId: 'core-2');
        h.deliver(
          pb.Envelope()..sessionClose = (pb.SessionClose()..sessionId = 's1'),
        );
        expect(h.backend.calls, isNot(contains('stop')));
        expect(h.engine.activeSessionId, 's1');
        async.elapse(const Duration(minutes: 2));
      });
    });

    test('a retried open by the owner returns the running session', () {
      final h = Harness()..playing('t1');
      h.openSession('s1');
      expect(h.sent.first.sessionOpenResult.accepted, isTrue);
      expect(h.backend.calls, isNot(contains('stop')));
      expect(h.engine.activeSessionId, 's1');
    });
  });

  test('a reconnect hello reports the running session for reconciliation', () {
    final h = Harness()..playing('t1');
    final sent = <pb.Envelope>[];
    RendererConnection(
      incoming: const Stream<dynamic>.empty(),
      send: (frame) => sent.add(pb.Envelope.fromBuffer(frame)),
      engine: h.engine,
      identity: identity,
    );
    final hello = sent.single.hello;
    expect(hello.activeSessionId, 's1');
    expect(hello.sessionOwnerServerId, 'core-1');
  });

  test(
    'renderer socket backoff retries independently and resets on Welcome',
    () {
      fakeAsync((async) {
        var retries = 0;
        final backoff = RendererReconnectBackoff(() => retries++);
        for (final delay in [1, 2, 4, 8, 16, 30, 30, 30]) {
          final before = retries;
          backoff.failed();
          async.elapse(
            Duration(seconds: delay) - const Duration(milliseconds: 1),
          );
          expect(retries, before);
          async.elapse(const Duration(milliseconds: 1));
          expect(retries, before + 1);
        }

        backoff.connected();
        backoff.failed();
        async.elapse(const Duration(seconds: 1));
        expect(retries, 9);

        backoff.giveUp();
        backoff.failed();
        async.elapse(const Duration(minutes: 1));
        expect(retries, 9);
        backoff.dispose();
      });
    },
  );

  test('renderer socket backoff waits while held until resumed', () {
    fakeAsync((async) {
      var retries = 0;
      var held = true;
      final backoff = RendererReconnectBackoff(
        () => retries++,
        held: () => held,
      );
      backoff.failed();
      async.elapse(const Duration(minutes: 5));
      expect(retries, 0);
      held = false;
      backoff.resume();
      expect(retries, 1);
      backoff.resume();
      expect(retries, 1);

      // Held while its delay runs.
      backoff.failed();
      held = true;
      async.elapse(const Duration(minutes: 5));
      expect(retries, 1);
      held = false;
      backoff.resume();
      expect(retries, 2);

      backoff.failed();
      async.elapse(const Duration(seconds: 4));
      expect(retries, 3);
      backoff.dispose();
    });
  });

  test('the renderer socket stops retrying while the server is offline', () {
    fakeAsync((async) {
      SharedPreferences.setMockInitialValues({
        'Kalinka.host': 'kalinka.local',
        'Kalinka.port': 8000,
      });
      late SharedPreferences prefs;
      SharedPreferences.getInstance().then((p) => prefs = p);
      async.flushMicrotasks();
      final connection = _Connection();
      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          connectionStateProvider.overrideWith(() => connection),
        ],
      );
      addTearDown(container.dispose);
      int epoch() => container.read(rendererSocketRetryEpochProvider);
      final backoff = container.read(rendererReconnectBackoffProvider);

      connection.poweredOff();
      backoff.failed();
      async.elapse(const Duration(minutes: 5));
      expect(epoch(), 0);

      connection.set(ConnectionStatus.reconnecting);
      expect(epoch(), 1);
      backoff.failed();
      async.elapse(const Duration(seconds: 2));
      expect(epoch(), 2);
    });
  });

  test('an unexpected renderer socket close requests one retry', () async {
    final backend = FakeBackend();
    final engine = RendererEngine(backend);
    final incoming = StreamController<dynamic>(sync: true);
    final disconnects = <RendererDisconnectKind>[];
    final connection = RendererConnection(
      incoming: incoming.stream,
      send: (_) {},
      engine: engine,
      identity: identity,
      onDisconnected: disconnects.add,
    );

    await incoming.close();
    expect(disconnects, [RendererDisconnectKind.retryable]);
    connection.close();
    expect(disconnects, hasLength(1));
    engine.dispose();
  });

  test('a terminal Goodbye suppresses renderer reconnects', () {
    final backend = FakeBackend();
    final engine = RendererEngine(backend);
    final incoming = StreamController<dynamic>(sync: true);
    final disconnects = <RendererDisconnectKind>[];
    RendererConnection(
      incoming: incoming.stream,
      send: (_) {},
      engine: engine,
      identity: identity,
      onDisconnected: disconnects.add,
    );

    incoming.add(
      (pb.Envelope()
            ..goodbye = (pb.Goodbye()
              ..reason = pb.Goodbye_Reason.REASON_VERSION_UNSUPPORTED))
          .writeToBuffer(),
    );

    expect(disconnects, [RendererDisconnectKind.terminal]);
    incoming.close();
    engine.dispose();
  });
}
