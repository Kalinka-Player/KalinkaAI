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
  Offset handle(EqBand b) => Offset(x(b.hz), y(b.handleGain));
}

class ResponseGraph extends StatefulWidget {
  const ResponseGraph({
    super.key,
    required this.bands,
    required this.selected,
    required this.responseColor,
    required this.onSelect,
    this.onMove,
    this.onAdd,
    this.height = 240,
  });
  final List<EqBand> bands;
  final int selected;
  final Color responseColor;
  final ValueChanged<int> onSelect;
  final void Function(int, EqBand)? onMove;
  final ValueChanged<EqBand>? onAdd;
  final double height;
  @override
  State<ResponseGraph> createState() => _ResponseGraphState();
}

class _ResponseGraphState extends State<ResponseGraph> {
  int? dragging;
  double? dragScale;
  Offset? addPosition;
  EqBand? preview;
  late double limit = scaleForBands();
  double scaleForBands() {
    final responses = widget.bands.map((b) => b.response(_rate)).toList();
    var peak = widget.bands.fold<double>(
      3,
      (v, b) => math.max(v, b.handleGain.abs()),
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
    if (old.bands != widget.bands) {
      limit = scaleForBands();
      dragging = null;
      dragScale = null;
      preview = null;
    }
  }

  void endDrag({bool commit = false}) {
    final moved = preview;
    final index = dragging;
    if (index != null) {
      setState(() {
        dragging = null;
        dragScale = null;
        preview = null;
      });
      if (commit && moved != null) widget.onMove?.call(index, moved);
    }
  }

  int? hit(_Plot plot, Offset pos) {
    int? nearest;
    var best = 24.0;
    for (final (i, b) in widget.bands.indexed) {
      final distance = (plot.handle(b) - pos).distance;
      if (distance < best || (distance == best && i == widget.selected)) {
        nearest = i;
        best = distance;
      }
    }
    return nearest;
  }

  @override
  Widget build(BuildContext context) {
    final scale = dragScale ?? limit;
    var plotted = widget.bands;
    final index = dragging;
    if (preview != null && index != null && index < plotted.length) {
      plotted = [...plotted]..[index] = preview!;
    }
    return LayoutBuilder(
      builder: (context, box) {
        final plot = _Plot(Size(box.maxWidth, widget.height), scale);
        Offset graphPosition(Offset global) =>
            (context.findRenderObject()! as RenderBox).globalToLocal(global);
        return Semantics(
          label:
              'EQ band response at 48 kHz, ${widget.bands.length} bands. Edit individual bands in the band list.',
          child: SizedBox(
            width: box.maxWidth,
            height: widget.height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    excludeFromSemantics: true,
                    onDoubleTapDown: widget.onAdd == null
                        ? null
                        : (e) => addPosition = e.localPosition,
                    onDoubleTap: widget.onAdd == null
                        ? null
                        : () {
                            final p = addPosition;
                            if (p == null || !plot.area.contains(p)) return;
                            widget.onAdd!(
                              EqBand(
                                hz: plot.frequency(p.dx).roundToDouble(),
                                gain:
                                    (plot.gain(p.dy).clamp(-30, 30) * 10)
                                        .round() /
                                    10,
                              ),
                            );
                          },
                    child: CustomPaint(
                      painter: _ResponsePainter(
                        plotted,
                        widget.selected,
                        scale,
                        widget.responseColor,
                      ),
                    ),
                  ),
                ),
                // Only handles claim drags, so a swipe on empty space scrolls the phone page.
                for (final b in widget.bands)
                  if (plot.area.inflate(1).contains(plot.handle(b)))
                    Positioned.fromRect(
                      rect: Rect.fromCenter(
                        center: plot.handle(b),
                        width: 40,
                        height: 40,
                      ),
                      child: MouseRegion(
                        cursor: widget.onMove == null
                            ? SystemMouseCursors.click
                            : SystemMouseCursors.grab,
                        child: GestureDetector(
                          excludeFromSemantics: true,
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (e) {
                            final i = hit(
                              plot,
                              graphPosition(e.globalPosition),
                            );
                            if (i != null) widget.onSelect(i);
                          },
                          onPanDown: widget.onMove == null
                              ? null
                              : (e) {
                                  dragging = hit(
                                    plot,
                                    graphPosition(e.globalPosition),
                                  );
                                  if (dragging case final int i) {
                                    dragScale = scale;
                                    widget.onSelect(i);
                                  }
                                },
                          onPanUpdate: widget.onMove == null
                              ? null
                              : (e) {
                                  final i = dragging;
                                  if (i == null || i >= widget.bands.length) {
                                    return;
                                  }
                                  final b = widget.bands[i];
                                  final p = graphPosition(e.globalPosition);
                                  final gain =
                                      plot.gain(p.dy) *
                                      (b.shape == FilterShape.peak ? 1 : 2);
                                  setState(
                                    () => preview = b.change(
                                      hz: plot.frequency(p.dx).roundToDouble(),
                                      gain: b.shape.hasGain
                                          ? (gain.clamp(-30, 30) * 10).round() /
                                                10
                                          : null,
                                    ),
                                  );
                                },
                          onPanEnd: widget.onMove == null
                              ? null
                              : (_) => endDrag(commit: true),
                          onPanCancel: widget.onMove == null ? null : endDrag,
                        ),
                      ),
                    ),
              ],
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
  final Color responseColor;
  _ResponsePainter(this.bands, this.selected, this.limit, this.responseColor);
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
    for (final f in [
      20,
      if (area.width > 450) 50,
      100,
      if (area.width > 450) 200,
      if (area.width > 450) 500,
      1000,
      if (area.width > 450) 2000,
      if (area.width > 450) 5000,
      10000,
      20000,
    ]) {
      label(
        f >= 1000 ? '${f ~/ 1000}k' : '$f',
        Offset(plot.x(f.toDouble()), area.bottom + 15),
        align: 0.5,
      );
    }
    // Keep the five dB labels readable while adding guides between them.
    final subdivisions = (area.height / (4 * 16)).round().clamp(2, 4);
    final halfSteps = 2 * subdivisions;
    for (var step = -halfSteps; step <= halfSteps; step++) {
      final gain = limit * step / halfSteps;
      final y = plot.y(gain);
      final major = step % subdivisions == 0;
      line.color = step == 0
          ? KalinkaColors.borderDefault
          : major
          ? KalinkaColors.textSecondary.withValues(alpha: .2)
          : KalinkaColors.borderSubtle;
      canvas.drawLine(Offset(area.left, y), Offset(area.right, y), line);
      if (major) {
        label(
          '${gain > 0 ? "+" : ""}${gain.round()}',
          Offset(area.left - 9, y),
          align: 1,
        );
      }
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
            responseColor.withValues(alpha: .065),
            responseColor.withValues(alpha: .005),
          ],
        ).createShader(area),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = responseColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.restore();
    // Paint the selected handle last so it stays legible when bands overlap.
    for (final i in [
      for (var i = 0; i < bands.length; i++)
        if (i != selected) i,
      if (selected >= 0 && selected < bands.length) selected,
    ]) {
      final p = plot.handle(bands[i]);
      if (!area.inflate(1).contains(p)) continue;
      final active = i == selected;
      final radius = active ? 12.0 : 9.5;
      canvas.drawCircle(p, radius, Paint()..color = KalinkaColors.textPrimary);
      canvas.drawCircle(
        p,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = active ? 3 : 2
          ..color = KalinkaColors.accent,
      );
      label(
        '${i + 1}',
        p,
        align: .5,
        color: active ? KalinkaColors.accent : KalinkaColors.background,
      );
    }
  }

  @override
  bool shouldRepaint(_ResponsePainter old) =>
      old.bands != bands ||
      old.selected != selected ||
      old.limit != limit ||
      old.responseColor != responseColor;
}
