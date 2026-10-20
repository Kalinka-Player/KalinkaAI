import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/widgets/kalinka_button.dart';
import 'package:kalinka/widgets/kalinka_dialog.dart';

// Every dialog in the app renders through KalinkaDialog, so its placement is
// pinned down here: the window on phone, the panel it belongs to on tablet,
// and re-homed live when the window crosses the breakpoint while the dialog
// is open.

const _card = KalinkaDialog.cardKey;

Widget _host(KalinkaDialogSide side) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (ctx) => Center(
        child: ElevatedButton(
          onPressed: () => showKalinkaDialog<void>(
            context: ctx,
            builder: (_) => KalinkaDialog(
              side: side,
              icon: Icons.delete_outline,
              title: 'Dialog title',
              message: 'Dialog body',
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

Future<void> _open(WidgetTester tester, KalinkaDialogSide side) async {
  await tester.pumpWidget(_host(side));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _resizeTo(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  testWidgets('phone width: the card spans the window', (tester) async {
    await _resizeTo(tester, const Size(400, 800));
    await _open(tester, KalinkaDialogSide.browsing);

    final rect = tester.getRect(find.byKey(_card));
    expect(rect.left, 20);
    expect(rect.right, 380);
  });

  testWidgets('narrow desktop width: the card centres at its cap', (
    tester,
  ) async {
    // Default test window is 800x600: rail and browsing with a mini-player.
    await _open(tester, KalinkaDialogSide.browsing);

    final rect = tester.getRect(find.byKey(_card));
    expect(rect.left, 210);
    expect(rect.right, 670);
  });

  testWidgets('tablet width: a browsing dialog sits in the browsing pane', (
    tester,
  ) async {
    await _resizeTo(tester, const Size(1200, 800));
    await _open(tester, KalinkaDialogSide.browsing);

    // Capped at 460 and centred in the browsing pane (80..839).
    final rect = tester.getRect(find.byKey(_card));
    expect(rect.left, closeTo(229.5, 0.01));
    expect(rect.right, closeTo(689.5, 0.01));
  });

  testWidgets('tablet width: a player dialog sits in the player pane', (
    tester,
  ) async {
    await _resizeTo(tester, const Size(1200, 800));
    await _open(tester, KalinkaDialogSide.player);

    // The player's pane is the right 360dp here, so the card fills it to its
    // margins.
    final rect = tester.getRect(find.byKey(_card));
    expect(rect.left, 860);
    expect(rect.right, 1180);
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

  testWidgets(
    'an open dialog re-homes when the window crosses the breakpoint',
    (tester) async {
      await _resizeTo(tester, const Size(1200, 800));
      await _open(tester, KalinkaDialogSide.browsing);
      expect(tester.getRect(find.byKey(_card)).left, closeTo(229.5, 0.01));

      // Split → rail and browsing: the card centres beside the rail.
      await _resizeTo(tester, const Size(800, 800));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(_card)).center.dx, 440);

      // Phone → tablet: back into the browsing pane.
      await _resizeTo(tester, const Size(1200, 800));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byKey(_card));
      expect(rect.left, closeTo(229.5, 0.01));
      expect(rect.right, closeTo(689.5, 0.01));
    },
  );

  testWidgets('tapping the undimmed panel dismisses the dialog', (
    tester,
  ) async {
    await _resizeTo(tester, const Size(1200, 800));
    await _open(tester, KalinkaDialogSide.browsing);

    await tester.tapAt(const Offset(1000, 400)); // player pane, no scrim
    await tester.pumpAndSettle();
    expect(find.byKey(_card), findsNothing);
  });

  testWidgets('tapping the card itself keeps the dialog open', (tester) async {
    await _open(tester, KalinkaDialogSide.browsing);

    await tester.tapAt(tester.getCenter(find.byKey(_card)));
    await tester.pumpAndSettle();
    expect(find.byKey(_card), findsOneWidget);
  });
}
