import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

import 'provisioning_protocol.dart';
import 'provisioning_transport.dart';

ProvisioningTransport createProvisioningTransport() =>
    BleProvisioningTransport();

class BleProvisioningTransport implements ProvisioningTransport {
  String? _device;

  @override
  Stream<NearbyBox> get boxes => UniversalBle.scanStream.map(
    (d) => NearbyBox(
      d.deviceId,
      d.name?.isNotEmpty == true ? d.name! : 'Kalinka box',
    ),
  );

  @override
  Future<void> scan() async {
    // BLE library debug logging includes write payloads. Disable it before
    // any operation, including on developer builds.
    await UniversalBle.setLogLevel(BleLogLevel.none);
    await UniversalBle.requestPermissions();
    final availability = await UniversalBle.getBluetoothAvailabilityState();
    if (availability != AvailabilityState.poweredOn) {
      throw StateError('Turn on Bluetooth and allow Nearby devices access.');
    }
    await UniversalBle.startScan(
      scanFilter: ScanFilter(withServices: [provisionServiceUuid]),
    );
  }

  @override
  Future<void> stopScan() => UniversalBle.stopScan();

  @override
  Future<void> connect(String id) async {
    await stopScan();
    if (_device != null && _device != id) await disconnect();
    _device = id;
    if (await UniversalBle.getConnectionState(id) !=
        BleConnectionState.connected) {
      await UniversalBle.connect(id, timeout: const Duration(seconds: 20));
    }
    await UniversalBle.discoverServices(id);
    // The encrypted status read triggers OS pairing, including on iOS.
    // Give the user time to accept the system prompt.
    await UniversalBle.read(
      id,
      provisionServiceUuid,
      provisionStatusUuid,
      timeout: const Duration(seconds: 60),
    );
  }

  @override
  Future<Uint8List> read(String characteristic) => UniversalBle.read(
    _device!,
    provisionServiceUuid,
    characteristic,
    timeout: const Duration(seconds: 5),
  );

  @override
  Future<void> write(Uint8List frame) => UniversalBle.write(
    _device!,
    provisionServiceUuid,
    provisionCommandUuid,
    frame,
  );

  @override
  Future<void> disconnect() async {
    final id = _device;
    _device = null;
    if (id != null) await UniversalBle.disconnect(id);
  }

  @override
  Future<void> dispose() async {
    try {
      await stopScan();
    } finally {
      await disconnect();
    }
  }
}
