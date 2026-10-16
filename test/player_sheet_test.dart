import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/mini_player.dart';
import 'package:kalinka/widgets/now_playing_content.dart';
import 'package:kalinka/widgets/player_header.dart';
import 'package:kalinka/widgets/player_queue_view.dart';
import 'package:kalinka/widgets/player_view_switch.dart';

import 'support/home_shell.dart';

final _surface = find.ancestor(
  of: find.byType(NowPlayingContent),
  matching: find.byWidgetPredicate(
    (widget) => widget is Material && widget.color == KalinkaColors.background,
  ),
);

final _handle = find.descendant(
  of: find.byType(PlayerHeader),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Container &&
        widget.constraints ==
            const BoxConstraints.tightFor(width: 40, height: 4),
  ),
);

final _statusBar = find.byWidgetPredicate(
  (widget) =>
      widget is AnnotatedRegion<SystemUiOverlayStyle> &&
      widget.value.systemStatusBarContrastEnforced == false,
);

Future<void> _pumpPhone(
  WidgetTester tester, {
  Size size = const Size(375, 812),
  double topInset = 44,
}) async {
  await pumpHomeShell(tester, queue: SettableQueue(queueOf(4)), size: size);
  final insets = FakeViewPadding(top: topInset, bottom: 24);
  tester.view.padding = insets;
  tester.view.viewPadding = insets;
  await tester.pump();
}

void _expectNoStripAboveHandle(WidgetTester tester) {
  expect(
    tester.getTopLeft(_handle).dy - tester.getTopLeft(_surface).dy,
    closeTo(8, .01),
    reason: 'Only the header padding should move above the handle.',
  );
}

void _expectStatusBackground(WidgetTester tester, double height) {
  expect(tester.getRect(_statusBar), Rect.fromLTWH(0, 0, 375, height));
  final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
    _statusBar,
  );
  expect((region.child as ColoredBox).color, KalinkaColors.background);
  expect(region.value.statusBarColor, Colors.transparent);
  expect(region.value.statusBarIconBrightness, Brightness.light);
  expect(region.value.statusBarBrightness, Brightness.dark);
}

void main() {
  for (final scenario in [
    (size: const Size(375, 812), topInset: 44.0),
    (size: const Size(375, 812), topInset: 0.0),
    (size: const Size(812, 375), topInset: 24.0),
  ]) {
    testWidgets('sheet opens without a leading strip at ${scenario.size} '
        'with ${scenario.topInset} top inset', (tester) async {
      await _pumpPhone(
        tester,
        size: scenario.size,
        topInset: scenario.topInset,
      );
      await tester.tap(find.byType(MiniPlayer));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      expect(tester.getTopLeft(_surface).dy, greaterThan(scenario.topInset));
      _expectNoStripAboveHandle(tester);
      expect(_statusBar, findsNothing);
      final contentState = tester.state(find.byType(NowPlayingContent));

      await tester.pumpAndSettle();
      expect(tester.getTopLeft(_handle).dy, scenario.topInset + 8);
      _expectNoStripAboveHandle(tester);
      expect(tester.state(find.byType(NowPlayingContent)), same(contentState));
      if (scenario.topInset > 0) {
        expect(
          tester.getRect(_statusBar),
          Rect.fromLTWH(0, 0, scenario.size.width, scenario.topInset),
        );
      } else {
        expect(_statusBar, findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('status background follows expansion and queue drag state', (
    tester,
  ) async {
    await _pumpPhone(tester);
    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();
    _expectStatusBackground(tester, 44);

    await tester.tap(
      find.descendant(
        of: find.byType(PlayerViewSwitch),
        matching: find.text('QUEUE'),
      ),
    );
    await tester.pumpAndSettle();
    final miniPlayer = find.descendant(
      of: find.byType(QueueMiniPlayer),
      matching: find.byType(MiniPlayer),
    );
    final miniPlayerRect = tester.getRect(miniPlayer);
    final gesture = await tester.startGesture(tester.getCenter(_handle));
    await gesture.moveBy(const Offset(0, 24));
    await tester.pump();
    final handleTop = tester.getTopLeft(_handle).dy;
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.getTopLeft(_handle).dy, closeTo(handleTop + 100, .01));
    _expectNoStripAboveHandle(tester);
    expect(_statusBar, findsNothing);
    expect(tester.getRect(miniPlayer), miniPlayerRect);

    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(_handle).dy, 52);
    _expectStatusBackground(tester, 44);

    await tester.tap(find.byTooltip('Minimise player'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    _expectNoStripAboveHandle(tester);
    expect(_statusBar, findsNothing);
    expect(tester.getRect(miniPlayer), miniPlayerRect);

    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingContent), findsNothing);
    expect(_statusBar, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
