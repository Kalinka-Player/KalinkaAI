import 'dart:async';

import 'package:flutter/foundation.dart';

import 'provisioning_protocol.dart';
import 'provisioning_transport.dart';

enum SetupPhase {
  scanning,
  choosing,
  connecting,
  credentials,
  joining,
  changingNetwork,
  reaching,
  done,
}

class ProvisionedEndpoint {
  final String name;
  final String host;
  final int port;
  final String? serverId;
  const ProvisionedEndpoint(this.name, this.host, this.port, this.serverId);
}

/// Transport and network handoff are injected so a fake exercises the same flow.
class ProvisioningController extends ChangeNotifier {
  final ProvisioningTransport transport;
  final Future<ProvisionedEndpoint?> Function(ProvisioningStatus, String?)
  reach;
  final Duration pollInterval;
  final Duration joinTimeout;
  final Duration handoffTimeout;
  final Duration wifiScanTimeout;
  final List<NearbyBox> boxes = [];
  final List<ProvisioningNetwork> networks = [];
  bool scanningWifi = false;
  WifiJoinStage? wifiStage;
  String? wifiScanError;
  int _wifiGeneration = 0;
  SetupPhase phase = SetupPhase.scanning;
  String? error;
  NearbyBox? selected;
  ProvisioningStatus? status;
  ProvisionedEndpoint? endpoint;
  StreamSubscription<NearbyBox>? _scanSubscription;
  Timer? _scanTimer;
  int _generation = 0;
  bool _disposed = false;
  String? _identity;

  ProvisioningController(
    this.transport,
    this.reach, {
    this.pollInterval = const Duration(seconds: 2),
    this.joinTimeout = const Duration(seconds: 100),
    this.handoffTimeout = const Duration(seconds: 150),
    this.wifiScanTimeout = const Duration(seconds: 30),
  });

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  Future<void> scan() async {
    final generation = ++_generation;
    ++_wifiGeneration;
    scanningWifi = false;
    final hadSelection = selected != null;
    selected = null;
    status = null;
    endpoint = null;
    _identity = null;
    networks.clear();
    wifiStage = null;
    wifiScanError = null;
    error = null;
    phase = SetupPhase.scanning;
    boxes.clear();
    _scanTimer?.cancel();
    await _scanSubscription?.cancel();
    if (!_current(generation)) return;
    _scanSubscription = transport.boxes.listen((box) {
      if (!_current(generation)) return;
      final index = boxes.indexWhere((b) => b.id == box.id);
      if (index < 0) {
        boxes.add(box);
      } else {
        boxes[index] = box;
      }
      _changed();
    });
    _changed();
    try {
      if (hadSelection) await transport.disconnect();
      if (!_current(generation)) return;
      await transport.scan();
      if (!_current(generation)) {
        await transport.stopScan();
        return;
      }
      _scanTimer = Timer(const Duration(seconds: 20), () async {
        try {
          await transport.stopScan();
        } catch (_) {}
        if (!_current(generation)) return;
        phase = SetupPhase.choosing;
        _changed();
      });
    } catch (_) {
      if (!_current(generation)) return;
      phase = SetupPhase.choosing;
      error =
          'Allow Bluetooth/Nearby devices access and turn on Bluetooth. '
          'On older Android phones, also turn on Location, then scan again.';
      _changed();
    }
  }

  Future<void> select(NearbyBox box) async {
    final generation = ++_generation;
    ++_wifiGeneration;
    scanningWifi = false;
    wifiScanError = null;
    networks.clear();
    wifiStage = null;
    _scanTimer?.cancel();
    if (selected?.id != box.id) {
      _identity = null;
      status = null;
    }
    selected = box;
    error = null;
    phase = SetupPhase.connecting;
    _changed();
    try {
      await transport.connect(box.id);
      // Returning to discovery owns disconnection. A late connection must
      // not disconnect a newly selected box, but disposal still needs cleanup.
      if (!_current(generation)) {
        if (_disposed) await transport.disconnect();
        return;
      }
      final next = ProvisioningStatus.decode(
        await transport.read(provisionStatusUuid),
      );
      if (!_current(generation)) return;
      status = next;
      if (next.state == BoxState.joining || next.state == BoxState.joined) {
        await _waitForJoin(generation);
      } else {
        phase = SetupPhase.credentials;
      }
    } on FormatException catch (e) {
      if (_current(generation)) error = e.message;
    } catch (_) {
      if (_current(generation)) {
        error =
            'Could not pair with this box. Accept the pairing prompt and try again. '
            'If the box was reflashed, forget it in Bluetooth settings first.';
      }
    }
    if (!_current(generation)) return;
    if (error != null && phase == SetupPhase.connecting) {
      phase = SetupPhase.choosing;
    }
    _changed();
  }

  Future<void> join(String ssid, String password, String country) async {
    if (scanningWifi) return;
    final generation = ++_generation;
    phase = SetupPhase.joining;
    error = null;
    wifiStage = WifiJoinStage.preparing;
    _changed();
    try {
      // Password entry can outlast the Bluetooth connection.
      final ready = await _readStatus(generation);
      if (ready == null) return;
      status = ready;
      if (ready.state == BoxState.joining || ready.state == BoxState.joined) {
        await _waitForJoin(generation);
        _changed();
        return;
      }
      if (ready.state != BoxState.idle && ready.state != BoxState.failed) {
        throw StateError('Setup is closed');
      }
      try {
        // A lost final acknowledgement does not mean the join was rejected.
        for (final frame in provisionFrames({
          'op': 'join',
          'ssid': ssid,
          'password': password,
          'country': country,
        })) {
          if (!_current(generation)) return;
          await transport.write(frame);
        }
      } catch (_) {
        if (!_current(generation)) return;
        final next = await _readStatus(generation);
        if (next == null) return;
        if (next.state != BoxState.joining &&
            next.state != BoxState.joined &&
            next.state != BoxState.failed) {
          rethrow;
        }
        status = next;
      }
      await _waitForJoin(generation);
    } catch (_) {
      if (_current(generation)) {
        error =
            'Could not confirm the box’s status. Retry to check whether it joined Wi-Fi.';
        phase = SetupPhase.joining;
      }
    }
    _changed();
  }

  Future<ProvisioningStatus?> _readStatus(int generation) => _withBleRecovery(
    () async =>
        ProvisioningStatus.decode(await transport.read(provisionStatusUuid)),
    () => _current(generation),
  );

  /// Retries reads and idempotent operations, never credential submission.
  Future<T?> _withBleRecovery<T>(
    Future<T> Function() operation,
    bool Function() current,
  ) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (!current()) return null;
      try {
        if (attempt > 0) {
          // Discard stale GATT state before retrying the secure connection.
          await transport.disconnect();
          if (!current()) return null;
          await transport.connect(selected!.id);
          if (!current()) {
            if (_disposed) await transport.disconnect();
            return null;
          }
        }
        final result = await operation();
        return current() ? result : null;
      } on FormatException {
        rethrow;
      } catch (_) {
        if (attempt == 2) rethrow;
        if (!current()) return null;
        await Future<void>.delayed(pollInterval);
      }
    }
    return null;
  }

  Future<void> _waitForJoin(int generation) async {
    if (!_current(generation)) return;
    final deadline = DateTime.now().add(joinTimeout);
    phase = SetupPhase.joining;
    _changed();
    while (_current(generation) && DateTime.now().isBefore(deadline)) {
      final next = await _readStatus(generation);
      if (next == null) return;
      status = next;
      if (status!.state == BoxState.joining && status!.canReportProgress) {
        try {
          final stage = decodeWifiProgress(
            await transport.read(provisionProgressUuid),
          );
          if (!_current(generation)) return;
          if (stage != wifiStage) {
            wifiStage = stage;
            _changed();
          }
        } catch (_) {
          // Status remains authoritative if optional progress is unavailable.
        }
      }
      if (!_current(generation)) return;
      if (status!.state == BoxState.failed) {
        error = status!.failureMessage;
        // The failure reason identifies a missed final progress update too.
        wifiStage = switch (status!.reason) {
          3 => WifiJoinStage.gettingAddress,
          6 => WifiJoinStage.saving,
          1 || 2 || 4 || 5 || 7 => WifiJoinStage.authenticating,
          _ => wifiStage,
        };
        return;
      }
      if (status!.state == BoxState.joined) {
        await _handoff(generation);
        return;
      }
      await Future<void>.delayed(pollInterval);
    }
    if (_current(generation)) {
      error =
          'The box has not confirmed a connection. Retry to check its status.';
    }
  }

  Future<void> retryHandoff() => _handoff(++_generation);

  Future<void> reconnect() async {
    if (selected != null) await select(selected!);
  }

  Future<void> changeNetwork() async {
    if (selected == null || status?.canChangeNetwork != true) return;
    final generation = ++_generation;
    ++_wifiGeneration;
    scanningWifi = false;
    error = null;
    phase = SetupPhase.changingNetwork;
    _changed();
    try {
      await transport.connect(selected!.id);
      if (!_current(generation)) return;
      for (final frame in provisionFrames({'op': 'change_network'})) {
        if (!_current(generation)) return;
        await transport.write(frame);
      }
      final deadline = DateTime.now().add(const Duration(seconds: 45));
      while (_current(generation) && DateTime.now().isBefore(deadline)) {
        final next = ProvisioningStatus.decode(
          await transport.read(provisionStatusUuid),
        );
        if (!_current(generation)) return;
        status = next;
        if (next.state == BoxState.idle || next.state == BoxState.failed) {
          networks.clear();
          wifiStage = null;
          phase = SetupPhase.credentials;
          _changed();
          return;
        }
        await Future<void>.delayed(pollInterval);
      }
      if (!_current(generation)) return;
      throw StateError('reset timed out');
    } catch (_) {
      if (_current(generation)) {
        error =
            'The box has not reopened network selection. Keep the phone close and '
            'try again while Bluetooth setup is available.';
        phase = SetupPhase.choosing;
        _changed();
      }
    }
  }

  Future<void> scanWifi(String country) async {
    if (phase != SetupPhase.credentials ||
        scanningWifi ||
        status?.canScanWifi != true) {
      return;
    }
    final generation = _generation;
    final wifiGeneration = ++_wifiGeneration;
    bool current() => _current(generation) && wifiGeneration == _wifiGeneration;
    wifiScanError = null;
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(country)) {
      wifiScanError = 'Enter your two-letter country code before scanning.';
      _changed();
      return;
    }
    scanningWifi = true;
    networks.clear();
    _changed();
    try {
      await _readStatus(generation);
      if (!current()) return;
      for (final frame in provisionFrames({'op': 'scan', 'country': country})) {
        if (!current()) return;
        await transport.write(frame);
      }
      final deadline = DateTime.now().add(wifiScanTimeout);
      ProvisioningNetworkPage? first;
      while (current() && DateTime.now().isBefore(deadline)) {
        first = await _withBleRecovery(
          () async => ProvisioningNetworkPage.decode(
            await transport.read(provisionNetworksUuid),
          ),
          current,
        );
        if (first == null) return;
        if (first.state == 'failed') throw StateError('scan failed');
        if (first.state == 'ready') break;
        await Future<void>.delayed(pollInterval);
      }
      if (!current()) return;
      if (first == null || first.state != 'ready' || first.page != 0) {
        throw StateError('scan timed out');
      }
      final found = [...first.networks];
      for (var page = 1; page < first.pages; page++) {
        final next = await _withBleRecovery(() async {
          for (final frame in provisionFrames({
            'op': 'networks',
            'page': page,
          })) {
            if (!current()) return null;
            await transport.write(frame);
          }
          if (!current()) return null;
          return ProvisioningNetworkPage.decode(
            await transport.read(provisionNetworksUuid),
          );
        }, current);
        if (next == null) return;
        if (next.id != first.id ||
            next.page != page ||
            next.pages != first.pages ||
            next.state != 'ready') {
          throw StateError('scan changed');
        }
        found.addAll(next.networks);
      }
      networks.addAll(found);
    } catch (_) {
      if (current()) {
        wifiScanError =
            'Could not get networks from the box. Retry the scan, '
            'reconnect to the box, or enter the network name below.';
      }
    } finally {
      if (current()) {
        scanningWifi = false;
        _changed();
      }
    }
  }

  Future<void> _handoff(int generation) async {
    phase = SetupPhase.reaching;
    error = null;
    _changed();
    final deadline = DateTime.now().add(handoffTimeout);
    while (_current(generation) && DateTime.now().isBefore(deadline)) {
      try {
        _identity ??= decodeProvisioningIdentity(
          await transport.read(provisionIdentityUuid),
        );
      } catch (_) {
        // The network address is enough for direct handoff when BLE drops.
      }
      if (!_current(generation)) return;
      try {
        final found = await reach(status!, _identity);
        if (!_current(generation)) return;
        if (found != null) {
          endpoint = found;
          try {
            for (final frame in provisionFrames({'op': 'complete'})) {
              if (!_current(generation)) return;
              await transport.write(frame);
            }
          } catch (_) {
            /* The box also closes setup after its grace period. */
          }
          if (!_current(generation)) return;
          phase = SetupPhase.done;
          _changed();
          return;
        }
      } catch (_) {
        /* Core may still be starting. */
      }
      await Future<void>.delayed(pollInterval);
    }
    if (_current(generation)) {
      error = status!.isTest
          ? 'Test credentials received. Start Kalinka on the laptop to test the network handoff.'
          : 'The box joined Wi-Fi but could not be reached. Put this phone on the same network, '
                'allow Local Network access, and check that the router allows devices to communicate.';
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _scanTimer?.cancel();
    unawaited(_scanSubscription?.cancel());
    unawaited(transport.dispose().catchError((_) {}));
    super.dispose();
  }
}
