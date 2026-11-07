import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/widgets/kalinka_bottom_sheet.dart';
import 'package:kalinka/widgets/kalinka_centered_surface.dart';
import 'package:kalinka/widgets/kalinka_popover.dart';
import 'package:kalinka/widgets/sheet_anchor.dart';

// Phone sheets retain their panel anchor. Wider windows default to a dialog
// centered in the whole window, independent of the panel width.

const _sheetKey = Key('sheet_content');

Widget _host({required bool anchored}) {
  Widget openButton = Center(
    child: Builder(
      builder: (ctx) => ElevatedButton(
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
  void phone(WidgetTester tester, {double width = 600}) {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('sheet launched inside a SheetAnchor spans the panel', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(_host(anchored: true));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byKey(_sheetKey));
    expect(rect.left, 0);
    expect(rect.right, 300);
  });

  testWidgets('a wide window centers the dialog across both panes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(anchored: true));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(KalinkaAnchoredSurface), findsNothing);
    expect(find.byType(KalinkaCenteredSurface), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    // The caller is in the left pane, but its dialog centers in the window.
    final rect = tester.getRect(find.byKey(_sheetKey));
    expect(rect.width, kSheetMaxWidth);
    expect(rect.center, const Offset(1000, 400));
  });

  testWidgets('tap beside the anchored sheet still dismisses it', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(_host(anchored: true));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Right of the panel, at sheet height — the dismiss zone behind the
    // sheet must close it, mirroring the barrier above.
    await tester.tapAt(const Offset(500, 790));
    await tester.pumpAndSettle();
    expect(find.byKey(_sheetKey), findsNothing);
  });

  testWidgets('anchored sheet tracks the panel across window resizes', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(_host(anchored: true));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(700, 800);
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byKey(_sheetKey));
    expect(rect.left, 0);
    expect(rect.right, 350);
  });

  testWidgets('sheet without an anchor keeps the default placement', (
    tester,
  ) async {
    phone(tester, width: 700);
    await tester.pumpWidget(_host(anchored: false));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The 640dp sheet cap still centres a sheet in a 700dp phone layout.
    final rect = tester.getRect(find.byKey(_sheetKey));
    expect(rect.left, 30);
    expect(rect.right, 670);
  });
}
