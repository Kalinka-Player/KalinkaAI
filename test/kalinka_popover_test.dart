import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/kalinka_bottom_sheet.dart';
import 'package:kalinka/widgets/kalinka_button.dart';
import 'package:kalinka/widgets/kalinka_dialog.dart';
import 'package:kalinka/widgets/kalinka_centered_surface.dart';
import 'package:kalinka/widgets/kalinka_popover.dart';

const triggerKey = ValueKey('popup-trigger');
final reviewKey = GlobalKey();

class _RouteLocalizations extends DefaultMaterialLocalizations {
  const _RouteLocalizations();

  @override
  String get dialogLabel => 'Localized dialog';
}

class _RouteLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _RouteLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      SynchronousFuture(const _RouteLocalizations());

  @override
  bool shouldReload(_RouteLocalizationsDelegate old) => false;
}

Future<void> capture(WidgetTester tester, String name) async {
  final dir = Platform.environment['KALINKA_REVIEW_DIR'];
  if (dir == null) return;
  await tester.runAsync(() async {
    final boundary =
        reviewKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$dir/popup-$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void size(WidgetTester tester, Size value) {
  tester.view.physicalSize = value;
  tester.view.devicePixelRatio = 1;
}

Widget host({
  Alignment alignment = Alignment.topLeft,
  bool dialog = false,
  bool useBeak = true,
  List<LocalizationsDelegate<dynamic>> localizationsDelegates = const [],
  ValueChanged<String?>? onResult,
}) => RepaintBoundary(
  key: reviewKey,
  child: MaterialApp(
    localizationsDelegates: localizationsDelegates,
    theme: AppTheme.dark(),
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Align(
          alignment: alignment,
          child: Builder(
            builder: (context) => TextButton(
              key: triggerKey,
              onPressed: () async {
                final result = dialog
                    ? await showKalinkaDialog<String>(
                        context: context,
                        builder: (_) => KalinkaDialog(
                          side: KalinkaDialogSide.full,
                          title: 'Confirm',
                          content: const TextField(),
                        ),
                      )
                    : await showKalinkaBottomSheet<String>(
                        context: context,
                        useBeak: useBeak,
                        contentBuilder: (context) => Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SheetHeader(title: 'EDIT'),
                            const Padding(
                              padding: EdgeInsets.all(20),
                              child: TextField(),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, 'saved'),
                              child: const Text('Save'),
                            ),
                          ],
                        ),
                      );
                onResult?.call(result);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final (family, file) in [
      (KalinkaFonts.sansFamily, 'IBMPlexSans-Regular.ttf'),
      (KalinkaFonts.monoFamily, 'IBMPlexMono-Regular.ttf'),
    ]) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$file'))).load();
    }
    final material = File(
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (material.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(ByteData.sublistView(material.readAsBytesSync())),
          ))
          .load();
    }
  });
  for (final useBeak in [false, true]) {
    testWidgets(
      '${useBeak ? 'beaked picker' : 'settings dialog'} announces a localized route across resizing',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          addTearDown(tester.view.reset);
          size(tester, const Size(390, 844));
          await tester.pumpWidget(
            host(
              useBeak: useBeak,
              localizationsDelegates: const [_RouteLocalizationsDelegate()],
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();

          final route = find.bySemanticsLabel('Localized dialog');
          for (final window in [
            const Size(390, 844),
            const Size(1200, 800),
            const Size(390, 844),
          ]) {
            size(tester, window);
            await tester.pumpAndSettle();
            expect(route, findsOneWidget);
            expect(
              tester.getSemantics(route),
              matchesSemantics(
                label: 'Localized dialog',
                scopesRoute: true,
                namesRoute: true,
                textDirection: TextDirection.ltr,
              ),
            );
            expect(find.bySemanticsLabel('Save'), findsOneWidget);
          }

          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(route, findsNothing);
          expect(find.bySemanticsLabel('Open'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  for (final alignment in [
    Alignment.topLeft,
    Alignment.topCenter,
    Alignment.topRight,
    Alignment.bottomLeft,
    Alignment.bottomCenter,
    Alignment.bottomRight,
  ]) {
    testWidgets('wide popup points toward $alignment and stays on screen', (
      tester,
    ) async {
      size(tester, const Size(1200, 800));
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(alignment: alignment));
      final trigger = tester.getRect(find.byKey(triggerKey));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final surface = find.byKey(KalinkaAnchoredSurface.surfaceKey);
      expect(surface, findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        tester.widget<ModalBarrier>(find.byType(ModalBarrier).last).color?.a ??
            0,
        0,
      );
      final bounds = tester.getRect(surface);
      expect(bounds.left, greaterThanOrEqualTo(12));
      expect(bounds.right, lessThanOrEqualTo(1188));
      expect(bounds.top, greaterThanOrEqualTo(12));
      expect(bounds.bottom, lessThanOrEqualTo(788));
      expect(bounds.overlaps(trigger), isFalse);
      expect(
        tester.widget<Material>(surface).shape,
        isA<KalinkaPopoverBorder>(),
      );
      final shape = tester.widget<Material>(surface).shape!;
      final path = shape.getOuterPath(Offset.zero & bounds.size);
      // At each side the beak reaches toward the trigger; immediately beside
      // its narrow tip is empty space, rather than a rectangular card edge.
      final horizontal = alignment.x != 0;
      final tip = horizontal
          ? Offset(
              alignment.x < 0 ? 1 : bounds.width - 1,
              trigger.center.dy - bounds.top,
            )
          : Offset(
              trigger.center.dx - bounds.left,
              alignment.y < 0 ? 1 : bounds.height - 1,
            );
      expect(path.contains(tip), isTrue);
      expect(
        path.contains(
          tip + (horizontal ? const Offset(0, 14) : const Offset(14, 0)),
        ),
        isFalse,
      );
      await capture(tester, alignment.toString());
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(600, 400));
      await tester.pumpAndSettle();
      // The chosen point may be inside a tall popup; Escape always dismisses.
      if (find.byType(KalinkaAnchoredSurface).evaluate().isNotEmpty) {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }
      expect(find.byType(KalinkaAnchoredSurface), findsNothing);
    });
  }

  testWidgets('phone sheet drags closed and a wide popup returns its result', (
    tester,
  ) async {
    size(tester, const Size(390, 844));
    addTearDown(tester.view.reset);
    final results = <String?>[];
    await tester.pumpWidget(host(onResult: results.add));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      tester.widget<ModalBarrier>(find.byType(ModalBarrier).last).color!.a,
      closeTo(0.6, 0.01),
    );
    await capture(tester, 'phone');
    await tester.fling(find.text('EDIT'), const Offset(0, 400), 1200);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(results, [null]);
    size(tester, const Size(1000, 800));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(results, [null, 'saved']);
  });

  testWidgets(
    'confirmation from a narrow pane centers in the whole window after async work',
    (tester) async {
      size(tester, const Size(1200, 800));
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Builder(
              builder: (pageContext) => Align(
                alignment: Alignment.topRight,
                child: SizedBox(
                  width: 240,
                  child: KalinkaButton(
                    key: triggerKey,
                    label: 'Open',
                    onTap: () async {
                      await Future<void>.delayed(Duration.zero);
                      if (!pageContext.mounted) return;
                      await showKalinkaDialog<void>(
                        context: pageContext,
                        builder: (_) => const KalinkaDialog(
                          side: KalinkaDialogSide.full,
                          title: 'Async confirmation',
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final surface = find.byKey(KalinkaDialog.cardKey);
      expect(surface, findsOneWidget);
      expect(find.byType(KalinkaAnchoredSurface), findsNothing);
      expect(tester.getRect(surface).center, const Offset(600, 400));
      expect(
        tester
            .widget<ColoredBox>(
              find.byKey(const ValueKey('kalinka-dialog-scrim')),
            )
            .color
            .a,
        closeTo(0.6, 0.01),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('large text popup avoids keyboard and opens without motion', (
    tester,
  ) async {
    size(tester, const Size(1200, 800));
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.pumpWidget(host());
    await tester.tap(find.text('Open'));
    await tester.pump();
    final surface = find.byKey(KalinkaAnchoredSurface.surfaceKey);
    expect(surface, findsOneWidget);
    expect(tester.getRect(surface).bottom, lessThanOrEqualTo(468));
    expect(find.text('Save').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    await capture(tester, 'keyboard-large-text');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(surface, findsNothing);
  });

  testWidgets(
    'settings sheet becomes centered and dimmed while preserving edits',
    (tester) async {
      size(tester, const Size(390, 844));
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(useBeak: false));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Keep my settings');
      size(tester, const Size(1200, 800));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(KalinkaAnchoredSurface), findsNothing);
      final surface = find.byKey(KalinkaCenteredSurface.surfaceKey);
      expect(tester.getRect(surface).center, const Offset(600, 400));
      expect(
        tester.widget<ModalBarrier>(find.byType(ModalBarrier).last).color!.a,
        closeTo(0.6, 0.01),
      );
      expect(find.text('Keep my settings'), findsOneWidget);
      await capture(tester, 'centered-settings');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(surface, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final dialog in [false, true]) {
    testWidgets(
      '${dialog ? 'dialog' : 'sheet'} preserves input across layout changes',
      (tester) async {
        size(tester, const Size(390, 844));
        addTearDown(tester.view.reset);
        await tester.pumpWidget(host(dialog: dialog));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Unsaved edit');
        size(tester, const Size(1200, 800));
        await tester.pumpAndSettle();
        expect(
          find.byType(KalinkaAnchoredSurface),
          dialog ? findsNothing : findsOneWidget,
        );
        expect(find.text('Unsaved edit'), findsOneWidget);
        if (!dialog) {
          expect(
            tester
                    .widget<ModalBarrier>(find.byType(ModalBarrier).last)
                    .color
                    ?.a ??
                0,
            0,
          );
        }
        // A phone on its side retains the mobile presentation.
        size(tester, const Size(812, 375));
        await tester.pumpAndSettle();
        expect(find.byType(KalinkaAnchoredSurface), findsNothing);
        expect(find.text('Unsaved edit'), findsOneWidget);
        if (!dialog) {
          expect(
            tester
                .widget<ModalBarrier>(find.byType(ModalBarrier).last)
                .color
                ?.a,
            closeTo(0.6, 0.01),
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
