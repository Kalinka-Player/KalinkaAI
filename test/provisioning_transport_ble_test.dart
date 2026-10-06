import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/providers/provisioning_protocol.dart';
import 'package:kalinka/providers/provisioning_transport_ble.dart';
import 'package:universal_ble/universal_ble.dart';

class _BlePlatform extends UniversalBlePlatform {
  Completer<void>? stopGate;
  Completer<void>? connectGate;
  Completer<void>? discoveryGate;
  Completer<void>? readGate;
  final connected = <String>{};
  final connections = <String>[];
  final disconnections = <String>[];
  final discoveries = <String>[];
  final reads = <String>[];
  final writes = <String>[];

  @override
  Future<void> stopScan() async {
    final gate = stopGate;
    stopGate = null;
    await gate?.future;
  }

  @override
  Future<BleConnectionState> getConnectionState(String id) async =>
      connected.contains(id)
      ? BleConnectionState.connected
      : BleConnectionState.disconnected;

  @override
  Future<void> connect(
    String deviceId, {
    Duration? connectionTimeout,
    bool autoConnect = false,
    ConnectionPlatformConfig? platformConfig,
  }) async {
    connections.add(deviceId);
    final gate = connectGate;
    connectGate = null;
    await gate?.future;
    connected.add(deviceId);
    updateConnection(deviceId, true);
  }

  @override
  Future<void> disconnect(String deviceId) async {
    disconnections.add(deviceId);
    connected.remove(deviceId);
    updateConnection(deviceId, false);
  }

  @override
  Future<List<BleService>> discoverServices(
    String id,
    bool withDescriptors,
  ) async {
    discoveries.add(id);
    final gate = discoveryGate;
    discoveryGate = null;
    await gate?.future;
    return [];
  }

  @override
  Future<Uint8List> readValue(
    String id,
    String service,
    String characteristic, {
    Duration? timeout,
  }) async {
    reads.add(id);
    final gate = readGate;
    readGate = null;
    await gate?.future;
    return Uint8List(10);
  }

  @override
  Future<void> writeValue(
    String id,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty property,
  ) async {
    writes.add(id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  late _BlePlatform platform;
  late BleProvisioningTransport transport;

  setUp(() async {
    platform = _BlePlatform();
    UniversalBle.setInstance(platform);
    await UniversalBle.setLogLevel(BleLogLevel.none);
    UniversalBle.queueType = QueueType.none;
    transport = BleProvisioningTransport();
  });
  tearDown(() async {
    await transport.dispose();
    UniversalBle.queueType = QueueType.global;
  });

  test(
    'Back and a new selection invalidate a connect waiting for stopScan',
    () async {
      final gate = Completer<void>();
      platform.stopGate = gate;
      final obsolete = expectLater(transport.connect('old'), throwsStateError);
      await _flush();
      final back = transport.disconnect();
      final selected = transport.connect('new');
      gate.complete();
      await obsolete;
      await back;
      await selected;
      await transport.read(provisionStatusUuid);
      await transport.write(Uint8List.fromList([1]));
      expect(platform.connections, ['new']);
      expect(platform.disconnections, isEmpty);
      expect(platform.reads, everyElement('new'));
      expect(platform.writes, ['new']);
    },
  );

  for (final stage in ['connect', 'discover', 'pair']) {
    for (final nextId in ['new', 'old']) {
      test(
        'late $stage cleanup cannot disconnect the next selection ($nextId)',
        () async {
          final gate = Completer<void>();
          switch (stage) {
            case 'connect':
              platform.connectGate = gate;
            case 'discover':
              platform.discoveryGate = gate;
            case 'pair':
              platform.readGate = gate;
          }
          final obsolete = expectLater(
            transport.connect('old'),
            throwsStateError,
          );
          await _flush();
          final selected = transport.connect(nextId);
          gate.complete();
          await obsolete;
          await selected;
          await transport.write(Uint8List.fromList([1]));
          expect(platform.connections, ['old', nextId]);
          expect(platform.disconnections, ['old']);
          expect(platform.connected, {nextId});
          expect(platform.writes, [nextId]);
        },
      );
    }
  }

  test('queued credentials cannot move to a new box', () async {
    await transport.connect('old');
    final gate = Completer<void>();
    platform.readGate = gate;
    final oldRead = expectLater(
      transport.read(provisionStatusUuid),
      throwsStateError,
    );
    await _flush();
    final oldWrite = expectLater(
      transport.write(Uint8List.fromList([1])),
      throwsStateError,
    );
    final selected = transport.connect('new');
    gate.complete();
    await oldRead;
    await oldWrite;
    await selected;
    expect(platform.writes, isEmpty);
    await transport.write(Uint8List.fromList([2]));
    expect(platform.writes, ['new']);
  });

  test(
    'dispose invalidates a pending connection and releases that device',
    () async {
      final gate = Completer<void>();
      platform.connectGate = gate;
      final obsolete = expectLater(transport.connect('old'), throwsStateError);
      await _flush();
      final disposed = transport.dispose();
      gate.complete();
      await obsolete;
      await disposed;
      expect(platform.connected, isEmpty);
      expect(platform.disconnections, ['old']);
      expect(platform.discoveries, isEmpty);
      await expectLater(transport.connect('new'), throwsStateError);
      await expectLater(transport.write(Uint8List(1)), throwsStateError);
    },
  );
}
