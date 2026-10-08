import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/widgets/kalinka_button.dart';

import 'support/haptic_recorder.dart';

void main() {
  testWidgets('full-width button truncates a long label without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              child: KalinkaButton(
                label: 'Connect to Some Very Long Kalinka Server Name',
                fullWidth: true,
              ),
            ),
          ),
        ),
      ),
    );

    // Without the Flexible wrap the Row overflows and throws in debug.
    expect(tester.takeException(), isNull);
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.overflow, TextOverflow.ellipsis);
    expect(text.maxLines, 1);
  });

  testWidgets('intrinsic button lays out inside an unbounded Row', (
    tester,
  ) async {
    // Outer Rows give non-flex children infinite width — the label must
    // not be Flexible there or the inner Row asserts.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(children: [KalinkaButton(label: 'Try again')]),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('a tap acts without vibrating, whatever the variant', (
    tester,
  ) async {
    final haptics = HapticRecorder.install();
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              KalinkaButton(label: 'Accent', onTap: () => taps++),
              KalinkaButton(
                label: 'Neutral',
                variant: KalinkaButtonVariant.neutral,
                onTap: () => taps++,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Accent'));
    await tester.tap(find.text('Neutral'));
    await tester.pump();
    expect(taps, 2);
    expect(haptics.calls, isEmpty);
  });

  testWidgets('a disabled button ignores taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KalinkaButton(
            label: 'Off',
            enabled: false,
            onTap: () => taps++,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Off'), warnIfMissed: false);
    expect(taps, 0);
  });
}
