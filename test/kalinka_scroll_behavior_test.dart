import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/widgets/kalinka_scroll_behavior.dart';
import 'package:kalinka/widgets/modifier_click.dart';

Widget _app(Widget child, {bool reducedMotion = false}) => MaterialApp(
  scrollBehavior: const KalinkaScrollBehavior(),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
      child: Scaffold(body: Center(child: child)),
    ),
  ),
);

void main() {
  final down = find.byTooltip('Scroll down one page');

  testWidgets('the cue follows content and viewport size before any gesture', (
    tester,
  ) async {
    Future<void> layout(double viewHeight, double contentHeight) async {
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 250,
            height: viewHeight,
            child: SingleChildScrollView(
              child: SizedBox(height: contentHeight),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await layout(200, 200);
    expect(down, findsNothing);
    await layout(200, 201);
    expect(down.hitTestable(), findsOneWidget);
    await layout(260, 201);
    expect(down, findsNothing);
    await layout(260, 500);
    expect(down.hitTestable(), findsOneWidget);
  });

  testWidgets(
    'resizing repositions an unchanged page button without rebuilding it',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 600);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(ListView(children: const [SizedBox(height: 1600)])),
      );
      await tester.pumpAndSettle();
      final finder = find.widgetWithIcon(
        IconButton,
        Icons.keyboard_arrow_down_rounded,
      );
      final button = tester.widget<IconButton>(finder);
      final center = tester.getCenter(finder);

      tester.view.physicalSize = const Size(960, 680);
      await tester.pumpAndSettle();
      expect(tester.getCenter(finder), center + const Offset(80, 80));
      expect(tester.widget<IconButton>(finder), same(button));
    },
  );

  testWidgets('drag and wheel over the button, then click while it is dim', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var rowTaps = 0;
    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 250,
          height: 200,
          child: ListView.builder(
            controller: controller,
            itemCount: 30,
            itemExtent: 50,
            itemBuilder: (_, i) =>
                InkWell(onTap: () => rowTaps++, child: Text('Row $i')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final center = tester.getCenter(down);
    final button = find.widgetWithIcon(
      IconButton,
      Icons.keyboard_arrow_down_rounded,
    );
    double opacity() => tester
        .widget<IconButton>(button)
        .style!
        .backgroundColor!
        .resolve({})!
        .a;
    expect(tester.getSize(button), const Size(48, 48));
    final idle = opacity();
    expect(idle, inExclusiveRange(0, 1));
    final drag = await tester.startGesture(center);
    await drag.moveBy(const Offset(0, -24));
    await drag.moveBy(const Offset(0, -80));
    await tester.pump();
    expect(controller.offset, greaterThan(0));
    expect(opacity(), lessThan(idle));
    await drag.up();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(opacity(), idle);
    final beforeWheel = controller.offset;
    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, 50)),
    );
    await tester.pump();
    expect(controller.offset, beforeWheel + 50);
    expect(opacity(), lessThan(idle));
    final beforeTap = controller.offset;
    await tester.tap(down);
    await tester.pumpAndSettle();
    expect(controller.offset, beforeTap + 200);
    expect(rowTaps, 0);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(down, findsNothing);
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(down.hitTestable(), findsOneWidget);
  });

  testWidgets(
    'a modified click on the page button leaves the row underneath alone',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      var selected = false;
      await tester.pumpWidget(
        _app(
          ListView.builder(
            controller: controller,
            itemCount: 60,
            itemExtent: 50,
            itemBuilder: (_, i) => ModifierClick(
              onModifiedClick: () => selected = true,
              child: InkWell(onTap: () {}, child: Text('Row $i')),
            ),
          ),
          reducedMotion: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(down, kind: PointerDeviceKind.mouse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(selected, isFalse);
      expect(controller.offset, controller.position.viewportDimension);
    },
  );

  testWidgets(
    'remote and keyboard page the visible area above the player bar',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          ScrollConfiguration(
            behavior: const KalinkaScrollBehavior(bottomClearance: 60),
            child: SizedBox(
              height: 200,
              width: 300,
              child: SingleChildScrollView(
                controller: controller,
                child: const SizedBox(height: 470),
              ),
            ),
          ),
          reducedMotion: true,
        ),
      );
      await tester.pumpAndSettle();
      final view = find.byType(SingleChildScrollView);
      expect(
        tester.getBottomLeft(down).dy,
        lessThanOrEqualTo(tester.getBottomLeft(view).dy - 60),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(controller.offset, 140);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(controller.offset, 270);
      await tester.pumpAndSettle();
      expect(down, findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets('a nested RTL rail pages itself while the outer list stays put', (
    tester,
  ) async {
    final outer = ScrollController();
    final rail = ScrollController();
    addTearDown(outer.dispose);
    addTearDown(rail.dispose);
    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 250,
          height: 200,
          child: ListView(
            controller: outer,
            children: [
              Directionality(
                textDirection: TextDirection.rtl,
                child: SizedBox(
                  height: 68,
                  child: SingleChildScrollView(
                    controller: rail,
                    scrollDirection: Axis.horizontal,
                    child: const SizedBox(width: 530),
                  ),
                ),
              ),
              const SizedBox(height: 300),
            ],
          ),
        ),
        reducedMotion: true,
      ),
    );
    await tester.pumpAndSettle();
    final left = find.byTooltip('Scroll left one page');
    await tester.tap(left);
    expect(rail.offset, 250);
    await tester.pump();
    await tester.tap(left);
    await tester.pumpAndSettle();
    expect(rail.offset, 280);
    expect(left, findsNothing);
    expect(outer.offset, 0);
    expect(down.hitTestable(), findsOneWidget);
  });
}
