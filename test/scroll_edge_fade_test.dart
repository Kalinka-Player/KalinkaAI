import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/widgets/scroll_edge_fade.dart';

void main() {
  testWidgets('a rail built past its end settles without a build scheduled '
      'mid-layout', (tester) async {
    // As a rebuilt rail whose restored offset lands just beyond its new end:
    // its first layout starts a scroll back.
    final controller = ScrollController(initialScrollOffset: 750);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            height: 80,
            child: ScrollEdgeFade(
              axis: Axis.horizontal,
              child: ListView(
                controller: controller,
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < 10; i++) const SizedBox(width: 100),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(controller.offset, 700);
  });
}
