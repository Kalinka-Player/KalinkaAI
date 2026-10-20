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
}) => PlayQueueState(
  trackList: [
    for (var i = 0; i < count; i++)
      Track(
        id: 'track-$i',
        title: 'Evening track $i',
        duration: 200,
        performer: Artist(id: 'artist', name: 'A favourite artist'),
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
  Size size = const Size(432, 1200),
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
    'offline preview stays readable and inactive; exclusive or empty queue hides it',
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
      queue.set(_queue(index: 9, seq: 3));
      await tester.pumpAndSettle();
      expect(_preview, findsNothing);
      queue.set(PlayQueueState.empty);
      await tester.pumpAndSettle();
      expect(_preview, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (name, size, scale) in [
    ('short', const Size(432, 720), 1.0),
    ('desktop', const Size(432, 1080), 1.0),
    ('tall', const Size(432, 1200), 1.0),
    ('large-text', const Size(375, 812), 2.0),
    ('landscape', const Size(812, 375), 1.0),
  ]) {
    testWidgets('$name keeps artwork at the top and controls reachable', (
      tester,
    ) async {
      final captureKey = GlobalKey();
      await _pump(
        tester,
        queue: SettableQueue(_queue()),
        size: size,
        scale: scale,
        captureKey: captureKey,
      );
      expect(
        tester.getRect(_art).top,
        closeTo(tester.getRect(find.byType(PlayerHeader)).bottom + 24, 0.1),
      );
      if (size.height >= 1080) {
        expect(_preview, findsOneWidget);
        expect(_rows.evaluate().length, inInclusiveRange(3, 5));
        expect(tester.getRect(_preview).bottom, lessThanOrEqualTo(size.height));
        expect(
          tester.getRect(_rows.first).top,
          greaterThan(
            tester.getRect(find.byType(RendererSwitcherDropdown)).bottom,
          ),
        );
      } else {
        expect(_preview, findsNothing);
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
      await tester.ensureVisible(find.byType(RendererSwitcherDropdown));
      await tester.pumpAndSettle();
      expect(
        find.byType(RendererSwitcherDropdown).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
