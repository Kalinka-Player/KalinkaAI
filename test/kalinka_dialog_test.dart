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
    await _open(tester, KalinkaDialogSide.right);

    final rect = tester.getRect(find.byKey(_card));
    expect(rect.left, 20);
    expect(rect.right, 380);
  });

  testWidgets('narrow desktop width: the card centres at its cap', (
    tester,
  ) async {
    // Default test window is 800x600 — wider than the card, below the tablet
    // breakpoint, so there is no panel to pick.
    await _open(tester, KalinkaDialogSide.right);

    final rect = tester.getRect(find.byKey(_card));
    expect(rect.left, 170);
    expect(rect.right, 630);
  });

  testWidgets('tablet width: a right-side dialog sits in the right panel', (
    tester,
  ) async {
    await _resizeTo(tester, const Size(1200, 800));
    await _open(tester, KalinkaDialogSide.right);

    // Capped at 460 and centred in the browsing panel (415..1200).
    final rect = tester.getRect(find.byKey(_card));
    expect(rect.left, closeTo(577.5, 0.01));
    expect(rect.right, closeTo(1037.5, 0.01));
  });

  testWidgets('tablet width: a left-side dialog sits in the left panel', (
    tester,
  ) async {
    await _resizeTo(tester, const Size(1200, 800));
    await _open(tester, KalinkaDialogSide.left);

    // The player panel is 414 wide here, so the card fills it to its margins.
    final rect = tester.getRect(find.byKey(_card));
    expect(rect.left, 20);
    expect(rect.right, closeTo(394, 0.01));
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
      await _open(tester, KalinkaDialogSide.right);
      expect(tester.getRect(find.byKey(_card)).left, closeTo(577.5, 0.01));

      // Tablet → phone: the card re-centres on the (now single) layout rather
      // than staying pinned to a half that no longer exists.
      await _resizeTo(tester, const Size(800, 800));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(_card)).center.dx, 400);

      // Phone → tablet: back into the right panel.
      await _resizeTo(tester, const Size(1200, 800));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byKey(_card));
      expect(rect.left, closeTo(577.5, 0.01));
      expect(rect.right, closeTo(1037.5, 0.01));
    },
  );

  testWidgets('tapping the undimmed panel dismisses the dialog', (
    tester,
  ) async {
    await _resizeTo(tester, const Size(1200, 800));
    await _open(tester, KalinkaDialogSide.right);

    await tester.tapAt(const Offset(200, 400)); // left panel, no scrim
    await tester.pumpAndSettle();
    expect(find.byKey(_card), findsNothing);
  });

  testWidgets('tapping the card itself keeps the dialog open', (tester) async {
    await _open(tester, KalinkaDialogSide.right);

    await tester.tapAt(tester.getCenter(find.byKey(_card)));
    await tester.pumpAndSettle();
    expect(find.byKey(_card), findsOneWidget);
  });
}
