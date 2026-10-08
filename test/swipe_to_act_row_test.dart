import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalinka/widgets/swipe_to_act_row.dart';

// Count image resolutions independently of the image cache: even a warm cache
// can hide a remount that would flash with asynchronously decoded artwork.
class _ArtworkProvider extends ImageProvider<_ArtworkProvider> {
  _ArtworkProvider(this.image);

  final ui.Image image;
  int resolutions = 0;

  @override
  Future<_ArtworkProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  void resolveStreamForKey(
    ImageConfiguration configuration,
    ImageStream stream,
    _ArtworkProvider key,
    ImageErrorListener handleError,
  ) {
    resolutions++;
    stream.setCompleter(
      OneFrameImageStreamCompleter(
        SynchronousFuture(ImageInfo(image: image.clone())),
      ),
    );
  }
}

void main() {
  for (final direction in [-1.0, 1.0]) {
    testWidgets('artwork stays clipped to the row while moving $direction', (
      tester,
    ) async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 60, 60),
        Paint()..color = Colors.white,
      );
      final picture = recorder.endRecording();
      final artwork = await tester.runAsync(() => picture.toImage(60, 60));
      picture.dispose();
      addTearDown(artwork!.dispose);
      final captureKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: captureKey,
                child: ColoredBox(
                  color: Colors.black,
                  child: SizedBox(
                    width: 408,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: SwipeToActRow(
                        onAddToQueue: () {},
                        onPlayNext: () {},
                        child: SizedBox(
                          height: 76,
                          child: Row(
                            children: [
                              if (direction > 0) const Spacer(),
                              Image(
                                image: _ArtworkProvider(artwork),
                                width: 60,
                                height: 60,
                              ),
                              if (direction < 0) const Spacer(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      Future<void> expectMarginUntouched() async {
        final paintedPixels = await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(captureKey),
          );
          final frame = await boundary.toImage(pixelRatio: 1);
          final data = await frame.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final bytes = data!.buffer.asUint8List();
          var count = 0;
          for (var y = 0; y < frame.height; y++) {
            for (var x = 0; x < frame.width; x++) {
              if (x >= 24 && x < frame.width - 24) continue;
              final offset = (y * frame.width + x) * 4;
              if (bytes[offset] != 0 ||
                  bytes[offset + 1] != 0 ||
                  bytes[offset + 2] != 0) {
                count++;
              }
            }
          }
          frame.dispose();
          return count;
        });
        expect(
          paintedPixels,
          0,
          reason:
              'Translated artwork must never paint beyond the row clip, including between cached frames.',
        );
      }

      await expectMarginUntouched();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(SwipeToActRow)),
      );
      await gesture.moveBy(Offset(direction * 24, 0));
      await tester.pump();
      // Check successive held-drag frames as the image crosses the row edge.
      for (var frame = 0; frame < 5; frame++) {
        await gesture.moveBy(Offset(direction * 12, 0));
        await tester.pump(const Duration(milliseconds: 16));
        await expectMarginUntouched();
      }
      await gesture.cancel();
      await tester.pumpAndSettle();
      await expectMarginUntouched();
    });
  }

  testWidgets('confirmation does not flash over the artwork', (tester) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 60, 60),
      Paint()..color = const Color(0xFF1248A0),
    );
    final picture = recorder.endRecording();
    final artwork = await tester.runAsync(() => picture.toImage(60, 60));
    picture.dispose();
    addTearDown(artwork!.dispose);
    final captureKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: captureKey,
              child: SizedBox(
                width: 360,
                child: SwipeToActRow(
                  onAddToQueue: () {},
                  onPlayNext: () {},
                  child: SizedBox(
                    height: 76,
                    child: Row(
                      children: [
                        Image(
                          image: _ArtworkProvider(artwork),
                          width: 60,
                          height: 60,
                        ),
                        const Text('Album'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Future<List<int>?> artworkPixel() => tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(captureKey),
      );
      final point = boundary.globalToLocal(
        tester.getCenter(find.byType(Image)),
      );
      final frame = await boundary.toImage(pixelRatio: 1);
      final bytes = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
      final offset = (point.dy.floor() * frame.width + point.dx.floor()) * 4;
      final pixel = bytes!.buffer.asUint8List(offset, 4).toList();
      frame.dispose();
      return pixel;
    });

    final before = await artworkPixel();
    expect(before, [0x12, 0x48, 0xA0, 0xFF]);
    await tester.drag(find.byType(SwipeToActRow), const Offset(-180, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(await artworkPixel(), before);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'rapid opposite swipes each commit once without fighting the spring',
    (tester) async {
      var queued = 0;
      var playedNext = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: SwipeToActRow(
                  onAddToQueue: () => queued++,
                  onPlayNext: () => playedNext++,
                  child: const SizedBox(height: 76, child: Text('Album')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.drag(find.byType(SwipeToActRow), const Offset(-180, 0));
      await tester.pump();
      expect(playedNext, 1);
      await tester.pump(const Duration(milliseconds: 80));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(SwipeToActRow)),
      );
      await gesture.moveBy(const Offset(24, 0));
      await gesture.moveBy(const Offset(240, 0));
      await tester.pump();
      final position = tester.getTopLeft(find.text('Album'));
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.getTopLeft(find.text('Album')), position);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(queued, 1);
      expect(playedNext, 1);
    },
  );

  for (final direction in [-1.0, 1.0]) {
    for (final commit in [false, true]) {
      final action = direction < 0 ? 'play next' : 'add to queue';
      testWidgets(
        '${commit ? 'committed' : 'short'} $action swipe preserves artwork',
        (tester) async {
          final image = await tester.runAsync(() => createTestImage());
          addTearDown(image!.dispose);
          final provider = _ArtworkProvider(image);
          var queued = 0;
          var playedNext = 0;

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 360,
                    child: SwipeToActRow(
                      onAddToQueue: () => queued++,
                      onPlayNext: () => playedNext++,
                      child: SizedBox(
                        height: 76,
                        child: Row(
                          children: [
                            Image(
                              image: provider,
                              width: 60,
                              height: 60,
                              gaplessPlayback: true,
                            ),
                            const Text('Catalog album'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();

          final artworkState = tester.state(find.byType(Image));
          final originalPosition = tester.getTopLeft(find.byType(Image));
          void expectArtworkPreserved() {
            expect(tester.state(find.byType(Image)), same(artworkState));
            expect(provider.resolutions, 1);
            expect(
              tester.widget<RawImage>(find.byType(RawImage)).image,
              isNotNull,
            );
          }

          // Repeat to cover both the first, lazy confirmation and later swipes.
          for (var attempt = 0; attempt < 2; attempt++) {
            final gesture = await tester.startGesture(
              tester.getCenter(find.byType(SwipeToActRow)),
            );
            await gesture.moveBy(Offset(direction * 24, 0));
            await tester.pump();
            await gesture.moveBy(Offset(direction * 30, 0));
            await tester.pump();
            expectArtworkPreserved();
            expect(
              (tester.getTopLeft(find.byType(Image)).dx - originalPosition.dx) *
                  direction,
              greaterThan(0),
            );

            if (commit) {
              await gesture.moveBy(Offset(direction * 120, 0));
              await tester.pump();
              expectArtworkPreserved();
            }
            await gesture.up();
            await tester.pump();
            expectArtworkPreserved();
            await tester.pump(const Duration(milliseconds: 100));
            expectArtworkPreserved();
            await tester.pumpAndSettle();
            expectArtworkPreserved();
            expect(tester.getTopLeft(find.byType(Image)), originalPosition);
            expect(queued, commit && direction > 0 ? attempt + 1 : 0);
            expect(playedNext, commit && direction < 0 ? attempt + 1 : 0);
          }
        },
      );
    }
  }
}
