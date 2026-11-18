import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/widgets/keyboard/app_keyboard_navigation.dart';
import 'package:kalinka/widgets/settings_controls/settings_numeric_input.dart';
import 'package:kalinka/widgets/settings_controls/settings_password_input.dart';
import 'package:kalinka/widgets/settings_controls/settings_slider.dart';
import 'package:kalinka/widgets/settings_controls/settings_text_input.dart';

import 'support/focus.dart';

Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

Future<void> pump(
  WidgetTester tester,
  Widget editor, {
  bool shell = false,
}) async {
  Widget body = Center(
    child: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(onPressed: () {}, child: const Text('Before')),
          editor,
          TextButton(onPressed: () {}, child: const Text('After')),
        ],
      ),
    ),
  );
  if (shell) {
    body = AppKeyboardNavigation(
      child: AppKeyboardRegion(area: AppKeyboardArea.content, child: body),
    );
  }
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
  await tester.pumpAndSettle();
}

bool get typing =>
    FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<EditableText>() !=
    null;

void main() {
  for (final shell in [false, true]) {
    for (final kind in ['text', 'number', 'password']) {
      testWidgets(
        '$kind is navigable and editable ${shell ? 'in shell' : 'standalone'}',
        (tester) async {
          final staged = <Object>[];
          final field = switch (kind) {
            'number' => SettingsNumericInput(
              value: 10,
              min: 0,
              max: 100,
              onChanged: staged.add,
            ),
            'password' => SettingsPasswordInput(
              value: '',
              onChanged: staged.add,
            ),
            _ => SettingsTextInput(value: 'Original', onChanged: staged.add),
          };
          await pump(tester, field, shell: shell);
          await key(tester, LogicalKeyboardKey.tab);
          await key(tester, LogicalKeyboardKey.arrowDown);
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'Text entry navigation',
          );
          expect(typing, isFalse);
          expect(tester.testTextInput.isVisible, isFalse);
          expect(find.text('Enter to edit'), findsOneWidget);
          await key(tester, LogicalKeyboardKey.arrowDown);
          expect(focusIsOn(find.widgetWithText(TextButton, 'After')), isTrue);
          expect(staged, isEmpty);
          await key(tester, LogicalKeyboardKey.arrowUp);
          await key(tester, LogicalKeyboardKey.enter);
          expect(typing, isTrue);
          await tester.enterText(
            find.byType(TextField),
            kind == 'number' ? '42' : 'New value',
          );
          await key(tester, LogicalKeyboardKey.arrowLeft);
          expect(typing, isTrue, reason: 'arrows edit text after activation');
          await key(tester, LogicalKeyboardKey.escape);
          expect(typing, isFalse);
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'Text entry navigation',
          );
          expect(tester.testTextInput.isVisible, isFalse);
          expect(staged.last, kind == 'number' ? 42 : 'New value');
          await key(tester, LogicalKeyboardKey.arrowDown);
          expect(focusIsOn(find.widgetWithText(TextButton, 'After')), isTrue);
        },
      );
    }
  }

  testWidgets('Tab leaves an editing field without an extra wrapper stop', (
    tester,
  ) async {
    await pump(tester, SettingsTextInput(value: '', onChanged: (_) {}));
    await key(tester, LogicalKeyboardKey.tab);
    await key(tester, LogicalKeyboardKey.tab);
    expect(typing, isFalse);
    await key(tester, LogicalKeyboardKey.enter);
    expect(typing, isTrue);
    await key(tester, LogicalKeyboardKey.tab);
    expect(focusIsOn(find.widgetWithText(TextButton, 'After')), isTrue);
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Text entry navigation',
    );
  });

  testWidgets(
    'TextFormField enters its text before its suffix and preserves submit',
    (tester) async {
      var submitted = 0;
      await pump(
        tester,
        AppKeyboardTextEntry(
          child: TextFormField(
            onFieldSubmitted: (_) => submitted++,
            decoration: InputDecoration(
              suffixIcon: IconButton(
                onPressed: () {},
                icon: const Icon(Icons.visibility),
              ),
            ),
          ),
        ),
      );
      await key(tester, LogicalKeyboardKey.tab);
      await key(tester, LogicalKeyboardKey.arrowDown);
      await key(tester, LogicalKeyboardKey.enter);
      expect(typing, isTrue);
      expect(submitted, 0);
      await key(tester, LogicalKeyboardKey.tab);
      expect(focusIsOn(find.byType(IconButton)), isTrue);
      await key(tester, LogicalKeyboardKey.escape);
      await key(tester, LogicalKeyboardKey.enter);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(submitted, 1);
    },
  );

  testWidgets('disabled fields are skipped', (tester) async {
    await pump(
      tester,
      const AppKeyboardTextEntry(child: TextField(enabled: false)),
    );
    await key(tester, LogicalKeyboardKey.tab);
    await key(tester, LogicalKeyboardKey.tab);
    expect(focusIsOn(find.widgetWithText(TextButton, 'After')), isTrue);
  });

  testWidgets('autofocus and pointer still edit directly', (tester) async {
    await pump(
      tester,
      SettingsTextInput(value: 'Hello', autofocus: true, onChanged: (_) {}),
    );
    expect(typing, isTrue);
    await key(tester, LogicalKeyboardKey.escape);
    expect(typing, isFalse);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(typing, isTrue);
  });

  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets(
      '$kind text editing hides keyboard cues until navigation resumes',
      (tester) async {
        await pump(
          tester,
          SettingsTextInput(value: 'Hello', onChanged: (_) {}),
        );
        final field = find.byType(TextField);
        final frame = find.descendant(
          of: find.byType(AppKeyboardTextEntry),
          matching: find.byWidgetPredicate(
            (w) =>
                w is DecoratedBox &&
                w.position == DecorationPosition.foreground &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).border is Border,
          ),
        );
        Color frameColor() =>
            ((tester.widget<DecoratedBox>(frame.first).decoration
                            as BoxDecoration)
                        .border!
                    as Border)
                .top
                .color;
        Future<void> click() async {
          final gesture = await tester.startGesture(
            tester.getCenter(field),
            kind: kind,
          );
          await gesture.up();
          await tester.pumpAndSettle();
        }

        await click();
        expect(typing, isTrue);
        await tester.enterText(field, 'Edited');
        await key(tester, LogicalKeyboardKey.arrowLeft);
        expect(find.text('Esc to finish editing'), findsNothing);
        expect(frameColor(), Colors.transparent);
        await key(tester, LogicalKeyboardKey.escape);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Text entry navigation',
        );
        expect(frameColor(), isNot(Colors.transparent));
        expect(find.text('Enter to edit'), findsOneWidget);
        await key(tester, LogicalKeyboardKey.enter);
        expect(find.text('Esc to finish editing'), findsOneWidget);
        expect(frameColor(), isNot(Colors.transparent));
        await click();
        expect(typing, isTrue);
        expect(find.text('Esc to finish editing'), findsNothing);
        expect(frameColor(), Colors.transparent);
      },
    );
  }

  testWidgets(
    'settings slider is navigable and adjustable without a shell host',
    (tester) async {
      final staged = <double>[];
      await pump(
        tester,
        SettingsSlider(
          label: 'Latency',
          value: 50,
          min: 0,
          max: 100,
          step: 5,
          onChanged: staged.add,
        ),
      );
      await key(tester, LogicalKeyboardKey.tab);
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Slider navigation',
      );
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(focusIsOn(find.widgetWithText(TextButton, 'After')), isTrue);
      expect(staged, isEmpty);
      await key(tester, LogicalKeyboardKey.arrowUp);
      await key(tester, LogicalKeyboardKey.enter);
      await key(tester, LogicalKeyboardKey.arrowRight);
      expect(staged, [55]);
      await key(tester, LogicalKeyboardKey.escape);
      await key(tester, LogicalKeyboardKey.arrowUp);
      expect(focusIsOn(find.widgetWithText(TextButton, 'Before')), isTrue);
    },
  );
}
