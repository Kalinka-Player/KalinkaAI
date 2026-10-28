import 'dart:async';

import 'package:dio/dio.dart' show DioException, RequestOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart' show ModulesAndDevices;
import 'package:kalinka/data_model/presentation_schema.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/onboarding_provider.dart';
import 'package:kalinka/providers/playback_time_provider.dart';
import 'package:kalinka/screens/onboarding_screen.dart';
import 'package:kalinka/screens/provisioning_screen.dart';
import 'package:kalinka/widgets/discovery_screen.dart';
import 'package:kalinka/widgets/server_chip.dart';
import 'package:universal_ble/universal_ble.dart';

import 'support/home_shell.dart';

/// A server that answers only once [up], reporting whether it is [setUp].
class _Server extends HomeApi {
  _Server({this.up = false, this.setUp = false});

  bool up;
  final bool setUp;
  int probes = 0;

  @override
  Future<ModulesAndDevices> listModules() async {
    probes++;
    if (!up) {
      throw DioException(
        requestOptions: RequestOptions(path: '/server/modules'),
      );
    }
    return ModulesAndDevices(inputModules: const [], devices: const []);
  }

  @override
  Future<PresentationSchema> getSettingsSchema() async =>
      const PresentationSchema(schemaVersion: 'v1', pages: []);

  @override
  Future<Map<String, dynamic>> getSettings() async => {
    'schema_version': 'v1',
    'values': {OnboardingStatusNotifier.serverOobeFlagPath: setUp},
  };
}

/// The real reconnect loop, from a live connection.
class _Live extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() {
    super.build();
    return ConnectionStatus.connected;
  }
}

class _Lifecycle extends AppLifecycleNotifier {
  @override
  AppLifecycleState build() => AppLifecycleState.resumed;

  void set(AppLifecycleState next) => state = next;
}

/// Bluetooth waiting on the permission prompt.
class _PermissionPrompt extends UniversalBlePlatform {
  @override
  Future<void> requestPermissions({bool withAndroidFineLocation = false}) =>
      Completer<void>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ProviderContainer> _pumpPlayer(
  WidgetTester tester,
  _Server server,
) async {
  final container = await pumpHomeShell(
    tester,
    queue: SettableQueue(queueOf(0)),
    api: server,
    connection: _Live.new,
    overrides: [appLifecycleProvider.overrideWith(_Lifecycle.new)],
  );
  // The queue socket opens once a probe has found the server.
  final connection = container.read(connectionStateProvider.notifier);
  container.listen(
    retryEpochProvider,
    (_, _) => Future.microtask(connection.connected),
  );
  return container;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _openPicker(WidgetTester tester) async {
  await tester.tap(find.byType(ServerChip));
  await _settle(tester);
  await tester.tap(find.text('Connect to different server'));
  await _settle(tester);
  expect(find.byType(DiscoveryScreen), findsOneWidget);
}

bool _onTop(WidgetTester tester, Finder screen) =>
    ModalRoute.of(tester.element(screen))!.isCurrent;

void main() {
  testWidgets('the stored server coming back stays behind Set up a box', (
    tester,
  ) async {
    UniversalBle.setInstance(_PermissionPrompt());
    final server = _Server();
    final container = await _pumpPlayer(tester, server);
    final connection = container.read(connectionStateProvider.notifier);
    final lifecycle =
        container.read(appLifecycleProvider.notifier) as _Lifecycle;
    connection.startReconnecting();
    await tester.pump();

    await _openPicker(tester);
    await tester.tap(find.text('SET UP A BOX'));
    await _settle(tester);
    await tester.tap(find.text('Search using Bluetooth'));
    await _settle(tester);
    expect(find.byType(ProvisioningScreen), findsOneWidget);

    lifecycle.set(AppLifecycleState.paused);
    lifecycle.set(AppLifecycleState.resumed);
    server.up = true;
    await tester.pump(const Duration(seconds: 30));
    await _settle(tester);

    expect(server.probes, 0);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(_onTop(tester, find.byType(ProvisioningScreen)), isTrue);

    // As when a probe sent before the picker opened brings the socket back.
    connection.connected();
    await _settle(tester);

    expect(find.byType(OnboardingScreen), findsNothing);
    expect(_onTop(tester, find.byType(ProvisioningScreen)), isTrue);
  });

  testWidgets('a server picked that is not set up opens setup once the '
      'picker closes', (tester) async {
    final server = _Server(up: true);
    await _pumpPlayer(tester, server);

    await _openPicker(tester);
    // The scan finds nothing, which offers the address field.
    await tester.pump(const Duration(seconds: 7));
    await tester.enterText(find.byType(TextField), '10.0.0.5:8000');
    await tester.tap(find.text('Connect'));
    await tester.pump();
    expect(find.byType(OnboardingScreen), findsNothing);

    await _settle(tester);
    await _settle(tester);

    expect(find.byType(DiscoveryScreen), findsNothing);
    final wizard = tester.widget<OnboardingScreen>(
      find.byType(OnboardingScreen),
    );
    expect(wizard.startAtSetup, isTrue);
  });

  for (final leave in ['Cancel', 'Back']) {
    testWidgets('$leave on the picker reconnects to the stored server', (
      tester,
    ) async {
      final server = _Server(setUp: true);
      final container = await _pumpPlayer(tester, server);
      container.read(connectionStateProvider.notifier).startReconnecting();
      await tester.pump();

      await _openPicker(tester);
      final probes = server.probes;
      await tester.pump(const Duration(seconds: 20));
      expect(server.probes, probes);

      if (leave == 'Cancel') {
        await tester.tap(find.text('Cancel'));
      } else {
        await tester.binding.handlePopRoute();
      }
      await _settle(tester);
      expect(find.byType(DiscoveryScreen), findsNothing);
      expect(server.probes, probes + 1);

      server.up = true;
      await tester.pump(const Duration(seconds: 5));
      expect(server.probes, probes + 2);
      expect(
        container.read(connectionStateProvider),
        ConnectionStatus.connected,
      );
    });
  }

  testWidgets('a screen replaced with the picker open reconnects again', (
    tester,
  ) async {
    final server = _Server(setUp: true);
    final container = await _pumpPlayer(tester, server);
    container.read(connectionStateProvider.notifier).startReconnecting();
    await tester.pump();
    await _openPicker(tester);
    final probes = server.probes;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SizedBox()),
      ),
    );
    await tester.pump();
    expect(server.probes, probes + 1);

    server.up = true;
    await tester.pump(const Duration(seconds: 7));
    expect(container.read(connectionStateProvider), ConnectionStatus.connected);
  });
}
