import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/coach_marks_overlay.dart';
import 'package:kalinka/widgets/kalinka_button.dart';

/// Hosts the tour over three targets and can drop the middle one, the way a
/// server without renderers drops the output switcher's stop.
class _Host extends StatefulWidget {
  final Rect middle;

  const _Host({this.middle = const Rect.fromLTWH(20, 140, 40, 40)});

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
            Positioned.fromRect(
              rect: widget.middle,
              child: SizedBox(key: _middle),
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

/// The spotlight pulses forever, so pumpAndSettle would never return, and a
/// target that isn't there is looked for again over a few frames.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump();
  }
}

const _phone = Size(360, 800);
const _landscape = Size(800, 360);

// Where the Home tour's controls sit on a phone.
const _searchEntry = Rect.fromLTWH(16, 340, 328, 48);
const _outputSwitcher = Rect.fromLTWH(300, 740, 44, 44);
const _connectionDot = Rect.fromLTWH(320, 14, 28, 28);

// And on a phone held sideways.
const _wideSearchEntry = Rect.fromLTRB(112.5, 119, 687.5, 173);
const _landscapeSwitcher = Rect.fromLTWH(740, 306, 44, 44);
const _landscapeDot = Rect.fromLTWH(700, 14, 28, 28);

const _longBody =
    'Search from here — by name, or by describing what you want, like '
    '“mellow late-night jazz”, when smart search is on. Nothing plays until '
    'you add it.';

/// The cutout around a target.
Rect _hole(Rect target) => target.inflate(6);

/// The pulse's full reach: the cutout's 6, the ring's 22 and its glow's 10.
Rect _pulse(Rect target) => target.inflate(38);

/// The tour, one stop per rect, titled 'Stop 1', 'Stop 2'...; a null rect
/// leaves that stop's key unmounted. The returned notifier moves the targets.
Future<ValueNotifier<List<Rect?>>> _pumpTour(
  WidgetTester tester,
  List<Rect?> targets, {
  Size size = _phone,
  double textScale = 1,
  String body = 'What this control does.',
  VoidCallback? onDismiss,
  bool reducedMotion = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final placed = ValueNotifier(targets);
  addTearDown(placed.dispose);
  final keys = [for (final _ in targets) GlobalKey()];
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reducedMotion,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: ValueListenableBuilder(
          valueListenable: placed,
          builder: (context, targets, _) => Stack(
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
                        body: body,
                      ),
                  ],
                  onDismiss: onDismiss ?? () {},
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  return placed;
}

/// The painted card.
Rect _card(WidgetTester tester, String title) => tester.getRect(
  find
      .ancestor(of: find.text(title), matching: find.byType(DecoratedBox))
      .first,
);

bool _inside(Rect outer, Rect inner) =>
    inner.left >= outer.left &&
    inner.top >= outer.top &&
    inner.right <= outer.right &&
    inner.bottom <= outer.bottom;

/// Skip and Next or Done sit whole inside the card, and the card on screen.
void _expectControlsShown(WidgetTester tester, Rect card, Size window) {
  expect(_inside(Offset.zero & window, card), isTrue, reason: 'card $card');
  for (final control in [find.text('Skip'), find.byType(KalinkaButton)]) {
    final rect = tester.getRect(control);
    expect(_inside(card, rect), isTrue, reason: '$rect in card $card');
  }
}

/// Lays its target out only from its third frame, as a control still
/// waiting on its own layout would.
class _LateTarget extends StatefulWidget {
  final GlobalKey targetKey;

  const _LateTarget({required this.targetKey});

  @override
  State<_LateTarget> createState() => _LateTargetState();
}

class _LateTargetState extends State<_LateTarget> {
  int _frames = 0;

  @override
  Widget build(BuildContext context) {
    final ready = _frames >= 3;
    if (!ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _frames++);
      });
    }
    return SizedBox(
      key: widget.targetKey,
      width: ready ? _searchEntry.width : 0,
      height: ready ? _searchEntry.height : 0,
    );
  }
}

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

  testWidgets('a stop dropped from under the card slides it to the next', (
    tester,
  ) async {
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const _Host(middle: _outputSwitcher));
    await _settle(tester);
    await _next(tester);
    final start = _card(tester, 'Choose where it plays').top;

    tester.state<_HostState>(find.byType(_Host)).dropMiddleStop();
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 110));
    final halfway = _card(tester, 'Your server lives here').top;
    await tester.pump(const Duration(milliseconds: 200));
    final end = _card(tester, 'Your server lives here').top;

    expect(halfway, greaterThan(start));
    expect(halfway, lessThan(end));
  });

  testWidgets('the card sits in the third away from each control', (
    tester,
  ) async {
    await _pumpTour(tester, [_searchEntry, _outputSwitcher, _connectionDot]);

    // Shown in place on the first stop, with no slide from the centre.
    var card = _card(tester, 'Stop 1');
    expect(card.overlaps(_pulse(_searchEntry)), isFalse);
    expect(card.top, greaterThanOrEqualTo(_phone.height * 2 / 3));

    await _next(tester);
    card = _card(tester, 'Stop 2');
    expect(card.overlaps(_pulse(_outputSwitcher)), isFalse);
    expect(card.bottom, lessThanOrEqualTo(_phone.height / 3));

    await _next(tester);
    card = _card(tester, 'Stop 3');
    expect(card.overlaps(_pulse(_connectionDot)), isFalse);
    expect(card.top, greaterThanOrEqualTo(_phone.height * 2 / 3));
  });

  testWidgets('a target laid out a few frames late still places the card', (
    tester,
  ) async {
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: _searchEntry.left,
                top: _searchEntry.top,
                child: _LateTarget(targetKey: key),
              ),
              Positioned.fill(
                child: CoachMarksOverlay(
                  stops: [
                    CoachMarkStop(
                      targetKey: key,
                      title: 'Stop 1',
                      body: 'What this control does.',
                    ),
                  ],
                  onDismiss: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );

    Rect? firstShown;
    for (var i = 0; i < 8 && firstShown == null; i++) {
      await tester.pump();
      if (find.text('Stop 1').evaluate().isNotEmpty) {
        firstShown = _card(tester, 'Stop 1');
      }
    }
    expect(firstShown, isNotNull);
    expect(firstShown!.top, greaterThanOrEqualTo(_phone.height * 2 / 3));
    expect(firstShown.overlaps(_pulse(_searchEntry)), isFalse);
  });

  testWidgets('in a short window the card goes beside a tall control', (
    tester,
  ) async {
    const control = Rect.fromLTWH(200, 120, 48, 120);
    await _pumpTour(tester, [control], size: _landscape);

    final card = _card(tester, 'Stop 1');
    expect(card.left, greaterThanOrEqualTo(_pulse(control).right));
    _expectControlsShown(tester, card, _landscape);
  });

  testWidgets('held sideways, each card keeps off the control it describes', (
    tester,
  ) async {
    await _pumpTour(
      tester,
      [_wideSearchEntry, _landscapeSwitcher, _landscapeDot],
      size: _landscape,
      body: _longBody,
    );

    // No side of the wide search entry has room for the whole pulse.
    var card = _card(tester, 'Stop 1');
    expect(card.overlaps(_hole(_wideSearchEntry)), isFalse);
    _expectControlsShown(tester, card, _landscape);

    await _next(tester);
    card = _card(tester, 'Stop 2');
    expect(card.overlaps(_pulse(_landscapeSwitcher)), isFalse);
    _expectControlsShown(tester, card, _landscape);

    await _next(tester);
    card = _card(tester, 'Stop 3');
    expect(card.overlaps(_pulse(_landscapeDot)), isFalse);
    _expectControlsShown(tester, card, _landscape);
  });

  testWidgets('on a narrow phone the card keeps off the control', (
    tester,
  ) async {
    const size = Size(280, 640);
    const entry = Rect.fromLTWH(16, 280, 248, 48);
    await _pumpTour(tester, [entry], size: size, body: _longBody);

    final card = _card(tester, 'Stop 1');
    expect(card.overlaps(_pulse(entry)), isFalse);
    _expectControlsShown(tester, card, size);
  });

  testWidgets('a window too small to keep clear still shows the buttons', (
    tester,
  ) async {
    await _pumpTour(
      tester,
      [_wideSearchEntry],
      size: _landscape,
      textScale: 2,
      body: _longBody,
    );

    _expectControlsShown(tester, _card(tester, 'Stop 1'), _landscape);
  });

  testWidgets('with nothing to spotlight the card is centred', (tester) async {
    await _pumpTour(tester, [null]);

    final card = _card(tester, 'Stop 1');
    expect(card.center.dx, moreOrLessEquals(_phone.width / 2));
    expect(card.center.dy, moreOrLessEquals(_phone.height / 2));
  });

  testWidgets('a centred card stays put between untargeted stops', (
    tester,
  ) async {
    await _pumpTour(tester, [_searchEntry, null, null]);
    await _next(tester);

    await tester.tap(find.text('Next'));
    await _settle(tester);
    final card = _card(tester, 'Stop 3');
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

  testWidgets('a target that moves mid-slide turns the card where it is', (
    tester,
  ) async {
    final targets = await _pumpTour(tester, [_searchEntry, _outputSwitcher]);
    await tester.tap(find.text('Next'));
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 110));
    final before = _card(tester, 'Stop 2').top;

    const moved = Rect.fromLTWH(300, 60, 44, 44);
    targets.value = [_searchEntry, moved];
    await tester.pump();
    await tester.pump();
    expect(_card(tester, 'Stop 2').top, moreOrLessEquals(before));

    await tester.pump(const Duration(milliseconds: 300));
    expect(_card(tester, 'Stop 2').overlaps(_pulse(moved)), isFalse);
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

  // Last in the file: loaded fonts stay for every test after them.
  group('in the bundled fonts', () {
    setUpAll(() async {
      for (final (family, files) in [
        (
          KalinkaFonts.sansFamily,
          ['IBMPlexSans-Regular.ttf', 'IBMPlexSans-Medium.ttf'],
        ),
        (KalinkaFonts.monoFamily, ['IBMPlexMono-SemiBold.ttf']),
      ]) {
        final loader = FontLoader(family);
        for (final file in files) {
          loader.addFont(rootBundle.load('assets/fonts/$file'));
        }
        await loader.load();
      }
    });

    testWidgets('with large text the body scrolls and the buttons stay', (
      tester,
    ) async {
      const size = Size(360, 640);
      const entry = Rect.fromLTRB(16, 237.5, 344, 291.5);
      await _pumpTour(
        tester,
        [entry],
        size: size,
        textScale: 2,
        body: _longBody,
      );

      final card = _card(tester, 'Stop 1');
      expect(card.overlaps(_pulse(entry)), isFalse);
      _expectControlsShown(tester, card, size);
      final body = tester.state<ScrollableState>(find.byType(Scrollable));
      expect(body.position.maxScrollExtent, greaterThan(0));
    });
  });
}
