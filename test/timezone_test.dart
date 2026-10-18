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

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeBox box, {
  String? local = 'Europe/London',
}) async {
  final container = ProviderContainer(
    overrides: [
      ...soundcardOverrides(await boxPrefs(), box: box),
      localTimezoneProvider.overrideWith((ref) async => local),
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
      'The box shows the time in Asia/Kolkata.',
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
      'atlantis',
    );
    await tester.pumpAndSettle();
    expect(find.text('No time zone matches “atlantis”.'), findsOne);
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
      find.text('Updating Kalinka on this box lets the app set its time zone.'),
      findsOne,
    );
    await tester.tap(find.text('Time zone'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('timezone-search')), findsNothing);
  });

  test('an old name counts as the zone the box set for it', () async {
    final box = FakeBox(answers: [_setsTimezone]);
    final container = ProviderContainer(
      overrides: soundcardOverrides(await boxPrefs(), box: box),
    );
    addTearDown(container.dispose);
    await container.read(boxControlProvider.future);
    final change = container.read(timezoneChangeProvider.notifier);

    expect(change.isOn('Asia/Calcutta', 'Asia/Kolkata'), isFalse);
    expect(await change.apply('Asia/Calcutta'), isTrue);

    expect(box.zone, 'Asia/Kolkata');
    expect(change.isOn('Asia/Calcutta', 'Asia/Kolkata'), isTrue);
    expect(change.isOn('Europe/London', 'Asia/Kolkata'), isFalse);
  });
}
