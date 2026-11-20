import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/widgets/dialog_scroll_scope.dart';
import 'package:kalinka/widgets/kalinka_bottom_sheet.dart';
import 'package:kalinka/widgets/kalinka_dialog.dart';

final up = find.byKey(const ValueKey('dialog-overflow-up'));
final down = find.byKey(const ValueKey('dialog-overflow-down'));
final left = find.byKey(const ValueKey('dialog-overflow-left'));
final right = find.byKey(const ValueKey('dialog-overflow-right'));

void main() {
  testWidgets('only the open sheet decorates its list', (tester) async {
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
    expect(down, findsOneWidget);
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
    final viewport = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    viewport.jumpTo(350);
    await tester.pumpAndSettle();
    final card = tester.getRect(find.byKey(KalinkaDialog.cardKey));
    expect(card.contains(tester.getCenter(up)), isTrue);
    expect(card.contains(tester.getCenter(down)), isTrue);
    viewport.jumpTo(0);
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
    expect(down, findsOneWidget);
    expect(controller.position.viewportDimension, 240);
    expect(controller.position.maxScrollExtent, 1);
    controller.jumpTo(1);
    await tester.pumpAndSettle();
    expect(down, findsNothing);
    expect(up, findsOneWidget);
    await layout(241, 241);
    expect(up, findsNothing);
    expect(down, findsNothing);
    expect(controller.position.viewportDimension, 241);
    await layout(300, 1200);
    expect(controller.position.viewportDimension, 300);
    final hint = tester.widget(down);
    await layout(320, 1200);
    expect(controller.position.viewportDimension, 320);
    expect(tester.widget(down), same(hint));
    await layout(12, 1200);
    expect(controller.position.viewportDimension, 12);
    expect(down, findsOneWidget);
    await layout(320, 120);
    expect(down, findsNothing);
  });

  testWidgets('a Material options menu shows hints on its own route', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DialogScrollScope(
            child: PopupMenuButton<int>(
              constraints: const BoxConstraints(maxHeight: 320, minWidth: 160),
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
    expect(down, findsOneWidget);
    await tester.drag(find.text('Option 1'), const Offset(0, -140));
    await tester.pumpAndSettle();
    expect(up, findsOneWidget);
    await tester.ensureVisible(find.text('Option 0'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Option 0'));
    await tester.pumpAndSettle();
    expect(down, findsNothing);
  });

  testWidgets('rows receive taps and wheel events through the hint', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    int? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 240,
            child: DialogScrollScope(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                controller: controller,
                itemExtent: 48,
                itemCount: 40,
                itemBuilder: (_, i) =>
                    InkWell(onTap: () => tapped = i, child: Text('Row $i')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final point = tester.getCenter(down);
    await tester.tapAt(point);
    await tester.pumpAndSettle();
    expect(tapped, 4);
    expect(controller.offset, 0);
    await tester.sendEventToBinding(
      PointerScrollEvent(position: point, scrollDelta: const Offset(0, 80)),
    );
    await tester.pumpAndSettle();
    expect(controller.offset, 80);
    expect(up, findsOneWidget);
  });

  for (final (axis, reverse, rtl, forward, back) in [
    (Axis.vertical, false, false, down, up),
    (Axis.vertical, true, false, up, down),
    (Axis.horizontal, false, false, right, left),
    (Axis.horizontal, false, true, left, right),
    (Axis.horizontal, true, true, right, left),
  ]) {
    testWidgets('hints follow scrolling on $axis, reverse $reverse, RTL $rtl', (
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
      expect(forward, findsOneWidget);
      controller.jumpTo(400);
      await tester.pumpAndSettle();
      expect(back, findsOneWidget);
      expect(forward, findsOneWidget);
      final viewport = tester.getRect(find.byType(Viewport));
      expect(viewport.size, const Size(280, 240));
      final mark = tester.getSize(forward);
      expect(
        axis == Axis.vertical ? mark.width : mark.height,
        greaterThan(3 * (axis == Axis.vertical ? mark.height : mark.width)),
      );
      expect(forward.hitTestable(), findsNothing);
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(forward, findsNothing);
      expect(back, findsOneWidget);
      controller.jumpTo(0);
      await tester.pumpAndSettle();
      expect(back, findsNothing);
    });
  }
}
