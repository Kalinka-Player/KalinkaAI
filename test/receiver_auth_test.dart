import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/receiver_control.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/receiver_provider.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/kalinka_dialog.dart';
import 'package:kalinka/widgets/receiver_approval.dart';
import 'package:kalinka/widgets/receiver_panel.dart';

import 'receiver_controls_test.dart' as f;
import 'support/home_shell.dart';

Map<String, dynamic> pending({
  String method = 'confirmation',
  double seconds = 60,
}) => {
  ...f.row(paired: true),
  'pairing_mode': 'confirm',
  'actions': [
    ...f.row()['actions'] as List,
    {'command': 'answer_pairing', 'available': true},
  ],
  'pairing_request': {
    'request_id': 'approval-1',
    'device_name': 'Pixel 9 Pro',
    'method': method,
    'code': method == 'confirmation' ? '000042' : null,
    'remaining_seconds': seconds,
  },
};

final captureKey = GlobalKey();

Future<void> capture(WidgetTester tester, String name) async {
  final dir = Platform.environment['KALINKA_REVIEW_DIR'];
  if (dir == null) return;
  await tester.runAsync(() async {
    final boundary =
        captureKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(dir).create(recursive: true);
    await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> pump(
  WidgetTester tester,
  f.Inventory inventory, {
  Size size = const Size(375, 812),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(await f.prefs()),
        receiversProvider.overrideWith(() => inventory),
      ],
      child: RepaintBoundary(
        key: captureKey,
        child: MaterialApp(
          theme: AppTheme.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: const ReceiverApprovalHost(
            child: Scaffold(body: ConnectSourceButton()),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class PasswordInventory extends f.Inventory {
  PasswordInventory(super.initial);
  int reveals = 0;
  Completer<String>? pendingPassword;
  @override
  Future<String> revealPassword(ReceiverSnapshot receiver) {
    reveals++;
    return pendingPassword?.future ?? Future.value('room-secret');
  }
}

void main() {
  setUpAll(() async {
    for (final (family, file) in [
      ('IBM Plex Sans', 'IBMPlexSans-Regular.ttf'),
      ('IBM Plex Mono', 'IBMPlexMono-Regular.ttf'),
      ('Playfair Display', 'PlayfairDisplay-Regular.ttf'),
    ]) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$file'))).load();
    }
    final icons = File(
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(ByteData.sublistView(icons.readAsBytesSync())),
          ))
          .load();
    }
  });

  testWidgets(
    'Bluetooth lists paired devices directly and pairing needs no app approval',
    (tester) async {
      final inventory = f.Inventory(
        ReceiverInventory(receivers: [ReceiverSnapshot.fromJson(f.row())]),
      );
      await pump(tester, inventory);
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(find.text('Bluetooth'), findsOneWidget);
      expect(find.text('Pixel 9 Pro'), findsOneWidget);
      expect(find.text('Paired'), findsOneWidget);
      expect(find.byTooltip('Device options for Pixel 9 Pro'), findsOneWidget);
      expect(find.text('Forget'), findsNothing);
      expect(find.text('Paired devices'), findsOneWidget);
      expect(find.text('Saved devices'), findsNothing);
      expect(find.text('Allow audio'), findsNothing);
      expect(find.text('Remove audio access'), findsNothing);
      final beforePairing = tester.getRect(find.byType(ReceiverPanel));
      inventory.pendingCommand = Completer<void>();
      await tester.tap(find.text('Pair new'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.getRect(find.byType(ReceiverPanel)), beforePairing);
      inventory.pendingCommand!.complete();
      await tester.pumpAndSettle();
      expect(inventory.commands.single, {'command': 'open_pairing'});
      expect(find.byType(ReceiverApproval), findsNothing);
      await capture(tester, 'bluetooth-devices');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Disconnect retains pairing while Forget requires explicit confirmation',
    (tester) async {
      final row = f.row();
      row['sessions'] = [
        {
          'session_id': 'session-1',
          'peer_id': 'phone-1',
          'name': 'Pixel 9 Pro',
          'playing': true,
        },
      ];
      final inventory = f.Inventory(
        ReceiverInventory(receivers: [ReceiverSnapshot.fromJson(row)]),
      );
      await pump(tester, inventory);
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(find.text('Connected'), findsOneWidget);
      await tester.tap(find.byTooltip('Device options for Pixel 9 Pro'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();
      expect(inventory.commands.single, {
        'command': 'disconnect_audio',
        'session_id': 'session-1',
      });
      await tester.tap(find.byTooltip('Device options for Pixel 9 Pro'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forget'));
      await tester.pumpAndSettle();
      expect(find.text('Forget Pixel 9 Pro?'), findsOneWidget);
      expect(
        find.text('Removes the Bluetooth pairing. Pair again to reconnect.'),
        findsOneWidget,
      );
      await capture(tester, 'bluetooth-forget');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(KalinkaDialog), findsNothing);
      expect(inventory.commands.length, 1);
      await tester.tap(find.byTooltip('Device options for Pixel 9 Pro'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forget'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(KalinkaDialog),
          matching: find.text('Forget'),
        ),
      );
      await tester.pumpAndSettle();
      expect(inventory.commands.last, {
        'command': 'forget_device',
        'peer_id': 'phone-1',
      });
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final action in ['Disconnect', 'Forget']) {
    testWidgets('$action keeps the device row stable while pending', (
      tester,
    ) async {
      final inventory = f.Inventory(
        ReceiverInventory(
          receivers: [
            ReceiverSnapshot.fromJson({
              ...f.row(),
              'peers': [
                ...(f.row()['peers'] as List),
                {'peer_id': 'laptop-1', 'name': 'Laptop', 'paired': true},
              ],
              'sessions': [
                {
                  'session_id': 'session-1',
                  'peer_id': 'phone-1',
                  'name': 'Pixel 9 Pro',
                },
              ],
            }),
          ],
        ),
      );
      await pump(tester, inventory);
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      final before = tester.getRect(find.byType(ReceiverPanel));
      final menu = find.byTooltip('Device options for Pixel 9 Pro');
      final icon = find.descendant(
        of: menu,
        matching: find.byIcon(Icons.more_vert),
      );
      final iconRect = tester.getRect(icon);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      inventory.pendingCommand = Completer<void>();
      await tester.tap(find.text(action));
      if (action == 'Forget') {
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(KalinkaDialog),
            matching: find.text('Forget'),
          ),
        );
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      expect(tester.getRect(find.byType(ReceiverPanel)), before);
      expect(tester.getRect(find.byType(CircularProgressIndicator)), iconRect);
      await capture(tester, 'bluetooth-${action.toLowerCase()}-loading');
      inventory.pendingCommand!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('mobile Connect stays in source strip and opens a compact list', (
    tester,
  ) async {
    final bluetooth = {
      ...f.row(),
      'effective_name': 'Test',
      'peers': [
        {
          ...(f.row()['peers'] as List).first as Map<String, dynamic>,
          'connected': true,
        },
        {
          'peer_id': 'laptop-1',
          'name': 'Laptop',
          'paired': true,
          'connected': false,
        },
      ],
      'sessions': [
        {
          'session_id': 'session-1',
          'peer_id': 'phone-1',
          'name': 'Pixel 9 Pro',
        },
      ],
    };
    final inventory = f.Inventory(
      ReceiverInventory(
        receivers: [
          ReceiverSnapshot.fromJson(bluetooth),
          ReceiverSnapshot.fromJson({
            ...f.row(),
            'receiver_id': 'airplay',
            'kind': 'airplay',
            'title': 'AirPlay',
            'actions': [],
            'peers': [],
            'password_required': false,
            'password_reveal_available': true,
            'instructions': "Choose this speaker in your device's AirPlay menu on the same network.",
          }),
        ],
      ),
    );
    await pumpHomeShell(
      tester,
      queue: SettableQueue(queueOf(0)),
      receivers: () => inventory,
      size: const Size(375, 812),
      themed: true,
      captureKey: captureKey,
    );
    expect(find.byKey(const ValueKey('connect-source-button')), findsOneWidget);
    expect(find.text('Connect a device'), findsNothing);
    await capture(tester, 'mobile-home');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Bluetooth'), findsOneWidget);
    expect(find.text('AirPlay'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, 'mobile-connect');
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('Paired'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Paired devices')).dy -
          tester
              .getBottomLeft(find.byKey(const ValueKey('receiver-pair-new')))
              .dy,
      lessThanOrEqualTo(12),
    );
    inventory.replace(
      ReceiverInventory(
        receivers: [
          ReceiverSnapshot.fromJson({
            ...bluetooth,
            'pairing': {'window_id': 'window-2', 'remaining_seconds': 103},
          }),
          ...inventory.initial.receivers.skip(1),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pairing · 1:43'), findsOneWidget);
    expect(find.text('Pair new'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Paired devices')).dy -
          tester.getBottomLeft(find.byTooltip('Stop pairing')).dy,
      lessThanOrEqualTo(12),
    );
    await capture(tester, 'mobile-connect-pairing');
    await tester.tap(find.byTooltip('Device options for Laptop'));
    await tester.pumpAndSettle();
    expect(find.text('Forget'), findsOneWidget);
    expect(find.text('Disconnect'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Device options for Pixel 9 Pro'));
    await tester.pumpAndSettle();
    expect(find.text('Forget'), findsOneWidget);
    expect(find.text('Disconnect'), findsOneWidget);
    await capture(tester, 'mobile-device-menu');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  for (final (size, scale) in [
    (const Size(375, 812), 1.0),
    (const Size(320, 700), 2.0),
    (const Size(812, 375), 1.0),
    (const Size(640, 900), 3.0),
  ]) {
    testWidgets(
      'AirPlay password toggles and clears at $size with $scale text',
      (tester) async {
        final inventory = PasswordInventory(
          ReceiverInventory(
            receivers: [
              ReceiverSnapshot.fromJson({
                ...f.row(),
                'receiver_id': 'airplay',
                'title': 'AirPlay',
                'kind': 'airplay',
                'password_required': true,
                'password_reveal_available': true,
                'actions': [],
                'peers': [],
              }),
            ],
          ),
        );
        await pump(tester, inventory, size: size, scale: scale);
        await tester.tap(find.text('Connect'));
        await tester.pumpAndSettle();
        expect(
          find.text('Password required - click to reveal'),
          findsOneWidget,
        );
        expect(find.text('room-secret'), findsNothing);
        expect(inventory.reveals, 0);
        await capture(tester, 'airplay-password-hidden-${size.width}-$scale');
        await tester.tap(find.text('AirPlay'));
        await tester.pumpAndSettle();
        expect(find.text('room-secret'), findsOneWidget);
        expect(find.byIcon(Icons.expand_less), findsOneWidget);
        expect(find.text('Show password'), findsNothing);
        await capture(tester, 'airplay-password-revealed-${size.width}-$scale');
        await tester.tap(find.text('AirPlay'));
        await tester.pumpAndSettle();
        expect(find.text('room-secret'), findsNothing);
        inventory.pendingPassword = Completer<String>();
        final beforeReveal = tester.getRect(find.byType(ReceiverPanel));
        final chevron = tester.getRect(find.byIcon(Icons.expand_more));
        await tester.tap(find.text('AirPlay'));
        await tester.pump();
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(tester.getRect(find.byType(ReceiverPanel)), beforeReveal);
        expect(tester.getRect(find.byType(CircularProgressIndicator)), chevron);
        await capture(tester, 'airplay-password-loading-${size.width}-$scale');
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        inventory.pendingPassword!.complete('room-secret');
        await tester.pumpAndSettle();
        expect(find.text('room-secret'), findsNothing);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        inventory.pendingPassword = null;
        await tester.tap(find.text('AirPlay'));
        await tester.pumpAndSettle();
        expect(find.text('room-secret'), findsOneWidget);
        final revealCount = inventory.reveals;
        for (final (required, available) in [(false, true), (true, false)]) {
          inventory.replace(
            ReceiverInventory(
              receivers: [
                ReceiverSnapshot.fromJson({
                  ...f.row(),
                  'receiver_id': 'airplay',
                  'title': 'AirPlay',
                  'kind': 'airplay',
                  'password_required': required,
                  'password_reveal_available': available,
                }),
              ],
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('room-secret'), findsNothing);
          expect(
            find.text(required ? 'Password required' : 'No password required'),
            findsOneWidget,
          );
          await tester.tap(find.text('AirPlay'));
          await tester.pumpAndSettle();
          expect(inventory.reveals, revealCount);
        }
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final accept in [true, false]) {
    testWidgets(
      'closed panel surfaces real zero-prefixed code and explicit $accept',
      (tester) async {
        final inventory = f.Inventory(
          ReceiverInventory(receivers: [ReceiverSnapshot.fromJson(pending())]),
        );
        await pump(tester, inventory);
        expect(
          find.text('Check this code matches your device'),
          findsOneWidget,
        );
        expect(find.text('000'), findsOneWidget);
        expect(find.text('042'), findsOneWidget);
        await capture(tester, 'approval-$accept');
        expect(inventory.commands, isEmpty);
        await tester.tap(find.text(accept ? 'Codes match' : 'Reject'));
        await tester.pump();
        expect(inventory.commands.single, {
          'command': 'answer_pairing',
          'request_id': 'approval-1',
          'accept': accept,
        });
        inventory.replace(
          ReceiverInventory(receivers: [ReceiverSnapshot.fromJson(f.row())]),
        );
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'cancellation or offline state closes approval without an answer',
    (tester) async {
      final inventory = f.Inventory(
        ReceiverInventory(receivers: [ReceiverSnapshot.fromJson(pending())]),
      );
      await pump(tester, inventory);
      inventory.replace(
        ReceiverInventory(
          receivers: inventory.initial.receivers,
          error: 'Offline',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(inventory.commands, isEmpty);
      // Reconnecting can restore the same still-pending request.
      inventory.replace(inventory.initial);
      await tester.pumpAndSettle();
      expect(find.text('Codes match'), findsOneWidget);
      inventory.replace(
        ReceiverInventory(receivers: [ReceiverSnapshot.fromJson(f.row())]),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'expired request cannot be accepted and code-less approval invents no code',
    (tester) async {
      final inventory = f.Inventory(
        ReceiverInventory(
          receivers: [
            ReceiverSnapshot.fromJson(
              pending(method: 'authorization', seconds: 0),
            ),
          ],
        ),
      );
      await pump(tester, inventory);
      expect(find.text('Codes match'), findsNothing);
      expect(find.text('000'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(inventory.commands, isEmpty);
      inventory.replace(const ReceiverInventory());
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('closing connection sheet leaves the pairing window open', (
    tester,
  ) async {
    final inventory = f.Inventory(
      ReceiverInventory(
        receivers: [ReceiverSnapshot.fromJson(f.row(paired: true))],
      ),
    );
    await pump(tester, inventory);
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Stop pairing'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(inventory.commands, isEmpty);
    expect(find.byTooltip('Stop pairing'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  for (final (size, scale) in [
    (const Size(320, 700), 2.0),
    (const Size(812, 375), 1.0),
    (const Size(640, 900), 3.0),
  ]) {
    testWidgets('approval fits $size at $scale text', (tester) async {
      final inventory = f.Inventory(
        ReceiverInventory(receivers: [ReceiverSnapshot.fromJson(pending())]),
      );
      await pump(tester, inventory, size: size, scale: scale);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Reject'));
      expect(find.text('Codes match'), findsOneWidget);
      inventory.replace(const ReceiverInventory());
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'wide sidebar lists enabled receivers and anchors their popover',
    (tester) async {
      final inventory = PasswordInventory(
        ReceiverInventory(
          receivers: [
            ReceiverSnapshot.fromJson(f.row()),
            ReceiverSnapshot.fromJson({
              ...f.row(enabled: false),
              'receiver_id': 'airplay',
              'title': 'AirPlay',
              'kind': 'airplay',
            }),
          ],
        ),
      );
      await pumpHomeShell(
        tester,
        queue: SettableQueue(queueOf(0)),
        receivers: () => inventory,
        size: const Size(1440, 900),
        themed: true,
        captureKey: captureKey,
      );
      expect(find.byKey(const ValueKey('connect-source-button')), findsNothing);
      final entry = find.byKey(const ValueKey('navigation-receiver-bluetooth'));
      expect(entry, findsOneWidget);
      expect(
        find.byKey(const ValueKey('navigation-receiver-airplay')),
        findsNothing,
      );
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.text('Pair new'), findsOneWidget);
      await capture(tester, 'wide-popover');
      await tester.tap(find.byTooltip('Device options for Pixel 9 Pro'));
      await tester.pumpAndSettle();
      expect(find.text('Forget'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(ReceiverPanel)).width,
        lessThanOrEqualTo(380),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(ReceiverPanel), findsNothing);
      inventory.replace(
        ReceiverInventory(
          receivers: [
            ReceiverSnapshot.fromJson({
              ...f.row(),
              'receiver_id': 'airplay',
              'title': 'AirPlay',
              'kind': 'airplay',
              'password_required': true,
              'password_reveal_available': true,
            }),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('navigation-receiver-airplay')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pumpAndSettle();
      expect(find.text('room-secret'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'wide-airplay-password');
      await tester.tap(find.byIcon(Icons.expand_less));
      await tester.pumpAndSettle();
      expect(find.text('room-secret'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
