import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/widgets/keyboard/app_keyboard_navigation.dart';

import 'support/focus.dart';

Widget button(String label, {FocusNode? focusNode, VoidCallback? onPressed}) =>
    TextButton(
      focusNode: focusNode,
      onPressed: onPressed ?? () {},
      child: Text(label),
    );

Widget region(AppKeyboardArea area, Widget child) =>
    AppKeyboardRegion(area: area, child: child);

Future<void> pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: AppKeyboardNavigation(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

Future<void> backTab(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await key(tester, LogicalKeyboardKey.tab);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
}

String? get area =>
    FocusManager.instance.primaryFocus?.nearestScope?.debugLabel;

void main() {
  testWidgets(
    'Tab follows area order, Shift-Tab reverses, and re-entry remembers focus',
    (tester) async {
      await pump(
        tester,
        Column(
          children: [
            region(AppKeyboardArea.player, button('Player')),
            region(
              AppKeyboardArea.content,
              Row(children: [button('First'), button('Second')]),
            ),
            region(AppKeyboardArea.navigation, button('Navigation')),
            region(AppKeyboardArea.playback, button('Playback')),
            region(AppKeyboardArea.toolbar, button('Toolbar')),
          ],
        ),
      );
      for (final expected in AppKeyboardArea.values) {
        await key(tester, LogicalKeyboardKey.tab);
        expect(area, expected.name);
        if (expected == AppKeyboardArea.content) {
          await key(tester, LogicalKeyboardKey.arrowRight);
          expect(focusIsOn(find.widgetWithText(TextButton, 'Second')), isTrue);
        }
      }
      await key(tester, LogicalKeyboardKey.tab);
      expect(area, 'navigation');
      await backTab(tester);
      expect(area, 'player');
      await backTab(tester);
      await backTab(tester);
      expect(focusIsOn(find.widgetWithText(TextButton, 'Second')), isTrue);
    },
  );

  testWidgets(
    'empty, disabled and hidden areas are skipped, including nested areas',
    (tester) async {
      await pump(
        tester,
        region(
          AppKeyboardArea.content,
          Column(
            children: [
              region(AppKeyboardArea.navigation, const Text('Empty')),
              region(
                AppKeyboardArea.toolbar,
                const TextButton(onPressed: null, child: Text('Disabled')),
              ),
              button('Content'),
              ExcludeFocus(
                child: region(AppKeyboardArea.playback, button('Hidden')),
              ),
              region(AppKeyboardArea.player, button('Player')),
            ],
          ),
        ),
      );
      await key(tester, LogicalKeyboardKey.tab);
      expect(area, 'content');
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(area, 'content');
      await key(tester, LogicalKeyboardKey.tab);
      expect(area, 'player');
      await key(tester, LogicalKeyboardKey.tab);
      expect(area, 'content');
    },
  );

  testWidgets('arrows follow grid geometry and stop at area boundaries', (
    tester,
  ) async {
    var activated = 0;
    await pump(
      tester,
      Row(
        children: [
          region(AppKeyboardArea.navigation, button('Rail')),
          Expanded(
            child: region(
              AppKeyboardArea.content,
              Column(
                children: [
                  Row(children: [button('A'), button('B')]),
                  Row(
                    children: [
                      button('C'),
                      button('D', onPressed: () => activated++),
                    ],
                  ),
                ],
              ),
            ),
          ),
          region(AppKeyboardArea.player, button('Player')),
        ],
      ),
    );
    await key(tester, LogicalKeyboardKey.tab);
    await key(tester, LogicalKeyboardKey.tab);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(focusIsOn(find.widgetWithText(TextButton, 'B')), isTrue);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(focusIsOn(find.widgetWithText(TextButton, 'D')), isTrue);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(focusIsOn(find.widgetWithText(TextButton, 'D')), isTrue);
    await key(tester, LogicalKeyboardKey.enter);
    expect(activated, 1);
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(focusIsOn(find.widgetWithText(TextButton, 'C')), isTrue);
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(focusIsOn(find.widgetWithText(TextButton, 'A')), isTrue);
  });

  for (final horizontal in [false, true]) {
    testWidgets(
      'arrows traverse and reveal a lazy ${horizontal ? 'horizontal' : 'vertical'} list with no cache',
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        await pump(
          tester,
          Center(
            child: SizedBox(
              width: 240,
              height: 180,
              child: region(
                AppKeyboardArea.content,
                ListView.builder(
                  controller: scroll,
                  scrollDirection: horizontal ? Axis.horizontal : Axis.vertical,
                  scrollCacheExtent: const ScrollCacheExtent.pixels(0),
                  itemExtent: 60,
                  itemCount: 40,
                  itemBuilder: (_, i) => button('Item $i'),
                ),
              ),
            ),
          ),
        );
        await key(tester, LogicalKeyboardKey.tab);
        for (var i = 1; i < 40; i++) {
          await key(
            tester,
            horizontal
                ? LogicalKeyboardKey.arrowRight
                : LogicalKeyboardKey.arrowDown,
          );
          expect(
            focusIsOn(find.widgetWithText(TextButton, 'Item $i')),
            isTrue,
            reason: 'item $i',
          );
          final rect = FocusManager.instance.primaryFocus!.rect;
          final viewport = tester.getRect(find.byType(ListView));
          expect(viewport.contains(rect.topLeft), isTrue);
          expect(rect.right, lessThanOrEqualTo(viewport.right + 0.1));
          expect(rect.bottom, lessThanOrEqualTo(viewport.bottom + 0.1));
        }
        expect(scroll.offset, greaterThan(0));
        for (var i = 38; i >= 0; i--) {
          await key(
            tester,
            horizontal
                ? LogicalKeyboardKey.arrowLeft
                : LogicalKeyboardKey.arrowUp,
          );
          expect(
            focusIsOn(find.widgetWithText(TextButton, 'Item $i')),
            isTrue,
            reason: 'return item $i',
          );
        }
        expect(scroll.offset, 0);
      },
    );
  }

  testWidgets('a text field retains caret keys and Tab leaves its area', (
    tester,
  ) async {
    final text = TextEditingController(text: 'music');
    final focus = FocusNode();
    addTearDown(text.dispose);
    addTearDown(focus.dispose);
    await pump(
      tester,
      Column(
        children: [
          region(
            AppKeyboardArea.toolbar,
            Row(
              children: [
                Expanded(
                  child: TextField(controller: text, focusNode: focus),
                ),
                button('After field'),
              ],
            ),
          ),
          region(AppKeyboardArea.content, button('Content')),
        ],
      ),
    );
    focus.requestFocus();
    await tester.pump();
    text.selection = const TextSelection.collapsed(offset: 3);
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(text.selection.extentOffset, 2);
    expect(focus.hasFocus, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await key(tester, LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    expect(focusIsOn(find.widgetWithText(TextButton, 'After field')), isTrue);
    expect(text.selection.extentOffset, 2);
    await key(tester, LogicalKeyboardKey.tab);
    expect(area, 'content');
  });

  testWidgets('arrows pass a slider in a horizontal bar without adjusting it', (
    tester,
  ) async {
    var value = 0.5;
    await pump(
      tester,
      region(
        AppKeyboardArea.playback,
        Row(
          children: [
            button('Track'),
            Expanded(
              child: AppKeyboardSlider(
                child: Slider(value: value, onChanged: (v) => value = v),
              ),
            ),
            button('Output'),
            button('Play'),
          ],
        ),
      ),
    );
    await key(tester, LogicalKeyboardKey.tab);
    // Start at the left edge regardless of which target reading order enters.
    for (var i = 0; i < 4; i++) {
      await key(tester, LogicalKeyboardKey.arrowLeft);
    }
    expect(focusIsOn(find.widgetWithText(TextButton, 'Track')), isTrue);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(focusIsOn(find.byType(AppKeyboardSlider)), isTrue);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(focusIsOn(find.widgetWithText(TextButton, 'Output')), isTrue);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(focusIsOn(find.widgetWithText(TextButton, 'Play')), isTrue);
    await key(tester, LogicalKeyboardKey.arrowLeft);
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(focusIsOn(find.byType(AppKeyboardSlider)), isTrue);
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(focusIsOn(find.widgetWithText(TextButton, 'Track')), isTrue);
    expect(value, 0.5);
  });

  testWidgets(
    'slider enters adjustment explicitly and exits with Enter or Escape',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      var value = 0.5;
      await pump(
        tester,
        region(
          AppKeyboardArea.playback,
          Column(
            children: [
              button('Above'),
              AppKeyboardSlider(
                child: Slider(
                  focusNode: focus,
                  value: value,
                  onChanged: (v) => value = v,
                ),
              ),
              button('Below'),
            ],
          ),
        ),
      );
      await key(tester, LogicalKeyboardKey.tab);
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(focusIsOn(find.byType(AppKeyboardSlider)), isTrue);
      expect(focus.hasFocus, isFalse);
      expect(find.text('Enter or Space to adjust'), findsOneWidget);
      await key(tester, LogicalKeyboardKey.enter);
      expect(focus.hasFocus, isTrue);
      expect(
        find.text('Left/Right to adjust · Enter or Esc to finish'),
        findsOneWidget,
      );
      await key(tester, LogicalKeyboardKey.arrowRight);
      expect(value, greaterThan(0.5));
      expect(focus.hasFocus, isTrue);
      await key(tester, LogicalKeyboardKey.escape);
      expect(focus.hasFocus, isFalse);
      expect(focusIsOn(find.byType(AppKeyboardSlider)), isTrue);
      await key(tester, LogicalKeyboardKey.space);
      expect(focus.hasFocus, isTrue);
      await key(tester, LogicalKeyboardKey.enter);
      expect(focus.hasFocus, isFalse);
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(focusIsOn(find.widgetWithText(TextButton, 'Below')), isTrue);
      await key(tester, LogicalKeyboardKey.arrowUp);
      expect(focusIsOn(find.byType(AppKeyboardSlider)), isTrue);
      await key(tester, LogicalKeyboardKey.arrowUp);
      expect(focusIsOn(find.widgetWithText(TextButton, 'Above')), isTrue);
    },
  );

  testWidgets('local overlay scopes retain Tab traversal', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await pump(
      tester,
      region(
        AppKeyboardArea.content,
        Column(
          children: [
            button('Background'),
            FocusScope(
              child: Row(
                children: [
                  button('Local A', focusNode: focus),
                  button('Local B'),
                ],
              ),
            ),
            region(AppKeyboardArea.player, button('Player')),
          ],
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await key(tester, LogicalKeyboardKey.tab);
    expect(focusIsOn(find.widgetWithText(TextButton, 'Local B')), isTrue);
    await key(tester, LogicalKeyboardKey.tab);
    expect(focus.hasFocus, isTrue);
  });

  testWidgets('Tab leaves adjustment and returns to slider navigation', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var value = 0.5;
    await pump(
      tester,
      Column(
        children: [
          region(
            AppKeyboardArea.playback,
            Row(
              children: [
                button('Track'),
                Expanded(
                  child: AppKeyboardSlider(
                    child: Slider(
                      focusNode: focus,
                      value: value,
                      onChanged: (v) => value = v,
                    ),
                  ),
                ),
                button('Play'),
              ],
            ),
          ),
          region(AppKeyboardArea.player, button('Player')),
        ],
      ),
    );
    await key(tester, LogicalKeyboardKey.tab);
    for (var i = 0; i < 3; i++) {
      await key(tester, LogicalKeyboardKey.arrowLeft);
    }
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.enter);
    expect(focus.hasFocus, isTrue);
    await key(tester, LogicalKeyboardKey.tab);
    expect(area, 'player');
    await backTab(tester);
    expect(focusIsOn(find.byType(AppKeyboardSlider)), isTrue);
    expect(focus.hasFocus, isFalse);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(focusIsOn(find.widgetWithText(TextButton, 'Play')), isTrue);
    expect(value, 0.5);
  });

  testWidgets('pointer can adjust a grouped slider directly', (tester) async {
    var value = 0.5;
    await pump(
      tester,
      region(
        AppKeyboardArea.playback,
        AppKeyboardSlider(
          child: Slider(value: value, onChanged: (v) => value = v),
        ),
      ),
    );
    final rect = tester.getRect(find.byType(Slider));
    await tester.tapAt(Offset(rect.left + rect.width * 0.75, rect.center.dy));
    await tester.pumpAndSettle();
    expect(value, greaterThan(0.5));
  });

  testWidgets('dialog Tab stays modal and dismissal restores its caller', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await pump(
      tester,
      Builder(
        builder: (context) => region(
          AppKeyboardArea.content,
          button(
            'Open',
            focusNode: focus,
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                actions: [
                  button('Cancel', onPressed: () => Navigator.pop(context)),
                  button('Confirm'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await key(tester, LogicalKeyboardKey.tab);
    await key(tester, LogicalKeyboardKey.enter);
    for (var i = 0; i < 4; i++) {
      await key(tester, LogicalKeyboardKey.tab);
      expect(focusIsOn(find.byType(AlertDialog)), isTrue);
    }
    await key(tester, LogicalKeyboardKey.escape);
    expect(focus.hasFocus, isTrue);
  });
}
