import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/server_update_provider.dart';
import 'package:kalinka/providers/upgrade_provider.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/utils/version_order.dart';
import 'package:kalinka/widgets/server_update_banner.dart';
import 'package:kalinka/widgets/upgrade_overlay.dart';

import 'haptic_recorder.dart';

/// A server being upgraded: what `GET /server/update` and `/server/version`
/// answer, and every version `PUT /server/upgrade` was asked for.
class UpgradeServer implements KalinkaPlayerProxy {
  UpgradeServer(this.update, {this.version = '5.14.0'});

  Map<String, dynamic> update;
  String version;

  /// Both GETs fail, as while the new package restarts the server.
  bool down = false;

  /// Thrown by the next requests in turn; once empty, requests are accepted.
  final refusals = <ServerUpgradeException>[];
  void Function(String version)? onUpgrade;

  final requested = <String>[];
  int updateReads = 0;
  int versionReads = 0;

  @override
  Future<Map<String, dynamic>?> getServerUpdateInfo() async {
    updateReads++;
    if (down) throw Exception('server down');
    return update;
  }

  @override
  Future<void> upgradeServer(String version) async {
    requested.add(version);
    onUpgrade?.call(version);
    if (refusals.isNotEmpty) throw refusals.removeAt(0);
  }

  @override
  Future<Map<String, dynamic>> getServerVersion() async {
    versionReads++;
    if (down) throw Exception('server down');
    return {'server_version': version};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Map<String, dynamic> updateInfo({
  required String current,
  required String latest,
  bool web = false,
}) => {
  'current_version': current,
  'latest_version': latest,
  'update_available': isNewerVersion(latest, current) || web,
  'upgrade_supported': true,
  'web_current_version': web ? '0.21.1' : '0.21.2',
  'web_latest_version': '0.21.2',
  'web_update_available': web,
};

/// [UpgradeNotifier]'s deadline follows [async]'s clock.
ProviderContainer upgradeContainer(UpgradeServer server, FakeAsync async) {
  final start = DateTime(2026, 11, 2, 12);
  final container = ProviderContainer(
    overrides: [
      kalinkaProxyProvider.overrideWithValue(server),
      upgradeProvider.overrideWith(
        () => UpgradeNotifier(now: () => start.add(async.elapsed)),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// The update banner with the upgrade overlay over it, as Settings has them.
Future<ProviderContainer> pumpUpgradeBanner(
  WidgetTester tester,
  UpgradeServer server,
) async {
  HapticRecorder.install();
  final container = ProviderContainer(
    overrides: [kalinkaProxyProvider.overrideWithValue(server)],
  );
  addTearDown(container.dispose);
  await container.read(serverUpdateProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => Stack(
              children: [
                const ServerUpdateBanner(),
                if (ref.watch(upgradeProvider).isUpgrading)
                  UpgradeOverlay(onDismiss: () {}),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> confirmUpgrade(WidgetTester tester) async {
  await tester.tap(find.text('Software updates available'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Restart & Update'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}
