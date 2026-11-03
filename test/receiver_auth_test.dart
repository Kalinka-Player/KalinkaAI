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
import 'package:kalinka/widgets/receiver_approval.dart';
import 'package:kalinka/widgets/receiver_panel.dart';

import 'receiver_controls_test.dart' as f;
import 'support/home_shell.dart';

Map<String, dynamic> pending({
  String method = 'confirmation',
  double seconds = 60,
}) => {
  ...f.row(paired: true),
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

  testWidgets('older Bluetooth receivers cannot bypass explicit approval', (
    tester,
  ) async {
    final row = f.row();
    row['actions'] = (row['actions'] as List)
        .where((a) => a['command'] != 'answer_pairing')
        .toList();
    final inventory = f.Inventory(
      ReceiverInventory(receivers: [ReceiverSnapshot.fromJson(row)]),
    );
    await pump(tester, inventory);
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Pair a device'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Bluetooth'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Pair a device'),
          )
          .onPressed,
      isNull,
    );
    expect(
      find.text('Update the server to pair with device approval.'),
      findsOneWidget,
    );
    expect(inventory.commands, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('mobile Connect stays in source strip and opens a compact list', (
    tester,
  ) async {
    final inventory = f.Inventory(
      ReceiverInventory(
        receivers: [
          ReceiverSnapshot.fromJson({...f.row(), 'peers': []}),
          ReceiverSnapshot.fromJson({
            ...f.row(),
            'receiver_id': 'airplay',
            'kind': 'airplay',
            'title': 'AirPlay',
            'actions': [],
            'peers': [],
            'password_required': true,
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
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'AirPlay password is explicitly revealed, hidden and cleared on background',
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
      await pump(tester, inventory);
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(find.text('Password required'), findsOneWidget);
      expect(find.text('room-secret'), findsNothing);
      expect(inventory.reveals, 0);
      await tester.tap(find.text('Show password'));
      await tester.pumpAndSettle();
      expect(find.text('room-secret'), findsOneWidget);
      await tester.tap(find.text('Hide password'));
      await tester.pumpAndSettle();
      expect(find.text('room-secret'), findsNothing);
      inventory.pendingPassword = Completer<String>();
      await tester.tap(find.text('Show password'));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      inventory.pendingPassword!.complete('room-secret');
      await tester.pumpAndSettle();
      expect(find.text('room-secret'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );

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
    expect(find.text('Stop pairing'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(inventory.commands, isEmpty);
    expect(find.text('Stop pairing'), findsNothing);
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
      final inventory = f.Inventory(
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
      expect(find.text('Pair a device'), findsOneWidget);
      await capture(tester, 'wide-popover');
      expect(
        tester.getSize(find.byType(ReceiverPanel)).width,
        lessThanOrEqualTo(380),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(ReceiverPanel), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
