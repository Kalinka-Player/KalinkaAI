import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/server_update_provider.dart';
import 'package:kalinka/providers/upgrade_provider.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/server_update_banner.dart';

class _Api implements KalinkaPlayerProxy {
  final Map<String, dynamic>? info;
  _Api(this.info);
  @override
  Future<Map<String, dynamic>?> getServerUpdateInfo() async => info;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Upgrade extends UpgradeNotifier {
  String? requestedVersion;
  @override
  Future<void> executeUpgrade(String version) async =>
      requestedVersion = version;
}

const _currentBundle = {
  'current_version': '5.9.0',
  'latest_version': '5.9.0',
  'update_available': true,
  'upgrade_supported': true,
};
const _supervisor = {
  'supervisor_current_version': '0.4.0',
  'supervisor_latest_version': '0.5.0',
  'supervisor_update_available': true,
};
const _renderer = {
  'renderer_current_version': '1.2.0',
  'renderer_latest_version': '1.3.0',
  'renderer_update_available': true,
};
const _web = {
  'web_current_version': '0.21.1',
  'web_latest_version': '0.21.2',
  'web_update_available': true,
};

Future<_Upgrade> _pump(
  WidgetTester tester,
  Map<String, dynamic>? info, {
  Size size = const Size(375, 812),
  double scale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final upgrade = _Upgrade();
  final container = ProviderContainer(
    overrides: [
      kalinkaProxyProvider.overrideWithValue(_Api(info)),
      upgradeProvider.overrideWith(() => upgrade),
    ],
  );
  addTearDown(container.dispose);
  await container.read(serverUpdateProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: const Scaffold(
          body: SingleChildScrollView(child: ServerUpdateBanner()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return upgrade;
}

void main() {
  testWidgets(
    'supervisor update names the component and sends the unchanged bundle target',
    (tester) async {
      final upgrade = await _pump(tester, {..._currentBundle, ..._supervisor});
      expect(find.text('Software updates available'), findsOneWidget);
      expect(find.text('Supervisor: 0.4.0 → 0.5.0'), findsOneWidget);
      expect(find.textContaining('Server:'), findsNothing);
      await tester.tap(find.text('Software updates available'));
      await tester.pumpAndSettle();
      expect(find.text('Update player software?'), findsOneWidget);
      expect(find.text('Supervisor: 0.4.0 → 0.5.0'), findsNWidgets(2));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(upgrade.requestedVersion, isNull);
      await tester.tap(find.text('Software updates available'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restart & Update'));
      await tester.pumpAndSettle();
      expect(upgrade.requestedVersion, '5.9.0');
      expect(tester.takeException(), isNull);
    },
  );

  for (final (response, expected) in [
    (
      {..._currentBundle, 'latest_version': '5.10.0'},
      ['Server: 5.9.0 → 5.10.0'],
    ),
    ({..._currentBundle, ..._renderer}, ['Renderer: 1.2.0 → 1.3.0']),
    ({..._currentBundle, ..._web}, ['Web player: 0.21.1 → 0.21.2']),
    (
      {
        ..._currentBundle,
        ..._renderer,
        ..._supervisor,
        ..._web,
        'latest_version': '5.10.0',
      },
      [
        'Server: 5.9.0 → 5.10.0',
        'Renderer: 1.2.0 → 1.3.0',
        'Supervisor: 0.4.0 → 0.5.0',
        'Web player: 0.21.1 → 0.21.2',
      ],
    ),
    (
      {..._currentBundle, ..._supervisor, 'supervisor_update_available': false},
      <String>[],
    ),
    (
      {..._currentBundle, ..._supervisor, 'supervisor_latest_version': null},
      ['Supervisor update'],
    ),
  ]) {
    testWidgets('update details respect backend flags: $expected', (
      tester,
    ) async {
      await _pump(tester, response);
      expect(find.text('Software updates available'), findsOneWidget);
      for (final text in expected) {
        expect(find.text(text), findsOneWidget);
      }
      if (expected.isEmpty) {
        expect(find.textContaining('Supervisor:'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('no update target cannot open a broken upgrade action', (
    tester,
  ) async {
    await _pump(tester, {..._currentBundle, 'latest_version': null});
    expect(find.text('Software updates available'), findsOneWidget);
    expect(find.byType(InkWell), findsNothing);
  });

  for (final response in [
    null,
    {..._currentBundle, 'upgrade_supported': false},
  ]) {
    testWidgets('unknown or unsupported updates remain hidden: $response', (
      tester,
    ) async {
      await _pump(tester, response);
      expect(find.text('Software updates available'), findsNothing);
      expect(find.text('Your player is up to date'), findsNothing);
    });
  }

  for (final (size, scale) in [
    (const Size(320, 850), 2.0),
    (const Size(812, 375), 1.0),
  ]) {
    testWidgets('update details and confirmation adapt to $size at $scale', (
      tester,
    ) async {
      await _pump(
        tester,
        {..._currentBundle, ..._renderer, ..._supervisor},
        size: size,
        scale: scale,
      );
      await tester.tap(find.text('Software updates available'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Restart & Update'));
      await tester.pumpAndSettle();
      expect(find.text('Restart & Update').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
