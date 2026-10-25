import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/box_control_provider.dart';
import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/demo_mode.dart';
import 'package:kalinka/providers/onboarding_provider.dart';
import 'package:kalinka/providers/server_info_provider.dart';
import 'package:kalinka/providers/source_modules_provider.dart';
import 'package:kalinka/providers/supervisor_api.dart';
import 'package:kalinka/providers/url_resolver.dart';
import 'package:kalinka/providers/websocket_provider.dart';
import 'package:kalinka/screens/music_player_screen.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/box_actions.dart';
import 'package:kalinka/widgets/kalinka_bottom_sheet.dart';
import 'package:kalinka/widgets/kalinka_dialog.dart';
import 'package:kalinka/widgets/kalinka_toast_overlay.dart';
import 'package:kalinka/widgets/server_chip.dart';
import 'package:kalinka/widgets/server_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'support/server_answer.dart';

class _Box implements SupervisorApi {
  _Box({this.actions = const {'poweroff'}, this.available = true});

  final Set<String> actions;
  final bool available;
  final runs = <(BoxAction, String)>[];
  BoxActionException? refusal;

  @override
  Future<SupervisorInfo?> info() async => available
      ? SupervisorInfo(
          version: '0.2.0',
          protocol: 1,
          minProtocol: 1,
          serverId: 'server-1',
          actions: actions,
        )
      : null;

  @override
  Future<({SupervisorReach reach, SupervisorInfo? info})> probe() async {
    final answer = await info();
    return (
      reach: answer == null ? SupervisorReach.absent : SupervisorReach.answered,
      info: answer,
    );
  }

  @override
  Future<void> run(BoxAction action, {required String serverId}) async {
    runs.add((action, serverId));
    if (refusal != null) throw refusal!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Connected extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

class _Queue extends PlayQueueStateStore {
  @override
  PlayQueueState build() => PlayQueueState.empty;
}

Future<SharedPreferences> _pumpPlayer(
  WidgetTester tester, {
  required Size size,
  required _Box box,
  bool demo = false,
  double textScale = 1,
  Widget home = const MusicPlayerScreen(),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    'Kalinka.name': 'Living room',
    'Kalinka.host': 'kalinka.local',
    'Kalinka.port': 8000,
    OnboardingStatusNotifier.sharedPrefOobeComplete: true,
    OnboardingStatusNotifier.sharedPrefCoachMarksShown: true,
  });
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        connectionStateProvider.overrideWith(_Connected.new),
        serverAnswering('box-1'),
        playQueueStateStoreProvider.overrideWith(_Queue.new),
        demoModeProvider.overrideWithValue(demo),
        serverIdentityProvider.overrideWith((ref) async => 'server-1'),
        supervisorApiProvider.overrideWithValue(box),
        serverInfoProvider.overrideWith(
          (ref) async => const ServerInfo(version: '5.8.0', latencyMs: 2),
        ),
        sourceModulesProvider.overrideWith((ref) => <ModuleInfo>[]),
        sourceCountProvider.overrideWithValue(1),
        urlResolverProvider.overrideWithValue(UrlResolver('')),
        webSocketProvider.overrideWith(
          (ref, path) => Completer<WebSocketChannel>().future,
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: KalinkaToastHost(child: child!),
        ),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return prefs;
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byType(ServerChip));
  await tester.pumpAndSettle();
}

Future<void> _askToPowerOff(WidgetTester tester) async {
  await _openMenu(tester);
  // The menu's row: a wide rail has a Power off of its own.
  final powerOff = find.descendant(
    of: find.byType(SheetRow),
    matching: find.text('Power off'),
  );
  await tester.ensureVisible(powerOff);
  await tester.tap(powerOff);
  await tester.pumpAndSettle();
  expect(find.byType(ServerSheetContent), findsNothing);
  expect(find.byType(ServerSheet), findsNothing);
  expect(find.text('Power off streamer?'), findsOneWidget);
}

final _confirm = find.descendant(
  of: find.byType(BoxActionDialog),
  matching: find.text('Power off'),
);

void main() {
  for (final size in [
    const Size(375, 812),
    const Size(667, 375),
    const Size(900, 1280),
    const Size(1280, 800),
  ]) {
    testWidgets('power off remains reachable with large text at $size', (
      tester,
    ) async {
      final box = _Box();
      final phone = size.width < kKalinkaTabletBreakpoint;
      await _pumpPlayer(
        tester,
        size: size,
        box: box,
        textScale: 2,
        // Isolate the phone sheet from the mini-player's existing fixed-height
        // track label, which overflows at 2x text even with the menu closed.
        home: phone
            ? Consumer(
                builder: (context, ref, _) => Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      final action =
                          await showKalinkaBottomSheet<ServerSheetAction>(
                            context: context,
                            contentBuilder: (_) => const ServerSheetContent(),
                          );
                      if (action == ServerSheetAction.powerOff &&
                          context.mounted) {
                        await runBoxAction(context, ref, BoxAction.powerOff);
                      }
                    },
                    child: const Text('Open menu'),
                  ),
                ),
              )
            : const MusicPlayerScreen(),
      );
      if (phone) {
        await tester.tap(find.text('Open menu'));
        await tester.pumpAndSettle();
      } else {
        await _openMenu(tester);
      }
      final row = find.ancestor(
        of: find.text('Power off'),
        matching: find.byType(SheetRow),
      );
      await tester.ensureVisible(row);
      expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
      await tester.tap(find.text('Power off'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(box.runs, isEmpty);
    });
  }

  for (final size in [const Size(375, 812), const Size(1280, 800)]) {
    final layout = size.width < 900 ? 'phone' : 'tablet';

    testWidgets('$layout menu shuts down only after confirmation', (
      tester,
    ) async {
      final box = _Box();
      final prefs = await _pumpPlayer(tester, size: size, box: box);

      await _askToPowerOff(tester);
      expect(box.runs, isEmpty);
      if (layout == 'tablet') {
        final card = tester.getRect(find.byKey(KalinkaDialog.cardKey));
        expect(
          card.right,
          lessThanOrEqualTo(size.width - kalinkaPlayerPaneWidth(size.width)),
        );
      }
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(box.runs, isEmpty);

      await _askToPowerOff(tester);
      // Dismissing the confirmation also leaves the server running.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(BoxActionDialog), findsNothing);
      expect(box.runs, isEmpty);

      await _askToPowerOff(tester);
      await tester.tap(_confirm);
      await tester.pumpAndSettle();
      expect(box.runs, [(BoxAction.powerOff, 'server-1')]);
      expect(find.textContaining('Powering off.'), findsOneWidget);
      expect(prefs.getString('Kalinka.host'), 'kalinka.local');
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
    });

    testWidgets('$layout reports a shutdown refusal', (tester) async {
      final box = _Box()
        ..refusal = const BoxActionException('busy', 'The streamer is busy.');
      await _pumpPlayer(tester, size: size, box: box);
      await _askToPowerOff(tester);
      await tester.tap(_confirm);
      await tester.pumpAndSettle();

      expect(box.runs, [(BoxAction.powerOff, 'server-1')]);
      expect(find.text('The streamer is busy.'), findsOneWidget);
      expect(find.textContaining('Powering off.'), findsNothing);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
    });

    for (final reason in ['unsupported', 'no supervisor', 'demo']) {
      testWidgets('$layout omits power off for $reason', (tester) async {
        final box = _Box(
          available: reason != 'no supervisor',
          actions: reason == 'unsupported' ? {'reboot'} : {'poweroff'},
        );
        await _pumpPlayer(tester, size: size, box: box, demo: reason == 'demo');
        await _openMenu(tester);
        expect(find.text('Power off'), findsNothing);
        expect(box.runs, isEmpty);
      });
    }
  }
}
