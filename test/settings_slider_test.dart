// The slider reports values on the step grid without asking Material for a
// discrete slider: that mode animates the thumb toward each stop over a fixed
// 75 ms, which reads as the thumb trailing the finger for the whole drag.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/widgets/settings_controls/settings_slider.dart';

import 'support/haptic_recorder.dart';

void main() {
  Future<double?> drag(
    WidgetTester tester, {
    required double min,
    required double max,
    double? step,
    required double fraction,
  }) async {
    double? committed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: SettingsSlider(
                label: 'Latency',
                value: min,
                min: min,
                max: max,
                step: step,
                onChanged: (v) => committed = v,
              ),
            ),
          ),
        ),
      ),
    );

    final track = tester.getRect(find.byType(Slider));
    // The Material slider insets the track by the overlay radius on each side.
    const inset = 14.0;
    final usable = track.width - 2 * inset;
    await tester.dragFrom(
      Offset(track.left + inset, track.center.dy),
      Offset(usable * fraction, 0),
    );
    await tester.pumpAndSettle();
    return committed;
  }

  testWidgets('a dragged value lands on the declared step', (tester) async {
    final committed = await drag(
      tester,
      min: 20,
      max: 1000,
      step: 10,
      fraction: 0.5,
    );

    expect(committed, isNotNull);
    expect((committed! - 20) % 10, 0, reason: 'on the grid');
    expect(committed, closeTo(510, 20));
  });

  testWidgets('the grid is measured from the minimum, not from zero', (
    tester,
  ) async {
    final committed = await drag(
      tester,
      min: 5,
      max: 200,
      step: 5,
      fraction: 0.37,
    );

    expect((committed! - 5) % 5, 0);
  });

  testWidgets('no step leaves the range continuous', (tester) async {
    final committed = await drag(tester, min: 0, max: 100, fraction: 0.333);

    expect(committed, isNot(closeTo(committed!.roundToDouble(), 0.0001)));
  });

  testWidgets('touching the thumb is silent; each tenth of travel ticks', (
    tester,
  ) async {
    final haptics = HapticRecorder.install();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: SettingsSlider(
                label: 'Latency',
                value: 0,
                min: 0,
                max: 100,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    final track = tester.getRect(find.byType(Slider));
    const inset = 14.0;
    final usable = track.width - 2 * inset;

    final gesture = await tester.startGesture(
      Offset(track.left + inset, track.center.dy),
    );
    await gesture.moveBy(Offset(usable * 0.06, 0));
    await tester.pump();
    expect(haptics.calls, isEmpty);

    await gesture.moveBy(Offset(usable * 0.06, 0));
    await tester.pump();
    expect(haptics.calls, ['selectionClick']);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a drag never reports past the ends', (tester) async {
    expect(
      await drag(tester, min: 20, max: 1000, step: 10, fraction: 1.4),
      1000,
    );
    expect(
      await drag(tester, min: 20, max: 1000, step: 10, fraction: -0.4),
      20,
    );
  });
}
