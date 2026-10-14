import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/providers/network_setup_api.dart';
import 'package:kalinka/providers/onboarding_provider.dart';
import 'package:kalinka/screens/setup_method_screen.dart';
import 'package:kalinka/screens/network_setup_screen.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/onboarding/step_network.dart';

class FakeSetupApi extends NetworkSetupApi {
  final Map<String, dynamic> response;
  final List<String> commands = [];
  Future<Map<String, dynamic>> Function()? readStatus;
  Future<void> Function(String)? sendCommand;
  FakeSetupApi(this.response) : super(Uri.parse('http://192.168.4.1'));
  @override
  Future<Map<String, dynamic>> status() async =>
      readStatus == null ? response : await readStatus!();
  @override
  Future<void> command(
    String operation, [
    Map<String, Object> fields = const {},
  ]) async {
    commands.add(operation);
    await sendCommand?.call(operation);
  }
}

void main() {
  test(
    'HTTP setup uses bounded same-endpoint requests and a stable session',
    () async {
      final dio = Dio();
      final api = NetworkSetupApi(Uri.parse('http://192.168.4.1'), client: dio);
      final requests = <RequestOptions>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) {
            requests.add(r);
            h.resolve(
              Response(
                requestOptions: r,
                statusCode: r.method == 'GET' ? 200 : 202,
                data: {'available': true},
              ),
            );
          },
        ),
      );
      expect((await api.status())['available'], true);
      await api.command('open');
      await api.command('join', {
        'ssid': 'home',
        'password': 'test-password',
        'country': 'GB',
      });
      expect(
        requests.every(
          (r) => r.uri.toString() == 'http://192.168.4.1/v1/setup',
        ),
        true,
      );
      expect(requests[1].headers['X-Kalinka-Setup-Client'], api.session);
      expect(requests[2].headers['X-Kalinka-Setup-Client'], api.session);
      expect(requests[2].data['password'], 'test-password');
      api.dispose();
    },
  );

  test('old wizard resume steps migrate past the new Network step', () {
    final old = {
      'name': 'Box',
      'scheme': 'http',
      'host': 'box.local',
      'port': 8000,
      'step': 5,
    };
    final resume = OobeResume.fromJson(old)!;
    expect(resume.step, 6);
    expect(
      OobeResume.fromJson(jsonDecode(jsonEncode(resume.toJson())))!.step,
      6,
    );
  });

  for (final kind in ['wired', 'wifi']) {
    testWidgets(
      'existing $kind connection remains visible and is not changed',
      (tester) async {
        final api = FakeSetupApi({
          'available': true,
          'network': {
            'connected': true,
            'kind': kind,
            'address': '192.168.1.20',
          },
          'setup': {'state': 4, 'networks': []},
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: NetworkSetupPanel(endpoint: api.base, api: api),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(
          find.text(
            kind == 'wired' ? 'Connected by Ethernet' : 'Connected by Wi-Fi',
          ),
          findsOneWidget,
        );
        expect(find.text('Connect to Wi-Fi'), findsOneWidget);
        expect(api.commands, isEmpty);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('network panel fits a small phone and validates credentials', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakeSetupApi({
      'available': true,
      'hotspot': true,
      'network': {'connected': false},
      'setup': {
        'state': 0,
        'networks': [
          {'ssid': 'Home', 'security': 'wpa2'},
          {'ssid': 'Open', 'security': 'open'},
        ],
      },
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: NetworkSetupPanel(endpoint: api.base, api: api),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Connect to Wi-Fi'));
    await tester.tap(find.text('Connect to Wi-Fi'));
    await tester.pump();
    expect(api.commands, isEmpty);
    expect(find.text('Use a network name of 1–32 bytes.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'accepted credentials offer reconnection without claiming success',
    (tester) async {
      final api = FakeSetupApi({
        'available': true,
        'network': {'connected': false},
        'setup': {'state': 0, 'networks': []},
      });
      var reconnected = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: NetworkSetupPanel(
                endpoint: api.base,
                api: api,
                onReconnect: () => reconnected = true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'GB');
      await tester.enterText(fields.at(1), 'Home');
      await tester.enterText(fields.at(2), 'test-password');
      await tester.ensureVisible(find.text('Connect to Wi-Fi'));
      await tester.tap(find.text('Connect to Wi-Fi'));
      await tester.pump();
      expect(api.commands, ['open', 'join']);
      expect(find.text('Reconnect after changing Wi-Fi'), findsOneWidget);
      await tester.ensureVisible(find.text('Reconnect after changing Wi-Fi'));
      await tester.tap(find.text('Reconnect after changing Wi-Fi'));
      expect(reconnected, true);
      expect(find.text('Connected by Wi-Fi'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  group('in-flight network requests', () {
    late FakeSetupApi api;
    final busy = <bool>[];

    setUp(() {
      busy.clear();
      api = FakeSetupApi({
        'available': true,
        'network': {'connected': false},
        'setup': {'state': 0, 'networks': []},
      });
    });

    Future<void> ready(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: NetworkSetupPanel(
                endpoint: api.base,
                api: api,
                onBusy: busy.add,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'GB');
      await tester.enterText(fields.at(1), 'Home');
      await tester.enterText(fields.at(2), 'test-password');
    }

    Future<void> join(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Connect to Wi-Fi'));
      await tester.tap(find.text('Connect to Wi-Fi'));
      await tester.pump();
    }

    testWidgets('an older status cannot undo an accepted join', (tester) async {
      await ready(tester);
      final stale = Completer<Map<String, dynamic>>();
      api.readStatus = () => stale.future;
      await tester.pump(const Duration(seconds: 2));
      await join(tester);
      stale.complete(api.response);
      await tester.pump();
      expect(api.commands, ['open', 'join']);
      expect(busy.last, true);
      expect(find.text('Connect to Wi-Fi'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('scanning keeps the parent action busy until results arrive', (
      tester,
    ) async {
      await ready(tester);
      await tester.ensureVisible(find.text('Find Wi-Fi networks'));
      await tester.tap(find.text('Find Wi-Fi networks'));
      await tester.pump();
      expect(api.commands, ['open', 'scan']);
      expect(busy.last, true);
      api.response['setup'] = {
        'state': 0,
        'scan_state': 'ready',
        'networks': [],
      };
      await tester.pump(const Duration(seconds: 2));
      expect(busy.last, false);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('leaving while opening setup never sends credentials', (
      tester,
    ) async {
      await ready(tester);
      final opening = Completer<void>();
      api.sendCommand = (_) => opening.future;
      await join(tester);
      expect(api.commands, ['open']);
      await tester.pumpWidget(const SizedBox());
      opening.complete();
      await tester.pump();
      expect(api.commands, ['open']);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'leaving before the join reply does not touch disposed fields',
      (tester) async {
        await ready(tester);
        final joining = Completer<void>();
        api.sendCommand = (operation) async {
          if (operation == 'join') await joining.future;
        };
        await join(tester);
        expect(api.commands, ['open', 'join']);
        await tester.pumpWidget(const SizedBox());
        joining.complete();
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  });

  for (final size in [const Size(375, 812), const Size(812, 375)]) {
    for (final hotspot in [false, true]) {
      testWidgets('setup screen fits large text at $size (hotspot: $hotspot)', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: hotspot
                ? NetworkSetupScreen(
                    endpoint: Uri.parse('http://192.168.4.1'),
                    hotspot: true,
                  )
                : const SetupMethodScreen(),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  for (final size in [
    const Size(375, 812),
    const Size(812, 375),
    const Size(1024, 768),
  ]) {
    testWidgets('network setup supports large text at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = FakeSetupApi({
        'available': true,
        'hotspot': true,
        'network': {'connected': false},
        'setup': {'state': 0, 'networks': []},
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: NetworkSetupPanel(endpoint: api.base, api: api),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Connect to Wi-Fi'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('Back from hotspot setup returns to the transport choices', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SetupMethodScreen(),
                ),
              ),
              child: const Text('Start setup'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Start setup'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Use the temporary Wi-Fi hotspot'));
    await tester.tap(find.text('Use the temporary Wi-Fi hotspot'));
    await tester.pumpAndSettle();
    expect(find.text('Connect your box'), findsOneWidget);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Search using Bluetooth'), findsOneWidget);
    expect(find.text('Start setup'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('setup offers Bluetooth and hotspot choices', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: const SetupMethodScreen()),
    );
    expect(find.text('Search using Bluetooth'), findsOneWidget);
    expect(find.text('Use the temporary Wi-Fi hotspot'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
