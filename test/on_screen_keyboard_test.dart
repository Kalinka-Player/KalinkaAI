import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virtual_keypad/virtual_keypad.dart';

import 'package:kalinka/providers/connection_settings_provider.dart';
import 'package:kalinka/providers/kiosk_provider.dart';
import 'package:kalinka/providers/on_screen_keyboard_provider.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/client_settings_section.dart';
import 'package:kalinka/widgets/kalinka_bottom_sheet.dart';
import 'package:kalinka/widgets/keyboard/on_screen_keyboard_host.dart';
import 'package:kalinka/widgets/settings_controls/settings_numeric_input.dart';
import 'package:kalinka/widgets/settings_controls/settings_password_input.dart';

const keyboardKey = ValueKey('on-screen-keyboard');
const submitKey = ValueKey('keyboard-submit');
const captureKey = ValueKey('keyboard-capture');

Future<ProviderContainer> pumpKeyboard(
  WidgetTester tester,
  Widget child, {
  bool enabled = true,
  Size size = const Size(800, 480),
  double textScale = 1,
  bool reducedMotion = true,
  Widget? home,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({
    OnScreenKeyboardNotifier.preferenceKey: enabled,
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reducedMotion,
          ),
          child: RepaintBoundary(
            key: captureKey,
            child: OnScreenKeyboardHost(child: child!),
          ),
        ),
        home: home ?? Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Finder keyNamed(String name) => find.descendant(
  of: find.byType(VirtualKeypad),
  matching: find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == name,
  ),
);

Future<void> press(WidgetTester tester, String name) async {
  await tester.tap(keyNamed(name));
  await tester.pumpAndSettle();
}

void main() {
  for (final (size, scale, columns) in [
    (const Size(1024, 600), 1.0, 5),
    (const Size(800, 480), 1.0, 4),
    (const Size(667, 375), 1.0, 4),
    (const Size(375, 667), 1.0, 4),
    (const Size(320, 600), 2.0, 3),
  ]) {
    testWidgets(
      'globe opens every layout without scrolling at $size / $scale',
      (tester) async {
        final controller = TextEditingController(text: 'word');
        final focus = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focus.dispose);
        addTearDown(() => KeyboardLayoutProvider.instance.setLanguage('en'));
        await pumpKeyboard(
          tester,
          TextField(controller: controller, focusNode: focus),
          size: size,
          textScale: scale,
        );
        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();
        controller.selection = const TextSelection(
          baseOffset: 1,
          extentOffset: 3,
        );
        final panel = tester.getRect(find.byKey(keyboardKey));
        final globe = keyNamed('Switch language');
        final space = keyNamed('Space');
        expect(
          find.descendant(
            of: globe,
            matching: find.byIcon(Icons.language_outlined),
          ),
          findsOneWidget,
        );
        expect(
          tester.getRect(globe).right,
          closeTo(tester.getRect(space).left, 0.1),
        );
        expect(
          tester.getRect(globe).center.dy,
          tester.getRect(space).center.dy,
        );
        await tester.tap(globe);
        await tester.pumpAndSettle();
        final picker = find.byKey(const ValueKey('keyboard-language-picker'));
        expect(
          find.byKey(ValueKey('keyboard-language-grid-$columns')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: picker, matching: find.byType(Scrollable)),
          findsNothing,
        );
        expect(tester.getRect(find.byKey(keyboardKey)), panel);
        final choices = KeyboardLayoutProvider.instance.languageCodes;
        expect(choices.length, 16);
        for (final code in choices) {
          final button = find.byKey(ValueKey('keyboard-language-$code'));
          expect(button.hitTestable(), findsOneWidget);
          final rect = tester.getRect(button);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width));
          expect(rect.bottom, lessThanOrEqualTo(size.height));
          expect(rect.width, greaterThanOrEqualTo(48));
          expect(rect.height, greaterThanOrEqualTo(48));
        }
        expect(focus.hasFocus, isTrue);
        expect(controller.text, 'word');
        expect(
          controller.selection,
          const TextSelection(baseOffset: 1, extentOffset: 3),
        );
        await tester.tap(find.byKey(const ValueKey('keyboard-language-de')));
        await tester.pumpAndSettle();
        expect(picker, findsNothing);
        expect(KeyboardLayoutProvider.instance.currentLanguageCode, 'de');
        expect(focus.hasFocus, isTrue);
        await press(tester, 'ü');
        expect(controller.text, 'wüd');
        await press(tester, 'Switch language');
        expect(find.byIcon(Icons.check_rounded), findsWidgets);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(picker, findsNothing);
        expect(find.byKey(keyboardKey), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'layout grid resizes, cancels outside and closes when keyboard is disabled',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final container = await pumpKeyboard(
        tester,
        TextField(focusNode: focus),
        size: const Size(1024, 600),
      );
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await press(tester, 'Switch language');
      tester.view.physicalSize = const Size(375, 667);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('keyboard-language-grid-4')),
        findsOneWidget,
      );
      for (final code in KeyboardLayoutProvider.instance.languageCodes) {
        expect(
          find.byKey(ValueKey('keyboard-language-$code')).hitTestable(),
          findsOneWidget,
        );
      }
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('keyboard-language-picker')),
        findsNothing,
      );
      expect(focus.hasFocus, isTrue);
      await press(tester, 'Switch language');
      await tester.tap(find.byTooltip('Close keyboard layouts'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('keyboard-language-picker')),
        findsNothing,
      );
      expect(focus.hasFocus, isTrue);
      await press(tester, 'Switch language');
      await container.read(onScreenKeyboardProvider.notifier).setEnabled(false);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('keyboard-language-picker')),
        findsNothing,
      );
      expect(find.byKey(keyboardKey), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('1024x600 panel has 48dp-tall letter keys and visible row gaps', (
    tester,
  ) async {
    var sideTaps = 0;
    final background = GlobalKey();
    await pumpKeyboard(
      tester,
      const SizedBox.shrink(),
      size: const Size(1024, 600),
      home: Scaffold(
        resizeToAvoidBottomInset: false,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => sideTaps++,
          child: SizedBox.expand(
            key: background,
            child: const Align(
              alignment: Alignment.topCenter,
              child: TextField(),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    final panel = tester.getRect(find.byKey(keyboardKey));
    expect(panel, const Rect.fromLTWH(62, 378, 900, 222));
    expect(
      tester.getRect(find.byKey(background)),
      const Rect.fromLTWH(0, 0, 1024, 600),
    );
    // Measure the key faces, not their surrounding margins: the material
    // panel must shrink along with the keys rather than adding side bands.
    final keyFace = find.descendant(
      of: keyNamed('q'),
      matching: find.byType(InkWell),
    );
    final keySize = tester.getSize(keyFace);
    expect(keySize.height, greaterThanOrEqualTo(48));
    expect(keySize.width, greaterThan(keySize.height));
    expect(keySize.width / keySize.height, lessThanOrEqualTo(2));
    final nextRowFace = find.descendant(
      of: keyNamed('a'),
      matching: find.byType(InkWell),
    );
    expect(
      tester.getTopLeft(nextRowFace).dy - tester.getBottomLeft(keyFace).dy,
      closeTo(6, 0.01),
    );
    sideTaps = 0;
    await tester.tapAt(const Offset(20, 550));
    expect(sideTaps, 1);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(667, 375),
    const Size(800, 480),
    const Size(1440, 900),
    const Size(800, 1280),
  ]) {
    testWidgets('letter keys widen up to a 2:1 ratio at $size', (tester) async {
      await pumpKeyboard(tester, const TextField(), size: size);
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      final face = tester.getSize(
        find.descendant(of: keyNamed('q'), matching: find.byType(InkWell)),
      );
      expect(face.width, greaterThan(face.height));
      expect(face.width / face.height, lessThanOrEqualTo(2.001));
      final panel = tester.getRect(find.byKey(keyboardKey));
      expect(panel.width, lessThanOrEqualTo(size.width));
      expect(panel.width, lessThanOrEqualTo(900));
      expect(panel.center.dx, size.width / 2);
      expect(panel.height, lessThanOrEqualTo(size.height * 0.37));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('actions move above portrait keys without resetting the layout', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await pumpKeyboard(
      tester,
      TextField(controller: controller, focusNode: focus),
      size: const Size(375, 812),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await press(tester, 'Shift');
    final keypadState = tester.state(find.byType(VirtualKeypad));
    for (final size in [
      const Size(375, 812),
      const Size(812, 375),
      const Size(375, 667),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      final panel = tester.getRect(find.byKey(keyboardKey));
      final keys = tester.getRect(find.byType(VirtualKeypad));
      final hide = tester.getRect(
        find.byKey(const ValueKey('hide-on-screen-keyboard')),
      );
      final submit = tester.getRect(find.byKey(submitKey));
      if (size.height > size.width) {
        expect(keys.left, panel.left);
        expect(keys.right, panel.right);
        expect(keys.top - panel.top, 48);
        expect(hide.bottom, lessThanOrEqualTo(keys.top));
        expect(submit.bottom, lessThanOrEqualTo(keys.top));
        expect(hide.center.dy, submit.center.dy);
      } else {
        expect(panel.right - keys.right, 52);
        expect(hide.left, greaterThanOrEqualTo(keys.right));
        expect(submit.left, greaterThanOrEqualTo(keys.right));
      }
      expect(panel.height, lessThanOrEqualTo(size.height * 0.37));
      expect(tester.state(find.byType(VirtualKeypad)), same(keypadState));
      expect(keyNamed('A'), findsOneWidget);
      expect(focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    }
    await press(tester, 'A');
    expect(controller.text, 'A');
    await tester.tap(find.byKey(const ValueKey('hide-on-screen-keyboard')));
    await tester.pumpAndSettle();
    expect(find.byKey(keyboardKey), findsNothing);
  });

  testWidgets('focus changes can reverse a closing keyboard without a jump', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final container = await pumpKeyboard(
      tester,
      TextField(focusNode: focus),
      reducedMotion: false,
    );
    focus.requestFocus();
    await tester.pumpAndSettle();
    final openTop = tester.getTopLeft(find.byKey(keyboardKey)).dy;
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final closingTop = tester.getTopLeft(find.byKey(keyboardKey)).dy;
    expect(closingTop, greaterThan(openTop));
    focus.requestFocus();
    await tester.pump();
    await tester.pump();
    // Reopening keeps the existing panel and its current position.
    expect(tester.getTopLeft(find.byKey(keyboardKey)).dy, closingTop);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(keyboardKey)).dy, openTop);
    expect(focus.hasFocus, isTrue);
    // Turning the preference off during a transition must not leave an
    // invisible panel reserving space or an input client held by the keypad.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await container.read(onScreenKeyboardProvider.notifier).setEnabled(false);
    await tester.pumpAndSettle();
    expect(find.byKey(keyboardKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final localDisplay in [false, true]) {
    test('device default respects saved choices and server changes, '
        'local display: $localDisplay', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      ProviderContainer create() => ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          localDisplayKioskProvider.overrideWithValue(localDisplay),
          // Generic kiosk mode must not enable the keyboard by itself.
          kioskLaunchProvider.overrideWithValue(true),
        ],
      );
      final first = create();
      expect(first.read(onScreenKeyboardProvider), localDisplay);
      expect(
        prefs.containsKey(OnScreenKeyboardNotifier.preferenceKey),
        isFalse,
      );
      await first
          .read(onScreenKeyboardProvider.notifier)
          .setEnabled(!localDisplay);
      await first
          .read(connectionSettingsProvider.notifier)
          .setDevice('Second server', 'second.local', 80);
      first.dispose();
      final next = create();
      expect(next.read(onScreenKeyboardProvider), !localDisplay);
      await next
          .read(onScreenKeyboardProvider.notifier)
          .setEnabled(localDisplay);
      next.dispose();
      final last = create();
      expect(last.read(onScreenKeyboardProvider), localDisplay);
      last.dispose();
    });
  }

  testWidgets('client toggle saves immediately without a server', (
    tester,
  ) async {
    final container = await pumpKeyboard(
      tester,
      const ClientSettingsSection(),
      enabled: false,
    );
    await tester.tap(find.byKey(const ValueKey('on-screen-keyboard-setting')));
    await tester.pumpAndSettle();
    expect(container.read(onScreenKeyboardProvider), isTrue);
    expect(
      container
          .read(sharedPrefsProvider)
          .getBool(OnScreenKeyboardNotifier.preferenceKey),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('default platform input is restored after toggling at runtime', (
    tester,
  ) async {
    final controller = TextEditingController();
    final container = await pumpKeyboard(
      tester,
      TextField(controller: controller),
      enabled: false,
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.byKey(keyboardKey), findsNothing);
    await container.read(onScreenKeyboardProvider.notifier).setEnabled(true);
    await tester.pumpAndSettle();
    expect(find.byKey(keyboardKey), findsOneWidget);
    await press(tester, 'a');
    expect(controller.text, 'a');
    expect(
      tester.testTextInput.setClientArgs!['inputType']['name'],
      'TextInputType.none',
    );
    await container.read(onScreenKeyboardProvider.notifier).setEnabled(false);
    await tester.pumpAndSettle();
    expect(find.byKey(keyboardKey), findsNothing);
    expect(
      tester.testTextInput.setClientArgs!['inputType']['name'],
      'TextInputType.text',
    );
    await tester.enterText(find.byType(TextField), 'physical');
    expect(controller.text, 'physical');
  });

  testWidgets('insertion replaces selection and emits onChanged and Search', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'hello');
    final edits = <String>[];
    final submissions = <String>[];
    await pumpKeyboard(
      tester,
      TextField(
        controller: controller,
        onChanged: edits.add,
        onSubmitted: submissions.add,
        textInputAction: TextInputAction.search,
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 4);
    await press(tester, 'a');
    await press(tester, 'b');
    expect(controller.text, 'habo');
    expect(edits, ['hao', 'habo']);
    await tester.tap(find.byKey(submitKey));
    await tester.pumpAndSettle();
    expect(submissions, ['habo']);
    expect(find.byKey(keyboardKey), findsNothing);
  });

  testWidgets('backspace deletes whole emoji and combining characters', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'a👩🏽‍💻e\u0301');
    await pumpKeyboard(tester, TextField(controller: controller));
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    await press(tester, 'Backspace');
    expect(controller.text, 'a👩🏽‍💻');
    await press(tester, 'Backspace');
    expect(controller.text, 'a');
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 1);
    await press(tester, 'Backspace');
    await press(tester, 'Backspace');
    expect(controller.text, '');
  });

  testWidgets('formatters and maxLength still apply to keypad edits', (
    tester,
  ) async {
    final controller = TextEditingController();
    await pumpKeyboard(
      tester,
      TextField(
        controller: controller,
        maxLength: 2,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[ab]'))],
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    for (final key in ['a', 'c', 'b', 'a']) {
      await press(tester, key);
    }
    expect(controller.text, 'ab');
    await press(tester, 'Backspace');
    await press(tester, 'a');
    expect(controller.text, 'aa');
  });

  testWidgets('password settings stay masked and stage on Done', (
    tester,
  ) async {
    final staged = <String>[];
    await pumpKeyboard(
      tester,
      SettingsPasswordInput(value: '', onChanged: staged.add),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await press(tester, 'a');
    await press(tester, 'Shift');
    await press(tester, 'B');
    await press(tester, 'Show symbols');
    await press(tester, '!');
    expect(
      tester.widget<TextField>(find.byType(TextField)).obscureText,
      isTrue,
    );
    await tester.tap(find.byKey(submitKey));
    await tester.pumpAndSettle();
    expect(staged.last, 'aB!');
    expect(find.byKey(keyboardKey), findsNothing);
  });

  testWidgets('signed decimal fields show both signs and decimal keys', (
    tester,
  ) async {
    final controller = TextEditingController();
    await pumpKeyboard(
      tester,
      TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(
          signed: true,
          decimal: true,
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(keyNamed('q'), findsNothing);
    expect(keyNamed('Switch language'), findsNothing);
    for (final key in ['-', '1', '.', '5']) {
      await press(tester, key);
    }
    expect(controller.text, '-1.5');
  });

  testWidgets('numeric settings stage values and Done commits bounds', (
    tester,
  ) async {
    final staged = <num>[];
    await pumpKeyboard(
      tester,
      SettingsNumericInput(value: 10, min: 5, max: 100, onChanged: staged.add),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    final controller = tester
        .widget<TextField>(find.byType(TextField))
        .controller!;
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
    await press(tester, '4');
    await press(tester, '2');
    expect(staged.last, 42);
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 2);
    for (final key in ['2', '0', '0']) {
      await press(tester, key);
    }
    await tester.tap(find.byKey(submitKey));
    await tester.pumpAndSettle();
    expect(staged.last, 100);
  });

  testWidgets('Next switches fields and newline remains editable', (
    tester,
  ) async {
    final first = TextEditingController();
    final second = TextEditingController();
    await pumpKeyboard(
      tester,
      Column(
        children: [
          TextField(controller: first, textInputAction: TextInputAction.next),
          TextField(
            controller: second,
            maxLines: 3,
            textInputAction: TextInputAction.newline,
          ),
        ],
      ),
    );
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    await press(tester, 'a');
    await tester.tap(find.byKey(submitKey));
    await tester.pumpAndSettle();
    await press(tester, 'b');
    await press(tester, 'New line');
    await press(tester, 'c');
    expect(first.text, 'a');
    expect(second.text, 'b\nc');
    await tester.tap(find.byKey(const ValueKey('hide-on-screen-keyboard')));
    await tester.pumpAndSettle();
    expect(find.byKey(keyboardKey), findsNothing);
    await tester.tap(find.byType(TextField).last);
    await tester.pumpAndSettle();
    expect(find.byKey(keyboardKey), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(keyboardKey), findsNothing);
  });

  testWidgets('disabled and read-only fields never open the keyboard', (
    tester,
  ) async {
    await pumpKeyboard(
      tester,
      const Column(
        children: [
          TextField(readOnly: true),
          TextField(enabled: false),
          TextField(keyboardType: TextInputType.none),
        ],
      ),
    );
    for (final field in find.byType(TextField).evaluate()) {
      await tester.tap(find.byWidget(field.widget));
      await tester.pumpAndSettle();
      expect(find.byKey(keyboardKey), findsNothing);
    }
  });

  for (final size in [
    const Size(375, 667),
    const Size(667, 375),
    const Size(800, 480),
    const Size(1024, 600),
    const Size(1280, 800),
  ]) {
    testWidgets('modal editors remain above the keyboard at $size', (
      tester,
    ) async {
      String? saved;
      await pumpKeyboard(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showKalinkaBottomSheet<String>(
                context: context,
                contentBuilder: (context) => SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: TextField(
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (value) => Navigator.of(context).pop(value),
                  ),
                ),
              );
            },
            child: const Text('Edit'),
          ),
        ),
        size: size,
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      final panel = tester.getRect(find.byKey(keyboardKey));
      final keys = tester.getRect(find.byType(VirtualKeypad));
      expect(panel.left, keys.left);
      expect(panel.right - keys.right, size.height > size.width ? 0 : 52);
      expect(panel.height, lessThanOrEqualTo(size.height * 0.37));
      expect(panel.center.dx, size.width / 2);
      expect(
        tester.getBottomLeft(find.byType(TextField)).dy,
        lessThan(tester.getTopLeft(find.byKey(keyboardKey)).dy),
      );
      await press(tester, 'a');
      await tester.tap(find.byKey(submitKey));
      await tester.pumpAndSettle();
      expect(saved, 'a');
      expect(find.byKey(keyboardKey), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (size, scale) in [
    (const Size(320, 800), 2.0),
    (const Size(375, 667), 1.0),
    (const Size(800, 480), 1.0),
    (const Size(1280, 800), 1.0),
  ]) {
    testWidgets(
      'accent choices flow horizontally and stay visible at $size / $scale',
      (tester) async {
        final controller = TextEditingController(text: 'old');
        await pumpKeyboard(
          tester,
          TextField(controller: controller),
          size: size,
          textScale: scale,
        );
        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();
        controller.selection = const TextSelection(
          baseOffset: 0,
          extentOffset: 3,
        );
        await tester.longPress(keyNamed('a'));
        await tester.pumpAndSettle();
        final picker = find.byKey(const ValueKey('keyboard-accent-picker'));
        expect(
          find.descendant(of: picker, matching: find.byType(Scrollable)),
          findsNothing,
        );
        final keyboard = tester.getRect(find.byKey(keyboardKey));
        final first = tester.getRect(
          find.byKey(const ValueKey('keyboard-accent-à')),
        );
        final second = tester.getRect(
          find.byKey(const ValueKey('keyboard-accent-á')),
        );
        expect(second.top, first.top);
        expect(second.left, greaterThan(first.left));
        for (final accent in kLatinAccents['a']!) {
          final key = find.byKey(ValueKey('keyboard-accent-$accent'));
          final rect = tester.getRect(key);
          expect(key.hitTestable(), findsOneWidget);
          expect(rect.left, greaterThanOrEqualTo(keyboard.left));
          expect(rect.right, lessThanOrEqualTo(keyboard.right));
          expect(rect.top, greaterThanOrEqualTo(keyboard.top));
          expect(rect.bottom, lessThanOrEqualTo(keyboard.bottom));
          expect(rect.width, greaterThanOrEqualTo(48));
          expect(rect.height, greaterThanOrEqualTo(48));
        }
        await tester.tap(find.byKey(const ValueKey('keyboard-accent-ä')));
        await tester.pumpAndSettle();
        expect(controller.text, 'ä');
        expect(picker, findsNothing);
        await press(tester, 'b');
        expect(controller.text, 'äb');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('accent selection consumes Shift but preserves caps lock', (
    tester,
  ) async {
    final controller = TextEditingController();
    await pumpKeyboard(tester, TextField(controller: controller));
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await press(tester, 'Shift');
    await tester.longPress(keyNamed('U'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('keyboard-accent-Ü')));
    await tester.pumpAndSettle();
    await press(tester, 'a');
    expect(controller.text, 'Üa');
    await press(tester, 'Shift');
    await press(tester, 'Shift');
    await tester.longPress(keyNamed('S'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('keyboard-accent-ẞ')));
    await tester.pumpAndSettle();
    await press(tester, 'A');
    expect(controller.text, 'ÜaẞA');
  });

  testWidgets(
    'outside tap and Escape cancel accents without closing the keyboard',
    (tester) async {
      final controller = TextEditingController();
      await pumpKeyboard(tester, TextField(controller: controller));
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.longPress(keyNamed('e'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('keyboard-accent-picker')),
        findsNothing,
      );
      expect(find.byKey(keyboardKey), findsOneWidget);
      expect(controller.text, isEmpty);
      await tester.longPress(keyNamed('e'));
      await tester.pumpAndSettle();
      final keyboard = tester.getRect(find.byKey(keyboardKey));
      await tester.tapAt(keyboard.bottomRight - const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('keyboard-accent-picker')),
        findsNothing,
      );
      expect(controller.text, isEmpty);
      await press(tester, 'a');
      expect(controller.text, 'a');
    },
  );

  testWidgets('accent and language menus retain the active field', (
    tester,
  ) async {
    final controller = TextEditingController();
    await pumpKeyboard(tester, TextField(controller: controller));
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.longPress(keyNamed('e'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('é'));
    await tester.pumpAndSettle();
    expect(controller.text, 'é');
    await tester.longPress(keyNamed('Space'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('keyboard-language-picker')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('keyboard-language-en')));
    await tester.pumpAndSettle();
    await press(tester, 'a');
    expect(controller.text, 'éa');
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text and reduced motion fit a narrow client', (
    tester,
  ) async {
    await pumpKeyboard(
      tester,
      const Column(children: [ClientSettingsSection(), TextField()]),
      size: const Size(375, 667),
      textScale: 2,
    );
    await tester.ensureVisible(find.byType(TextField));
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await press(tester, 'a');
    expect(tester.takeException(), isNull);
  });

  testWidgets('render keyboard with bundled fonts for inspection', (
    tester,
  ) async {
    if (!const bool.fromEnvironment('KEYBOARD_SCREENSHOT')) return;
    await tester.runAsync(() async {
      await (FontLoader(KalinkaFonts.sansFamily)
            ..addFont(rootBundle.load('assets/fonts/IBMPlexSans-Regular.ttf')))
          .load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
    await pumpKeyboard(
      tester,
      const Padding(
        padding: EdgeInsets.all(20),
        child: TextField(
          decoration: InputDecoration(labelText: 'Search your music'),
        ),
      ),
      size: const Size(1280, 800),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await press(tester, 'a');
    await tester.pump(const Duration(milliseconds: 150));
    Future<void> capture(String name) => tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(captureKey),
      );
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await capture('kalinka-on-screen-keyboard');
    await tester.longPress(keyNamed('a'));
    await tester.pumpAndSettle();
    await capture('kalinka-keyboard-accents-wide');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(375, 667);
    await tester.pumpAndSettle();
    await capture('kalinka-keyboard-phone-toolbar');
    await tester.longPress(keyNamed('a'));
    await tester.pumpAndSettle();
    await capture('kalinka-keyboard-accents-phone');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    for (final (size, name) in [
      (const Size(1024, 600), '1024'),
      (const Size(800, 480), '800'),
      (const Size(375, 667), 'phone'),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      await capture('kalinka-keyboard-proportions-$name');
      await press(tester, 'Switch language');
      await capture('kalinka-keyboard-layout-grid-$name');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }
  });
}
