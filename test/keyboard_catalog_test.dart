import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/providers/search_session_provider.dart';
import 'package:kalinka/providers/shell_nav_provider.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/mini_player.dart';
import 'package:kalinka/widgets/search/search_composer.dart';
import 'package:kalinka/widgets/search/search_session_view.dart';
import 'package:virtual_keypad/virtual_keypad.dart';

import 'support/home_shell.dart';

class _CatalogApi extends HomeApi {
  final filters = <String?>[];

  @override
  Future<BrowseItemsList> browse(
    String id, {
    int offset = 0,
    int limit = 10,
    String? filter,
  }) async {
    filters.add(filter);
    return BrowseItemsList(offset, limit, 0, const []);
  }
}

final _keyboard = find.byKey(const ValueKey('on-screen-keyboard'));
final _mini = find.byType(MiniPlayer);
final _field = find.byType(TextField);
const _capture = ValueKey('catalog-keyboard-capture');

Future<void> _focusFilter(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('catalog-bar-search'));
  if (button.evaluate().isNotEmpty) {
    await tester.tap(button);
  } else {
    await tester.tap(_field);
  }
  // Attach the TextInput client and let the host start clearing the bar.
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('catalogue input and keyboard survive window resizing', (
    tester,
  ) async {
    final container = await pumpHomeShell(
      tester,
      queue: SettableQueue(queueOf(2)),
      api: _CatalogApi(),
      size: const Size(1440, 900),
      onScreenKeyboard: true,
      reducedMotion: false,
    );
    container.read(playerViewProvider.notifier).show(PlayerView.queue);
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(
          id: 'kalinka:localfiles:catalog:albums',
          title: 'Albums',
          filters: const [
            FilterSpec(id: 'q', kind: FilterKind.text, label: 'Search albums'),
          ],
        );
    await tester.pumpAndSettle();
    await _focusFilter(tester);
    await tester.pumpAndSettle();
    await tester.enterText(_field, 'Mozart');
    final controller = tester.widget<TextField>(_field).controller!;
    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 4);

    for (final size in [
      const Size(1380, 800),
      const Size(1320, 800),
      const Size(1340, 800),
      const Size(1200, 800),
      const Size(800, 480),
      const Size(400, 800),
      const Size(1440, 900),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(_keyboard.hitTestable(), findsOneWidget, reason: '$size');
      expect(_mini.hitTestable(), findsNothing, reason: '$size');
      expect(tester.widget<TextField>(_field).controller, same(controller));
      expect(controller.text, 'Mozart');
      expect(
        controller.selection,
        const TextSelection(baseOffset: 1, extentOffset: 4),
      );
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );
      expect(container.read(searchSessionProvider).catalogFilter.text, isEmpty);
    }
    // Keys must still reach the original client and replace its selection.
    await tester.tap(
      find.descendant(
        of: find.byType(VirtualKeypad),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'a',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.text, 'Mart');
    await tester.tap(find.byKey(const ValueKey('keyboard-submit')));
    await tester.pumpAndSettle();
    expect(container.read(searchSessionProvider).catalogFilter.text, 'Mart');
    expect(_keyboard, findsNothing);
    await _focusFilter(tester);
    await tester.pumpAndSettle();
    expect(_keyboard.hitTestable(), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(400, 800);
    await tester.pumpAndSettle();
    expect(_keyboard, findsNothing);
    expect(_mini.hitTestable(), findsOneWidget);
    await tester.tap(_field);
    await tester.pumpAndSettle();
    expect(_keyboard.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('main search keyboard survives phone and tablet layout changes', (
    tester,
  ) async {
    final container = await pumpHomeShell(
      tester,
      queue: SettableQueue(queueOf(2)),
      size: const Size(1440, 900),
      onScreenKeyboard: true,
      reducedMotion: false,
    );
    container.read(homeSearchRequestProvider.notifier).request();
    await tester.pumpAndSettle();
    final field = find.descendant(
      of: find.byType(SearchComposer),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, 'Mozart');
    final editable = find.descendant(
      of: field,
      matching: find.byType(EditableText),
    );
    final inputState = tester.state(editable);
    for (final size in [
      const Size(800, 480),
      const Size(400, 800),
      const Size(1440, 900),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(_keyboard.hitTestable(), findsOneWidget, reason: '$size');
      expect(tester.widget<TextField>(field).controller!.text, 'Mozart');
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      expect(tester.state(editable), same(inputState));
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.byTooltip('Close search'));
    await tester.pumpAndSettle();
    expect(_keyboard, findsNothing);
  });

  for (final size in [
    const Size(400, 800),
    const Size(800, 480),
    const Size(1024, 600),
    const Size(1440, 900),
  ]) {
    testWidgets('catalogue keyboard clears and restores mini-player at $size', (
      tester,
    ) async {
      if (const bool.fromEnvironment('KEYBOARD_SCREENSHOT')) {
        await tester.runAsync(() async {
          await (FontLoader(KalinkaFonts.sansFamily)..addFont(
                rootBundle.load('assets/fonts/IBMPlexSans-Regular.ttf'),
              ))
              .load();
          await (FontLoader(KalinkaFonts.monoFamily)..addFont(
                rootBundle.load('assets/fonts/IBMPlexMono-Regular.ttf'),
              ))
              .load();
          await (FontLoader(KalinkaFonts.displayFamily)..addFont(
                rootBundle.load('assets/fonts/PlayfairDisplay-Regular.ttf'),
              ))
              .load();
          await (FontLoader(
            'KalinkaIcons',
          )..addFont(rootBundle.load('assets/fonts/KalinkaIcons.ttf'))).load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        });
      }
      final api = _CatalogApi();
      final container = await pumpHomeShell(
        tester,
        queue: SettableQueue(queueOf(2)),
        api: api,
        size: size,
        onScreenKeyboard: true,
        reducedMotion: false,
        themed: true,
        captureKey: _capture,
      );
      container.read(playerViewProvider.notifier).show(PlayerView.queue);
      container
          .read(searchSessionProvider.notifier)
          .openCatalog(
            id: 'kalinka:localfiles:catalog:albums',
            title: 'Albums',
            filters: const [
              FilterSpec(
                id: 'q',
                kind: FilterKind.text,
                label: 'Search albums',
              ),
            ],
          );
      await tester.pumpAndSettle();
      expect(_mini.hitTestable(), findsOneWidget);
      final originalBar = tester.getRect(_mini);
      final barriersBefore = find.byType(ModalBarrier).evaluate().length;

      await _focusFilter(tester);
      expect(container.read(searchEntryModeProvider), isFalse);
      await tester.pump(const Duration(milliseconds: 100));
      expect(_keyboard, findsNothing);
      expect(tester.getTopLeft(_mini).dy, greaterThan(originalBar.top));

      await tester.pump(kMiniPlayerHideDuration);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(_keyboard, findsOneWidget);
      expect(_mini.hitTestable(), findsNothing);
      final enteringTop = tester.getTopLeft(_keyboard).dy;
      expect(
        enteringTop,
        greaterThan(size.height - tester.getSize(_keyboard).height),
      );
      expect(enteringTop, lessThan(size.height));
      await tester.pumpAndSettle();
      final openTop = tester.getTopLeft(_keyboard).dy;
      expect(
        tester.getSize(_keyboard).height,
        lessThanOrEqualTo(size.height * 0.37),
      );
      expect(openTop, lessThan(enteringTop));
      expect(tester.getBottomRight(_keyboard).dy, size.height);
      // The catalogue still fills the window behind the floating panel, so its
      // content is painted beside the keyboard instead of ending in a blank band.
      expect(
        tester.getRect(find.byType(SearchSessionView)).bottom,
        size.height,
      );
      expect(tester.getBottomRight(_field).dy, lessThanOrEqualTo(openTop));
      // The keypad's own Navigator confines its route barrier to the keys.
      // It must not add a barrier or scrim over the catalogue.
      final keyboardBarriers = find.descendant(
        of: _keyboard,
        matching: find.byType(ModalBarrier),
      );
      expect(
        find.byType(ModalBarrier).evaluate().length -
            keyboardBarriers.evaluate().length,
        barriersBefore,
      );

      final a = find.descendant(
        of: find.byType(VirtualKeypad),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'a',
        ),
      );
      await tester.tap(a);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(_field).controller!.text, 'a');

      if (const bool.fromEnvironment('KEYBOARD_SCREENSHOT')) {
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(_capture),
          );
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('/tmp/kalinka-catalog-keyboard-${size.width.toInt()}.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.tap(find.byKey(const ValueKey('keyboard-submit')));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(_keyboard, findsOneWidget);
      expect(tester.getTopLeft(_keyboard).dy, greaterThan(openTop));
      expect(_mini.hitTestable(), findsNothing);
      await tester.pumpAndSettle();
      expect(_keyboard, findsNothing);
      expect(_mini.hitTestable(), findsOneWidget);
      expect(tester.getRect(_mini), originalBar);
      expect(container.read(searchSessionProvider).catalogFilter.text, 'a');
      expect(api.filters.last, contains('a'));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reduced motion clears the bar without waiting for animation', (
    tester,
  ) async {
    final container = await pumpHomeShell(
      tester,
      queue: SettableQueue(queueOf(2)),
      api: _CatalogApi(),
      onScreenKeyboard: true,
      reducedMotion: true,
    );
    container
        .read(searchSessionProvider.notifier)
        .openCatalog(
          id: 'kalinka:localfiles:catalog:albums',
          title: 'Albums',
          filters: const [
            FilterSpec(id: 'q', kind: FilterKind.text, label: 'Search albums'),
          ],
        );
    await tester.pumpAndSettle();
    await _focusFilter(tester);
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    expect(_keyboard.hitTestable(), findsOneWidget);
    expect(tester.getBottomRight(_keyboard).dy, 800);
    expect(_mini.hitTestable(), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    expect(_keyboard, findsNothing);
    expect(_mini.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'dismissal while the mini-player is hiding cancels presentation',
    (tester) async {
      final container = await pumpHomeShell(
        tester,
        queue: SettableQueue(queueOf(2)),
        api: _CatalogApi(),
        onScreenKeyboard: true,
        reducedMotion: false,
      );
      container
          .read(searchSessionProvider.notifier)
          .openCatalog(
            id: 'kalinka:localfiles:catalog:albums',
            title: 'Albums',
            filters: const [
              FilterSpec(
                id: 'q',
                kind: FilterKind.text,
                label: 'Search albums',
              ),
            ],
          );
      await tester.pumpAndSettle();
      await _focusFilter(tester);
      await tester.pump(const Duration(milliseconds: 80));
      expect(_keyboard, findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_keyboard, findsNothing);
      expect(_mini.hitTestable(), findsOneWidget);

      await tester.tap(_field);
      await tester.pumpAndSettle();
      expect(_keyboard.hitTestable(), findsOneWidget);
      expect(_mini.hitTestable(), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an editor above an inactive shell does not wait for its ticker',
    (tester) async {
      await pumpHomeShell(
        tester,
        queue: SettableQueue(queueOf(2)),
        onScreenKeyboard: true,
        reducedMotion: false,
      );
      final navigator = Navigator.of(tester.element(_mini));
      navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: TextField()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(_field);
      await tester.pumpAndSettle();
      expect(_keyboard.hitTestable(), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pumpAndSettle();
      expect(_keyboard, findsNothing);
      expect(_mini.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
