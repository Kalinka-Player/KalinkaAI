import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/widgets/swipe_to_act_row.dart';
import 'package:kalinka/widgets/swipe_to_delete_row.dart';

import 'support/haptic_recorder.dart';

const _row = SizedBox(height: 56, width: double.infinity, child: Text('row'));

Future<void> _pump(WidgetTester tester, Widget row) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(body: Column(children: [row])),
  ),
);

/// Drags the row by [distances] in turn; the first stays inside touch slop
/// accounting, which a horizontal drag swallows before reporting movement.
Future<void> _swipe(WidgetTester tester, List<double> distances) async {
  final gesture = await tester.startGesture(tester.getCenter(find.text('row')));
  for (final dx in distances) {
    await gesture.moveBy(Offset(dx, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  group('swipe to add / play next', () {
    late List<String> actions;

    Widget row() => SwipeToActRow(
      onAddToQueue: () => actions.add('queue'),
      onPlayNext: () => actions.add('next'),
      child: _row,
    );

    setUp(() => actions = []);

    testWidgets('a short swipe only ticks as it unlocks', (tester) async {
      final haptics = HapticRecorder.install();
      await _pump(tester, row());
      await _swipe(tester, [20, 20]);
      expect(haptics.calls, ['selectionClick']);
      expect(actions, isEmpty);
    });

    testWidgets('a swipe past the threshold pops on release', (tester) async {
      final haptics = HapticRecorder.install();
      await _pump(tester, row());
      await _swipe(tester, [20, 20, 100]);
      expect(haptics.calls, ['selectionClick', 'native:hapticCorkPop']);
      expect(actions, ['queue']);

      await _swipe(tester, [-20, -20, -100]);
      expect(actions, ['queue', 'next']);
    });

    testWidgets('falls back where the composition cannot play', (tester) async {
      final haptics = HapticRecorder.install()..nativePlays = false;
      await _pump(tester, row());
      await _swipe(tester, [20, 20, 100]);
      expect(haptics.calls, [
        'selectionClick',
        'native:hapticCorkPop',
        'mediumImpact',
      ]);
    });
  });

  group('swipe to remove', () {
    late int deletes;

    Widget row() => SwipeToDeleteRow(onDelete: () => deletes++, child: _row);

    setUp(() => deletes = 0);

    testWidgets('a short swipe only ticks as it unlocks', (tester) async {
      final haptics = HapticRecorder.install();
      await _pump(tester, row());
      await _swipe(tester, [-20, -20]);
      expect(haptics.calls, ['selectionClick']);
      expect(deletes, 0);
    });

    testWidgets('a swipe past the threshold thuds on release', (tester) async {
      final haptics = HapticRecorder.install();
      await _pump(tester, row());
      await _swipe(tester, [-20, -20, -120]);
      expect(haptics.calls, ['selectionClick', 'native:hapticDelete']);
      expect(deletes, 1);
    });
  });
}
