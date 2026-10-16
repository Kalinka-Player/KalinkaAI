@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/providers/network_setup_session_web.dart';
import 'package:web/web.dart' as web;

void main() {
  const key = 'kalinka.setup.client';
  const first = '0123456789abcdef0123456789abcdef';
  const next = 'abcdef0123456789abcdef0123456789';

  setUp(() => web.window.sessionStorage.removeItem(key));
  tearDown(() => web.window.sessionStorage.removeItem(key));

  test('restores the session after the runtime generates a new identity', () {
    expect(restoreSetupSession(first), first);
    expect(restoreSetupSession(next), first);
    expect(web.window.sessionStorage.getItem(key), first);
  });

  test('replaces an invalid saved session before sending commands', () {
    web.window.sessionStorage.setItem(key, 'invalid');
    expect(restoreSetupSession(next), next);
    expect(web.window.sessionStorage.getItem(key), next);
  });
}
