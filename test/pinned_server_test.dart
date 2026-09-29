import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/providers/pinned_server.dart';

void main() {
  test('host:port parses', () {
    expect(parseHostPort('127.0.0.1:8000'), (host: '127.0.0.1', port: 8000));
    expect(parseHostPort('streamer.local:8090'), (
      host: 'streamer.local',
      port: 8090,
    ));
  });

  test('anything else is no server', () {
    expect(parseHostPort(''), isNull);
    expect(parseHostPort('localhost'), isNull);
    expect(parseHostPort(':8000'), isNull);
    expect(parseHostPort('localhost:http'), isNull);
    expect(parseHostPort('localhost:70000'), isNull);
  });
}
