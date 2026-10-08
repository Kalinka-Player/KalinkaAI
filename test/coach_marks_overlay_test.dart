import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/widgets/coach_marks_overlay.dart';

/// Hosts the tour over three targets and can drop the middle one, the way a
/// server without renderers drops the output switcher's stop.
class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final _first = GlobalKey();
  final _middle = GlobalKey();
  final _last = GlobalKey();
  bool _middleStop = true;
  bool _dismissed = false;

  void dropMiddleStop() => setState(() => _middleStop = false);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Positioned(
              top: 40,
              left: 20,
              child: SizedBox(key: _first, width: 40, height: 40),
            ),
            Positioned(
              top: 140,
              left: 20,
              child: SizedBox(key: _middle, width: 40, height: 40),
            ),
            Positioned(
              top: 240,
              left: 20,
              child: SizedBox(key: _last, width: 40, height: 40),
            ),
            if (!_dismissed)
              Positioned.fill(
                child: CoachMarksOverlay(
                  stops: [
                    CoachMarkStop(
                      targetKey: _first,
                      title: 'Find music',
                      body: 'Search and browse from here.',
                    ),
                    if (_middleStop)
                      CoachMarkStop(
                        targetKey: _middle,
                        title: 'Choose where it plays',
                        body: 'The cast icon switches outputs.',
                      ),
                    CoachMarkStop(
                      targetKey: _last,
                      title: 'Your server lives here',
                      body: 'The green dot shows you are connected.',
                    ),
                  ],
                  onDismiss: () => setState(() => _dismissed = true),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The spotlight pulses forever, so pumpAndSettle would never return.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('a stop that disappears mid-tour leaves the index in range', (
    tester,
  ) async {
    await tester.pumpWidget(const _Host());
    await _settle(tester);

    // Advance to the last stop, then lose one from under it.
    await tester.tap(find.text('Next'));
    await _settle(tester);
    await tester.tap(find.text('Next'));
    await _settle(tester);
    expect(find.text('Your server lives here'), findsOneWidget);
    expect(find.text('3 / 3'), findsOneWidget);

    tester.state<_HostState>(find.byType(_Host)).dropMiddleStop();
    await _settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Your server lives here'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
  });

  testWidgets('the stop for a missing control is never shown', (tester) async {
    await tester.pumpWidget(const _Host());
    await _settle(tester);

    tester.state<_HostState>(find.byType(_Host)).dropMiddleStop();
    await _settle(tester);

    expect(find.text('1 / 2'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await _settle(tester);

    expect(find.text('Choose where it plays'), findsNothing);
    expect(find.text('Your server lives here'), findsOneWidget);
  });
}
