import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/widgets/kalinka_bottom_sheet.dart';
import 'package:kalinka/widgets/sheet_anchor.dart';

// showModalBottomSheet positions sheets against the whole window (M3 caps
// them at 640px and centres them). SheetAnchor pins sheets launched from a
// tablet panel to that panel's horizontal bounds instead — these tests pin
// down the geometry and the tap-outside dismiss on the uncovered side.

const _sheetKey = Key('sheet_content');

Widget _host({required bool anchored}) {
  Widget openButton = Builder(
    builder: (ctx) => Center(
      child: ElevatedButton(
        onPressed: () => showKalinkaBottomSheet<void>(
          context: ctx,
          contentBuilder: (_) => const SizedBox(key: _sheetKey, height: 120),
        ),
        child: const Text('open'),
      ),
    ),
  );
  if (anchored) openButton = SheetAnchor(child: openButton);
  return MaterialApp(
    home: Scaffold(
      body: Row(
        children: [
          Expanded(child: openButton),
          const Expanded(child: SizedBox.expand()),
        ],
      ),
    ),
  );
}

void main() {
  // Default test window is 800x600 — the anchored panel is the left 400px.
  testWidgets('sheet launched inside a SheetAnchor spans the panel', (
    tester,
  ) async {
    await tester.pumpWidget(_host(anchored: true));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byKey(_sheetKey));
    expect(rect.left, 0);
    expect(rect.right, 400);
  });

  testWidgets('a sheet over a wide panel keeps to its width, centred', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(anchored: true));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The panel is the left 1000.
    final rect = tester.getRect(find.byKey(_sheetKey));
    expect(rect.width, kSheetMaxWidth);
    expect(rect.center.dx, 500);
  });

  testWidgets('tap beside the anchored sheet still dismisses it', (
    tester,
  ) async {
    await tester.pumpWidget(_host(anchored: true));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Right of the panel, at sheet height — the dismiss zone behind the
    // sheet must close it, mirroring the barrier above.
    await tester.tapAt(const Offset(600, 590));
    await tester.pumpAndSettle();
    expect(find.byKey(_sheetKey), findsNothing);
  });

  testWidgets('anchored sheet tracks the panel across window resizes', (
    tester,
  ) async {
    await tester.pumpWidget(_host(anchored: true));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.binding.setSurfaceSize(const Size(1000, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byKey(_sheetKey));
    expect(rect.left, 0);
    expect(rect.right, 500);
  });

  testWidgets('sheet without an anchor keeps the default placement', (
    tester,
  ) async {
    await tester.pumpWidget(_host(anchored: false));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // M3 default: 640px wide, centred in the 800px window.
    final rect = tester.getRect(find.byKey(_sheetKey));
    expect(rect.left, 80);
    expect(rect.right, 720);
  });
}
