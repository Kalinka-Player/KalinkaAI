import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../providers/connection_settings_provider.dart';
import '../providers/connection_state_provider.dart'
    show ConnectionStatus, connectionStateProvider, retryEpochProvider;
import 'ws_connect.dart' show connectWs;
import 'package:logger/logger.dart';

final logger = Logger();

/// Forces a new renderer socket without changing global connection state.
final rendererSocketRetryEpochProvider =
    NotifierProvider<RendererSocketRetryEpochNotifier, int>(
      RendererSocketRetryEpochNotifier.new,
    );

class RendererSocketRetryEpochNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state++;
}

/// Heartbeat interval for the event sockets. Dart sends a WebSocket ping on
/// this cadence and closes the socket if the peer stops answering, so a
/// connection killed while backgrounded (machine sleep, NAT/idle timeout)
/// is detected instead of lingering silently half-open. The pings also keep
/// idle NAT mappings alive, preventing some drops outright.
const _heartbeatInterval = Duration(seconds: 15);

/// Cap how long a single connect attempt may hang. `WebSocket.connect` has no
/// timeout of its own, so on a dead/blackholed route (e.g. a fresh socket built
/// on resume after the old one silently died) it can stall indefinitely,
/// leaving the app reporting "connected" over an empty, never-replayed queue.
/// On timeout the connect fails and the normal reconnect cycle takes over.
const _connectTimeout = Duration(seconds: 5);

/// The play-queue event socket is the single source of truth for global
/// connection state. Only its successful open — which triggers the server's
/// replay of the current queue — may report `connected`; only its failure may
/// drive `connecting`/`startReconnecting`. Auxiliary sockets (e.g. /device/ws,
/// opened lazily on first now-playing) piggyback on the queue socket's
/// reconnect cycle via the retry epoch and must not touch connection state,
/// otherwise a device socket opening while the queue socket is still dead would
/// flip the UI to a green "connected" indicator over an empty queue (issue #21).
const _connectionStatePath = '/queue/ws';

/// Provides a configured [WebSocketChannel] for the given path.
///
/// Centralises connection semantics (host/port, heartbeat, connect timeout)
/// and closes the channel when the provider is torn down.
final webSocketProvider = FutureProvider.family<WebSocketChannel, String>((
  ref,
  path,
) async {
  final settings = ref.watch(connectionSettingsProvider);
  final connection = ref.read(connectionStateProvider.notifier);

  if (!settings.isSet) {
    // Stay in loading state rather than entering error state.
    // Riverpod rebuilds this provider when connectionSettingsProvider changes,
    // so the loading future is abandoned and a fresh connection is attempted.
    await Completer<void>().future; // never completes
    throw StateError('unreachable');
  }

  // Renderer retries are independent and may stop after a terminal Goodbye.
  final isRenderer = path == '/renderer/ws';
  if (isRenderer) {
    ref.watch(rendererSocketRetryEpochProvider);
  } else {
    ref.watch(retryEpochProvider);
  }

  // UI-owned sockets pause after the global reconnect escalation.
  final currentStatus = ref.read(connectionStateProvider);
  if (!isRenderer && currentStatus == ConnectionStatus.offline) {
    await Completer<void>().future; // never completes until rebuilt
    throw StateError('unreachable');
  }

  // Only the play-queue socket owns global connection state (see
  // _connectionStatePath). Auxiliary sockets (e.g. /device/ws) must not touch
  // it — a second socket initialising lazily must not downgrade global state.
  final ownsConnectionState = path == _connectionStatePath;

  // Defer state updates to avoid modifying providers during build.
  // Skip during reconnection (connecting() would cancel the retry timer that
  // drives epoch increments) and when already connected (e.g. a stale-socket
  // resume rebuilds the queue socket without dropping the connected state).
  if (ownsConnectionState &&
      currentStatus != ConnectionStatus.reconnecting &&
      currentStatus != ConnectionStatus.connected) {
    Future.microtask(connection.connecting);
  }

  final uri = Uri(
    scheme: settings.wsScheme,
    host: settings.host,
    port: settings.port,
    path: path.startsWith('/') ? path.substring(1) : path,
  );

  final channel = connectWs(uri, pingInterval: _heartbeatInterval);
  try {
    // The explicit timeout also bounds web, where connectWs applies none.
    await channel.ready.timeout(_connectTimeout);
    // Report `connected` only for the queue socket, whose open triggers the
    // queue replay — a device socket opening over a still-dead queue must not.
    if (ownsConnectionState) {
      Future.microtask(connection.connected);
    }

    ref.onDispose(() {
      channel.sink.close();
    });

    return channel;
  } on Object catch (e) {
    // Close the half-open channel so a late connect doesn't leak.
    channel.sink.close();
    logger.e('WebSocket connection error to $uri', error: e);
    // Only the queue socket drives global reconnection; an auxiliary socket
    // failing rebuilds on the next retry epoch without churning the (possibly
    // healthy) queue connection.
    if (ownsConnectionState) {
      Future.microtask(connection.startReconnecting);
    }
    rethrow;
  }
});

final deviceWebSocketProvider = webSocketProvider('/device/ws');

final queueWebSocketProvider = webSocketProvider(_connectionStatePath);
