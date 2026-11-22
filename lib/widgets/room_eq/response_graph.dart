import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data_model/room_eq.dart';
import '../../theme/app_theme.dart';

const _rate = 48000.0;
const _floor = 20.0;
const _ceiling = 20000.0;

class _Plot {
  final Rect area;
  final double db;
  _Plot(Size size, this.db)
    : area = Rect.fromLTRB(38, 18, size.width - 15, size.height - 30);
  double x(double hz) =>
      area.left +
      math.log(hz / _floor) / math.log(_ceiling / _floor) * area.width;
  double y(double gain) => area.center.dy - gain / db * area.height / 2;
  double frequency(double x) =>
      _floor *
      math.pow(_ceiling / _floor, ((x - area.left) / area.width).clamp(0, 1));
  double gain(double y) =>
      ((area.center.dy - y) * db * 2 / area.height).clamp(-db, db);
  Offset handle(EqBand b) =>
      Offset(x(b.hz), y(b.shape == FilterShape.peak ? b.gain : b.gain / 2));
}

class ResponseGraph extends StatefulWidget {
  const ResponseGraph({
    super.key,
    required this.bands,
    required this.selected,
    required this.onSelect,
    required this.onMove,
    this.height = 240,
  });
  final List<EqBand> bands;
  final int selected;
  final ValueChanged<int> onSelect;
  final ValueChanged<EqBand> onMove;
  final double height;
  @override
  State<ResponseGraph> createState() => _ResponseGraphState();
}

class _ResponseGraphState extends State<ResponseGraph> {
  int? dragging;
  double? dragScale;
  late double limit = scaleForBands();
  double scaleForBands() {
    final responses = widget.bands.map((b) => b.response(_rate)).toList();
    var peak = widget.bands.fold<double>(
      3,
      (v, b) => math.max(v, b.gain.abs()),
    );
    for (var i = 0; i <= 192; i++) {
      final hz = _floor * math.pow(_ceiling / _floor, i / 192);
      final w = 2 * math.pi * hz / _rate;
      final db = responses.fold<double>(0, (v, r) => v + r(w));
      if (db.isFinite) peak = math.max(peak, db.abs());
    }
    return 2 * (peak * 1.08 / 2).ceilToDouble();
  }

  @override
  void didUpdateWidget(ResponseGraph old) {
    super.didUpdateWidget(old);
    if (old.bands != widget.bands) limit = scaleForBands();
  }

  void endDrag() {
    if (dragging != null) {
      setState(() {
        dragging = null;
        dragScale = null;
      });
    }
  }

  int? hit(_Plot plot, Offset pos) {
    int? nearest;
    var best = 24.0;
    for (final (i, b) in widget.bands.indexed) {
      final distance = (plot.handle(b) - pos).distance;
      if (distance < best) {
        nearest = i;
        best = distance;
      }
    }
    return nearest;
  }

  @override
  Widget build(BuildContext context) {
    final scale = dragScale ?? limit;
    return LayoutBuilder(
      builder: (context, box) {
        final plot = _Plot(Size(box.maxWidth, widget.height), scale);
        return Semantics(
          label:
              'Filter response at 48 kHz, ${widget.bands.length} bands. Frequency and gain can also be adjusted below.',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (e) {
              final i = hit(plot, e.localPosition);
              if (i != null) widget.onSelect(i);
            },
            onPanDown: (e) {
              dragging = hit(plot, e.localPosition);
              if (dragging case final int i) {
                dragScale = scale;
                widget.onSelect(i);
              }
            },
            onPanUpdate: (e) {
              final i = dragging;
              if (i == null || i >= widget.bands.length) return;
              final b = widget.bands[i];
              final gain =
                  plot.gain(e.localPosition.dy) *
                  (b.shape == FilterShape.peak ? 1 : 2);
              widget.onMove(
                b.change(
                  hz: plot.frequency(e.localPosition.dx).roundToDouble(),
                  gain: (gain.clamp(-30, 30) * 10).round() / 10,
                ),
              );
            },
            onPanEnd: (_) => endDrag(),
            onPanCancel: endDrag,
            child: CustomPaint(
              size: Size(box.maxWidth, widget.height),
              painter: _ResponsePainter(widget.bands, widget.selected, scale),
            ),
          ),
        );
      },
    );
  }
}

class _ResponsePainter extends CustomPainter {
  final List<EqBand> bands;
  final int selected;
  final double limit;
  _ResponsePainter(this.bands, this.selected, this.limit);
  @override
  void paint(Canvas canvas, Size size) {
    final plot = _Plot(size, limit), area = plot.area;
    if (area.isEmpty) return;
    final line = Paint()..strokeWidth = 1;
    void label(
      String value,
      Offset at, {
      double align = 0,
      Color color = KalinkaColors.textSecondary,
    }) {
      final t = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            fontFamily: 'IBM Plex Mono',
            fontSize: 11,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      t.paint(
        canvas,
        Offset(
          (at.dx - align * t.width).clamp(0, math.max(0, size.width - t.width)),
          at.dy - t.height / 2,
        ),
      );
    }

    for (final f in [
      20,
      30,
      40,
      50,
      60,
      80,
      100,
      200,
      300,
      400,
      500,
      600,
      800,
      1000,
      2000,
      3000,
      4000,
      5000,
      6000,
      8000,
      10000,
      20000,
    ]) {
      final x = plot.x(f.toDouble());
      line.color = KalinkaColors.borderSubtle;
      canvas.drawLine(Offset(x, area.top), Offset(x, area.bottom), line);
    }
    for (final f in [20, 100, 1000, 10000, 20000]) {
      label(
        f >= 1000 ? '${f ~/ 1000}k' : '$f',
        Offset(plot.x(f.toDouble()), area.bottom + 15),
        align: 0.5,
      );
    }
    for (final g in [-limit, -limit / 2, 0.0, limit / 2, limit]) {
      final y = plot.y(g);
      line.color = g == 0
          ? KalinkaColors.borderDefault
          : KalinkaColors.borderSubtle;
      canvas.drawLine(Offset(area.left, y), Offset(area.right, y), line);
      label(
        '${g > 0 ? "+" : ""}${g.round()}',
        Offset(area.left - 9, y),
        align: 1,
      );
    }
    final responses = bands.map((b) => b.response(_rate)).toList();
    Path curve({int? solo}) {
      final path = Path();
      final n = math.max(1, (area.width / 2).ceil());
      for (var i = 0; i <= n; i++) {
        final x = area.left + area.width * i / n;
        final w = 2 * math.pi * plot.frequency(x) / _rate;
        final db = solo == null
            ? responses.fold<double>(0, (v, r) => v + r(w))
            : responses[solo](w);
        if (i == 0) {
          path.moveTo(x, plot.y(db));
        } else {
          path.lineTo(x, plot.y(db));
        }
      }
      return path;
    }

    canvas.save();
    canvas.clipRect(area.inflate(1));
    if (bands.length > 1 && selected >= 0 && selected < bands.length) {
      canvas.drawPath(
        curve(solo: selected),
        Paint()
          ..color = KalinkaColors.textMuted
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    final path = curve();
    final fill = Path.from(path)
      ..lineTo(area.right, area.bottom)
      ..lineTo(area.left, area.bottom)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            KalinkaColors.accent.withValues(alpha: .19),
            KalinkaColors.accent.withValues(alpha: .016),
          ],
        ).createShader(area),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = KalinkaColors.accentBright
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4,
    );
    canvas.restore();
    for (final (i, b) in bands.indexed) {
      final p = plot.handle(b);
      if (!area.inflate(1).contains(p)) continue;
      final active = i == selected;
      canvas.drawCircle(
        p,
        active ? 10 : 6,
        Paint()
          ..color = active
              ? KalinkaColors.textPrimary
              : KalinkaColors.surfaceElevated,
      );
      canvas.drawCircle(
        p,
        active ? 10 : 6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = active
              ? KalinkaColors.textPrimary
              : KalinkaColors.accentTint,
      );
      if (active) {
        label('${i + 1}', p, align: .5, color: KalinkaColors.background);
      }
    }
  }

  @override
  bool shouldRepaint(_ResponsePainter old) =>
      old.bands != bands || old.selected != selected || old.limit != limit;
}
