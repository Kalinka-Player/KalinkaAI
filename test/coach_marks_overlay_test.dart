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

const _phone = Size(360, 800);

// Where the Home tour's controls sit on a phone.
const _searchEntry = Rect.fromLTWH(16, 340, 328, 48);
const _outputSwitcher = Rect.fromLTWH(300, 740, 44, 44);
const _connectionDot = Rect.fromLTWH(320, 14, 28, 28);

/// The tour on a phone, one stop per rect, titled 'Stop 1', 'Stop 2'...; a
/// null rect leaves that stop's key unmounted.
Future<void> _pumpTour(
  WidgetTester tester,
  List<Rect?> targets, {
  VoidCallback? onDismiss,
  bool reducedMotion = false,
}) async {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final keys = [for (final _ in targets) GlobalKey()];
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
        child: child!,
      ),
      home: Scaffold(
        body: Stack(
          children: [
            for (final (i, rect) in targets.indexed)
              if (rect != null)
                Positioned.fromRect(
                  rect: rect,
                  child: SizedBox(key: keys[i]),
                ),
            Positioned.fill(
              child: CoachMarksOverlay(
                stops: [
                  for (final (i, key) in keys.indexed)
                    CoachMarkStop(
                      targetKey: key,
                      title: 'Stop ${i + 1}',
                      body: 'What this control does.',
                    ),
                ],
                onDismiss: onDismiss ?? () {},
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await _settle(tester);
}

/// The painted card, without its side margins.
Rect _card(WidgetTester tester, String title) => tester.getRect(
  find
      .ancestor(of: find.text(title), matching: find.byType(DecoratedBox))
      .first,
);

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.text('Next'));
  await _settle(tester);
  await tester.pump(const Duration(milliseconds: 300));
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

  testWidgets('the card sits in the third away from each control', (
    tester,
  ) async {
    await _pumpTour(tester, [_searchEntry, _outputSwitcher, _connectionDot]);

    // Shown in place on the first stop, with no slide from the centre.
    var card = _card(tester, 'Stop 1');
    expect(card.overlaps(_searchEntry.inflate(6)), isFalse);
    expect(card.top, greaterThanOrEqualTo(_phone.height * 2 / 3));

    await _next(tester);
    card = _card(tester, 'Stop 2');
    expect(card.overlaps(_outputSwitcher.inflate(6)), isFalse);
    expect(card.bottom, lessThanOrEqualTo(_phone.height / 3));

    await _next(tester);
    card = _card(tester, 'Stop 3');
    expect(card.overlaps(_connectionDot.inflate(6)), isFalse);
    expect(card.top, greaterThanOrEqualTo(_phone.height * 2 / 3));
  });

  testWidgets('with nothing to spotlight the card is centred', (tester) async {
    await _pumpTour(tester, [null]);

    final card = _card(tester, 'Stop 1');
    expect(card.center.dx, moreOrLessEquals(_phone.width / 2));
    expect(card.center.dy, moreOrLessEquals(_phone.height / 2));
  });

  testWidgets('the card slides between stops', (tester) async {
    await _pumpTour(tester, [_searchEntry, _outputSwitcher]);
    final start = _card(tester, 'Stop 1').top;

    await tester.tap(find.text('Next'));
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 110));
    final halfway = _card(tester, 'Stop 2').top;
    await tester.pump(const Duration(milliseconds: 200));
    final end = _card(tester, 'Stop 2').top;

    expect(halfway, lessThan(start));
    expect(halfway, greaterThan(end));
  });

  testWidgets('with reduced motion the card moves at once', (tester) async {
    await _pumpTour(tester, [
      _searchEntry,
      _outputSwitcher,
    ], reducedMotion: true);

    await tester.tap(find.text('Next'));
    await _settle(tester);

    expect(
      _card(tester, 'Stop 2').bottom,
      lessThanOrEqualTo(_phone.height / 3),
    );
  });

  testWidgets('tapping the scrim advances and Done ends the tour', (
    tester,
  ) async {
    var dismissed = 0;
    await _pumpTour(tester, [
      _searchEntry,
      _outputSwitcher,
    ], onDismiss: () => dismissed++);

    await tester.tapAt(const Offset(180, 150));
    await _settle(tester);
    expect(find.text('Stop 2'), findsOneWidget);
    expect(dismissed, 0);

    await tester.tap(find.text('Done'));
    await _settle(tester);
    expect(dismissed, 1);
  });

  testWidgets('Skip ends the tour', (tester) async {
    var dismissed = 0;
    await _pumpTour(tester, [
      _searchEntry,
      _outputSwitcher,
    ], onDismiss: () => dismissed++);

    await tester.tap(find.text('Skip'));
    await _settle(tester);
    expect(dismissed, 1);
    expect(find.text('Stop 2'), findsNothing);
  });
}
