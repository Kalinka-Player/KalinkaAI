import 'dart:async';
import 'dart:convert';
import 'dart:typed_data' show Uint8List;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/ext_device_events.dart' show ExtDeviceEvent;
import '../data_model/playqueue_events.dart' show PlayQueueEvent;
import '../providers/connection_settings_provider.dart';
import '../providers/connection_state_provider.dart';
import '../providers/kalinka_player_api_provider.dart';
import '../providers/websocket_provider.dart'
    show closedByApp, deviceWebSocketProvider, queueWebSocketProvider;

import 'package:logger/logger.dart';

final logger = Logger();

StreamProvider<TEvent> makeEventBusProvider<TEvent>({
  required Stream<String> Function(Ref ref, CancelToken cancel) openStream,
  required TEvent Function(Object? json) decodeEvent,
}) {
  return StreamProvider.autoDispose<TEvent>((ref) async* {
    final cancel = CancelToken();
    final Stream<String> stream = openStream(ref, cancel);

    ref.onDispose(() {
      cancel.cancel();
    });

    await for (final line in stream) {
      if (cancel.isCancelled) {
        break;
      }

      if (line.isEmpty) continue;

      try {
        final obj = jsonDecode(line);
        yield decodeEvent(obj);
      } catch (e, stack) {
        logger.e('Failed to parse wire event: $e', error: e, stackTrace: stack);
        // Optionally: yield a special error event or just skip
        continue;
      }
    }
  });
}

Stream<String> openPlayQueueStream(Ref ref, CancelToken cancel) async* {
  final dio = ref.watch(httpClientProvider);
  final conn = ref.read(connectionStateProvider.notifier);
  final url = '/queue/events';
  final resp = await dio.get<ResponseBody>(
    url,
    options: Options(responseType: ResponseType.stream),
    cancelToken: cancel,
  );

  if (!cancel.isCancelled) {
    conn.connected();
  }

  StreamTransformer<Uint8List, List<int>> unit8Transformer =
      StreamTransformer.fromHandlers(
        handleData: (data, sink) {
          sink.add(List<int>.from(data));
        },
      );

  yield* resp.data!.stream
      .transform(unit8Transformer)
      .transform(utf8.decoder)
      .transform(const LineSplitter());
}

// WebSocket-based queue stream (expects text frames with JSON)
Stream<String> openPlayQueueWsStream(Ref ref, CancelToken cancel) async* {
  final channel = await ref.watch(queueWebSocketProvider.future);
  final conn = ref.read(connectionStateProvider.notifier);

  // Close the socket if the caller cancels via CancelToken
  cancel.whenCancel.then((_) => channel.sink.close());

  try {
    yield* channel.stream.map((event) {
      if (event is String) return event;
      if (event is List<int>) return utf8.decode(event);
      return event.toString();
    });
  } finally {
    channel.sink.close();
    // Stream ended — if not intentionally cancelled or replaced AND the user
    // hasn't deliberately disconnected (settings cleared), the server dropped
    // the connection. Trigger reconnection so the UI reflects the lost
    // connection.
    if (!cancel.isCancelled &&
        !closedByApp(channel) &&
        ref.read(connectionSettingsProvider).isSet) {
      conn.startReconnecting();
    }
  }
}

// Web-Socket-based external device stream (expects text frames with JSON)
Stream<String> openExtDeviceWsStream(Ref ref, CancelToken cancel) async* {
  final channel = await ref.watch(deviceWebSocketProvider.future);
  final conn = ref.read(connectionStateProvider.notifier);

  // Close the socket if the caller cancels via CancelToken
  cancel.whenCancel.then((_) => channel.sink.close());

  try {
    yield* channel.stream.map((event) {
      if (event is String) return event;
      if (event is List<int>) return utf8.decode(event);
      return event.toString();
    });
  } finally {
    channel.sink.close();
    // Stream ended — if not intentionally cancelled or replaced AND the user
    // hasn't deliberately disconnected (settings cleared), the server dropped
    // the connection. Trigger reconnection so the UI reflects the lost
    // connection.
    if (!cancel.isCancelled &&
        !closedByApp(channel) &&
        ref.read(connectionSettingsProvider).isSet) {
      conn.startReconnecting();
    }
  }
}

Stream<String> openExtDeviceStream(Ref ref, CancelToken cancel) async* {
  final dio = ref.watch(httpClientProvider);
  final url = '/device/events';
  final resp = await dio.get<ResponseBody>(
    url,
    options: Options(responseType: ResponseType.stream),
    cancelToken: cancel,
  );

  StreamTransformer<Uint8List, List<int>> unit8Transformer =
      StreamTransformer.fromHandlers(
        handleData: (data, sink) {
          sink.add(List<int>.from(data));
        },
      );

  yield* resp.data!.stream
      .transform(unit8Transformer)
      .transform(utf8.decoder)
      .transform(const LineSplitter());
}

final playQueueEventBusProvider = makeEventBusProvider<PlayQueueEvent>(
  openStream: openPlayQueueWsStream,
  decodeEvent: (json) => PlayQueueEvent.fromJson(json as Map<String, Object?>),
);

final extDeviceEventBusProvider = makeEventBusProvider<ExtDeviceEvent>(
  openStream: openExtDeviceWsStream,
  decodeEvent: (json) => ExtDeviceEvent.fromJson(json as Map<String, Object?>),
);
