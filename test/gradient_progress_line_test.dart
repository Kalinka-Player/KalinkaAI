import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/widgets/gradient_progress_line.dart';

void main() {
  Widget buildLine(GradientProgressLineMode mode, {double progress = 0.5}) =>
      MaterialApp(
        home: Scaffold(
          body: GradientProgressLine(progress: progress, mode: mode),
        ),
      );

  // The app scaffolding draws its own CustomPaint and AnimatedBuilder.
  Finder inLine(Type type) => find.descendant(
        of: find.byType(GradientProgressLine),
        matching: find.byType(type),
      );

  testWidgets('normal mode renders CustomPaint directly without shimmer',
      (tester) async {
    await tester.pumpWidget(buildLine(GradientProgressLineMode.normal));
    await tester.pump();

    expect(inLine(CustomPaint), findsOneWidget);
    expect(inLine(AnimatedBuilder), findsNothing);
  });

  testWidgets('reconnecting mode wraps in AnimatedBuilder for shimmer',
      (tester) async {
    await tester.pumpWidget(buildLine(GradientProgressLineMode.reconnecting));
    await tester.pump();

    expect(inLine(AnimatedBuilder), findsOneWidget);
    expect(inLine(CustomPaint), findsOneWidget);
  });

  testWidgets('offline mode wraps in AnimatedBuilder for shimmer',
      (tester) async {
    await tester.pumpWidget(buildLine(GradientProgressLineMode.offline));
    await tester.pump();

    expect(inLine(AnimatedBuilder), findsOneWidget);
    expect(inLine(CustomPaint), findsOneWidget);
  });

  testWidgets('switching from reconnecting to normal removes AnimatedBuilder',
      (tester) async {
    await tester
        .pumpWidget(buildLine(GradientProgressLineMode.reconnecting));
    await tester.pump();
    expect(inLine(AnimatedBuilder), findsOneWidget);

    await tester.pumpWidget(buildLine(GradientProgressLineMode.normal));
    await tester.pump();
    expect(inLine(AnimatedBuilder), findsNothing);
  });

  testWidgets('switching from normal to offline adds AnimatedBuilder',
      (tester) async {
    await tester.pumpWidget(buildLine(GradientProgressLineMode.normal));
    await tester.pump();
    expect(inLine(AnimatedBuilder), findsNothing);

    await tester.pumpWidget(buildLine(GradientProgressLineMode.offline));
    await tester.pump();
    expect(inLine(AnimatedBuilder), findsOneWidget);
  });

  testWidgets('switching from offline to reconnecting keeps AnimatedBuilder',
      (tester) async {
    await tester.pumpWidget(buildLine(GradientProgressLineMode.offline));
    await tester.pump();
    expect(inLine(AnimatedBuilder), findsOneWidget);

    await tester
        .pumpWidget(buildLine(GradientProgressLineMode.reconnecting));
    await tester.pump();
    expect(inLine(AnimatedBuilder), findsOneWidget);
  });
}
