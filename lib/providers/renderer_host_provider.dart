/// Hosts a renderer inside the app itself: on platforms with an audio
/// backend (web, for now) it registers with the connected server over
/// `/renderer/ws`, making this device an output the server can play through.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../renderer/renderer_connection.dart';
import '../renderer/renderer_engine.dart';
import '../renderer/renderer_identity.dart';
import '../renderer/renderer_platform.dart';
import 'connection_settings_provider.dart';
import 'demo_mode.dart';
import 'renderer_provider.dart';
import 'websocket_provider.dart';

const String sharedPrefRendererId = 'Kalinka.rendererId';

/// Outlives WebSocket connections so the owning Core can reclaim its session.
final rendererEngineProvider = Provider<RendererEngine?>((ref) {
  final backend = createRendererBackend();
  if (backend == null) return null;
  final engine = RendererEngine(backend);
  ref.onDispose(engine.dispose);
  return engine;
});

final rendererIdentityProvider = FutureProvider<RendererIdentity>((ref) async {
  final prefs = ref.watch(sharedPrefsProvider);
  var rendererId = prefs.getString(sharedPrefRendererId);
  if (rendererId == null) {
    rendererId = newUuid();
    await prefs.setString(sharedPrefRendererId, rendererId);
  }
  final info = await PackageInfo.fromPlatform();
  return RendererIdentity(
    rendererId: rendererId,
    instanceId: newUuid(),
    friendlyName: browserDescription() ?? 'Kalinka',
    softwareVersion: info.version,
    os: kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase(),
  );
});

final rendererWebSocketProvider = webSocketProvider('/renderer/ws');

/// Reconnect policy for `/renderer/ws`, independent of the UI socket.
class RendererReconnectBackoff {
  static const _delays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 16),
    Duration(seconds: 30),
  ];

  final void Function() _retry;
  Timer? _timer;
  int _attempt = 0;
  bool _terminal = false;

  RendererReconnectBackoff(this._retry);

  void connected() {
    _timer?.cancel();
    _timer = null;
    _attempt = 0;
  }

  void failed() {
    if (_terminal || _timer != null) return;
    final index = _attempt < _delays.length ? _attempt : _delays.length - 1;
    _attempt++;
    _timer = Timer(_delays[index], () {
      _timer = null;
      if (!_terminal) _retry();
    });
  }

  void giveUp() {
    _terminal = true;
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

final rendererReconnectBackoffProvider = Provider<RendererReconnectBackoff>((
  ref,
) {
  // Terminal rejection applies only to the current endpoint.
  ref.watch(connectionSettingsProvider.select((settings) => settings.address));
  final backoff = RendererReconnectBackoff(() {
    if (ref.mounted) {
      ref.read(rendererSocketRetryEpochProvider.notifier).increment();
    }
  });
  ref.onDispose(backoff.dispose);
  return backoff;
});

/// Maintains one renderer protocol connection to the selected Core.
final rendererHostProvider = Provider<void>((ref) {
  final engine = ref.watch(rendererEngineProvider);
  if (engine == null) return;
  // The demo server turns every outside renderer away at the handshake.
  if (ref.watch(demoModeProvider)) return;
  final reconnect = ref.watch(rendererReconnectBackoffProvider);
  if (!ref.watch(rendererListProvider.select((s) => s.supported))) return;
  final identity = ref.watch(rendererIdentityProvider).value;
  if (identity == null) return;
  // Only a settled AsyncData holds a live socket; while loading or errored,
  // `value` would replay the previous — closed — channel.
  final socket = ref.watch(rendererWebSocketProvider);
  final channel = switch (socket) {
    AsyncData(:final value) => value,
    _ => null,
  };
  if (channel == null) {
    if (socket case AsyncError()) reconnect.failed();
    return;
  }

  final connection = RendererConnection(
    incoming: channel.stream,
    send: channel.sink.add,
    engine: engine,
    identity: identity,
    onWelcomed: reconnect.connected,
    onDisconnected: (kind) {
      switch (kind) {
        case RendererDisconnectKind.retryable:
          reconnect.failed();
        case RendererDisconnectKind.terminal:
          reconnect.giveUp();
      }
    },
  );
  final unregisterPageHide = onPageHide(connection.close);
  ref.onDispose(() {
    unregisterPageHide();
    // Provider rebuilds may be route changes; only page unload is shutdown.
    connection.disconnect();
  });
});
