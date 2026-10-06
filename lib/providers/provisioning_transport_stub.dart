import 'dart:typed_data';
import 'provisioning_transport.dart';

ProvisioningTransport createProvisioningTransport() => _Unsupported();

class _Unsupported implements ProvisioningTransport {
  @override
  Stream<NearbyBox> get boxes => const Stream.empty();
  @override
  Future<void> scan() async =>
      throw UnsupportedError('Use the installed app for nearby setup.');
  @override
  Future<void> stopScan() async {}
  @override
  Future<void> connect(String id) async =>
      throw UnsupportedError('Bluetooth unavailable');
  @override
  Future<Uint8List> read(String characteristic) async =>
      throw UnsupportedError('Bluetooth unavailable');
  @override
  Future<void> write(Uint8List frame) async =>
      throw UnsupportedError('Bluetooth unavailable');
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> dispose() async {}
}
