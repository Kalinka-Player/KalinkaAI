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
  final List<Map<String, Object>> payloads = [];
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
    payloads.add(fields);
    await sendCommand?.call(operation);
    if (operation == 'scan') {
      response['setup'] = {...response['setup'] as Map, 'scan_state': 'ready'};
    } else if (operation == 'join') {
      response['setup'] = {...response['setup'] as Map, 'state': 1};
    } else if (operation == 'change_network') {
      response['setup'] = {'state': 0, 'scan_state': 'idle', 'networks': []};
    }
  }
}

Map<String, dynamic> status({
  String? kind,
  int state = 0,
  bool available = true,
  String? ssid,
}) => {
  'available': available,
  'network': {
    'connected': kind != null,
    'kind': kind,
    'address': '192.168.1.20',
    'ssid': ?ssid,
  },
  'setup': {
    'state': state,
    'scan_state': 'idle',
    'networks': [
      {'ssid': 'Home', 'security': 'wpa2'},
      {'ssid': 'Open', 'security': 'open'},
    ],
  },
};

const manualEntry = 'Can’t find your network? Enter SSID manually';
final countryField = find.byKey(const ValueKey('network-country'));
final ssidField = find.byKey(const ValueKey('network-ssid'));
final passwordField = find.byKey(const ValueKey('network-password'));

Future<void> mountPanel(
  WidgetTester tester,
  FakeSetupApi api, {
  ValueChanged<bool>? onBusy,
  VoidCallback? onReconnect,
  Locale locale = const Locale('en', 'GB'),
  double scale = 1,
}) async {
  tester.platformDispatcher.localeTestValue = locale;
  addTearDown(tester.platformDispatcher.clearLocaleTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: NetworkSetupPanel(
            endpoint: api.base,
            api: api,
            onBusy: onBusy,
            onReconnect: onReconnect,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> finishScan(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
  await tester.pump();
}

Future<void> manualCredentials(WidgetTester tester) async {
  await tester.ensureVisible(find.text(manualEntry));
  await tester.tap(find.text(manualEntry));
  await tester.pump();
  await tester.enterText(ssidField, 'Home');
  await tester.enterText(passwordField, 'test-password');
}

Future<void> join(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Connect to Wi-Fi'));
  await tester.tap(find.text('Connect to Wi-Fi'));
  await tester.pump();
}

Future<void> chooseCountry(
  WidgetTester tester,
  String query,
  String label,
) async {
  await tester.ensureVisible(countryField);
  final input = find.descendant(
    of: countryField,
    matching: find.byType(TextField),
  );
  await tester.tap(input);
  await tester.enterText(input, query);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(MenuItemButton, label).last);
  await tester.pump();
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

  testWidgets('waits for box status before showing its network connection', (
    tester,
  ) async {
    final response = Completer<Map<String, dynamic>>();
    final api = FakeSetupApi(status(kind: 'wired', state: 4));
    api.readStatus = () => response.future;
    await mountPanel(tester, api);
    expect(find.text('Looking for your box…'), findsOneWidget);
    expect(find.text('Network connection'), findsNothing);
    expect(api.commands, isEmpty);
    response.complete(api.response);
    await tester.pump();
    expect(find.text('Looking for your box…'), findsNothing);
    expect(find.text('Connected by Ethernet'), findsOneWidget);
    expect(find.text('Finding Wi-Fi networks…'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final kind in ['wired', 'wifi', null]) {
    testWidgets('discovers automatically once while keeping $kind connection', (
      tester,
    ) async {
      final api = FakeSetupApi(status(kind: kind, state: kind == null ? 0 : 4));
      await mountPanel(tester, api);
      expect(api.commands, ['open', 'scan']);
      expect(api.payloads.last, {'country': 'GB'});
      expect(find.text('Finding Wi-Fi networks…'), findsOneWidget);
      expect(ssidField, findsNothing);
      expect(passwordField, findsNothing);
      if (kind != null) {
        expect(
          find.text(
            kind == 'wired' ? 'Connected by Ethernet' : 'Connected by Wi-Fi',
          ),
          findsOneWidget,
        );
      }
      await finishScan(tester);
      expect(find.text('Home'), findsOneWidget);
      await finishScan(tester);
      expect(api.commands, ['open', 'scan']);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('selecting a network asks only for its password', (tester) async {
    final api = FakeSetupApi(status());
    await mountPanel(tester, api);
    await finishScan(tester);
    await tester.tap(find.text('Open'));
    await tester.pump();
    expect(passwordField, findsNothing);
    await tester.tap(find.text('Home'));
    await tester.pump();
    expect(passwordField, findsOneWidget);
    expect(ssidField, findsNothing);
    await tester.enterText(passwordField, 'test-password');
    await join(tester);
    expect(api.commands, ['open', 'scan', 'open', 'join']);
    expect(api.payloads.last, {
      'ssid': 'Home',
      'password': 'test-password',
      'country': 'GB',
    });
    expect(find.text('Connecting to Home…'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'shows the connected SSID and keeps it separate from a new join',
    (tester) async {
      final api = FakeSetupApi(
        status(kind: 'wifi', state: 4, ssid: 'Current Wi-Fi'),
      );
      await mountPanel(tester, api);
      expect(find.text('Current Wi-Fi'), findsOneWidget);
      expect(find.text('192.168.1.20'), findsOneWidget);
      await finishScan(tester);
      await manualCredentials(tester);
      await tester.enterText(ssidField, 'New Wi-Fi');
      await join(tester);
      expect(find.text('Current Wi-Fi'), findsOneWidget);
      expect(find.text('Connecting to New Wi-Fi…'), findsOneWidget);
      expect(passwordField, findsNothing);
      api.response.addAll(status(kind: 'wifi', state: 2, ssid: 'New Wi-Fi'));
      await finishScan(tester);
      expect(find.text('Current Wi-Fi'), findsNothing);
      expect(find.text('Connecting to New Wi-Fi…'), findsNothing);
      expect(find.text('New Wi-Fi'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('restores the joining network name from supervisor status', (
    tester,
  ) async {
    final response = status(state: 1);
    response['setup']['target_ssid'] = 'Café Wi-Fi';
    final api = FakeSetupApi(response);
    await mountPanel(tester, api);
    expect(find.text('Connecting to Café Wi-Fi…'), findsOneWidget);
    expect(find.text('Please wait…'), findsOneWidget);
    expect(api.commands, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Ethernet never displays a Wi-Fi name', (tester) async {
    final api = FakeSetupApi(
      status(kind: 'wired', state: 4, ssid: 'Other Wi-Fi'),
    );
    await mountPanel(tester, api);
    expect(find.text('Connected by Ethernet'), findsOneWidget);
    expect(find.text('Other Wi-Fi'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('manual entry validates credentials and can return to the list', (
    tester,
  ) async {
    final api = FakeSetupApi(status());
    await mountPanel(tester, api);
    await finishScan(tester);
    await tester.tap(find.text(manualEntry));
    await tester.pump();
    expect(ssidField, findsOneWidget);
    expect(passwordField, findsOneWidget);
    await join(tester);
    expect(api.commands, ['open', 'scan']);
    expect(find.text('Use a network name of 1–32 bytes.'), findsOneWidget);
    expect(
      find.text('Use 8–63 letters, numbers, spaces or symbols.'),
      findsOneWidget,
    );
    await tester.enterText(passwordField, 'test-password');
    await tester.ensureVisible(find.text('Back to available networks'));
    await tester.tap(find.text('Back to available networks'));
    await tester.pump();
    expect(find.text('Home'), findsOneWidget);
    expect(passwordField, findsNothing);
    await tester.tap(find.text('Home'));
    await tester.pump();
    expect(
      tester.widget<TextFormField>(passwordField).controller!.text,
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('missing locale country starts scanning when supplied', (
    tester,
  ) async {
    final api = FakeSetupApi(status());
    await mountPanel(tester, api, locale: const Locale('en'));
    expect(api.commands, isEmpty);
    expect(
      find.text('Choose your country below to find nearby networks.'),
      findsOneWidget,
    );
    await chooseCountry(tester, 'gb', 'United Kingdom (GB)');
    expect(api.commands, ['open', 'scan']);
    expect(api.payloads.last, {'country': 'GB'});
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'country names are searchable and selection rescans with its code',
    (tester) async {
      final api = FakeSetupApi(status());
      await mountPanel(tester, api);
      await finishScan(tester);
      await tester.ensureVisible(find.text('Wi-Fi region · GB'));
      await tester.tap(find.text('Wi-Fi region · GB'));
      await tester.pumpAndSettle();
      await chooseCountry(tester, 'Germany', 'Germany (DE)');
      expect(api.commands, ['open', 'scan', 'open', 'scan']);
      expect(api.payloads.last, {'country': 'DE'});
      await finishScan(tester);
      await manualCredentials(tester);
      await join(tester);
      expect(api.payloads.last['country'], 'DE');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('does not scan when setup is unavailable or joining', (
    tester,
  ) async {
    for (final response in [status(available: false), status(state: 1)]) {
      final api = FakeSetupApi(response);
      await mountPanel(tester, api);
      expect(api.commands, isEmpty);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('failed discovery offers manual entry and a retry', (
    tester,
  ) async {
    final api = FakeSetupApi(status());
    await mountPanel(tester, api);
    api.response['setup'] = {
      'state': 0,
      'scan_state': 'failed',
      'networks': [],
    };
    await finishScan(tester);
    expect(
      find.text(
        'Could not find networks. Try again or enter your network name manually.',
      ),
      findsOneWidget,
    );
    await manualCredentials(tester);
    expect(passwordField, findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'accepted credentials offer reconnection without claiming success',
    (tester) async {
      final api = FakeSetupApi({...status(), 'hotspot': true});
      var reconnected = false;
      await mountPanel(tester, api, onReconnect: () => reconnected = true);
      await finishScan(tester);
      await manualCredentials(tester);
      await join(tester);
      expect(api.commands, ['open', 'scan', 'open', 'join']);
      expect(find.text('Reconnect after changing Wi-Fi'), findsOneWidget);
      await tester.ensureVisible(find.text('Reconnect after changing Wi-Fi'));
      await tester.tap(find.text('Reconnect after changing Wi-Fi'));
      expect(reconnected, true);
      expect(find.text('Connected by Wi-Fi'), findsNothing);
      expect(
        find.text('Your box is connected and ready to use.'),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'success replaces credentials and changing network starts discovery',
    (tester) async {
      final api = FakeSetupApi(status());
      await mountPanel(tester, api);
      await finishScan(tester);
      await manualCredentials(tester);
      await join(tester);
      api.response.addAll(status(kind: 'wifi', state: 2));
      await finishScan(tester);
      expect(
        find.text('Your box is connected and ready to use.'),
        findsOneWidget,
      );
      expect(find.text('Change Wi-Fi network'), findsOneWidget);
      expect(find.text('Choose another network'), findsNothing);
      expect(passwordField, findsNothing);
      expect(ssidField, findsNothing);
      api.response.addAll(status(kind: 'wifi', state: 4));
      await finishScan(tester);
      expect(
        find.text('Your box is connected and ready to use.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Change Wi-Fi network'));
      await tester.pump();
      await finishScan(tester);
      expect(api.commands, [
        'open',
        'scan',
        'open',
        'join',
        'open',
        'change_network',
        'open',
        'scan',
      ]);
      expect(find.text('Finding Wi-Fi networks…'), findsOneWidget);
      expect(
        find.text('Your box is connected and ready to use.'),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'connecting hides credentials and can be cancelled into discovery',
    (tester) async {
      final api = FakeSetupApi(status());
      await mountPanel(tester, api);
      await finishScan(tester);
      await manualCredentials(tester);
      final joining = Completer<void>();
      api.sendCommand = (operation) async {
        if (operation == 'join') await joining.future;
        if (operation == 'open' && api.response['setup']['state'] == 1) {
          throw StateError('Cannot open setup while joining');
        }
      };
      await join(tester);
      expect(passwordField, findsNothing);
      expect(ssidField, findsNothing);
      expect(find.text('Please wait…'), findsOneWidget);
      joining.complete();
      await tester.pump();
      final cancelling = Completer<void>();
      api.sendCommand = (operation) async {
        expect(operation, 'change_network');
        await cancelling.future;
      };
      await tester.tap(find.text('Choose another network'));
      await tester.pump();
      await tester.tap(find.text('Choose another network'));
      await tester.pump();
      expect(api.commands, ['open', 'scan', 'open', 'join', 'change_network']);
      cancelling.complete();
      await tester.pump();
      api.sendCommand = null;
      await finishScan(tester);
      expect(api.commands, [
        'open',
        'scan',
        'open',
        'join',
        'change_network',
        'open',
        'scan',
      ]);
      expect(find.text('Finding Wi-Fi networks…'), findsOneWidget);
      expect(passwordField, findsNothing);
      await finishScan(tester);
      await tester.tap(find.text(manualEntry));
      await tester.pump();
      expect(
        tester.widget<TextFormField>(passwordField).controller!.text,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a failed cancellation keeps the waiting screen and offers retry',
    (tester) async {
      final api = FakeSetupApi(status());
      await mountPanel(tester, api);
      await finishScan(tester);
      await manualCredentials(tester);
      await join(tester);
      api.sendCommand = (_) async => throw StateError('unreachable');
      await tester.tap(find.text('Choose another network'));
      await tester.pump();
      expect(find.text('Please wait…'), findsOneWidget);
      expect(passwordField, findsNothing);
      api.sendCommand = null;
      await tester.tap(find.text('Choose another network'));
      await tester.pump();
      await finishScan(tester);
      expect(find.text('Finding Wi-Fi networks…'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a join failure keeps the selected network and allows retry', (
    tester,
  ) async {
    final api = FakeSetupApi(status());
    await mountPanel(tester, api);
    await finishScan(tester);
    await tester.tap(find.text('Home'));
    await tester.pump();
    await tester.enterText(passwordField, 'test-password');
    await join(tester);
    api.response['setup'] = {
      'state': 3,
      'reason': 2,
      'scan_state': 'ready',
      'networks': [],
    };
    await finishScan(tester);
    expect(
      find.text('The Wi-Fi password was not accepted. Try again.'),
      findsOneWidget,
    );
    expect(find.text('Home'), findsOneWidget);
    expect(passwordField, findsOneWidget);
    expect(find.text('Connect to Wi-Fi'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  group('in-flight network requests', () {
    late FakeSetupApi api;
    final busy = <bool>[];
    setUp(() {
      busy.clear();
      api = FakeSetupApi(status());
    });
    Future<void> ready(WidgetTester tester) async {
      await mountPanel(tester, api, onBusy: busy.add);
      await finishScan(tester);
      api.commands.clear();
      await manualCredentials(tester);
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

    testWidgets('scanning stays busy until results arrive', (tester) async {
      await mountPanel(tester, api, onBusy: busy.add);
      expect(api.commands, ['open', 'scan']);
      expect(busy.last, true);
      await finishScan(tester);
      expect(busy.last, false);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('leaving while opening discovery never sends scan', (
      tester,
    ) async {
      final opening = Completer<void>();
      api.sendCommand = (_) => opening.future;
      await mountPanel(tester, api);
      expect(api.commands, ['open']);
      await tester.pumpWidget(const SizedBox());
      opening.complete();
      await tester.pump();
      expect(api.commands, ['open']);
      expect(tester.takeException(), isNull);
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
    const Size(320, 640),
    const Size(375, 812),
    const Size(812, 375),
    const Size(1024, 768),
  ]) {
    testWidgets('discovery and manual entry support large text at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = FakeSetupApi(
        status(
          kind: 'wifi',
          state: 4,
          ssid: '12345678901234567890123456789012',
        ),
      );
      await mountPanel(tester, api, scale: 2);
      await finishScan(tester);
      await tester.ensureVisible(find.text('Wi-Fi region · GB'));
      await tester.tap(find.text('Wi-Fi region · GB'));
      await tester.pumpAndSettle();
      await chooseCountry(tester, 'United States', 'United States (US)');
      await finishScan(tester);
      await manualCredentials(tester);
      await tester.ensureVisible(find.text('Connect to Wi-Fi'));
      await tester.enterText(ssidField, 'Another network with a long name');
      await join(tester);
      await tester.ensureVisible(find.text('Choose another network'));
      expect(
        find.text('Connecting to Another network with a long name…'),
        findsOneWidget,
      );
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
