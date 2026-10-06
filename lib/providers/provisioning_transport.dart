import 'dart:typed_data';

class NearbyBox {
  final String id;
  final String name;
  const NearbyBox(this.id, this.name);
}

abstract class ProvisioningTransport {
  Stream<NearbyBox> get boxes;
  Future<void> scan();
  Future<void> stopScan();
  Future<void> connect(String id);
  Future<Uint8List> read(String characteristic);
  Future<void> write(Uint8List frame);
  Future<void> disconnect();
  Future<void> dispose();
}
