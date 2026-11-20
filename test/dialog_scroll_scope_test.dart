import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/widgets/dialog_scroll_scope.dart';
import 'package:kalinka/widgets/kalinka_bottom_sheet.dart';
import 'package:kalinka/widgets/kalinka_dialog.dart';

final up = find.byTooltip('Scroll up one page');
final down = find.byTooltip('Scroll down one page');
final left = find.byTooltip('Scroll left one page');
final right = find.byTooltip('Scroll right one page');

void main() {
  testWidgets('only the open sheet adds controls to its list', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ListView(children: const [SizedBox(height: 1800)]),
            floatingActionButton: FloatingActionButton(
              onPressed: () => showKalinkaBottomSheet<void>(
                context: context,
                contentBuilder: (_) =>
                    ListView(children: const [SizedBox(height: 1800)]),
              ),
              child: const Icon(Icons.add),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(down, findsNothing);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(down.hitTestable(), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(down, findsNothing);
    expect(find.byType(DialogScrollScope), findsNothing);
  });

  testWidgets('a dialog list keeps both chevrons inside the card', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KalinkaDialog(
            side: KalinkaDialogSide.full,
            title: 'Devices',
            content: Column(
              children: [
                for (var i = 0; i < 40; i++)
                  SizedBox(height: 50, child: Text('Device $i')),
              ],
            ),
            actions: const [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(up, findsNothing);
    await tester.tap(down);
    await tester.pumpAndSettle();
    final card = tester.getRect(find.byKey(KalinkaDialog.cardKey));
    expect(card.contains(tester.getCenter(up)), isTrue);
    expect(card.contains(tester.getCenter(down)), isTrue);
    await tester.tap(up);
    await tester.pumpAndSettle();
    expect(up, findsNothing);
    expect(find.text('Device 0').hitTestable(), findsOneWidget);
  });

  testWidgets('exact fits, one pixel of overflow and live resize', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    Future<void> layout(double height, double content) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: height,
                child: DialogScrollScope(
                  child: SingleChildScrollView(
                    controller: controller,
                    child: SizedBox(height: content),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await layout(240, 240);
    expect(down, findsNothing);
    expect(up, findsNothing);
    await layout(240, 241);
    expect(down.hitTestable(), findsOneWidget);
    await tester.tap(down);
    await tester.pumpAndSettle();
    expect(down, findsNothing);
    expect(up.hitTestable(), findsOneWidget);
    await layout(241, 241);
    expect(up, findsNothing);
    expect(down, findsNothing);
    expect(controller.position.viewportDimension, 241);
    await layout(300, 1200);
    final button = find.widgetWithIcon(
      IconButton,
      Icons.keyboard_arrow_down_rounded,
    );
    final initial = tester.widget<IconButton>(button);
    await layout(320, 1200);
    expect(tester.widget<IconButton>(button), same(initial));
    await layout(12, 1200);
    expect(controller.position.viewportDimension, greaterThan(0));
    expect(down.hitTestable(), findsOneWidget);
    await layout(320, 120);
    expect(down, findsNothing);
  });

  testWidgets(
    'a Material options menu captures its list controls on its own route',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DialogScrollScope(
              child: PopupMenuButton<int>(
                constraints: const BoxConstraints(
                  maxHeight: 320,
                  minWidth: 160,
                ),
                itemBuilder: (_) => [
                  for (var i = 0; i < 30; i++)
                    PopupMenuItem(value: i, child: Text('Option $i')),
                ],
                child: const Text('Open options'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open options'));
      await tester.pumpAndSettle();
      await tester.tap(down);
      await tester.pumpAndSettle();
      expect(up.hitTestable(), findsOneWidget);
      await tester.tap(up);
      await tester.pumpAndSettle();
      expect(up, findsNothing);
      await tester.tap(find.text('Option 0'));
      await tester.pumpAndSettle();
      expect(down, findsNothing);
    },
  );

  for (final (axis, reverse, rtl, forward, back) in [
    (Axis.vertical, false, false, down, up),
    (Axis.vertical, true, false, up, down),
    (Axis.horizontal, false, false, right, left),
    (Axis.horizontal, false, true, left, right),
    (Axis.horizontal, true, true, right, left),
  ]) {
    testWidgets('pages both ways on $axis, reverse $reverse, RTL $rtl', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Directionality(
                textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                child: SizedBox(
                  width: 280,
                  height: 240,
                  child: DialogScrollScope(
                    child: ListView.builder(
                      controller: controller,
                      reverse: reverse,
                      scrollDirection: axis,
                      itemExtent: 40,
                      itemCount: 40,
                      itemBuilder: (_, i) => Text('Row $i'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(back, findsNothing);
      final page = controller.position.viewportDimension;
      await tester.tap(forward);
      await tester.pumpAndSettle();
      expect(controller.offset, page);
      expect(back.hitTestable(), findsOneWidget);
      expect(forward.hitTestable(), findsOneWidget);
      final viewport = tester.getRect(find.byType(Viewport));
      expect(viewport.overlaps(tester.getRect(back)), isFalse);
      expect(viewport.overlaps(tester.getRect(forward)), isFalse);
      final prior = controller.offset;
      final step = controller.position.viewportDimension;
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(controller.offset, prior - step);
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(forward, findsNothing);
      expect(back.hitTestable(), findsOneWidget);
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(forward.hitTestable(), findsOneWidget);
    });
  }
}
