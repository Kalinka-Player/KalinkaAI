import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/widgets/pending_changes_banner.dart';
import 'package:kalinka/widgets/settings_controls/settings_numeric_input.dart';
import 'package:kalinka/widgets/settings_controls/settings_password_input.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(body: Column(children: [child])),
  ),
);

void main() {
  testWidgets('a number is staged as typed, and Done closes the keyboard', (
    tester,
  ) async {
    final staged = <num>[];
    await _pump(
      tester,
      SettingsNumericInput(value: 10, min: 5, max: 100, onChanged: staged.add),
    );
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '42');
    // Recorded with the keyboard still up.
    expect(staged, [42]);
    expect(tester.testTextInput.isVisible, isTrue);

    // Out of bounds waits for the field to be left, then is pulled inside.
    await tester.enterText(find.byType(TextField), '200');
    expect(staged, [42]);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(staged, [42, 100]);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('Done on a password commits it and closes the keyboard', (
    tester,
  ) async {
    final staged = <String>[];
    await _pump(
      tester,
      SettingsPasswordInput(value: '', onChanged: staged.add),
    );
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'secret');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(staged.last, 'secret');
    expect(tester.testTextInput.isVisible, isFalse);
  });

  for (final action in ['discard', 'apply']) {
    testWidgets('$action leaves the field first, staging what it holds', (
      tester,
    ) async {
      final events = <String>[];
      await _pump(
        tester,
        Column(
          children: [
            SettingsPasswordInput(
              value: '',
              onChanged: (v) => events.add('staged $v'),
            ),
            PendingChangesBanner(
              pendingCount: 1,
              onDiscard: () => events.add('discard'),
              onApply: () => events.add('apply'),
            ),
          ],
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'typed');
      await tester.tap(find.byKey(ValueKey('pending-changes-$action')));
      await tester.pump();
      expect(events, ['staged typed', action]);
      expect(tester.testTextInput.isVisible, isFalse);
    });
  }
}
