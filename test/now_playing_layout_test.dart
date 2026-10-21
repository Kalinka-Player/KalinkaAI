import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/data_model/kalinka_ws_api.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/connection_state_provider.dart';
import 'package:kalinka/providers/kalinka_ws_api_provider.dart';
import 'package:kalinka/providers/renderer_provider.dart';
import 'package:kalinka/providers/renderer_host_provider.dart';
import 'package:kalinka/renderer/renderer_identity.dart';
import 'package:kalinka/providers/shell_nav_provider.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/now_playing_content.dart';
import 'package:kalinka/widgets/player_header.dart';
import 'package:kalinka/widgets/renderer_switcher.dart';

import 'support/home_shell.dart';

class _Api extends KalinkaWsApi {
  _Api(super.ref);
  final sent = <QueueCommand>[];
  @override
  Future<void> sendQueueCommand(QueueCommand command) async =>
      sent.add(command);
}

class _Renderers extends RendererListNotifier {
  @override
  RendererListState build() => const RendererListState(
    loaded: true,
    renderers: [
      RendererInfo(
        rendererId: 'amp',
        friendlyName: 'Living room',
        status: 'connected',
        active: true,
      ),
    ],
  );
}

final _preview = find.byKey(const ValueKey('now-playing-up-next'));
final _art = find.byKey(const ValueKey('now-playing-artwork'));
final _presentation = find.byKey(const ValueKey('now-playing-presentation'));
final _metadata = find.byKey(const ValueKey('now-playing-metadata'));
Finder _row(int index) => find.byKey(ValueKey('up-next-track-$index'));
Finder get _rows => find.byWidgetPredicate(
  (widget) =>
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith('up-next-track-'),
);

PlayQueueState _queue({
  int index = 0,
  int count = 10,
  bool exclusive = false,
  int seq = 1,
  bool longNames = false,
}) => PlayQueueState(
  trackList: [
    for (var i = 0; i < count; i++)
      Track(
        id: 'track-$i',
        title: longNames
            ? 'Evening track $i — a live recording from the northern coast'
            : 'Evening track $i',
        duration: 200,
        performer: Artist(
          id: 'artist',
          name: longNames
              ? 'A favourite artist with the late night orchestra'
              : 'A favourite artist',
        ),
        album: Album(id: 'album', title: 'Evening sessions', year: 2026),
      ),
  ],
  playbackState: PlaybackState(index: index, state: PlayerStateType.playing),
  playbackMode: PlaybackMode.empty,
  playbackControl: exclusive
      ? const PlaybackControl.exclusive(pluginId: 'connect', title: 'Connect')
      : const PlaybackControl.queue(),
  seq: seq,
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required SettableQueue queue,
  Size size = const Size(432, 1280),
  double scale = 1,
  Key? captureKey,
}) async {
  final container = await pumpHomeShell(
    tester,
    queue: queue,
    size: size,
    overrides: [
      kalinkaWsApiProvider.overrideWith((ref) => _Api(ref)),
      rendererListProvider.overrideWith(_Renderers.new),
      rendererIdentityProvider.overrideWith(
        (ref) async => const RendererIdentity(
          rendererId: 'this-device',
          instanceId: 'test',
          friendlyName: 'Test',
          softwareVersion: 'test',
          os: 'linux',
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: RepaintBoundary(
            key: captureKey,
            child: const Scaffold(body: NowPlayingContent(isTablet: true)),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  final captures = Platform.environment['KALINKA_REVIEW_DIR'];
  setUpAll(() async {
    if (captures == null) return;
    for (final (family, file) in [
      ('IBM Plex Sans', 'IBMPlexSans-Regular.ttf'),
      ('IBM Plex Sans', 'IBMPlexSans-SemiBold.ttf'),
      ('IBM Plex Mono', 'IBMPlexMono-Regular.ttf'),
      ('Playfair Display', 'PlayfairDisplay-Regular.ttf'),
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

  testWidgets('preview follows queue order and plays the existing occurrence', (
    tester,
  ) async {
    final queue = SettableQueue(_queue(index: 2));
    final container = await _pump(tester, queue: queue);
    final semantics = tester.ensureSemantics();
    expect(_rows, findsNWidgets(5));
    expect(
      find.descendant(of: _preview, matching: find.text('UP NEXT')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _preview, matching: find.text('· 7')),
      findsOneWidget,
    );
    expect(_row(2), findsNothing);
    expect(_row(3), findsOneWidget);
    expect(_row(7), findsOneWidget);
    expect(_row(8), findsNothing);
    final original = container.read(playQueueStateStoreProvider);
    expect(
      tester.getSemantics(_row(4)),
      matchesSemantics(
        label: 'Evening track 4, A favourite artist',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    await tester.tap(_row(4));
    await tester.pump();
    expect((container.read(kalinkaWsApiProvider) as _Api).sent, [
      const QueueCommand.play(index: 4),
    ]);
    expect(container.read(playQueueStateStoreProvider), same(original));
    queue.set(_queue(index: 5, seq: 2));
    await tester.pumpAndSettle();
    expect(_rows, findsNWidgets(4));
    expect(_row(6), findsOneWidget);
    expect(_row(3), findsNothing);
    expect(
      find.descendant(of: _preview, matching: find.text('· 4')),
      findsOneWidget,
    );
    final advanced = container.read(playQueueStateStoreProvider);
    queue.set(
      advanced.copyWith(
        trackList: [
          ...advanced.trackList.take(6),
          ...advanced.trackList.skip(6).toList().reversed,
        ],
        seq: 3,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: _row(6), matching: find.text('Evening track 9')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('View queue'));
    await tester.pumpAndSettle();
    expect(container.read(playerViewProvider), PlayerView.queue);
    expect(_preview, findsNothing);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('preview highlights stay neutral, inset and clickable', (
    tester,
  ) async {
    final captureKey = GlobalKey();
    final container = await _pump(
      tester,
      queue: SettableQueue(_queue()),
      captureKey: captureKey,
    );
    final heading = find.byTooltip('View queue');
    final headingRect = tester.getRect(heading);
    final label = find.descendant(of: heading, matching: find.text('UP NEXT'));
    final chevron = find.descendant(
      of: heading,
      matching: find.byIcon(Icons.chevron_right),
    );
    expect(
      tester.getRect(label).left - headingRect.left,
      greaterThanOrEqualTo(12),
    );
    expect(
      headingRect.right - tester.getRect(chevron).right,
      greaterThanOrEqualTo(12),
    );
    final artwork = find.descendant(
      of: _row(1),
      matching: find.byType(ClipRRect),
    );
    expect(
      tester.getRect(artwork).left - tester.getRect(_row(1)).left,
      greaterThanOrEqualTo(12),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    for (final target in [heading, _row(1)]) {
      await mouse.moveTo(tester.getCenter(target));
      await tester.pumpAndSettle();
      expect(
        tester.binding.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.click,
      );
      final ink = tester.widget<InkWell>(
        find.descendant(of: target, matching: find.byType(InkWell)),
      );
      for (final state in [
        WidgetState.hovered,
        WidgetState.pressed,
        WidgetState.focused,
      ]) {
        final color = ink.overlayColor!.resolve({state})!;
        expect(color.a, greaterThan(0));
        // Neutral surfaces can have a small warm tint, but no berry hue.
        expect((color.r - color.g).abs(), lessThan(0.02));
        expect((color.g - color.b).abs(), lessThan(0.02));
      }
    }
    if (captures != null) {
      await tester.runAsync(() async {
        final boundary =
            captureKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('$captures/hover.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    (container.read(connectionStateProvider.notifier) as SettableConnection)
        .set(ConnectionStatus.offline);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.binding.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.basic,
    );
    // Opening the cached queue remains available while playback is offline.
    await mouse.moveTo(tester.getCenter(heading));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.binding.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.click,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'resizing fits one to five rows without moving or shrinking the cover',
    (tester) async {
      final queue = SettableQueue(_queue());
      final container = await _pump(tester, queue: queue);
      final original = container.read(playQueueStateStoreProvider);
      final art = tester.getRect(_art);
      final previewTop = tester.getRect(_preview).top;
      final headerHeight = tester.getRect(_row(1)).top - previewTop;
      final rowHeight = tester.getSize(_row(1)).height;
      final minimumHeight = previewTop + headerHeight + rowHeight + 16;
      for (final rows in [1, 2, 3, 4, 5]) {
        tester.view.physicalSize = Size(
          432,
          minimumHeight + (rows - 1) * rowHeight + 0.5,
        );
        await tester.pumpAndSettle();
        expect(_rows, findsNWidgets(rows));
        expect(tester.getRect(_art), art);
        expect(container.read(playQueueStateStoreProvider), same(original));
      }
      tester.view.physicalSize = Size(432, minimumHeight - 1);
      await tester.pumpAndSettle();
      expect(_preview, findsNothing);
      expect(tester.getRect(_art), art);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'offline preview stays readable and inactive; exclusive or empty queue hides it, and its end says so',
    (tester) async {
      final queue = SettableQueue(_queue());
      final container = await _pump(tester, queue: queue);
      (container.read(connectionStateProvider.notifier) as SettableConnection)
          .set(ConnectionStatus.offline);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_preview, findsOneWidget);
      final button = tester.widget<TextButton>(
        find.descendant(of: _row(1), matching: find.byType(TextButton)),
      );
      expect(button.onPressed, isNull);
      (container.read(connectionStateProvider.notifier) as SettableConnection)
          .set(ConnectionStatus.connected);
      queue.set(_queue(exclusive: true, seq: 2));
      await tester.pumpAndSettle();
      expect(_preview, findsNothing);
      // At the end of the queue it says the queue is empty, as the queue does.
      queue.set(_queue(index: 9, seq: 3));
      await tester.pumpAndSettle();
      expect(_preview, findsOneWidget);
      expect(
        find.descendant(of: _preview, matching: find.text('Queue is empty')),
        findsOneWidget,
      );
      queue.set(PlayQueueState.empty);
      await tester.pumpAndSettle();
      expect(_preview, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('resizing rearranges the cover without changing playback', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      queue: SettableQueue(_queue()),
      size: const Size(432, 900),
    );
    final original = container.read(playQueueStateStoreProvider);
    final title = find.text('Evening track 0');
    expect(tester.getRect(title).top, greaterThan(tester.getRect(_art).bottom));
    tester.view.physicalSize = const Size(432, 500);
    await tester.pumpAndSettle();
    expect(tester.getRect(title).left, greaterThan(tester.getRect(_art).right));
    expect(
      tester.getCenter(_metadata).dy,
      closeTo(
        tester
            .getCenter(find.byKey(const ValueKey('now-playing-metadata-area')))
            .dy,
        0.1,
      ),
    );
    tester.view.physicalSize = const Size(432, 900);
    await tester.pumpAndSettle();
    expect(tester.getRect(title).top, greaterThan(tester.getRect(_art).bottom));
    expect(container.read(playQueueStateStoreProvider), same(original));
    expect((container.read(kalinkaWsApiProvider) as _Api).sent, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final (name, size, scale, sideBySide) in [
    ('short', const Size(432, 720), 1.0, false),
    ('desktop', const Size(432, 1080), 1.0, false),
    ('tall', const Size(432, 1200), 1.0, false),
    ('large-text', const Size(375, 812), 2.0, false),
    ('landscape', const Size(812, 375), 1.0, true),
    ('near-square', const Size(432, 540), 1.0, true),
    ('square', const Size(800, 800), 1.0, true),
    ('square-long-text', const Size(640, 640), 2.0, true),
    ('square-large-text', const Size(432, 500), 2.0, false),
    ('narrow-square', const Size(320, 400), 1.0, false),
  ]) {
    testWidgets('$name fits artwork, details and controls without scrolling', (
      tester,
    ) async {
      final captureKey = GlobalKey();
      final queue = _queue(longNames: name == 'square-long-text');
      await _pump(
        tester,
        queue: SettableQueue(queue),
        size: size,
        scale: scale,
        captureKey: captureKey,
      );
      expect(
        tester.getTopLeft(_presentation).dy,
        closeTo(
          tester.getRect(find.byType(PlayerHeader)).bottom +
              (sideBySide ? 8 : 32),
          0.1,
        ),
      );
      final title = find.text(queue.trackList.first.title);
      final titleBounds = tester.getRect(title);
      final artBounds = tester.getRect(_art);
      final output = find.byType(RendererSwitcherDropdown);
      expect(output, findsOneWidget);
      if (sideBySide) {
        expect(titleBounds.left, greaterThan(artBounds.right));
        expect(
          tester.getCenter(_metadata).dy,
          closeTo(
            tester
                .getCenter(
                  find.byKey(const ValueKey('now-playing-metadata-area')),
                )
                .dy,
            0.1,
          ),
        );
        final outputBounds = tester.getRect(output);
        expect(outputBounds.left, closeTo(titleBounds.left, 0.1));
        expect(
          outputBounds.bottom,
          closeTo(tester.getRect(_presentation).bottom, 0.1),
        );
        expect(
          artBounds.center.dy,
          closeTo(tester.getRect(_presentation).center.dy, 0.1),
        );
        expect(outputBounds.top, greaterThan(tester.getRect(_metadata).bottom));
        expect(outputBounds.right, lessThanOrEqualTo(size.width - 16));
        expect(tester.widget<Text>(title).textAlign, TextAlign.left);
        for (final text in [
          queue.trackList.first.performer!.name,
          'Evening sessions · 2026',
        ]) {
          expect(tester.getRect(find.text(text).first).left, titleBounds.left);
        }
      } else {
        expect(titleBounds.top, greaterThanOrEqualTo(artBounds.bottom));
      }
      if (size.height >= 1080) {
        expect(_preview, findsOneWidget);
        expect(_rows.evaluate().length, inInclusiveRange(1, 5));
        expect(tester.getRect(_preview).bottom, lessThanOrEqualTo(size.height));
        expect(
          tester.getRect(_rows.first).top,
          greaterThan(
            tester.getRect(find.byType(RendererSwitcherDropdown)).bottom,
          ),
        );
      } else if (!sideBySide) {
        expect(_preview, findsNothing);
      }
      if (name == 'square') {
        expect(_rows.evaluate().length, inInclusiveRange(1, 5));
        expect(tester.getRect(_preview).bottom, lessThanOrEqualTo(size.height));
      }
      if (captures != null) {
        await tester.runAsync(() async {
          final boundary =
              captureKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$captures/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      final scroll = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(NowPlayingContent),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scroll.position.maxScrollExtent, closeTo(0, 0.1));
      expect(scroll.position.pixels, closeTo(0, 0.1));
      final before = tester.getRect(_presentation);
      await tester.dragFrom(
        tester.getTopLeft(_presentation) + const Offset(4, 4),
        const Offset(0, -150),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(_presentation), before);
      expect(scroll.position.pixels, closeTo(0, 0.1));
      expect(
        find.byType(RendererSwitcherDropdown).hitTestable(),
        findsOneWidget,
      );
      expect(
        tester.getBottomRight(find.byType(RendererSwitcherDropdown)).dy,
        lessThanOrEqualTo(size.height),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
