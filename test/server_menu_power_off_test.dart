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
  _Box({
    this.actions = const {'poweroff'},
    this.available = true,
    this.scheduling = false,
  });

  final Set<String> actions;
  final bool available;
  final bool scheduling;
  final runs = <(BoxAction, String)>[];
  final scheduled = <(int, String)>[];
  final cancellations = <String>[];
  BoxPowerStatus? power = const BoxPowerStatus(
    serverId: 'server-1',
    state: 'on',
  );
  BoxActionException? refusal;

  @override
  Future<SupervisorInfo?> info() async => available
      ? SupervisorInfo(
          version: '0.2.0',
          protocol: 1,
          minProtocol: 1,
          serverId: 'server-1',
          actions: actions,
          supportsPowerOffSchedule: scheduling,
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
  Future<BoxPowerStatus?> powerStatus() async => power;

  @override
  Future<void> schedulePowerOff(int minutes, {required String serverId}) async {
    scheduled.add((minutes, serverId));
    if (refusal != null) throw refusal!;
    power = BoxPowerStatus(
      serverId: serverId,
      state: 'scheduled',
      remainingSeconds: minutes * 60,
    );
  }

  @override
  Future<void> cancelPowerOff({required String serverId}) async {
    cancellations.add(serverId);
    if (refusal != null) throw refusal!;
    power = BoxPowerStatus(serverId: serverId, state: 'on');
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
    const Size(1024, 800),
    const Size(1280, 800),
  ]) {
    testWidgets('schedules, counts down and cancels at $size', (tester) async {
      final box = _Box(scheduling: true);
      await _pumpPlayer(tester, size: size, box: box);
      await _askToPowerOff(tester);
      await tester.tap(find.byKey(const ValueKey('power-off-delay')));
      await tester.pumpAndSettle();
      for (final label in ['Now', '30 mins', '60 mins', '90 mins']) {
        expect(find.text(label), findsWidgets);
      }
      await tester.tap(find.text('30 mins').last);
      await tester.pumpAndSettle();
      expect(box.scheduled, isEmpty);
      await tester.tap(find.text('Set timer'));
      await tester.pumpAndSettle();
      expect(box.runs, isEmpty);
      expect(box.scheduled, [(30, 'server-1')]);
      if (size.width >= 720) {
        final rail = find.byKey(const ValueKey('navigation-powerOff'));
        final icon = find.descendant(
          of: rail,
          matching: find.byIcon(Icons.power_settings_new),
        );
        if (size.width >= 1280) {
          final label = find.descendant(
            of: rail,
            matching: find.text('Power off in 30m'),
          );
          expect(label, findsOneWidget);
          expect(icon, findsOneWidget);
          expect(tester.widget<Icon>(icon).color, KalinkaColors.accent);
          final text = tester.widget<Text>(label);
          final time = (text.textSpan! as TextSpan).children!.last as TextSpan;
          expect(time.text, '30m');
          expect(time.style?.color, KalinkaColors.accentTint);
          expect(text.style?.color, KalinkaColors.textSecondary);
        } else {
          expect(
            find.descendant(of: rail, matching: find.text('Off in')),
            findsOneWidget,
          );
          final number = find.descendant(of: rail, matching: find.text('30'));
          expect(number, findsOneWidget);
          expect(
            tester.widget<Text>(number).style?.color,
            KalinkaColors.accent,
          );
          expect(icon, findsNothing);
        }
      }
      await _openMenu(tester);
      final row = find.descendant(
        of: find.byType(SheetRow),
        matching: find.text('Power off in 30 minutes'),
      );
      await tester.ensureVisible(row);
      expect(row, findsOneWidget);
      // Another client changes the timer; the open menu and rail follow it.
      box.power = const BoxPowerStatus(
        serverId: 'server-1',
        state: 'scheduled',
        remainingSeconds: 61,
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      final updatedRow = find.descendant(
        of: find.byType(SheetRow),
        matching: find.text('Power off in 2 minutes'),
      );
      expect(updatedRow, findsOneWidget);
      await tester.tap(updatedRow);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel power-off'));
      await tester.pumpAndSettle();
      expect(box.cancellations, ['server-1']);
      expect(box.runs, isEmpty);
      expect(find.text('Off in'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }

  for (final minutes in [60, 90]) {
    testWidgets('schedules $minutes minutes and reports a refusal', (
      tester,
    ) async {
      final box = _Box(scheduling: true)
        ..refusal = const BoxActionException('busy', 'The streamer is busy.');
      await _pumpPlayer(tester, size: const Size(375, 812), box: box);
      await _askToPowerOff(tester);
      await tester.tap(find.byKey(const ValueKey('power-off-delay')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('$minutes mins').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set timer'));
      await tester.pumpAndSettle();
      expect(box.scheduled, [(minutes, 'server-1')]);
      expect(box.runs, isEmpty);
      expect(find.text('The streamer is busy.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('Now uses immediate shutdown and stale status is discarded', (
    tester,
  ) async {
    final box = _Box(scheduling: true)
      ..power = const BoxPowerStatus(
        serverId: 'another-server',
        state: 'scheduled',
        remainingSeconds: 600,
      );
    await _pumpPlayer(tester, size: const Size(375, 812), box: box);
    await _askToPowerOff(tester);
    expect(find.text('Now'), findsOneWidget);
    expect(find.text('Cancel power-off'), findsNothing);
    await tester.tap(_confirm);
    await tester.pumpAndSettle();
    expect(box.runs, [(BoxAction.powerOff, 'server-1')]);
    expect(box.scheduled, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('failed cancellation keeps countdown', (tester) async {
    final box = _Box(scheduling: true)
      ..power = const BoxPowerStatus(
        serverId: 'server-1',
        state: 'scheduled',
        remainingSeconds: 1800,
      )
      ..refusal = const BoxActionException(
        'unreachable',
        'The streamer did not answer.',
      );
    await _pumpPlayer(tester, size: const Size(1280, 800), box: box);
    await tester.tap(find.byKey(const ValueKey('navigation-powerOff')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel power-off'));
    await tester.pumpAndSettle();
    expect(find.text('The streamer did not answer.'), findsOneWidget);
    expect(find.text('Power off in 30m'), findsOneWidget);
    // Failed status reads must not leave an apparently live countdown behind.
    box.power = null;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Power off in 30m'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  for (final size in [
    const Size(375, 812),
    const Size(667, 375),
    const Size(900, 1280),
    const Size(1280, 800),
  ]) {
    testWidgets('power off remains reachable with large text at $size', (
      tester,
    ) async {
      final box = _Box(scheduling: true);
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
