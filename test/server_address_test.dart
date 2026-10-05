import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/providers/server_address.dart';

void main() {
  test('host:port is a server on the local network', () {
    expect(parseServerAddress('127.0.0.1:8000'), (
      scheme: 'http',
      host: '127.0.0.1',
      port: 8000,
    ));
    expect(parseServerAddress('streamer.local:8090'), (
      scheme: 'http',
      host: 'streamer.local',
      port: 8090,
    ));
  });

  test('a scheme may be named, and then its port may be left out', () {
    expect(parseServerAddress('https://demo.kalinkaplayer.com'), (
      scheme: 'https',
      host: 'demo.kalinkaplayer.com',
      port: 443,
    ));
    expect(parseServerAddress('http://127.0.0.1:8000'), (
      scheme: 'http',
      host: '127.0.0.1',
      port: 8000,
    ));
    expect(parseServerAddress(' https://demo.test:8443/ '), (
      scheme: 'https',
      host: 'demo.test',
      port: 8443,
    ));
  });

  test('anything else is no server', () {
    for (final value in [
      '',
      'localhost',
      ':8000',
      'localhost:http',
      'localhost:70000',
      'ftp://files.test',
      'https://',
      'https://demo.test:70000',
    ]) {
      expect(parseServerAddress(value), isNull, reason: value);
    }
  });
}
