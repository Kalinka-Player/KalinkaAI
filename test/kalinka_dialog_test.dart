import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/widgets/kalinka_button.dart';
import 'package:kalinka/widgets/kalinka_dialog.dart';
import 'package:kalinka/widgets/kalinka_popover.dart';

// Dialogs stay centered in the whole window at every size,
// including when their caller belongs to a narrow pane.

const _card = KalinkaDialog.cardKey;

Widget _host(KalinkaDialogSide side, {bool iconBeside = false}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topCenter,
      child: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () => showKalinkaDialog<void>(
            context: ctx,
            builder: (_) => KalinkaDialog(
              side: side,
              icon: Icons.delete_outline,
              title: 'Dialog title',
              message: 'Dialog body',
              iconBeside: iconBeside,
              actions: [
                KalinkaButton(label: 'OK', fullWidth: true, onTap: () {}),
              ],
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ),
);

Future<void> _open(
  WidgetTester tester,
  KalinkaDialogSide side, {
  bool iconBeside = false,
}) async {
  await tester.pumpWidget(_host(side, iconBeside: iconBeside));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _resizeTo(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('phone width: the card spans the window', (tester) async {
    await _resizeTo(tester, const Size(400, 800));
    await _open(tester, KalinkaDialogSide.browsing);

    final rect = tester.getRect(find.byKey(_card));
    expect(rect.left, 20);
    expect(rect.right, 380);
    expect(rect.center, const Offset(200, 400));
  });

  testWidgets('narrow desktop width: the card centers at its cap', (
    tester,
  ) async {
    // Default test window is 800x600: rail and browsing with a mini-player.
    await _open(tester, KalinkaDialogSide.browsing);

    final rect = tester.getRect(find.byKey(_card));
    expect(rect.left, 170);
    expect(rect.right, 630);
    expect(rect.center, const Offset(400, 300));
  });

  testWidgets('tablet width: a browsing dialog uses the whole window', (
    tester,
  ) async {
    await _resizeTo(tester, const Size(1200, 800));
    await _open(tester, KalinkaDialogSide.browsing);

    // Capped at 460 and centered in the whole window.
    final rect = tester.getRect(find.byKey(_card));
    expect(rect.left, 370);
    expect(rect.right, 830);
    expect(rect.center, const Offset(600, 400));
  });

  testWidgets('tablet width: a player dialog uses the whole window', (
    tester,
  ) async {
    await _resizeTo(tester, const Size(1200, 800));
    await _open(tester, KalinkaDialogSide.player);

    expect(find.byType(KalinkaAnchoredSurface), findsNothing);
    final rect = tester.getRect(find.byKey(_card));
    expect(rect.left, 370);
    expect(rect.right, 830);
    expect(rect.center, const Offset(600, 400));
  });

  testWidgets('tablet width: a full-width dialog centres in the window', (
    tester,
  ) async {
    await _resizeTo(tester, const Size(1200, 800));
    await _open(tester, KalinkaDialogSide.full);

    final rect = tester.getRect(find.byKey(_card));
    expect(rect.left, 370);
    expect(rect.right, 830);
  });

  testWidgets('an open dialog stays centered across window sizes', (
    tester,
  ) async {
    await _resizeTo(tester, const Size(1200, 800));
    await _open(tester, KalinkaDialogSide.browsing);
    expect(tester.getRect(find.byKey(_card)).left, 370);

    // Phones keep the card centered too.
    await _resizeTo(tester, const Size(400, 800));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(_card)).center, const Offset(200, 400));
    expect(find.byType(KalinkaAnchoredSurface), findsNothing);

    // Phone → tablet: remains centered.
    await _resizeTo(tester, const Size(1200, 800));
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byKey(_card));
    expect(rect.left, 370);
    expect(rect.right, 830);
    expect(rect.center, const Offset(600, 400));
  });

  testWidgets('tapping outside the centered dialog dismisses it', (
    tester,
  ) async {
    await _resizeTo(tester, const Size(1200, 800));
    await _open(tester, KalinkaDialogSide.browsing);

    await tester.tapAt(const Offset(1000, 400)); // Outside the card
    await tester.pumpAndSettle();
    expect(find.byKey(_card), findsNothing);
  });

  testWidgets('tapping the card itself keeps the dialog open', (tester) async {
    await _open(tester, KalinkaDialogSide.browsing);

    await tester.tapAt(tester.getCenter(find.byKey(_card)));
    await tester.pumpAndSettle();
    expect(find.byKey(_card), findsOneWidget);
  });

  testWidgets('the icon tile stands above the title by default', (
    tester,
  ) async {
    await _open(tester, KalinkaDialogSide.browsing);

    expect(
      tester.getRect(find.byIcon(Icons.delete_outline)).bottom,
      lessThan(tester.getRect(find.text('Dialog title')).top),
    );
  });

  testWidgets('beside, the icon leads the title and message, stacked', (
    tester,
  ) async {
    await _open(tester, KalinkaDialogSide.browsing, iconBeside: true);

    final tile = tester.getRect(find.byIcon(Icons.delete_outline));
    final title = tester.getRect(find.text('Dialog title'));
    final body = tester.getRect(find.text('Dialog body'));
    expect(title.left, greaterThan(tile.right));
    expect(body.left, title.left);
    expect(body.top, greaterThanOrEqualTo(title.bottom));
  });
}
