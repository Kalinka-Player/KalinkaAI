import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kalinka/providers/provisioning_controller.dart';
import 'package:kalinka/providers/provisioning_protocol.dart';
import 'package:kalinka/providers/provisioning_transport.dart';
import 'package:kalinka/screens/provisioning_screen.dart';

class FakeTransport implements ProvisioningTransport {
  final stream = StreamController<NearbyBox>.broadcast();
  final commands = <Map<String, dynamic>>[];
  final buffer = <int>[];
  BoxState state = BoxState.idle;
  int reason = 0;
  int connects = 0;
  int disconnects = 0;
  Completer<void>? pendingConnection;
  bool connected = true;
  int writtenFrames = 0;
  int? dropNetworkReadPage;
  bool dropNetworkPageAcknowledgement = false;
  bool dropRead = false;
  bool dropJoinAcknowledgement = false;
  int failedReconnects = 0;
  bool rejectJoinWrite = false;
  bool failJoin = false;
  bool disposed = false;
  bool canScan = false;
  bool failScan = false;
  bool failRead = false;
  bool holdScan = false;
  bool holdJoin = false;
  bool holdNetworkChange = false;
  bool changeSupported = false;
  int? currentStage;
  final progressStages = <int>[];
  int scanId = 0;
  int page = 0;
  Completer<Uint8List>? pendingScan;
  final networkList = [
    {'ssid': 'Home', 'signal': -42, 'security': 'wpa2'},
    {'ssid': 'Office', 'signal': -55, 'security': 'wpa2'},
    {'ssid': 'Public', 'signal': -60, 'security': 'open'},
    {'ssid': 'Café', 'signal': -70, 'security': 'wpa2'},
  ];

  @override
  Stream<NearbyBox> get boxes => stream.stream;
  @override
  Future<void> scan() async {}
  @override
  Future<void> stopScan() async {}
  @override
  Future<void> connect(String id) async {
    connects++;
    if (connects > 1 && failedReconnects > 0) {
      failedReconnects--;
      throw StateError('temporary reconnect failure');
    }
    await pendingConnection?.future;
    connected = true;
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
    connected = false;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await stream.close();
  }

  @override
  Future<Uint8List> read(String characteristic) async {
    if (failRead || !connected) throw StateError('box not responding');
    if (characteristic == provisionProgressUuid) {
      if (currentStage != null) return Uint8List.fromList([1, currentStage!]);
      final stage = progressStages.removeAt(0);
      if (progressStages.isEmpty) state = BoxState.joined;
      return Uint8List.fromList([1, stage]);
    }
    if (characteristic == provisionNetworksUuid) {
      if (dropNetworkReadPage == page) {
        dropNetworkReadPage = null;
        connected = false;
        throw StateError('scan connection lost');
      }
      if (pendingScan != null) return pendingScan!.future;
      return Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'v': 1,
            'id': scanId,
            'page': page,
            'pages': 2,
            'state': failScan
                ? 'failed'
                : holdScan
                ? 'scanning'
                : 'ready',
            'networks': networkList.skip(page * 3).take(3).toList(),
          }),
        ),
      );
    }
    if (dropRead && state == BoxState.joined) {
      dropRead = false;
      throw StateError('simulated BLE disconnect');
    }
    if (characteristic == provisionIdentityUuid) {
      return Uint8List.fromList(List.generate(16, (i) => i * 17));
    }
    return Uint8List.fromList([
      1,
      1 |
          (canScan ? 4 : 0) |
          (progressStages.isNotEmpty || currentStage != null ? 8 : 0) |
          (changeSupported ? 16 : 0),
      state.index,
      reason,
      192,
      168,
      1,
      4,
      31,
      187,
    ]);
  }

  @override
  Future<void> write(Uint8List frame) async {
    writtenFrames++;
    if (!connected) throw StateError('write on disconnected transport');
    expect(frame.length, lessThanOrEqualTo(20));
    if (frame[0] & 1 != 0) buffer.clear();
    buffer.addAll(frame.skip(1));
    if (frame[0] & 2 == 0) return;
    final command = jsonDecode(utf8.decode(buffer)) as Map<String, dynamic>;
    if (command['op'] == 'join' && rejectJoinWrite) {
      throw StateError('join never reached the box');
    }
    commands.add(command);
    if (command['op'] == 'scan') {
      scanId++;
      page = 0;
    }
    if (command['op'] == 'networks') {
      page = command['page'] as int;
      if (dropNetworkPageAcknowledgement) {
        dropNetworkPageAcknowledgement = false;
        connected = false;
        throw StateError('page acknowledgement lost');
      }
    }
    if (command['op'] == 'change_network') {
      state = holdNetworkChange ? BoxState.joining : BoxState.idle;
      reason = 0;
    }
    if (command['op'] == 'join') {
      state = failJoin
          ? BoxState.failed
          : holdJoin
          ? BoxState.joining
          : BoxState.joined;
      reason = failJoin ? 2 : 0;
      if (dropJoinAcknowledgement) {
        dropJoinAcknowledgement = false;
        throw StateError('final acknowledgement lost');
      }
    }
  }
}

void main() {
  test('changing network waits for the full server rollback budget', () {
    fakeAsync((async) {
      final transport = FakeTransport()
        ..changeSupported = true
        ..holdNetworkChange = true;
      final controller = ProvisioningController(transport, (_, _) async => null);
      controller.select(const NearbyBox('radio', 'Box'));
      async.flushMicrotasks();
      controller.changeNetwork();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 55));
      expect(controller.phase, SetupPhase.changingNetwork);
      expect(controller.error, isNull);
      transport.state = BoxState.idle;
      async.elapse(const Duration(seconds: 2));
      expect(controller.phase, SetupPhase.credentials);
      expect(controller.error, isNull);
      expect(transport.commands.map((c) => c['op']), ['change_network']);
      controller.dispose();
      async.flushMicrotasks();
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('changing network still times out when rollback never finishes', () {
    fakeAsync((async) {
      final transport = FakeTransport()
        ..changeSupported = true
        ..holdNetworkChange = true;
      final controller = ProvisioningController(transport, (_, _) async => null);
      controller.select(const NearbyBox('radio', 'Box'));
      async.flushMicrotasks();
      controller.changeNetwork();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 76));
      expect(controller.phase, SetupPhase.choosing);
      expect(controller.error, contains('has not reopened'));
      expect(transport.commands.map((c) => c['op']), ['change_network']);
      controller.dispose();
      async.flushMicrotasks();
      expect(async.pendingTimers, isEmpty);
    });
  });

  testWidgets(
    'wizard keeps its action above the keyboard on a small screen with large text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final transport = FakeTransport()..canScan = true;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: ProvisioningScreen(transport: transport),
          ),
        ),
      );
      await tester.pump();
      transport.stream.add(
        const NearbyBox('radio', 'A box with a longer name'),
      );
      await tester.pump();
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Enter custom SSID'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getBottomLeft(find.text('Connect to Wi-Fi')).dy,
        lessThan(460),
      );
      // Back edits the network choice rather than abandoning setup.
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Enter custom SSID'), findsOneWidget);
      expect(find.byKey(const ValueKey('custom-ssid')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('Back walks through the wizard before leaving setup', (
    tester,
  ) async {
    final transport = FakeTransport()..canScan = true;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ProvisioningScreen(transport: transport),
                ),
              ),
              child: const Text('Player discovery'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Player discovery'));
    await tester.pumpAndSettle();
    transport.stream.add(const NearbyBox('radio', 'Box'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('wifi-password')),
      'dummy secret',
    );
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Choose your Wi-Fi.'), findsOneWidget);
    expect(transport.disconnects, 0);
    // System navigation has the same behavior as the footer.
    await Navigator.of(
      tester.element(find.byType(ProvisioningScreen)),
    ).maybePop();
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('STEP 1 OF 2'), findsOneWidget);
    expect(find.text('Meet your Kalinka.'), findsOneWidget);
    expect(transport.disconnects, 1);
    transport.stream.add(const NearbyBox('radio', 'Box'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('wifi-password')))
          .controller!
          .text,
      isEmpty,
    );
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Player discovery'), findsOneWidget);
    expect(find.byType(ProvisioningScreen), findsNothing);
    expect(
      transport.commands.any((command) => command['op'] == 'join'),
      isFalse,
    );
  });

  test('returning to box discovery discards a pending Wi-Fi scan', () async {
    final transport = FakeTransport()
      ..canScan = true
      ..pendingScan = Completer<Uint8List>();
    final controller = ProvisioningController(transport, (_, _) async => null);
    addTearDown(controller.dispose);
    await controller.select(const NearbyBox('radio', 'Box'));
    final pending = controller.scanWifi('GB');
    await Future<void>.delayed(Duration.zero);
    await controller.scan();
    transport.pendingScan!.complete(
      Uint8List.fromList(
        utf8.encode(
          '{"v":1,"id":1,"state":"ready","page":0,"pages":1,"networks":[{"ssid":"Stale","signal":-42,"security":"wpa2"}]}',
        ),
      ),
    );
    await pending;
    expect(controller.phase, SetupPhase.scanning);
    expect(controller.selected, isNull);
    expect(controller.status, isNull);
    expect(controller.networks, isEmpty);
    expect(controller.scanningWifi, isFalse);
    expect(transport.disconnects, 1);
  });

  test(
    'a late pairing result cannot disconnect a newly selected box',
    () async {
      final transport = FakeTransport()..pendingConnection = Completer<void>();
      final oldConnection = transport.pendingConnection!;
      final controller = ProvisioningController(
        transport,
        (_, _) async => null,
      );
      addTearDown(controller.dispose);
      final oldSelection = controller.select(const NearbyBox('old', 'Old box'));
      await controller.scan();
      transport.pendingConnection = null;
      await controller.select(const NearbyBox('new', 'New box'));
      oldConnection.complete();
      await oldSelection;
      expect(controller.selected!.id, 'new');
      expect(controller.phase, SetupPhase.credentials);
      expect(transport.disconnects, 1);
    },
  );

  test(
    'choosing another network cancels a late successful player handoff',
    () async {
      final transport = FakeTransport()..changeSupported = true;
      final pending = Completer<ProvisionedEndpoint?>();
      final reaching = Completer<void>();
      final controller = ProvisioningController(transport, (_, _) {
        reaching.complete();
        return pending.future;
      });
      addTearDown(controller.dispose);
      await controller.select(const NearbyBox('radio', 'Box'));
      final join = controller.join('Home', 'dummy secret', 'GB');
      await reaching.future;
      await controller.changeNetwork();
      pending.complete(
        const ProvisionedEndpoint('Box', '192.168.1.4', 8123, null),
      );
      await join;
      expect(controller.phase, SetupPhase.credentials);
      expect(transport.commands.map((c) => c['op']), [
        'join',
        'change_network',
      ]);
    },
  );

  test(
    'reports real join stages and changes network without resending credentials',
    () async {
      final transport = FakeTransport()
        ..holdJoin = true
        ..changeSupported = true;
      transport.progressStages.addAll([1, 2, 3]);
      final controller = ProvisioningController(
        transport,
        (_, _) async => null,
        pollInterval: const Duration(milliseconds: 1),
        handoffTimeout: const Duration(milliseconds: 5),
      );
      addTearDown(controller.dispose);
      final stages = <WifiJoinStage?>[];
      controller.addListener(() => stages.add(controller.wifiStage));
      await controller.select(const NearbyBox('radio', 'Box'));
      await controller.join('Home', 'dummy secret', 'GB');
      expect(
        stages,
        containsAll([
          WifiJoinStage.preparing,
          WifiJoinStage.authenticating,
          WifiJoinStage.gettingAddress,
          WifiJoinStage.saving,
        ]),
      );
      expect(controller.phase, SetupPhase.reaching);
      await controller.changeNetwork();
      expect(controller.phase, SetupPhase.credentials);
      expect(transport.commands.map((c) => c['op']), [
        'join',
        'change_network',
      ]);
    },
  );

  testWidgets(
    'player checks stay active without Retry and Back reopens networks',
    (tester) async {
      final transport = FakeTransport()
        ..canScan = true
        ..changeSupported = true
        ..state = BoxState.joined;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ProvisioningScreen(
              transport: transport,
              reach: (_, _) async => null,
            ),
          ),
        ),
      );
      await tester.pump();
      transport.stream.add(const NearbyBox('radio', 'Box'));
      await tester.pump();
      await tester.tap(find.text('Box'));
      expect(transport.connects, 0);
      await tester.tap(find.text('Connect'));
      await tester.pump();
      expect(find.text('STEP 2 OF 2'), findsOneWidget);
      expect(find.text('Your box is on Wi-Fi.'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      await tester.pump(const Duration(seconds: 11));
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Choose another network'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Enter custom SSID'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(transport.commands.first['op'], 'change_network');
      expect(transport.commands.any((c) => c['op'] == 'join'), isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    },
  );

  testWidgets('only a reported failure stops progress and offers Retry', (
    tester,
  ) async {
    final transport = FakeTransport()
      ..canScan = true
      ..changeSupported = true
      ..holdJoin = true
      ..currentStage = 1;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ProvisioningScreen(
            transport: transport,
            reach: (_, _) async => null,
          ),
        ),
      ),
    );
    await tester.pump();
    transport.stream.add(const NearbyBox('radio', 'Box'));
    await tester.pump();
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('wifi-password')),
      'dummy secret',
    );
    await tester.tap(find.text('Connect to Wi-Fi'));
    await tester.pump();
    for (final stage in [1, 2, 3]) {
      transport.currentStage = stage;
      await tester.pump(const Duration(seconds: 12));
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Choose another network'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    }
    transport.state = BoxState.failed;
    transport.reason = 6;
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(2));
    expect(find.textContaining('could not save'), findsOneWidget);
    transport.currentStage = 1;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(find.byIcon(Icons.cancel_rounded), findsNothing);
    expect(find.text('Retry'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(transport.commands.where((c) => c['op'] == 'join'), hasLength(2));
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Choose your Wi-Fi.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });

  test(
    'join timeout preserves the last reported stage for failure display',
    () async {
      final transport = FakeTransport()
        ..holdJoin = true
        ..currentStage = 3;
      final controller = ProvisioningController(
        transport,
        (_, _) async => null,
        pollInterval: const Duration(milliseconds: 1),
        joinTimeout: const Duration(milliseconds: 8),
      );
      addTearDown(controller.dispose);
      await controller.select(const NearbyBox('radio', 'Box'));
      await controller.join('Home', 'dummy secret', 'GB');
      expect(controller.phase, SetupPhase.joining);
      expect(controller.wifiStage, WifiJoinStage.saving);
      expect(controller.error, contains('not confirmed'));
      expect(controller.endpoint, isNull);
    },
  );

  test('Wi-Fi picker reads all pages and leaves credentials unsent', () async {
    final transport = FakeTransport()..canScan = true;
    final controller = ProvisioningController(transport, (_, _) async => null);
    addTearDown(controller.dispose);
    await controller.select(const NearbyBox('radio', 'Box'));
    await controller.scanWifi('GB');
    expect(controller.networks.map((n) => n.ssid), [
      'Home',
      'Office',
      'Public',
      'Café',
    ]);
    expect(controller.networks[2].supported, isFalse);
    expect(controller.wifiScanError, isNull);
    expect(controller.phase, SetupPhase.credentials);
    expect(transport.commands.map((c) => c['op']), ['scan', 'networks']);
  });

  test(
    'scan failure and timeout allow retry and older boxes allow manual entry',
    () async {
      final transport = FakeTransport();
      final controller = ProvisioningController(
        transport,
        (_, _) async => null,
        pollInterval: const Duration(milliseconds: 1),
        wifiScanTimeout: const Duration(milliseconds: 5),
      );
      addTearDown(controller.dispose);
      await controller.select(const NearbyBox('radio', 'Box'));
      await controller.scanWifi('GB');
      expect(transport.commands, isEmpty);
      expect(controller.phase, SetupPhase.credentials);
      transport.canScan = true;
      await controller.reconnect();
      await controller.scanWifi('invalid');
      expect(transport.commands, isEmpty);
      for (final timeout in [false, true]) {
        transport.failScan = !timeout;
        transport.holdScan = timeout;
        await controller.scanWifi('GB');
        expect(controller.wifiScanError, contains('Retry'));
        expect(controller.scanningWifi, isFalse);
        expect(controller.phase, SetupPhase.credentials);
      }
      transport.holdScan = false;
      await controller.scanWifi('GB');
      expect(controller.wifiScanError, isNull);
      expect(controller.networks, hasLength(4));
    },
  );

  test('leaving while reading scan results cannot update or join', () async {
    final transport = FakeTransport()
      ..canScan = true
      ..pendingScan = Completer<Uint8List>();
    final controller = ProvisioningController(transport, (_, _) async => null);
    await controller.select(const NearbyBox('radio', 'Box'));
    final scan = controller.scanWifi('GB');
    await Future<void>.delayed(Duration.zero);
    await controller.join('Home', 'dummy secret', 'GB');
    expect(transport.commands.map((c) => c['op']), ['scan']);
    controller.dispose();
    transport.pendingScan!.complete(
      Uint8List.fromList(
        utf8.encode(
          '{"v":1,"id":1,"state":"ready","page":0,"pages":1,"networks":[]}',
        ),
      ),
    );
    await scan;
    expect(controller.networks, isEmpty);
    expect(transport.commands.map((c) => c['op']), ['scan']);
  });

  test(
    'BLE retry retrieves joined status without resending credentials',
    () async {
      final transport = FakeTransport()..failRead = true;
      final controller = ProvisioningController(
        transport,
        (status, id) async =>
            ProvisionedEndpoint('Box', status.address!, status.port, id),
      );
      addTearDown(controller.dispose);
      await controller.select(const NearbyBox('radio', 'Box'));
      expect(controller.phase, SetupPhase.choosing);
      expect(controller.error, isNotNull);
      transport.failRead = false;
      transport.state = BoxState.joined;
      await controller.reconnect();
      expect(controller.phase, SetupPhase.done);
      expect(transport.commands.map((c) => c['op']), ['complete']);
    },
  );

  testWidgets(
    'network picker fills SSID, rejects unsupported choices and permits manual entry',
    (tester) async {
      final transport = FakeTransport()..canScan = true;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(home: ProvisioningScreen(transport: transport)),
        ),
      );
      await tester.pump();
      transport.stream.add(const NearbyBox('radio', 'Box'));
      await tester.pump();
      await tester.tap(find.text('Box'));
      expect(transport.connects, 0);
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(find.text('Choose your Wi-Fi.'), findsOneWidget);
      expect(find.byKey(const ValueKey('custom-ssid')), findsNothing);
      expect(find.byKey(const ValueKey('wifi-password')), findsNothing);
      await tester.scrollUntilVisible(find.text('Public'), 100);
      await tester.drag(find.byType(ListView).first, const Offset(0, -100));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Public'));
      await tester.pump();
      expect(find.byKey(const ValueKey('wifi-password')), findsNothing);
      await tester.scrollUntilVisible(find.text('Home'), -100);
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(find.byKey(const ValueKey('custom-ssid')), findsNothing);
      expect(find.byKey(const ValueKey('wifi-password')), findsOneWidget);
      expect(find.text('Office'), findsNothing);
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Enter custom SSID'));
      await tester.tap(find.text('Enter custom SSID'));
      await tester.pumpAndSettle();
      final ssid = find.byKey(const ValueKey('custom-ssid'));
      await tester.enterText(ssid, 'Hidden network');
      expect(
        tester.widget<TextFormField>(ssid).controller!.text,
        'Hidden network',
      );
      expect(transport.commands.any((c) => c['op'] == 'join'), isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  test(
    'leaving during pairing disconnects a connection that completes late',
    () async {
      final transport = FakeTransport()..pendingConnection = Completer<void>();
      final controller = ProvisioningController(
        transport,
        (_, _) async => null,
      );
      final select = controller.select(const NearbyBox('radio', 'Box'));
      controller.dispose();
      transport.pendingConnection!.complete();
      await select;
      expect(transport.disconnects, 1);
      expect(transport.commands, isEmpty);
    },
  );

  test(
    'wire format matches image protocol, including default MTU and UTF-8',
    () {
      final data = Uint8List.fromList([1, 3, 2, 0, 192, 168, 1, 4, 31, 187]);
      final status = ProvisioningStatus.decode(data);
      expect(status.state, BoxState.joined);
      expect(status.address, '192.168.1.4');
      expect(status.port, 8123);
      expect(status.isTest, isTrue);
      expect(decodeProvisioningIdentity(Uint8List(0)), isNull);
      expect(
        decodeProvisioningIdentity(
          Uint8List.fromList(List.generate(16, (i) => i * 17)),
        ),
        '00112233-4455-6677-8899-aabbccddeeff',
      );
      final frames = provisionFrames({
        'op': 'join',
        'ssid': " Café'\\ room ",
        'password': 'dummy secret',
        'country': 'GB',
      });
      expect(frames.first[0] & 1, 1);
      expect(frames.last[0] & 2, 2);
      expect(frames.every((f) => f.length <= 20), isTrue);
      final decoded = jsonDecode(
        utf8.decode(frames.expand((f) => f.skip(1)).toList()),
      );
      expect(decoded['ssid'], " Café'\\ room ");
      expect(
        () =>
            ProvisioningStatus.decode(Uint8List.fromList([2, ...data.skip(1)])),
        throwsFormatException,
      );
    },
  );

  test(
    'credentials sent once; reconnect resumes result and completes network handoff',
    () async {
      final transport = FakeTransport()..dropRead = true;
      var reaches = 0;
      final controller = ProvisioningController(transport, (status, id) async {
        expect(id, '00112233-4455-6677-8899-aabbccddeeff');
        reaches++;
        if (reaches == 1) return null; // Core's cold start
        return ProvisionedEndpoint(
          'Living room',
          status.address!,
          status.port,
          id,
        );
      }, pollInterval: Duration.zero);
      addTearDown(controller.dispose);
      await controller.scan();
      transport.stream.add(const NearbyBox('radio', 'Kalinka-1234'));
      await Future<void>.delayed(Duration.zero);
      expect(controller.boxes.single.name, 'Kalinka-1234');
      await controller.select(controller.boxes.single);
      expect(controller.phase, SetupPhase.credentials);
      await controller.join(' Home ', 'dummy secret', 'GB');
      expect(controller.phase, SetupPhase.done);
      expect(transport.connects, 2);
      expect(transport.commands.map((c) => c['op']), ['join', 'complete']);
      expect(transport.commands.first['ssid'], ' Home ');
      expect(controller.endpoint!.host, '192.168.1.4');
    },
  );

  test(
    'lost final join acknowledgement resumes without resending credentials',
    () async {
      final transport = FakeTransport()
        ..dropJoinAcknowledgement = true
        ..dropRead = true;
      final controller = ProvisioningController(
        transport,
        (status, id) async =>
            ProvisionedEndpoint('Box', status.address!, status.port, id),
        pollInterval: Duration.zero,
      );
      addTearDown(controller.dispose);
      await controller.select(const NearbyBox('radio', 'Box'));
      await controller.join('Home', 'dummy secret', 'GB');
      expect(controller.phase, SetupPhase.done);
      expect(controller.error, isNull);
      expect(transport.commands.map((c) => c['op']), ['join', 'complete']);
      expect(transport.disconnects, 1);
    },
  );

  test('a temporary reconnect failure during joining is recovered', () async {
    final transport = FakeTransport()
      ..dropRead = true
      ..failedReconnects = 1;
    final controller = ProvisioningController(
      transport,
      (status, id) async =>
          ProvisionedEndpoint('Box', status.address!, status.port, id),
      pollInterval: Duration.zero,
    );
    addTearDown(controller.dispose);
    await controller.select(const NearbyBox('radio', 'Box'));
    await controller.join('Home', 'dummy secret', 'GB');
    expect(controller.phase, SetupPhase.done);
    expect(transport.connects, 3);
    expect(transport.commands.map((c) => c['op']), ['join', 'complete']);
  });

  test(
    'persistent disconnection exposes failure after bounded recovery',
    () async {
      final transport = FakeTransport();
      final controller = ProvisioningController(
        transport,
        (_, _) async => null,
        pollInterval: Duration.zero,
      );
      addTearDown(controller.dispose);
      await controller.select(const NearbyBox('radio', 'Box'));
      transport.failRead = true;
      await controller.join('Home', 'dummy secret', 'GB');
      expect(controller.phase, SetupPhase.joining);
      expect(controller.error, isNotNull);
      expect(transport.connects, 3);
      expect(transport.commands, isEmpty);
      expect(transport.writtenFrames, 0);
    },
  );

  test(
    'unreceived join is not automatically resent or reported successful',
    () async {
      final transport = FakeTransport()..rejectJoinWrite = true;
      final controller = ProvisioningController(
        transport,
        (_, _) async => null,
        pollInterval: Duration.zero,
      );
      addTearDown(controller.dispose);
      await controller.select(const NearbyBox('radio', 'Box'));
      await controller.join('Home', 'dummy secret', 'GB');
      expect(controller.phase, SetupPhase.joining);
      expect(controller.error, isNotNull);
      expect(controller.endpoint, isNull);
      expect(transport.commands, isEmpty);
    },
  );

  test(
    'disconnect during password entry reconnects before any write',
    () async {
      final transport = FakeTransport();
      final controller = ProvisioningController(
        transport,
        (status, id) async =>
            ProvisionedEndpoint('Box', status.address!, status.port, id),
        pollInterval: Duration.zero,
      );
      addTearDown(controller.dispose);
      await controller.select(const NearbyBox('radio', 'Box'));
      transport.connected = false;
      transport.failedReconnects = 1;
      await controller.join('Home', 'dummy secret', 'GB');
      expect(controller.phase, SetupPhase.done);
      expect(controller.error, isNull);
      expect(transport.connects, 3);
      expect(transport.commands.map((c) => c['op']), ['join', 'complete']);
      expect(
        transport.writtenFrames,
        provisionFrames({
              'op': 'join',
              'ssid': 'Home',
              'password': 'dummy secret',
              'country': 'GB',
            }).length +
            provisionFrames({'op': 'complete'}).length,
      );
    },
  );

  test(
    'preflight resumes an existing join without sending credentials',
    () async {
      final transport = FakeTransport();
      final controller = ProvisioningController(
        transport,
        (status, id) async =>
            ProvisionedEndpoint('Box', status.address!, status.port, id),
        pollInterval: Duration.zero,
      );
      addTearDown(controller.dispose);
      await controller.select(const NearbyBox('radio', 'Box'));
      transport.state = BoxState.joined;
      await controller.join('Home', 'dummy secret', 'GB');
      expect(controller.phase, SetupPhase.done);
      expect(transport.commands.map((c) => c['op']), ['complete']);
    },
  );

  test('leaving during preflight recovery never submits credentials', () async {
    final transport = FakeTransport();
    final controller = ProvisioningController(
      transport,
      (_, _) async => null,
      pollInterval: Duration.zero,
    );
    addTearDown(controller.dispose);
    await controller.select(const NearbyBox('radio', 'Box'));
    transport.connected = false;
    transport.pendingConnection = Completer<void>();
    final join = controller.join('Home', 'dummy secret', 'GB');
    while (transport.connects < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    await controller.scan();
    transport.pendingConnection!.complete();
    await join;
    expect(controller.phase, SetupPhase.scanning);
    expect(transport.writtenFrames, 0);
  });

  for (final page in [0, 1]) {
    test(
      'scan recovers a disconnect reading page $page without rescanning',
      () async {
        final transport = FakeTransport()
          ..canScan = true
          ..dropNetworkReadPage = page;
        final controller = ProvisioningController(
          transport,
          (_, _) async => null,
          pollInterval: Duration.zero,
        );
        addTearDown(controller.dispose);
        await controller.select(const NearbyBox('radio', 'Box'));
        await controller.scanWifi('GB');
        expect(controller.wifiScanError, isNull);
        expect(controller.networks.map((n) => n.ssid), [
          'Home',
          'Office',
          'Public',
          'Café',
        ]);
        expect(
          transport.commands.where((c) => c['op'] == 'scan'),
          hasLength(1),
        );
        expect(transport.commands.where((c) => c['op'] == 'join'), isEmpty);
        expect(transport.connects, 2);
      },
    );
  }

  test(
    'scan page acknowledgement loss safely retries the page selection',
    () async {
      final transport = FakeTransport()
        ..canScan = true
        ..dropNetworkPageAcknowledgement = true;
      final controller = ProvisioningController(
        transport,
        (_, _) async => null,
        pollInterval: Duration.zero,
      );
      addTearDown(controller.dispose);
      await controller.select(const NearbyBox('radio', 'Box'));
      await controller.scanWifi('GB');
      expect(controller.wifiScanError, isNull);
      expect(controller.networks, hasLength(4));
      expect(transport.commands.map((c) => c['op']), [
        'scan',
        'networks',
        'networks',
      ]);
    },
  );

  test(
    'persistent scan disconnect ends recovery with an actionable error',
    () async {
      final transport = FakeTransport()
        ..canScan = true
        ..dropNetworkReadPage = 0
        ..failedReconnects = 2;
      final controller = ProvisioningController(
        transport,
        (_, _) async => null,
        pollInterval: Duration.zero,
      );
      addTearDown(controller.dispose);
      await controller.select(const NearbyBox('radio', 'Box'));
      await controller.scanWifi('GB');
      expect(controller.scanningWifi, isFalse);
      expect(controller.networks, isEmpty);
      expect(controller.wifiScanError, contains('Retry'));
      expect(transport.connects, 3);
      expect(transport.commands.map((c) => c['op']), ['scan']);
    },
  );

  test('wrong password stops on failed join and allows retry', () async {
    final transport = FakeTransport()..failJoin = true;
    final controller = ProvisioningController(
      transport,
      (status, id) async =>
          ProvisionedEndpoint('Box', status.address!, status.port, id),
    );
    addTearDown(controller.dispose);
    await controller.select(const NearbyBox('radio', 'Box'));
    await controller.join('Home', 'dummy secret', 'GB');
    expect(controller.phase, SetupPhase.joining);
    expect(controller.wifiStage, WifiJoinStage.authenticating);
    expect(controller.error, contains('password was rejected'));
    expect(transport.commands.any((c) => c['op'] == 'complete'), isFalse);
    transport.failJoin = false;
    await controller.join('Home', 'corrected dummy', 'GB');
    expect(controller.phase, SetupPhase.done);
    expect(controller.error, isNull);
  });

  test(
    'unreachable LAN does not falsely finish setup; handoff can be retried',
    () async {
      final transport = FakeTransport();
      var reachable = false;
      final controller = ProvisioningController(
        transport,
        (status, id) async => reachable
            ? ProvisionedEndpoint('Box', status.address!, status.port, id)
            : null,
        pollInterval: const Duration(milliseconds: 1),
        handoffTimeout: const Duration(milliseconds: 8),
      );
      addTearDown(controller.dispose);
      await controller.select(const NearbyBox('radio', 'Box'));
      await controller.join('Home', 'dummy secret', 'GB');
      expect(controller.phase, SetupPhase.reaching);
      expect(controller.error, contains('same network'));
      expect(transport.commands.length, 1);
      reachable = true;
      await controller.retryHandoff();
      expect(controller.phase, SetupPhase.done);
      expect(transport.commands.map((c) => c['op']), ['join', 'complete']);
    },
  );

  test(
    'disposing during a pending handoff never connects or acknowledges afterwards',
    () async {
      final transport = FakeTransport();
      final pending = Completer<ProvisionedEndpoint?>();
      final reaching = Completer<void>();
      final controller = ProvisioningController(transport, (status, id) {
        reaching.complete();
        return pending.future;
      });
      await controller.select(const NearbyBox('radio', 'Box'));
      final join = controller.join('Home', 'dummy secret', 'GB');
      await reaching.future;
      controller.dispose();
      pending.complete(
        const ProvisionedEndpoint('Box', '192.168.1.4', 8123, null),
      );
      await join;
      expect(transport.commands.map((c) => c['op']), ['join']);
      expect(transport.disposed, isTrue);
    },
  );
}
