import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/widgets/onboarding/onboarding_step_scaffold.dart';

void main() {
  Widget wrap() => MaterialApp(
    home: Scaffold(
      body: OnboardingStepScaffold(
        stepNumber: 2,
        stepCount: 7,
        title: 'Audio output',
        children: const [Text('body')],
        onNext: () {},
      ),
    ),
  );

  testWidgets('a wide window keeps the shared setup column', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap());
    // A 600-wide column centered in 1400, plus the 20px header padding.
    expect(tester.getRect(find.text('Audio output')).left, closeTo(420, 1));
  });

  testWidgets('a narrow window keeps the 600 cap', (tester) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap());
    // Below the breakpoint: 600 centered in 800.
    expect(tester.getRect(find.text('Audio output')).left, closeTo(120, 1));
  });
}
