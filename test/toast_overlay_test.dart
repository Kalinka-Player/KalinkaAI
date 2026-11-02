// A toast answers something the user just did, so it has to be legible, and
// visible, where they did it — including on top of the route they did it from.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/providers/toast_provider.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/kalinka_toast_overlay.dart';

const _busy = 'Attic Pi is playing through another Kalinka server';
const _sheetColor = Color(0xFF00FF00);
const _boundaryKey = Key('boundary');
final _navKey = GlobalKey<NavigatorState>();

/// The app as [KalinkaApp] assembles it: the toast host wrapping the navigator.
Future<ProviderContainer> _pumpApp(
  WidgetTester tester, {
  Widget? home,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundaryKey,
      child: UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: _navKey,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: KalinkaToastHost(child: child!),
          ),
          home: home ?? const Scaffold(body: SizedBox.expand()),
        ),
      ),
    ),
  );
  return container;
}

/// Runs out the display timer a toast leaves behind, which would otherwise
/// fail the test as still pending once the tree is gone.
Future<void> _retireToast(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 10));

/// The card a toast is drawn on — its outermost decorated ancestor.
Finder _card(String message) => find
    .ancestor(of: find.text(message), matching: find.byType(Container))
    .first;

BoxDecoration _cardDecoration(WidgetTester tester, String message) =>
    tester.widget<Container>(_card(message)).decoration! as BoxDecoration;

/// The colour actually on screen at [at], read back off the rendered frame.
/// Widget-tree position proves nothing about what covers what.
Future<int> _pixelAt(WidgetTester tester, Offset at) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundaryKey),
  );
  late final ByteData? data;
  late final int width;
  // toImage never completes under the test's fake async.
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage();
    width = image.width;
    data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  });
  final rgba = data!.buffer.asUint8List();
  final i = ((at.dy.round() * width) + at.dx.round()) * 4;
  return (0xFF << 24) | (rgba[i] << 16) | (rgba[i + 1] << 8) | rgba[i + 2];
}

void main() {
  testWidgets('notifications stay capped and right-aligned as panes resize', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final toasts = await _pumpApp(tester);
    toasts
        .read(toastProvider.notifier)
        .show('Service unavailable', isError: true);
    toasts.read(toastProvider.notifier).show('Queue cleared');

    for (final size in [
      const Size(800, 600),
      const Size(375, 812),
      const Size(333, 600),
      const Size(332, 600), // Exactly the cap plus both 16dp gutters.
      const Size(320, 600),
      const Size(812, 375), // Landscape phone, without the navigation rail.
      const Size(1440, 900), // Toast belongs to browsing in the split layout.
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();

      final right = size.width == 1440 ? 987.0 : size.width - 16;
      final width = size.width < 332 ? size.width - 32 : 300.0;
      for (final message in ['Service unavailable', 'Queue cleared']) {
        final rect = tester.getRect(_card(message));
        expect(rect.width, width, reason: '$message at $size');
        expect(rect.right, right, reason: '$message at $size');
        if (size.width <= 332) expect(rect.left, 16);
      }
      expect(tester.takeException(), isNull);
    }
    await _retireToast(tester);
  });

  testWidgets('player-pane notifications use the same cap and right gutter', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final toasts = await _pumpApp(
      tester,
      home: const Scaffold(
        body: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: 432,
            child: Stack(
              children: [
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 24,
                  child: KalinkaToastOverlay(
                    isTablet: true,
                    scope: ToastScope.panel,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    toasts
        .read(toastProvider.notifier)
        .show(_busy, isError: true, inPanel: true);
    await tester.pumpAndSettle();

    expect(find.text(_busy), findsOneWidget);
    final rect = tester.getRect(_card(_busy));
    expect(rect.width, 300);
    expect(rect.right, 1420);
    expect(tester.takeException(), isNull);
    await _retireToast(tester);
  });

  testWidgets('queue activity stays compact but long messages obey the cap', (
    tester,
  ) async {
    final toasts = await _pumpApp(tester);
    toasts.read(toastProvider.notifier).beginQueueActivity('Adding…');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final compact = tester.getRect(_card('Adding…'));
    expect(compact.width, lessThan(300));
    expect(compact.right, 784);

    toasts.read(toastProvider.notifier).endQueueActivity(_busy, isError: true);
    await tester.pumpAndSettle();

    final wrapped = tester.getRect(_card(_busy));
    expect(wrapped.width, 300);
    expect(wrapped.right, compact.right);
    expect(wrapped.height, greaterThan(compact.height));
    expect(tester.takeException(), isNull);
    await _retireToast(tester);
  });

  testWidgets('a narrow notification wraps enlarged text without clipping', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final toasts = await _pumpApp(tester, textScaler: TextScaler.linear(2));
    toasts.read(toastProvider.notifier).show(_busy, isError: true);
    await tester.pumpAndSettle();

    final rect = tester.getRect(_card(_busy));
    final paragraph = tester.renderObject<RenderParagraph>(find.text(_busy));
    expect(rect.width, 288);
    expect(rect.right, 304);
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(rect.contains(tester.getRect(find.text(_busy)).bottomRight), isTrue);
    expect(tester.takeException(), isNull);
    await _retireToast(tester);
  });

  testWidgets('a toast raised behind a covering route paints over it', (
    tester,
  ) async {
    final toasts = await _pumpApp(tester);

    // The phone's Now Playing sheet, pared back to a route covering the
    // screen. Edge to edge, as that sheet is, so the sample lands on it
    // rather than beside it.
    showModalBottomSheet<void>(
      context: _navKey.currentContext!,
      isScrollControlled: true,
      backgroundColor: _sheetColor,
      constraints: const BoxConstraints(maxWidth: double.infinity),
      builder: (_) => const SizedBox.expand(),
    );
    await tester.pumpAndSettle();

    toasts.read(toastProvider.notifier).show(_busy, isError: true);
    await tester.pumpAndSettle();

    // Inside the card but clear of its border, glyph and text.
    final rect = tester.getRect(_card(_busy));
    expect(
      await _pixelAt(tester, Offset(rect.center.dx, rect.top + 4)),
      KalinkaColors.actionDeleteSurface.toARGB32(),
      reason: 'the sheet is painted over the toast',
    );
    await _retireToast(tester);
  });

  testWidgets('a failure does not look like every other toast', (tester) async {
    final toasts = await _pumpApp(tester);

    toasts.read(toastProvider.notifier).show(_busy, isError: true);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(
      _cardDecoration(tester, _busy).color,
      KalinkaColors.actionDeleteSurface,
    );
    await _retireToast(tester);
  });

  // MaterialApp's fallback for text with no Material in scope sets a
  // decoration our own style does not override, so it survives the merge.
  testWidgets('toast text is styled, not left to the debug fallback', (
    tester,
  ) async {
    final toasts = await _pumpApp(tester);

    toasts.read(toastProvider.notifier).show(_busy, isError: true);
    await tester.pumpAndSettle();

    final span =
        tester.renderObject<RenderParagraph>(find.text(_busy)).text as TextSpan;
    expect(span.style?.decoration ?? TextDecoration.none, TextDecoration.none);
    expect(span.style?.fontFamily, KalinkaFonts.sansFamily);
    await _retireToast(tester);
  });

  testWidgets('taps go through a toast to whatever is under it', (
    tester,
  ) async {
    var taps = 0;
    final toasts = await _pumpApp(
      tester,
      home: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => taps++,
        child: const SizedBox.expand(),
      ),
    );

    toasts.read(toastProvider.notifier).show(_busy, isError: true);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(_card(_busy)));

    expect(taps, 1);
    await _retireToast(tester);
  });

  testWidgets('a toast\'s action runs and takes the toast away', (
    tester,
  ) async {
    var taps = 0;
    var actions = 0;
    final toasts = await _pumpApp(
      tester,
      home: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => taps++,
        child: const SizedBox.expand(),
      ),
    );

    toasts
        .read(toastProvider.notifier)
        .show(
          _busy,
          isError: true,
          action: ToastAction('Settings', () => actions++),
        );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(actions, 1);
    expect(taps, 0, reason: 'the action is not also a tap on the screen');
    expect(find.text(_busy), findsNothing);
    await _retireToast(tester);
  });

  for (final scale in [2.0, 2.5]) {
    testWidgets(
      'Settings toast stays above the landscape mini-player at ${scale}x',
      (tester) async {
        const size = Size(812, 375);
        const message =
            "this output's sound card has no volume control of its own";
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);
        final container = await _pumpApp(
          tester,
          textScaler: TextScaler.linear(scale),
        );
        final inset = kalinkaMiniPlayerHeight(
          tester.element(find.byType(KalinkaToastHost)),
        );
        container.read(toastBottomInsetProvider.notifier).set(inset);
        var actions = 0;
        container
            .read(toastProvider.notifier)
            .show(
              message,
              isError: true,
              action: ToastAction('Settings', () => actions++),
            );
        await tester.pumpAndSettle();

        final card = tester.getRect(_card(message));
        final action = tester.getRect(find.text('Settings'));
        expect(card.width, 300);
        expect(card.top, greaterThanOrEqualTo(8));
        expect(card.bottom, lessThanOrEqualTo(size.height - inset - 8));
        expect(card.contains(action.topLeft), isTrue);
        expect(card.contains(action.bottomRight), isTrue);
        expect(find.text('Settings').hitTestable(), findsOneWidget);

        // A long explanation can scroll inside its card without moving the
        // recovery action off-screen.
        final scroll = find.descendant(
          of: _card(message),
          matching: find.byType(SingleChildScrollView),
        );
        await tester.drag(scroll, const Offset(0, -200));
        await tester.pumpAndSettle();
        expect(tester.getRect(find.text('Settings')), action);
        await tester.tap(find.text('Settings'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(actions, 1);
        expect(find.text(message), findsNothing);
        expect(tester.takeException(), isNull);
        await _retireToast(tester);
      },
    );
  }

  testWidgets('a success toast keeps the quiet surface and its dot', (
    tester,
  ) async {
    final toasts = await _pumpApp(tester);

    toasts.read(toastProvider.notifier).show('Queue cleared');
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    expect(
      _cardDecoration(tester, 'Queue cleared').color,
      KalinkaColors.surfaceElevated,
    );
    await _retireToast(tester);
  });
}
