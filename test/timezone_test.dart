import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/providers/box_control_provider.dart';
import 'package:kalinka/providers/supervisor_api.dart';
import 'package:kalinka/providers/timezone_provider.dart';
import 'package:kalinka/providers/toast_provider.dart';
import 'package:kalinka/widgets/box_section.dart';

import 'support/soundcard_fakes.dart';

final _setsTimezone = supervisorInfo(
  actions: const {'reboot', 'poweroff', setTimezoneAction},
);

String? _london() => 'Europe/London';

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeBox box, {
  String? Function() local = _london,
}) async {
  final container = ProviderContainer(
    overrides: [
      ...soundcardOverrides(await boxPrefs(), box: box),
      localTimezoneProvider.overrideWith((ref) async => local()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: BoxSection())),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _pick(WidgetTester tester, String query, String zone) async {
  await tester.tap(find.text('Time zone'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('timezone-search')), query);
  await tester.pumpAndSettle();
  await tester.tap(find.text(zone).first);
  await tester.pumpAndSettle();
}

/// Lets the toasts run out.
Future<void> _drain(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 6));

void main() {
  testWidgets('shows the box’s zone and sets the one picked once confirmed', (
    tester,
  ) async {
    final box = FakeBox(answers: [_setsTimezone]);
    final container = await _pump(tester, box);

    expect(find.text('Time zone'), findsOne);
    expect(find.text('UTC'), findsOne);
    await _pick(tester, 'kolk', 'Asia/Kolkata');
    expect(find.text('Change the time zone?'), findsOne);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(box.zonesSet, [
      ('Asia/Kolkata', const BoxIdentity(serverId: 'box-1')),
    ]);
    expect(find.text('Asia/Kolkata'), findsOne);
    expect(
      container.read(toastProvider).single.message,
      'The streamer shows the time in Asia/Kolkata.',
    );
    await _drain(tester);
  });

  testWidgets('lists this device’s zone first and finds a city by name', (
    tester,
  ) async {
    final box = FakeBox(answers: [_setsTimezone])
      ..zones = const ['America/New_York', 'Europe/London', 'UTC'];
    await _pump(tester, box);

    await tester.tap(find.text('Time zone'));
    await tester.pumpAndSettle();
    expect(find.text('THIS DEVICE'), findsOne);
    expect(
      tester.getTopLeft(find.text('Europe/London').first).dy,
      lessThan(tester.getTopLeft(find.text('ALL TIME ZONES')).dy),
    );
    await tester.enterText(
      find.byKey(const ValueKey('timezone-search')),
      'new york',
    );
    await tester.pumpAndSettle();
    expect(find.text('America/New York'), findsOne);
    expect(find.text('THIS DEVICE'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('timezone-search')),
      'new_york',
    );
    await tester.pumpAndSettle();
    expect(find.text('America/New York'), findsOne);
    await tester.enterText(
      find.byKey(const ValueKey('timezone-search')),
      'atlantis',
    );
    await tester.pumpAndSettle();
    expect(find.text('No time zone matches “atlantis”.'), findsOne);
  });

  testWidgets('reads this device’s zone again each time the picker opens', (
    tester,
  ) async {
    var here = 'Europe/London';
    await _pump(tester, FakeBox(answers: [_setsTimezone]), local: () => here);

    await tester.tap(find.text('Time zone'));
    await tester.pumpAndSettle();
    expect(find.text('Europe/London'), findsNWidgets(2));
    Navigator.of(tester.element(find.byKey(const ValueKey('timezone-search'))))
        .pop();
    await tester.pumpAndSettle();

    here = 'Asia/Kolkata';
    await tester.tap(find.text('Time zone'));
    await tester.pumpAndSettle();
    expect(find.text('Asia/Kolkata'), findsNWidgets(2));
    expect(find.text('Europe/London'), findsOne);
  });

  testWidgets('a second tap while the zones load opens one picker', (
    tester,
  ) async {
    final box = FakeBox(answers: [_setsTimezone])..holdZones = Completer();
    await _pump(tester, box);

    await tester.tap(find.text('Time zone'));
    await tester.pump();
    await tester.tap(find.text('Time zone'));
    await tester.pump();
    box.holdZones!.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('timezone-search')), findsOne);
  });

  testWidgets('a cancelled confirmation leaves the box alone', (tester) async {
    final box = FakeBox(answers: [_setsTimezone]);
    await _pump(tester, box);

    await _pick(tester, 'lond', 'Europe/London');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(box.zonesSet, isEmpty);
    expect(find.text('UTC'), findsOne);
  });

  testWidgets('reports a refusal and keeps the zone it had', (tester) async {
    final box = FakeBox(answers: [_setsTimezone])
      ..refusal = const BoxActionException('busy', 'The box is busy.');
    final container = await _pump(tester, box);

    await _pick(tester, 'lond', 'Europe/London');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    final toast = container.read(toastProvider).single;
    expect(toast.message, 'The box is busy.');
    expect(toast.isError, isTrue);
    expect(find.text('UTC'), findsOne);
    await _drain(tester);
  });

  testWidgets('reads the zone again after a change that timed out', (
    tester,
  ) async {
    final box = FakeBox(answers: [_setsTimezone])
      ..holdTimezone = Completer()
      ..refusal = const BoxActionException('unreachable', 'No answer.');
    await _pump(tester, box);

    await _pick(tester, 'lond', 'Europe/London');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    box.zone = 'Europe/London';
    box.holdTimezone!.complete();
    await tester.pumpAndSettle();

    expect(find.text('Europe/London'), findsOne);
    await _drain(tester);
  });

  testWidgets('reads the zone again, so one set on the box itself shows', (
    tester,
  ) async {
    final box = FakeBox(answers: [_setsTimezone]);
    final container = await _pump(tester, box);
    expect(find.text('UTC'), findsOne);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SizedBox()),
    );
    await tester.pumpAndSettle();
    box.zone = 'Europe/Paris';
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: BoxSection())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Europe/Paris'), findsOne);
  });

  testWidgets('an older supervisor shows the row disabled, saying why', (
    tester,
  ) async {
    final box = FakeBox(answers: [supervisorInfo()]);
    await _pump(tester, box);

    expect(find.text('Time zone'), findsOne);
    expect(
      find.text(
        'Updating Kalinka on this streamer lets the app set its time zone.',
      ),
      findsOne,
    );
    await tester.tap(find.text('Time zone'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('timezone-search')), findsNothing);
  });

  test('an old name counts as the zone the box set for it, after a new '
      'launch too', () async {
    final box = FakeBox(answers: [_setsTimezone]);
    final prefs = await boxPrefs();
    final container = ProviderContainer(
      overrides: soundcardOverrides(prefs, box: box),
    );
    await container.read(boxControlProvider.future);
    final change = container.read(timezoneChangeProvider.notifier);

    expect(change.isOn('Asia/Calcutta', 'Asia/Kolkata'), isFalse);
    expect(await change.apply('Asia/Calcutta'), isTrue);

    expect(box.zone, 'Asia/Kolkata');
    expect(change.isOn('Asia/Calcutta', 'Asia/Kolkata'), isTrue);
    expect(change.isOn('Europe/London', 'Asia/Kolkata'), isFalse);
    container.dispose();

    final relaunched = ProviderContainer(
      overrides: soundcardOverrides(prefs, box: box),
    );
    addTearDown(relaunched.dispose);
    expect(
      relaunched
          .read(timezoneChangeProvider.notifier)
          .isOn('Asia/Calcutta', 'Asia/Kolkata'),
      isTrue,
    );
  });

  test('drops the link once the box sets the old name as asked', () async {
    final box = FakeBox(answers: [_setsTimezone]);
    final container = ProviderContainer(
      overrides: soundcardOverrides(await boxPrefs(), box: box),
    );
    addTearDown(container.dispose);
    await container.read(boxControlProvider.future);
    final change = container.read(timezoneChangeProvider.notifier);

    await change.apply('Asia/Calcutta');
    box.zoneLinks = const {};
    await change.apply('Asia/Calcutta');

    expect(box.zone, 'Asia/Calcutta');
    expect(change.isOn('Asia/Calcutta', 'Asia/Calcutta'), isTrue);
  });

  test('a change answered after the app has gone touches nothing', () async {
    final box = FakeBox(answers: [_setsTimezone])..holdTimezone = Completer();
    final container = ProviderContainer(
      overrides: soundcardOverrides(await boxPrefs(), box: box),
    );
    await container.read(boxControlProvider.future);
    final applying = container
        .read(timezoneChangeProvider.notifier)
        .apply('Europe/London');
    container.dispose();
    box.holdTimezone!.complete();

    expect(await applying, isTrue);
    expect(box.zone, 'Europe/London');
  });
}
