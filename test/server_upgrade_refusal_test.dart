// A refused upgrade is not always a failure: renderers being brought forward
// first means "press it again in a moment", which only the server can say.
// The server also takes only the version its own check last found, which can
// move on between reading the banner and pressing Upgrade.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/server_update_provider.dart';
import 'package:kalinka/providers/upgrade_provider.dart';
import 'package:kalinka/widgets/upgrade_overlay.dart';

import 'support/haptic_recorder.dart';
import 'support/upgrade_server.dart';

const _listed = ServerUpdateInfo(
  currentVersion: '5.14.0',
  latestVersion: '5.14.0',
  updateAvailable: true,
  upgradeSupported: true,
  webCurrentVersion: '0.21.1',
  webLatestVersion: '0.21.2',
  webUpdateAvailable: true,
);

const _waitForRenderers = 'Renderers upgrade first: Kitchen did not answer';

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  /// A route answered with null does not answer at all.
  final Map<String, (int, Map<String, dynamic>)?> answers;
  _Adapter(this.answers);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final answer = answers['${options.method} ${options.path}'];
    if (answer == null) throw const SocketException('Connection refused');
    final (code, body) = answer;
    return ResponseBody.fromString(
      jsonEncode(body),
      code,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

KalinkaPlayerProxy _proxy(_Adapter adapter) => KalinkaPlayerProxyImpl(
  client: kalinkaHttpClient('http://server.test')..httpClientAdapter = adapter,
);

void main() {
  test('the server\'s reason for refusing is what the user reads', () {
    fakeAsync((async) {
      final server =
          UpgradeServer(updateInfo(current: '5.14.0', latest: '5.14.1'))
            ..refusals.add(
              const ServerUpgradeException(_waitForRenderers, statusCode: 409),
            );
      final container = upgradeContainer(server, async);

      container.read(upgradeProvider.notifier).executeUpgrade(_listed);
      async.elapse(Duration.zero);

      final state = container.read(upgradeProvider);
      expect(state.error, _waitForRenderers);
      expect(state.canRetry, isTrue);
      expect(server.requested, ['5.14.1']);
    });
  });

  for (final (status, retry) in [
    (403, false),
    (501, false),
    (400, false),
    (409, true),
    (500, true),
    (503, true),
    (null, true),
  ]) {
    test('a refusal with status $status ${retry ? 'offers' : 'has no'} '
        'Retry', () {
      fakeAsync((async) {
        final server = UpgradeServer(
          updateInfo(current: '5.14.0', latest: '5.14.1'),
        )..refusals.add(ServerUpgradeException('Refused', statusCode: status));
        final container = upgradeContainer(server, async);

        container.read(upgradeProvider.notifier).executeUpgrade(_listed);
        async.elapse(Duration.zero);

        final state = container.read(upgradeProvider);
        expect(state.error, 'Refused');
        expect(state.canRetry, retry);
        expect(state.isDone, isFalse);
      });
    });
  }

  test('a demo server\'s refusal reads in its words and is final', () async {
    final api = _proxy(
      _Adapter({
        'PUT /server/upgrade': (
          403,
          {
            'detail': {
              'code': 'demo_read_only',
              'message': 'This is a read-only demo server.',
            },
          },
        ),
      }),
    );

    await expectLater(
      api.upgradeServer('5.14.1'),
      throwsA(
        isA<ServerUpgradeException>()
            .having(
              (e) => e.message,
              'message',
              'This is a read-only demo server.',
            )
            .having((e) => e.statusCode, 'statusCode', 403)
            .having((e) => e.transient, 'transient', isFalse),
      ),
    );
  });

  test('a server that does not answer can be asked again', () async {
    final api = _proxy(_Adapter({'PUT /server/upgrade': null}));

    await expectLater(
      api.upgradeServer('5.14.1'),
      throwsA(
        isA<ServerUpgradeException>()
            .having(
              (e) => e.message,
              'message',
              'The server did not answer the upgrade request',
            )
            .having((e) => e.statusCode, 'statusCode', isNull)
            .having((e) => e.transient, 'transient', isTrue),
      ),
    );
  });

  test('Upgrade asks for the server\'s current update, not the listed one', () {
    fakeAsync((async) {
      final server = UpgradeServer(
        updateInfo(current: '5.14.0', latest: '5.14.0', web: true),
      );
      final container = upgradeContainer(server, async);
      ServerUpdateInfo? cached;
      container.read(serverUpdateProvider.future).then((u) => cached = u);
      async.elapse(Duration.zero);
      server.update = updateInfo(
        current: '5.14.0',
        latest: '5.14.1',
        web: true,
      );

      container.read(upgradeProvider.notifier).executeUpgrade(cached!);
      async.elapse(Duration.zero);

      expect(cached!.latestVersion, '5.14.0');
      expect(server.requested, ['5.14.1']);
      var state = container.read(upgradeProvider);
      expect(state.error, isNull);
      expect(state.targetVersion, '5.14.1');
      expect(state.packagesOnly, isFalse);
      expect(
        state.note,
        'Version 5.14.1 came out after the update was listed.',
      );
      expect(
        container.read(serverUpdateProvider).value!.changes,
        contains('Server: 5.14.0 → 5.14.1'),
      );

      server.version = '5.14.1';
      async.elapse(const Duration(seconds: 3));
      state = container.read(upgradeProvider);
      expect(state.isDone, isTrue);
      expect(
        state.note,
        'Version 5.14.1 came out after the update was listed.',
      );
    });
  });

  test('a listed update the server still offers carries no note', () {
    fakeAsync((async) {
      final server = UpgradeServer(
        updateInfo(current: '5.14.0', latest: '5.14.0', web: true),
      );
      final container = upgradeContainer(server, async);

      container.read(upgradeProvider.notifier).executeUpgrade(_listed);
      async.elapse(Duration.zero);

      expect(server.requested, ['5.14.0']);
      expect(container.read(upgradeProvider).note, isNull);
    });
  });

  test('a 409 after the update moved on is sent once more, with the new '
      'version', () {
    fakeAsync((async) {
      final server =
          UpgradeServer(updateInfo(current: '5.14.0', latest: '5.14.1'))
            ..refusals.add(
              const ServerUpgradeException(
                "Requested version '5.14.1' is not the available update '5.14.2'",
                statusCode: 409,
              ),
            );
      server.onUpgrade = (_) =>
          server.update = updateInfo(current: '5.14.0', latest: '5.14.2');
      final container = upgradeContainer(server, async);

      container.read(upgradeProvider.notifier).executeUpgrade(_listed);
      async.elapse(Duration.zero);

      expect(server.requested, ['5.14.1', '5.14.2']);
      final state = container.read(upgradeProvider);
      expect(state.error, isNull);
      expect(state.targetVersion, '5.14.2');
      expect(state.currentStep, UpgradeStep.installing);

      server.version = '5.14.2';
      async.elapse(const Duration(seconds: 3));
      expect(container.read(upgradeProvider).isDone, isTrue);
    });
  });

  test('a 409 the server words as a stale version, with the update '
      'unchanged, is not sent again', () {
    fakeAsync((async) {
      const detail =
          "Requested version '5.14.1' is not the available update '5.14.2'";
      final server = UpgradeServer(
        updateInfo(current: '5.14.0', latest: '5.14.1'),
      )..refusals.add(const ServerUpgradeException(detail, statusCode: 409));
      final container = upgradeContainer(server, async);

      container.read(upgradeProvider.notifier).executeUpgrade(_listed);
      async.elapse(Duration.zero);

      expect(server.requested, ['5.14.1']);
      expect(server.updateReads, 2);
      final state = container.read(upgradeProvider);
      expect(state.error, detail);
      expect(state.canRetry, isTrue);
    });
  });

  test('any other 409 shows the server\'s words at once, and Retry sends it '
      'again', () {
    fakeAsync((async) {
      final server =
          UpgradeServer(updateInfo(current: '5.14.0', latest: '5.14.1'))
            ..refusals.add(
              const ServerUpgradeException(_waitForRenderers, statusCode: 409),
            );
      final container = upgradeContainer(server, async);

      container.read(upgradeProvider.notifier).executeUpgrade(_listed);
      async.elapse(Duration.zero);

      expect(server.requested, ['5.14.1']);
      expect(server.updateReads, 1);
      var state = container.read(upgradeProvider);
      expect(state.error, _waitForRenderers);
      expect(state.canRetry, isTrue);
      expect(state.isUpgrading, isTrue);

      container.read(upgradeProvider.notifier)
        ..retry()
        ..retry();
      async.elapse(Duration.zero);

      expect(server.requested, ['5.14.1', '5.14.1']);
      state = container.read(upgradeProvider);
      expect(state.error, isNull);
      expect(state.canRetry, isFalse);
      expect(state.currentStep, UpgradeStep.installing);

      server.version = '5.14.1';
      async.elapse(const Duration(seconds: 3));
      expect(container.read(upgradeProvider).isDone, isTrue);
    });
  });

  test('pressing Upgrade on a stale banner sends the server\'s version in '
      'the request body', () {
    fakeAsync((async) {
      final adapter = _Adapter({
        'GET /server/update': (
          200,
          updateInfo(current: '5.14.0', latest: '5.14.1', web: true),
        ),
        'PUT /server/upgrade': (200, {'status': 'started'}),
        'GET /server/version': (200, {'server_version': '5.14.1'}),
      });
      final container = ProviderContainer(
        overrides: [kalinkaProxyProvider.overrideWithValue(_proxy(adapter))],
      );
      addTearDown(container.dispose);

      container.read(upgradeProvider.notifier).executeUpgrade(_listed);
      async.elapse(const Duration(milliseconds: 10));

      final put = adapter.requests.singleWhere((r) => r.method == 'PUT');
      expect(jsonDecode(put.data as String), {'version': '5.14.1'});

      async.elapse(const Duration(seconds: 4));
      expect(container.read(upgradeProvider).isDone, isTrue);
    });
  });

  test('a 409 keeps its status and the server\'s detail', () async {
    const detail =
        "Requested version '5.14.0' is not the available update "
        "'5.14.1'";
    final api = _proxy(
      _Adapter({
        'PUT /server/upgrade': (409, {'detail': detail}),
      }),
    );

    await expectLater(
      api.upgradeServer('5.14.0'),
      throwsA(
        isA<ServerUpgradeException>()
            .having((e) => e.statusCode, 'statusCode', 409)
            .having((e) => e.message, 'message', detail),
      ),
    );
  });

  test('an update already installed elsewhere ends as up to date, with no '
      'request sent', () {
    fakeAsync((async) {
      final server = UpgradeServer(
        updateInfo(current: '5.14.1', latest: '5.14.1'),
        version: '5.14.1',
      );
      final container = upgradeContainer(server, async);

      container.read(upgradeProvider.notifier).executeUpgrade(_listed);
      async.elapse(Duration.zero);

      expect(server.requested, isEmpty);
      final state = container.read(upgradeProvider);
      expect(state.isDone, isTrue);
      expect(state.upToDate, isTrue);
      expect(state.error, isNull);
      expect(state.targetVersion, '5.14.1');
    });
  });

  test('a refusal sent while the check could not be read ends as up to '
      'date on Retry', () {
    fakeAsync((async) {
      final server =
          UpgradeServer(
              updateInfo(current: '5.14.1', latest: '5.14.1'),
              version: '5.14.1',
            )
            ..down = true
            ..refusals.add(
              const ServerUpgradeException(
                'No update available',
                statusCode: 409,
              ),
            );
      final container = upgradeContainer(server, async);

      container.read(upgradeProvider.notifier).executeUpgrade(_listed);
      async.elapse(Duration.zero);

      expect(server.requested, ['5.14.0']);
      var state = container.read(upgradeProvider);
      expect(state.error, 'No update available');
      expect(state.canRetry, isTrue);

      server.down = false;
      container.read(upgradeProvider.notifier).retry();
      async.elapse(Duration.zero);

      expect(server.requested, ['5.14.0']);
      state = container.read(upgradeProvider);
      expect(state.upToDate, isTrue);
      expect(state.error, isNull);
    });
  });

  testWidgets('the overlay says the server is already up to date', (
    tester,
  ) async {
    final server = UpgradeServer(
      updateInfo(current: '5.14.0', latest: '5.14.1'),
    );
    await pumpUpgradeBanner(tester, server);
    server
      ..update = updateInfo(current: '5.14.1', latest: '5.14.1')
      ..version = '5.14.1';

    await confirmUpgrade(tester);

    expect(server.requested, isEmpty);
    expect(find.text('Already up to date'), findsOneWidget);
    expect(
      find.text(
        'The server runs version 5.14.1, with nothing left to install.',
      ),
      findsOneWidget,
    );
    expect(find.text('Installing new version'), findsNothing);
    expect(find.text('Close'), findsNothing);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(UpgradeOverlay), findsNothing);
    expect(find.text('Your player is up to date'), findsOneWidget);
  });

  testWidgets('Upgrade on a stale banner installs the newer release and says '
      'so', (tester) async {
    final server = UpgradeServer(
      updateInfo(current: '5.14.0', latest: '5.14.0', web: true),
    );
    await pumpUpgradeBanner(tester, server);
    server.update = updateInfo(current: '5.14.0', latest: '5.14.1', web: true);

    await confirmUpgrade(tester);

    expect(server.requested, ['5.14.1']);
    expect(
      find.text('Version 5.14.1 came out after the update was listed.'),
      findsOneWidget,
    );
    expect(
      find.text('Installing version 5.14.1… this can take several minutes.'),
      findsOneWidget,
    );
    expect(find.text('Installing new version'), findsOneWidget);
    expect(find.text('Updating packages'), findsNothing);
    expect(find.text('Server: 5.14.0 → 5.14.1'), findsOneWidget);

    server.version = '5.14.1';
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Upgrade complete'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('the overlay offers Retry for a refused request', (tester) async {
    HapticRecorder.install();
    final server =
        UpgradeServer(updateInfo(current: '5.14.0', latest: '5.14.1'))
          ..refusals.add(
            const ServerUpgradeException(_waitForRenderers, statusCode: 409),
          );
    final container = ProviderContainer(
      overrides: [kalinkaProxyProvider.overrideWithValue(server)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: UpgradeOverlay(onDismiss: () {})),
      ),
    );

    container.read(upgradeProvider.notifier).executeUpgrade(_listed);
    await tester.pump();
    await tester.pump();

    expect(find.text(_waitForRenderers), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();

    expect(server.requested, ['5.14.1', '5.14.1']);
    expect(find.text(_waitForRenderers), findsNothing);
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Installing new version'), findsOneWidget);

    server.version = '5.14.1';
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Upgrade complete'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });
}
