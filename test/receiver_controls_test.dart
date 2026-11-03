import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/data_model/receiver_control.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/kalinka_player_api_provider.dart';
import 'package:kalinka/providers/receiver_provider.dart';
import 'package:kalinka/providers/renderer_provider.dart';
import 'package:kalinka/providers/wire_event_provider.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/receiver_panel.dart';

import 'support/home_shell.dart';

Map<String, dynamic> row({bool enabled = true, bool paired = false}) => {
  'receiver_id': 'bluetooth',
  'title': 'Bluetooth',
  'kind': 'bluetooth',
  'enabled': enabled,
  'state': enabled ? 'ready' : 'disabled',
  'effective_name': 'Kitchen Kalinka',
  'instructions': 'Select this name in your device’s Bluetooth settings.',
  'pairing': paired
      ? {'window_id': 'window-1', 'remaining_seconds': 120}
      : null,
  'actions': [
    for (final command in [
      'open_pairing',
      'close_pairing',
      'answer_pairing',
      'grant_audio',
      'revoke_audio',
      'disconnect_audio',
    ])
      {'command': command, 'available': enabled},
  ],
  'peers': [
    {
      'peer_id': 'phone-1',
      'name': 'Pixel 9 Pro',
      'paired': true,
      'audio_allowed': true,
      'connected': true,
    },
  ],
  'sessions': [],
};

class Inventory extends ReceiversNotifier {
  Inventory(this.initial);
  final ReceiverInventory initial;
  final commands = <Map<String, dynamic>>[];
  @override
  ReceiverInventory build() => initial;
  @override
  Future<void> refresh() async {}
  @override
  Future<void> command(
    ReceiverSnapshot receiver,
    Map<String, dynamic> command,
  ) async => commands.add(command);
  void replace(ReceiverInventory value) {
    state = value;
  }
}

class Renderers extends RendererListNotifier {
  @override
  RendererListState build() => const RendererListState(loaded: true);
}

class Connection extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

Future<SharedPreferences> prefs() async {
  SharedPreferences.setMockInitialValues({
    'Kalinka.name': 'Kitchen Kalinka',
    'Kalinka.host': 'kitchen.local',
    'Kalinka.port': 8000,
  });
  return SharedPreferences.getInstance();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final icons = File(
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(ByteData.sublistView(icons.readAsBytesSync())),
          ))
          .load();
    }
    for (final (family, file) in [
      ('IBM Plex Sans', 'IBMPlexSans-Regular.ttf'),
      ('IBM Plex Mono', 'IBMPlexMono-Regular.ttf'),
    ]) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$file'))).load();
    }
  });

  test('snapshot events include disabled receivers and old replies cannot replace them', () async {
    final requests = <RequestInterceptorHandler>[];
    final options = <RequestOptions>[];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            options.add(o);
            requests.add(h);
          },
        ),
      );
    final events = StreamController<PlayQueueEvent>();
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(await prefs()),
        connectionStateProvider.overrideWith(Connection.new),
        httpClientProvider.overrideWithValue(dio),
        playQueueEventBusProvider.overrideWith((ref) => events.stream),
      ],
    );
    addTearDown(() {
      container.dispose();
      events.close();
      dio.close();
    });
    container.listen(receiversProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    for (var i = 0; i < 20 && requests.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(requests, hasLength(1));
    events.add(
      PlayQueueEvent.fromJson({
        'event_type': 'receivers_changed',
        'seq': 5,
        'receivers': [row(enabled: false)],
      }),
    );
    await Future<void>.delayed(Duration.zero);
    expect(container.read(receiversProvider).receivers.single.enabled, false);
    requests.first.resolve(
      Response(
        requestOptions: options.first,
        data: {
          'receivers': [row()],
        },
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(container.read(receiversProvider).receivers.single.enabled, false);
    final refresh = container.read(receiversProvider.notifier).refresh();
    await Future<void>.delayed(Duration.zero);
    for (var i = 0; i < 20 && requests.length < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    requests.last.reject(DioException(requestOptions: options.last));
    await refresh;
    expect(container.read(receiversProvider).receivers, hasLength(1));
    expect(container.read(receiversProvider).error, isNotNull);
  });

  test('a failed command is sent once and followed by a GET', () async {
    final methods = <String>[];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            methods.add(o.method);
            if (o.method == 'POST') {
              h.reject(
                DioException(
                  requestOptions: o,
                  type: DioExceptionType.receiveTimeout,
                ),
              );
            } else {
              h.resolve(
                Response(
                  requestOptions: o,
                  data: {
                    'receivers': [row()],
                  },
                ),
              );
            }
          },
        ),
      );
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(await prefs()),
        connectionStateProvider.overrideWith(Connection.new),
        httpClientProvider.overrideWithValue(dio),
        playQueueEventBusProvider.overrideWith((ref) => const Stream.empty()),
      ],
    );
    addTearDown(() {
      container.dispose();
      dio.close();
    });
    container.listen(receiversProvider, (_, _) {});
    final notifier = container.read(receiversProvider.notifier);
    await Future<void>.delayed(Duration.zero);
    for (
      var i = 0;
      i < 20 && container.read(receiversProvider).receivers.isEmpty;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    methods.clear();
    await expectLater(
      notifier.command(ReceiverSnapshot.fromJson(row()), {
        'command': 'open_pairing',
      }),
      throwsException,
    );
    expect(methods, ['POST', 'GET']);
  });

  for (final (width, height, scale) in [
    (375.0, 812.0, 1.0),
    (320.0, 700.0, 2.0),
    (812.0, 375.0, 1.0),
    (640.0, 900.0, 3.0),
  ]) {
    testWidgets('receiver panel fits $width × $height at $scale text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, height);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final inventory = Inventory(
        ReceiverInventory(
          receivers: [
            ReceiverSnapshot.fromJson(row(paired: true)),
            ReceiverSnapshot.fromJson({
              'receiver_id': 'airplay',
              'title': 'AirPlay',
              'kind': 'airplay',
              'enabled': false,
              'state': 'disabled',
              'effective_name': 'Kitchen Kalinka',
            }),
          ],
        ),
      );
      final key = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPrefsProvider.overrideWithValue(await prefs()),
            receiversProvider.overrideWith(() => inventory),
            rendererListProvider.overrideWith(Renderers.new),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, height),
                textScaler: TextScaler.linear(scale),
                disableAnimations: true,
              ),
              child: Scaffold(
                body: RepaintBoundary(key: key, child: const ReceiverPanel()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Play from a device'), findsOneWidget);
      expect(find.textContaining('Visible as Kitchen Kalinka'), findsOneWidget);
      final dir = Platform.environment['KALINKA_REVIEW_DIR'];
      if (dir != null) {
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$dir/receiver-$width-$scale.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.ensureVisible(find.text('Stop pairing'));
      await tester.tap(find.text('Stop pairing'));
      await tester.pump();
      expect(inventory.commands.single, {
        'command': 'close_pairing',
        'window_id': 'window-1',
      });
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('Home hides disabled receivers without any catalog sources', (
    tester,
  ) async {
    final inventory = Inventory(
      ReceiverInventory(
        receivers: [ReceiverSnapshot.fromJson(row(enabled: false))],
      ),
    );
    await pumpHomeShell(
      tester,
      queue: SettableQueue(queueOf(0)),
      receivers: () => inventory,
    );
    expect(find.text('Connect'), findsNothing);
    expect(find.text('Connect'), findsNothing);
  });

  testWidgets(
    'entry hides for empty inventory and remains for a failed refresh',
    (tester) async {
      final inventory = Inventory(const ReceiverInventory());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [receiversProvider.overrideWith(() => inventory)],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: ConnectSourceButton()),
          ),
        ),
      );
      expect(find.text('Connect'), findsNothing);
      inventory.replace(
        ReceiverInventory(
          receivers: [ReceiverSnapshot.fromJson(row())],
          error: 'Offline',
        ),
      );
      await tester.pump();
      expect(find.text('Connect'), findsOneWidget);
    },
  );
}
