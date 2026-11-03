import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/playqueue_events.dart';
import '../data_model/receiver_control.dart';
import 'connection_settings_provider.dart';
import 'connection_state_provider.dart';
import 'kalinka_player_api_provider.dart';
import 'server_address.dart';
import 'settings_provider.dart';
import 'playback_time_provider.dart';
import 'wire_event_provider.dart';

class ReceiverInventory {
  final List<ReceiverSnapshot> receivers;
  final bool loading;
  final String? error;
  const ReceiverInventory({
    this.receivers = const [],
    this.loading = false,
    this.error,
  });
}

class ReceiversNotifier extends Notifier<ReceiverInventory> {
  int _revision = 0;
  ServerAddress _server() => ref.read(connectionSettingsProvider).address;
  bool _stale(ServerAddress server) => !ref.mounted || _server() != server;

  @override
  ReceiverInventory build() {
    final settings = ref.watch(
      connectionSettingsProvider.select((s) => s.address),
    );
    _revision++;
    ref.listen(connectionStateProvider, (before, after) {
      if (after == ConnectionStatus.connected && before != after) {
        unawaited(refresh());
      } else if (after != ConnectionStatus.connected &&
          state.receivers.isNotEmpty) {
        _revision++;
        state = ReceiverInventory(
          receivers: state.receivers,
          error: 'Streamer unavailable. Reconnect to check receiver state.',
        );
      }
    });
    ref.listen(appLifecycleProvider, (before, after) {
      if (after == AppLifecycleState.resumed &&
          before != after &&
          ref.read(connectionSettingsProvider).isSet) {
        unawaited(refresh());
      }
    });
    ref.listen(playQueueEventBusProvider, (_, next) {
      if (next case AsyncData(:final value)) {
        final rows = switch (value) {
          ReceiversChangedEvent(:final receivers) => receivers,
          ReplayPlayQueueEvent(:final state) => state.receivers?.receivers,
          _ => null,
        };
        if (rows != null) {
          _revision++;
          state = ReceiverInventory(receivers: rows);
        }
      }
    });
    if (ref.read(connectionSettingsProvider).isSet) {
      Future.microtask(() {
        if (!_stale(settings)) return refresh();
      });
    }
    return const ReceiverInventory(loading: true);
  }

  Future<void> refresh() async {
    final server = _server();
    final revision = ++_revision;
    state = ReceiverInventory(
      receivers: state.receivers,
      loading: true,
      error: state.error,
    );
    try {
      final response = await ref.read(httpClientProvider).get('/receivers');
      if (_stale(server) || revision != _revision) return;
      state = ReceiverInventory(
        receivers: ReceiversSnapshot.fromJson(
          Map<String, dynamic>.from(response.data as Map),
        ).receivers,
      );
    } catch (error) {
      if (_stale(server) || revision != _revision) return;
      if (error is DioException && error.response?.statusCode == 404) {
        state = const ReceiverInventory(); // Servers before receiver API v1.
      } else {
        state = ReceiverInventory(
          receivers: state.receivers,
          error: 'Could not load receivers. Retry to check their state.',
        );
      }
    }
  }

  Future<void> command(
    ReceiverSnapshot receiver,
    Map<String, dynamic> command,
  ) async {
    final server = _server();
    // Never replay a POST after an uncertain result. A GET reconciles it.
    try {
      await ref
          .read(httpClientProvider)
          .post(
            '/receivers/${Uri.encodeComponent(receiver.id)}/commands',
            data: command,
          );
    } on DioException catch (error) {
      final data = error.response?.data;
      final detail = data is Map ? data['detail'] : null;
      throw Exception(
        detail is Map ? detail['message'] : 'The result is unknown. Check the refreshed receiver before trying again.',
      );
    } finally {
      if (!_stale(server)) await refresh();
    }
  }

  Future<String> revealPassword(ReceiverSnapshot receiver) async {
    final server = _server();
    final revision = _revision;
    final response = await ref
        .read(httpClientProvider)
        .post('/receivers/${Uri.encodeComponent(receiver.id)}/password');
    if (_stale(server) || revision != _revision) {
      throw StateError('Receiver changed');
    }
    return (response.data as Map)['password'] as String;
  }

  Future<void> setEnabled(ReceiverSnapshot receiver, bool enabled) async {
    final server = _server();
    try {
      await ref
          .read(settingsProvider.notifier)
          .applyLiveSetting('input_modules.${receiver.id}.enabled', enabled);
    } finally {
      if (!_stale(server)) await refresh();
    }
  }
}

final receiversProvider =
    NotifierProvider<ReceiversNotifier, ReceiverInventory>(
      ReceiversNotifier.new,
    );

final enabledReceiversProvider = Provider<List<ReceiverSnapshot>>(
  (ref) => ref
      .watch(receiversProvider)
      .receivers
      .where((receiver) => receiver.enabled)
      .toList(),
);
