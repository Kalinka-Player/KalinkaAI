import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/data_model/data_model.dart';
import 'package:kalinka/data_model/kalinka_ws_api.dart';
import 'package:kalinka/data_model/playqueue_events.dart';
import 'package:kalinka/providers/app_state_provider.dart';
import 'package:kalinka/providers/kalinka_ws_api_provider.dart';
import 'package:kalinka/theme/app_theme.dart';
import 'package:kalinka/widgets/queue_columns.dart';
import 'package:kalinka/widgets/queue_section_header.dart';
import 'package:kalinka/widgets/queue_zone.dart';

import 'support/home_shell.dart';

class _Api extends KalinkaWsApi {
  _Api(super.ref);
  final sent = <QueueCommand>[];

  @override
  Future<void> sendQueueCommand(QueueCommand command) async =>
      sent.add(command);
}

PlayQueueState _queue({bool albums = true}) => PlayQueueState(
  trackList: [
    for (var i = 0; i < 16; i++)
      Track(
        id: 'track-$i',
        title: 'Evening track $i',
        duration: 200,
        performer: Artist(id: 'artist', name: 'Northern Lights'),
        album: albums && i != 3
            ? Album(
                id: 'album-$i',
                title: 'Evening sessions $i — live at the old concert hall',
              )
            : null,
      ),
  ],
  playbackState: PlaybackState(index: 1, state: PlayerStateType.playing),
  playbackMode: PlaybackMode.empty,
  seq: 1,
);

Finder _header(String title) => find.widgetWithText(QueueSectionHeader, title);
Finder _cell(Finder parent, String text) =>
    find.descendant(of: parent, matching: find.text(text));

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  double width = 800,
  double scale = 1,
  bool albums = true,
  Key? captureKey,
}) async {
  final container = await pumpHomeShell(
    tester,
    queue: SettableQueue(_queue(albums: albums)),
    size: Size(width, 900),
    overrides: [kalinkaWsApiProvider.overrideWith((ref) => _Api(ref))],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: RepaintBoundary(
          key: captureKey,
          child: const Scaffold(body: QueueZone(bottomPadding: 16)),
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
    for (final (family, files) in [
      (
        'IBM Plex Sans',
        ['IBMPlexSans-Regular.ttf', 'IBMPlexSans-SemiBold.ttf'],
      ),
      (
        'IBM Plex Mono',
        ['IBMPlexMono-Regular.ttf', 'IBMPlexMono-SemiBold.ttf'],
      ),
    ]) {
      final loader = FontLoader(family);
      for (final file in files) {
        loader.addFont(rootBundle.load('assets/fonts/$file'));
      }
      await loader.load();
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

  for (final (width, scale, wide) in [
    (800.0, 1.0, true),
    (600.0, 1.0, true),
    (432.0, 1.0, false),
    (640.0, 2.0, false),
    (1280.0, 2.0, true),
  ]) {
    testWidgets('queue columns fit a $width pane at ${scale}x text', (
      tester,
    ) async {
      final key = GlobalKey();
      await _pump(tester, width: width, scale: scale, captureKey: key);
      for (final (heading, rowKey, index, time) in [
        ('NOW PLAYING', 'nowplaying_track-1', 1, '-3:20'),
        ('UP NEXT', 'upnext_track-2', 2, '3:20'),
      ]) {
        final header = _header(heading);
        final row = find.byKey(ValueKey(rowKey));
        final album = _cell(
          row,
          'Evening sessions $index — live at the old concert hall',
        );
        final hasLegend = wide && heading == 'UP NEXT';
        for (final label in ['TRACK / ARTIST', 'ALBUM', 'TIME']) {
          expect(
            _cell(header, label),
            hasLegend ? findsOneWidget : findsNothing,
          );
        }
        expect(album, wide ? findsOneWidget : findsNothing);
        if (hasLegend) {
          expect(
            tester.getTopLeft(_cell(header, 'ALBUM')).dx,
            closeTo(tester.getTopLeft(album).dx, 0.1),
          );
          expect(
            tester.getTopLeft(_cell(header, 'TRACK / ARTIST')).dx,
            closeTo(
              tester.getTopLeft(_cell(row, 'Evening track $index')).dx,
              0.1,
            ),
          );
          expect(
            tester.getBottomRight(_cell(header, 'TIME')).dx,
            closeTo(tester.getBottomRight(_cell(row, time)).dx, 0.1),
          );
          expect(
            tester.getBottomLeft(_cell(header, heading)).dy,
            lessThan(tester.getTopLeft(_cell(header, 'ALBUM')).dy),
          );
          expect(
            tester.getBottomLeft(_cell(header, 'ALBUM')).dy,
            lessThanOrEqualTo(tester.getTopLeft(row).dy),
          );
        }
      }
      expect(tester.takeException(), isNull);
      if (captures != null) {
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$captures/queue-$width-$scale.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }

  testWidgets(
    'column labels stay with the pinned Up Next heading and resizing preserves the queue',
    (tester) async {
      final container = await _pump(tester);
      final original = container.read(playQueueStateStoreProvider);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -260));
      await tester.pumpAndSettle();
      final header = _header('UP NEXT');
      expect(tester.getTopLeft(header).dy, closeTo(0, 0.1));
      expect(_cell(header, 'ALBUM').hitTestable(), findsOneWidget);
      tester.view.physicalSize = const Size(432, 900);
      await tester.pumpAndSettle();
      expect(find.byType(QueueColumnLegend), findsNothing);
      expect(container.read(playQueueStateStoreProvider), same(original));
      tester.view.physicalSize = const Size(800, 900);
      await tester.pumpAndSettle();
      expect(_cell(header, 'ALBUM').hitTestable(), findsOneWidget);
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
      scroll.position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Evening sessions 2 — live at the old concert hall'),
      );
      await tester.pump();
      expect((container.read(kalinkaWsApiProvider) as _Api).sent, [
        const QueueCommand.play(index: 2),
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('no empty Album column when the queue has no album metadata', (
    tester,
  ) async {
    await _pump(tester, albums: false);
    expect(find.byType(QueueColumnLegend), findsNothing);
    expect(find.text('ALBUM'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
