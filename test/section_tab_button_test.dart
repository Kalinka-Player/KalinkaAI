import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/section_tab_button.dart';

void main() {
  testWidgets('hover and keyboard focus highlight a tab without selecting it', (
    tester,
  ) async {
    final key = GlobalKey();
    var selections = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: key,
              child: SectionTabButton(
                label: 'Music sources',
                selected: false,
                onTap: () => selections++,
              ),
            ),
          ),
        ),
      ),
    );

    Future<Uint8List> pixels() async => (await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData();
      image.dispose();
      return bytes!.buffer.asUint8List();
    }))!;

    bool differs(Uint8List a, Uint8List b) =>
        a.length != b.length ||
        Iterable<int>.generate(a.length).any((i) => a[i] != b[i]);

    final tab = find.byType(SectionTabButton);
    final bounds = tester.getRect(tab);
    final resting = await pixels();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(700, 700));
    await mouse.moveTo(bounds.center);
    await tester.pumpAndSettle();
    final hovered = await pixels();
    expect(differs(resting, hovered), isTrue);
    // Rounded hover feedback leaves the corner outside the painted pill.
    expect(hovered.sublist(0, 4), resting.sublist(0, 4));
    expect(tester.getRect(tab), bounds);
    expect(selections, 0);

    await mouse.removePointer();
    await tester.pumpAndSettle();
    expect(differs(resting, await pixels()), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(differs(resting, await pixels()), isTrue);
    expect(tester.getRect(tab), bounds);
    expect(selections, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selections, 1);
    expect(tester.takeException(), isNull);
  });
}
