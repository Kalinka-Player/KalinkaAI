import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

import 'provisioning_protocol.dart';
import 'provisioning_transport.dart';

ProvisioningTransport createProvisioningTransport() =>
    BleProvisioningTransport();

class BleProvisioningTransport implements ProvisioningTransport {
  String? _device;
  String? _readyDevice;
  int _generation = 0;
  bool _disposed = false;
  Future<void> _operations = Future<void>.value();

  // Cleanup of an old connection must finish before another can own its handle.
  Future<T> _run<T>(Future<T> Function() operation) {
    final result = _operations.then((_) => operation());
    _operations = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  void _check(int generation) {
    if (_disposed || generation != _generation) {
      throw StateError('Bluetooth operation superseded.');
    }
  }

  @override
  Stream<NearbyBox> get boxes => UniversalBle.scanStream.map(
    (d) => NearbyBox(
      d.deviceId,
      d.name?.isNotEmpty == true ? d.name! : 'Kalinka box',
    ),
  );

  @override
  Future<void> scan() {
    final generation = _generation;
    return _run(() async {
      _check(generation);
      // BLE library logging includes credential payloads, even in debug builds.
      await UniversalBle.setLogLevel(BleLogLevel.none);
      _check(generation);
      await UniversalBle.requestPermissions();
      _check(generation);
      final availability = await UniversalBle.getBluetoothAvailabilityState();
      _check(generation);
      if (availability != AvailabilityState.poweredOn) {
        throw StateError('Turn on Bluetooth and allow Nearby devices access.');
      }
      await UniversalBle.startScan(
        scanFilter: ScanFilter(withServices: [provisionServiceUuid]),
      );
    });
  }

  @override
  Future<void> stopScan() => _run(UniversalBle.stopScan);

  @override
  Future<void> connect(String id) {
    final generation = ++_generation;
    _readyDevice = null;
    return _run(() async {
      _check(generation);
      try {
        await UniversalBle.setLogLevel(BleLogLevel.none);
        _check(generation);
        await UniversalBle.stopScan();
        _check(generation);
        if (_device != null && _device != id) await _closeDevice();
        _check(generation);
        _device = id;
        final state = await UniversalBle.getConnectionState(id);
        _check(generation);
        if (state != BleConnectionState.connected) {
          await UniversalBle.connect(id, timeout: const Duration(seconds: 20));
          _check(generation);
        }
        await UniversalBle.discoverServices(id);
        _check(generation);
        // The encrypted read triggers OS pairing; allow time for the prompt.
        await UniversalBle.read(
          id,
          provisionServiceUuid,
          provisionStatusUuid,
          timeout: const Duration(seconds: 60),
        );
        _check(generation);
        _readyDevice = id;
      } catch (_) {
        await _closeDevice();
        rethrow;
      }
    });
  }

  Future<T> _withDevice<T>(Future<T> Function(String) operation) {
    final generation = _generation;
    final id = _readyDevice;
    if (id == null) {
      return Future.error(StateError('No paired box is selected.'));
    }
    return _run(() async {
      _check(generation);
      final result = await operation(id);
      _check(generation);
      return result;
    });
  }

  @override
  Future<Uint8List> read(String characteristic) => _withDevice(
    (id) => UniversalBle.read(
      id,
      provisionServiceUuid,
      characteristic,
      timeout: const Duration(seconds: 5),
    ),
  );

  @override
  Future<void> write(Uint8List frame) => _withDevice(
    (id) => UniversalBle.write(
      id,
      provisionServiceUuid,
      provisionCommandUuid,
      frame,
    ),
  );

  Future<void> _closeDevice() async {
    final id = _device;
    _device = null;
    _readyDevice = null;
    if (id != null) await UniversalBle.disconnect(id);
  }

  @override
  Future<void> disconnect() {
    ++_generation;
    _readyDevice = null;
    return _run(_closeDevice);
  }

  @override
  Future<void> dispose() {
    _disposed = true;
    ++_generation;
    _readyDevice = null;
    return _run(() async {
      try {
        await UniversalBle.stopScan();
      } finally {
        await _closeDevice();
      }
    });
  }
}
