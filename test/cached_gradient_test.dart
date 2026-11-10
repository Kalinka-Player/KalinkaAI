import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalinka/widgets/cached_gradient.dart';

class _Ellipse extends GradientTransform {
  const _Ellipse();

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final radius = bounds.shortestSide / 2;
    final sx = bounds.width * .62 / radius;
    final sy = 200 / radius;
    final from = bounds.center;
    return Matrix4.diagonal3Values(sx, sy, 1)
      ..setTranslationRaw(from.dx - sx * from.dx, 120 - sy * from.dy, 0);
  }
}

const _gradient = RadialGradient(
  colors: [Color(0x42C2394B), Color(0x00C2394B)],
  transform: _Ellipse(),
);

const _fade = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0x00080808), Color(0xFF080808)],
  stops: [.8, .98],
);

Future<ui.Image> _render(BoxPainter painter, Size size, double dpr) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(dpr);
  canvas.drawColor(const Color(0xFF286496), BlendMode.src);
  painter.paint(canvas, const Offset(17, 23), ImageConfiguration(size: size));
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(
      ((size.width + 40) * dpr).ceil(),
      ((size.height + 50) * dpr).ceil(),
    );
  } finally {
    picture.dispose();
  }
}

void main() {
  testWidgets('cached bloom preserves gradient colour, shape and clipping', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final decoration in [
        CachedRadialGradientDecoration(gradient: _gradient),
        CachedVerticalGradientDecoration(gradient: _fade),
      ]) {
        final reference = BoxDecoration(gradient: decoration.gradient)
            .createBoxPainter();
        final cached = decoration.createBoxPainter();
        try {
          for (final (width, dpr) in [
            (240.0, 1.0),
            (900.0, 2.0),
            (1500.0, 1.0),
          ]) {
            final size = Size(width, 448);
            final a = await _render(reference, size, dpr);
            final b = await _render(cached, size, dpr);
            try {
              final before = (await a.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
              final after = (await b.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
              var maxDifference = 0;
              for (var y = 0; y < a.height; y += 7) {
                for (var x = 0; x < a.width; x += 7) {
                  for (var channel = 0; channel < 4; channel++) {
                    final i = (y * a.width + x) * 4 + channel;
                    final difference = (before.getUint8(i) - after.getUint8(i))
                        .abs();
                    if (difference > maxDifference) maxDifference = difference;
                  }
                }
              }
              expect(
                maxDifference,
                lessThanOrEqualTo(2),
                reason: 'Gradient changed at width $width and density $dpr',
              );
            } finally {
              a.dispose();
              b.dispose();
            }
          }
        } finally {
          reference.dispose();
          cached.dispose();
        }
      }
    });
  });

  testWidgets('resizing reuses one texture and disposing releases its handle', (
    tester,
  ) async {
    final created = <ui.Image>[];
    final previous = ui.Image.onCreate;
    ui.Image.onCreate = (image) {
      created.add(image);
      previous?.call(image);
    };
    try {
      for (final decoration in [
        CachedRadialGradientDecoration(gradient: _gradient),
        CachedVerticalGradientDecoration(gradient: _fade),
      ]) {
        created.clear();
        final painter = decoration.createBoxPainter();
        try {
          for (final width in [900.0, 899.0, 640.0, 1500.0]) {
            final recorder = ui.PictureRecorder();
            painter.paint(
              Canvas(recorder),
              Offset.zero,
              ImageConfiguration(size: Size(width, 448)),
            );
            recorder.endRecording().dispose();
          }
          expect(created, hasLength(1));
          expect(
            created.single.width,
            decoration.gradient is RadialGradient ? 256 : 1,
          );
          expect(created.single.height, 256);
        } finally {
          painter.dispose();
        }
        expect(created.single.debugDisposed, isTrue);
      }
    } finally {
      ui.Image.onCreate = previous;
    }
  });
}
