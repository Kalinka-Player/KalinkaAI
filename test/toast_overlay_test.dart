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
Future<ProviderContainer> _pumpApp(WidgetTester tester, {Widget? home}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundaryKey,
      child: UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: _navKey,
          builder: (_, child) => KalinkaToastHost(child: child!),
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
