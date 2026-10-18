import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/providers/settings_provider.dart';
import 'package:kalinka/providers/supervisor_api.dart';
import 'package:kalinka/providers/timezone_provider.dart';
import 'package:kalinka/screens/onboarding_screen.dart';

import 'support/soundcard_fakes.dart';

final _setsTimezone = supervisorInfo(
  actions: const {'reboot', 'poweroff', setTimezoneAction},
);

Future<void> _atNetworkStep(
  WidgetTester tester,
  FakeBox box, {
  String? local = 'Europe/London',
  double textScale = 1,
}) async {
  final container = ProviderContainer(
    overrides: [
      ...soundcardOverrides(await boxPrefs(), box: box),
      localTimezoneProvider.overrideWith((ref) async => local),
    ],
  );
  addTearDown(container.dispose);
  await container.read(settingsProvider.notifier).loadConfig();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: const OnboardingScreen(startAtSetup: true),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('Network'), findsOne);
  await tester.ensureVisible(find.text('TIME ZONE'));
  await tester.pumpAndSettle();
}

Future<void> _accept(WidgetTester tester, String zone) async {
  await tester.ensureVisible(find.text('Use $zone'));
  await tester.tap(find.text('Use $zone'));
  await tester.pumpAndSettle();
  expect(find.text('Change the time zone?'), findsOne);
  await tester.tap(find.text('Apply'));
  await tester.pumpAndSettle();
}

/// Lets the toasts and the network panel's polling run out.
Future<void> _drain(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 6));

void main() {
  testWidgets('proposes this device’s zone and sets it once confirmed', (
    tester,
  ) async {
    final box = FakeBox(answers: [_setsTimezone]);
    await _atNetworkStep(tester, box);

    expect(find.textContaining('This device is on Europe/London.'), findsOne);
    await _accept(tester, 'Europe/London');

    expect(box.zonesSet, [
      ('Europe/London', const BoxIdentity(serverId: 'box-1')),
    ]);
    expect(find.text('Use Europe/London'), findsNothing);
    expect(find.text('Europe/London'), findsOne);
    await _drain(tester);
  });

  testWidgets('the proposal stays away while the zone set is read back', (
    tester,
  ) async {
    final box = FakeBox(answers: [_setsTimezone]);
    await _atNetworkStep(tester, box);

    box.holdZone = Completer();
    await _accept(tester, 'Europe/London');
    expect(find.text('Use Europe/London'), findsNothing);
    box.holdZone!.complete();
    await tester.pumpAndSettle();

    expect(find.text('Use Europe/London'), findsNothing);
    expect(find.text('Europe/London'), findsOne);
    await _drain(tester);
  });

  testWidgets('a cancelled proposal leaves the box on its zone', (
    tester,
  ) async {
    final box = FakeBox(answers: [_setsTimezone]);
    await _atNetworkStep(tester, box);

    await tester.tap(find.text('Use Europe/London'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(box.zonesSet, isEmpty);
    expect(find.text('UTC'), findsOne);
    expect(find.text('Use Europe/London'), findsOne);
    await _drain(tester);
  });

  testWidgets('proposes nothing for a box already on this device’s zone', (
    tester,
  ) async {
    final box = FakeBox(answers: [_setsTimezone])..zone = 'Europe/London';
    await _atNetworkStep(tester, box);

    expect(find.text('Europe/London'), findsOne);
    expect(find.text('Use Europe/London'), findsNothing);
    await _drain(tester);
  });

  testWidgets('a device on an old zone name is not asked again once set', (
    tester,
  ) async {
    final box = FakeBox(answers: [_setsTimezone]);
    await _atNetworkStep(tester, box, local: 'Asia/Calcutta');

    await _accept(tester, 'Asia/Calcutta');

    expect(box.zone, 'Asia/Kolkata');
    expect(find.text('Asia/Kolkata'), findsOne);
    expect(find.text('Use Asia/Calcutta'), findsNothing);
    await _drain(tester);
  });

  testWidgets('a device that names no zone leaves the choice to the row', (
    tester,
  ) async {
    final box = FakeBox(answers: [_setsTimezone]);
    await _atNetworkStep(tester, box, local: null);

    expect(find.textContaining('This device is on'), findsNothing);
    await tester.tap(find.text('Time zone'));
    await tester.pumpAndSettle();
    expect(find.text('THIS DEVICE'), findsNothing);
    expect(find.text('Europe/London'), findsOne);
    await _drain(tester);
  });

  for (final (name, answer, reason) in [
    (
      'without a supervisor',
      null,
      'No box supervisor answers on this server, so it keeps the time zone '
          'of the computer it runs on. Set it there.',
    ),
    (
      'whose supervisor cannot set it',
      supervisorInfo(),
      'Updating Kalinka on this box lets the app set its time zone.',
    ),
    (
      'whose supervisor speaks another protocol',
      const SupervisorInfo(
        version: '9.0.0',
        protocol: 3,
        minProtocol: 2,
        serverId: 'box-1',
        actions: {setTimezoneAction},
      ),
      'The box’s supervisor and this app do not speak the same version. '
          'Update both to set the time zone here.',
    ),
  ]) {
    testWidgets('a box $name shows the row disabled, saying why', (
      tester,
    ) async {
      final box = FakeBox(answers: [answer]);
      await _atNetworkStep(tester, box);

      expect(find.text('Time zone'), findsOne);
      expect(find.text(reason), findsOne);
      expect(find.textContaining('This device is on'), findsNothing);
      await tester.tap(find.text('Time zone'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('timezone-search')), findsNothing);
      await _drain(tester);
    });
  }

  for (final (name, box, reason) in [
    (
      'did not answer',
      FakeBox(answers: [null])..noAnswer = SupervisorReach.silent,
      'The box did not answer. Tap to try again.',
    ),
    (
      'answers for another server',
      FakeBox(
        answers: [
          supervisorInfo(serverId: 'box-2', actions: const {setTimezoneAction}),
        ],
      ),
      'A different Kalinka box answers at this address. Tap to try again.',
    ),
  ]) {
    testWidgets('a box that $name is looked for again on a tap', (
      tester,
    ) async {
      await _atNetworkStep(tester, box);
      expect(find.text(reason), findsOne);

      box.answers
        ..clear()
        ..add(_setsTimezone);
      await tester.tap(find.text('Time zone'));
      await tester.pumpAndSettle();

      expect(find.text(reason), findsNothing);
      expect(find.text('UTC'), findsOne);
      expect(find.text('Use Europe/London'), findsOne);
      await _drain(tester);
    });
  }

  testWidgets('setup moves on without a zone confirmed', (tester) async {
    final box = FakeBox(answers: [_setsTimezone]);
    await _atNetworkStep(tester, box);

    await tester.tap(find.text('Keep this connection'));
    await tester.pumpAndSettle();

    expect(find.text('Music sources'), findsOne);
    expect(box.zonesSet, isEmpty);
    await _drain(tester);
  });

  testWidgets('the proposal fits a small phone with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _atNetworkStep(
      tester,
      FakeBox(answers: [_setsTimezone]),
      local: 'America/Argentina/Buenos_Aires',
      textScale: 2,
    );

    await tester.ensureVisible(find.text('Use America/Argentina/Buenos Aires'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });
}
