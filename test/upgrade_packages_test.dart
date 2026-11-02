// When only the web player, renderer or supervisor moves, the server answers
// on the same version throughout, so only its update check can say when the
// installer has finished.

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/providers/server_update_provider.dart';
import 'package:kalinka/providers/upgrade_provider.dart';
import 'package:kalinka/widgets/upgrade_overlay.dart';

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

void main() {
  test('a packages-only upgrade waits until no package is behind', () {
    fakeAsync((async) {
      final server = UpgradeServer(
        updateInfo(current: '5.14.0', latest: '5.14.0', web: true),
      );
      final container = upgradeContainer(server, async);

      container.read(upgradeProvider.notifier).executeUpgrade(_listed);
      async.elapse(Duration.zero);

      expect(server.requested, ['5.14.0']);
      var state = container.read(upgradeProvider);
      expect(state.packagesOnly, isTrue);
      expect(state.currentStep, UpgradeStep.updatingPackages);

      async.elapse(const Duration(seconds: 3));
      server.down = true;
      async.elapse(const Duration(seconds: 3));
      server.down = false;
      async.elapse(const Duration(seconds: 3));
      state = container.read(upgradeProvider);
      expect(state.isDone, isFalse);
      expect(state.error, isNull);
      expect(state.currentStep, UpgradeStep.updatingPackages);

      server.update = updateInfo(current: '5.14.0', latest: '5.14.0');
      async.elapse(const Duration(seconds: 3));

      state = container.read(upgradeProvider);
      expect(state.isDone, isTrue);
      expect(state.error, isNull);
      expect(state.completedSteps, {UpgradeStep.updatingPackages});
      expect(server.updateReads, 5);
      expect(server.versionReads, 0);
      expect(
        container.read(serverUpdateProvider).value!.updateAvailable,
        false,
      );
    });
  });

  test('a build newer than the latest release updates only its packages', () {
    fakeAsync((async) {
      const listed = ServerUpdateInfo(
        currentVersion: '5.17.0rc1',
        latestVersion: '5.16.0',
        updateAvailable: true,
        upgradeSupported: true,
        webCurrentVersion: '0.21.1',
        webLatestVersion: '0.21.2',
        webUpdateAvailable: true,
      );
      expect(listed.changes, ['Web player: 0.21.1 → 0.21.2']);
      final server = UpgradeServer(
        updateInfo(current: '5.17.0rc1', latest: '5.16.0', web: true),
        version: '5.17.0rc1',
      );
      final container = upgradeContainer(server, async);

      container.read(upgradeProvider.notifier).executeUpgrade(listed);
      async.elapse(Duration.zero);

      expect(server.requested, ['5.16.0']);
      var state = container.read(upgradeProvider);
      expect(state.packagesOnly, isTrue);
      expect(state.currentStep, UpgradeStep.updatingPackages);

      server.update = updateInfo(current: '5.17.0rc1', latest: '5.16.0');
      async.elapse(const Duration(seconds: 3));

      state = container.read(upgradeProvider);
      expect(state.isDone, isTrue);
      expect(state.error, isNull);
      expect(server.versionReads, 0);
    });
  });

  test('a packages-only upgrade on a server that names no package waits '
      'until it offers no update', () {
    fakeAsync((async) {
      const behind = {
        'current_version': '5.13.0',
        'latest_version': '5.13.0',
        'update_available': true,
        'upgrade_supported': true,
      };
      const listed = ServerUpdateInfo(
        currentVersion: '5.13.0',
        latestVersion: '5.13.0',
        updateAvailable: true,
        upgradeSupported: true,
      );
      final server = UpgradeServer(behind, version: '5.13.0');
      final container = upgradeContainer(server, async);

      container.read(upgradeProvider.notifier).executeUpgrade(listed);
      async.elapse(const Duration(seconds: 6));

      expect(server.requested, ['5.13.0']);
      var state = container.read(upgradeProvider);
      expect(state.isDone, isFalse);
      expect(state.currentStep, UpgradeStep.updatingPackages);

      server.update = {...behind, 'update_available': false};
      async.elapse(const Duration(seconds: 3));

      state = container.read(upgradeProvider);
      expect(state.isDone, isTrue);
      expect(state.error, isNull);
    });
  });

  test(
    'a packages-only upgrade that never finishes says so at the deadline',
    () {
      fakeAsync((async) {
        final server = UpgradeServer(
          updateInfo(current: '5.14.0', latest: '5.14.0', web: true),
        );
        final container = upgradeContainer(server, async);

        container.read(upgradeProvider.notifier).executeUpgrade(_listed);
        async.elapse(const Duration(minutes: 14, seconds: 57));
        expect(container.read(upgradeProvider).error, isNull);

        async.elapse(const Duration(seconds: 6));
        final state = container.read(upgradeProvider);
        expect(state.isDone, isFalse);
        expect(
          state.error,
          'The packages did not finish updating — check the server manually.',
        );
        expect(state.canRetry, isFalse);
      });
    },
  );

  test('a server upgrade waits for the new version, whatever the update '
      'check says mid-install', () {
    fakeAsync((async) {
      final server = UpgradeServer(
        updateInfo(current: '5.14.0', latest: '5.14.1', web: true),
      );
      final container = upgradeContainer(server, async);

      container.read(upgradeProvider.notifier).executeUpgrade(_listed);
      async.elapse(Duration.zero);
      expect(server.requested, ['5.14.1']);

      server.update = updateInfo(current: '5.14.1', latest: '5.14.1');
      async.elapse(const Duration(seconds: 3));
      var state = container.read(upgradeProvider);
      expect(state.packagesOnly, isFalse);
      expect(state.isDone, isFalse);
      expect(state.currentStep, UpgradeStep.installing);

      server.down = true;
      async.elapse(const Duration(seconds: 3));
      state = container.read(upgradeProvider);
      expect(state.currentStep, UpgradeStep.reconnecting);
      expect(state.completedSteps, {UpgradeStep.installing});

      server
        ..down = false
        ..version = '5.14.1';
      async.elapse(const Duration(seconds: 3));
      state = container.read(upgradeProvider);
      expect(state.isDone, isTrue);
      expect(state.completedSteps, {
        UpgradeStep.installing,
        UpgradeStep.reconnecting,
      });
    });
  });

  testWidgets('the overlay stays on Updating packages until the packages '
      'catch up, and the banner does not come back', (tester) async {
    final server = UpgradeServer(
      updateInfo(current: '5.14.0', latest: '5.14.0', web: true),
    );
    await pumpUpgradeBanner(tester, server);

    await confirmUpgrade(tester);

    expect(server.requested, ['5.14.0']);
    expect(find.text('Updating packages'), findsOneWidget);
    expect(find.text('Installing new version'), findsNothing);
    expect(
      find.text('Installing the new packages… this can take several minutes.'),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Upgrade complete'), findsNothing);
    expect(find.text('Updating packages'), findsOneWidget);

    server.update = updateInfo(current: '5.14.0', latest: '5.14.0');
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('Upgrade complete'), findsOneWidget);
    expect(find.text('All packages are up to date.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(UpgradeOverlay), findsNothing);
    expect(find.text('Software updates available'), findsNothing);
    expect(find.text('Your player is up to date'), findsOneWidget);
  });
}
