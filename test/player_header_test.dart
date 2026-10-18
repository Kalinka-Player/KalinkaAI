import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/renderer_host_provider.dart';
import 'package:kalinka/providers/renderer_provider.dart';
import 'package:kalinka/providers/shell_nav_provider.dart';
import 'package:kalinka/renderer/renderer_identity.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/player_header.dart';
import 'package:kalinka/widgets/player_view_switch.dart';
import 'package:kalinka/widgets/renderer_switcher.dart';

import 'support/focus.dart';
import 'support/home_shell.dart';

class _Connected extends ConnectionStateNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

class _Renderers extends RendererListNotifier {
  @override
  RendererListState build() => const RendererListState(loaded: true);
}

Future<void> _pumpHeader(
  WidgetTester tester, {
  double width = 480,
  double scale = 1,
  bool tablet = false,
  bool reduceMotion = false,
  bool away = false,
  VoidCallback? onClose,
}) async {
  tester.view.physicalSize = Size(width, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        rendererListProvider.overrideWith(_Renderers.new),
        // The queue view's ⋮ shows for a reachable, non-empty queue.
        playQueueStateStoreProvider.overrideWith(
          () => SettableQueue(queueOf(3)),
        ),
        connectionStateProvider.overrideWith(_Connected.new),
        rendererIdentityProvider.overrideWith(
          (ref) async => const RendererIdentity(
            rendererId: 'test',
            instanceId: 'test',
            friendlyName: 'Test',
            softwareVersion: '0',
            os: 'linux',
          ),
        ),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reduceMotion,
          ),
          child: child!,
        ),
        home: Scaffold(
          backgroundColor: KalinkaColors.background,
          body: Align(
            alignment: Alignment.topCenter,
            child: Consumer(
              builder: (context, ref, _) => PlayerHeader(
                isTablet: tablet,
                showingQueue: ref.watch(playerViewProvider) == PlayerView.queue,
                onClose: onClose ?? () {},
                away: away,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _segment(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Real metrics matter when deciding whether the labels fit beside the
    // header actions; the test font gives every glyph the same width.
    final loader = FontLoader(KalinkaFonts.monoFamily)
      ..addFont(rootBundle.load('assets/fonts/IBMPlexMono-SemiBold.ttf'));
    await loader.load();
  });

  for (final width in [320.0, 375.0, 480.0, 812.0]) {
    for (final scale in [1.0, 2.0, 3.2]) {
      testWidgets('header fits at ${width}dp and ${scale}x text', (
        tester,
      ) async {
        await _pumpHeader(tester, width: width, scale: scale);
        expect(tester.takeException(), isNull);

        final header = tester.getRect(find.byType(PlayerHeader));
        final viewSwitch = tester.getRect(find.byType(PlayerViewSwitch));
        final collapse = tester.getRect(find.byTooltip('Minimise player'));
        final output = tester.getRect(find.byType(RendererSwitcherButton));
        expect(header.contains(viewSwitch.topLeft), isTrue);
        expect(header.contains(viewSwitch.bottomRight), isTrue);
        expect(viewSwitch.overlaps(collapse), isFalse);
        expect(viewSwitch.overlaps(output), isFalse);
        expect(collapse.height, 36);
        expect(output.height, 36);
        if (scale == 1) {
          expect(viewSwitch.height, 48);
          if (width >= 375) {
            expect(viewSwitch.center.dy, closeTo(collapse.center.dy, .01));
          }
        }

        for (final label in ['PLAYING', 'QUEUE']) {
          final target = tester.getRect(_segment(label));
          expect(target.width, greaterThanOrEqualTo(48));
          expect(target.height, greaterThanOrEqualTo(48));
          final text = tester.renderObject<RenderParagraph>(find.text(label));
          expect(text.textScaler.scale(14), closeTo(14 * scale, 0.01));
          // Enlarged text must not be scaled back down during painting.
          expect(
            text.getTransformTo(null).getMaxScaleOnAxis(),
            closeTo(1, .01),
          );
          expect(
            text.getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: label.length),
            ),
            hasLength(1),
          );
        }

        // The edge of the padded target must work, not just the label.
        final queue = tester.getRect(_segment('QUEUE'));
        await tester.tapAt(queue.bottomLeft + const Offset(2, -2));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.getRect(find.byType(PlayerViewSwitch)), viewSwitch);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(PlayerViewSwitch)),
        );
        expect(container.read(playerViewProvider), PlayerView.queue);
      });
    }
  }

  testWidgets('wide header centres the switch beside its actions', (
    tester,
  ) async {
    await _pumpHeader(tester);
    final viewSwitch = tester.getRect(find.byType(PlayerViewSwitch));
    final collapse = tester.getRect(find.byTooltip('Minimise player'));
    expect(viewSwitch.center.dx, closeTo(240, .01));
    expect(viewSwitch.center.dy, closeTo(collapse.center.dy, .01));
  });

  testWidgets('narrow header gives the switch a separate row', (tester) async {
    await _pumpHeader(tester, width: 320);
    expect(
      tester.getTopLeft(find.byType(PlayerViewSwitch)).dy,
      greaterThan(tester.getBottomLeft(find.byTooltip('Minimise player')).dy),
    );
  });

  testWidgets('tablet header wraps its actions around enlarged view labels', (
    tester,
  ) async {
    await _pumpHeader(tester, width: 450, scale: 2, tablet: true);
    expect(tester.takeException(), isNull);
    final viewSwitch = tester.getRect(find.byType(PlayerViewSwitch));
    final output = tester.getRect(find.byType(RendererSwitcherDropdown));
    expect(viewSwitch.overlaps(output), isFalse);
    expect(output.top, greaterThan(viewSwitch.bottom));
    await tester.tap(find.text('QUEUE'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byType(PlayerViewSwitch)), viewSwitch);
  });

  testWidgets('keyboard activation and selected semantics survive reflow', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpHeader(tester, width: 320, scale: 3.2, reduceMotion: true);
    Focus.of(tester.element(find.text('PLAYING'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(
      tester.getSemantics(find.bySemanticsLabel('Queue')),
      isSemantics(isButton: true, isSelected: true, hasTapAction: true),
    );
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  for (final tablet in [false, true]) {
    for (final away in [false, true]) {
      testWidgets('${tablet ? 'tablet' : 'phone'} header '
          '${away ? 'while the server is away' : 'when connected'}: the '
          'output switcher ${away ? 'takes no input' : 'takes input'}, and '
          'the view switch still works', (tester) async {
        var closed = false;
        await _pumpHeader(
          tester,
          tablet: tablet,
          away: away,
          onClose: () => closed = true,
        );
        final output = find.byType(
          tablet ? RendererSwitcherDropdown : RendererSwitcherButton,
        );

        expect(output, findsOneWidget);
        expect(output.hitTestable(), away ? findsNothing : findsOneWidget);
        expect(await tabTo(tester, output), !away);

        await tester.tap(_segment('QUEUE'));
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(PlayerViewSwitch)),
        );
        expect(container.read(playerViewProvider), PlayerView.queue);
        if (!tablet) {
          await tester.tap(find.byTooltip('Minimise player'));
          expect(closed, isTrue);
        }
      });
    }
  }

  testWidgets('collapse action remains accessible after reflow', (
    tester,
  ) async {
    var closed = false;
    await _pumpHeader(tester, width: 320, onClose: () => closed = true);
    await tester.tap(find.byTooltip('Minimise player'));
    expect(closed, isTrue);
  });
}
