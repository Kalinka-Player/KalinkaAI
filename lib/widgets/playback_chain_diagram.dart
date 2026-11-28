import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../theme/app_theme.dart';
import 'audio_signal_path.dart';
import 'tap_highlight.dart';

const _markerSize = 32.0;
const _turnGutter = 18.0;
const _rowTop = 8.0;
const _lineColor = KalinkaColors.textMuted;

/// A vertical signal path beside settings, or a folded path above them.
class PlaybackChainDiagram extends StatelessWidget {
  final List<SignalStage> stages;
  final bool vertical;
  final VoidCallback? Function(String kind) shortcutFor;

  const PlaybackChainDiagram({
    super.key,
    required this.stages,
    required this.vertical,
    required this.shortcutFor,
  });

  @override
  Widget build(BuildContext context) {
    if (stages.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final slotWidth = 124 * MediaQuery.textScalerOf(context).scale(16) / 16;
        final columns = ((constraints.maxWidth - 2 * _turnGutter) / slotWidth)
            .floor()
            .clamp(1, 4);
        final linear = vertical || columns == 1;
        final perRow = linear ? 1 : math.min(columns, stages.length);
        return FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var start = 0; start < stages.length; start += perRow)
                _row(start, perRow, linear),
            ],
          ),
        );
      },
    );
  }

  Widget _row(int start, int columns, bool linear) {
    final count = math.min(columns, stages.length - start);
    final reverse = (start ~/ columns).isOdd;
    return CustomPaint(
      painter: _TrackPainter(
        columns: columns,
        count: count,
        reverse: reverse,
        linear: linear,
        incoming: start > 0,
        outgoing: start + count < stages.length,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          linear ? 0 : _turnGutter,
          _rowTop,
          linear ? 0 : _turnGutter,
          12,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          textDirection: reverse && !linear
              ? TextDirection.rtl
              : TextDirection.ltr,
          children: [
            for (var i = start; i < start + count; i++)
              Expanded(
                child: FocusTraversalOrder(
                  order: NumericFocusOrder(i.toDouble()),
                  child: _Stage(
                    stage: stages[i],
                    onTap: shortcutFor(stages[i].kind),
                    index: i,
                    endpoint: i == 0 || i == stages.length - 1,
                    linear: linear,
                  ),
                ),
              ),
            if (count < columns) Spacer(flex: columns - count),
          ],
        ),
      ),
    );
  }
}

class _Stage extends StatelessWidget {
  final SignalStage stage;
  final VoidCallback? onTap;
  final int index;
  final bool endpoint, linear;

  const _Stage({
    required this.stage,
    required this.onTap,
    required this.index,
    required this.endpoint,
    required this.linear,
  });

  @override
  Widget build(BuildContext context) {
    final marker = Container(
      width: _markerSize,
      height: _markerSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: endpoint
            ? KalinkaColors.accentFaded
            : KalinkaColors.surfaceRaised,
        border: Border.all(
          color: endpoint ? KalinkaColors.accent : KalinkaColors.textMuted,
        ),
      ),
      child: Icon(
        stage.icon,
        size: 17,
        color: endpoint
            ? KalinkaColors.accentBright
            : KalinkaColors.textPrimary,
      ),
    );
    final align = linear ? TextAlign.start : TextAlign.center;
    final label = Column(
      crossAxisAlignment: linear
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Wrap(
          alignment: linear ? WrapAlignment.start : WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text(
              stage.label,
              style: onTap == null
                  ? KalinkaTextStyles.trayRowLabel
                  : KalinkaTextStyles.trayRowLabel.copyWith(
                      decoration: TextDecoration.underline,
                      decorationColor: KalinkaColors.textMuted,
                    ),
              textAlign: align,
            ),
            if (stage.bitPerfect case final kept?) StepMark(bitPerfect: kept),
          ],
        ),
        if (stage.detail.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            stage.detail,
            style: KalinkaTextStyles.trayRowSublabel,
            textAlign: align,
          ),
        ],
      ],
    );
    final content = linear
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              marker,
              const SizedBox(width: 10),
              Expanded(child: label),
            ],
          )
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Column(children: [marker, const SizedBox(height: 7), label]),
          );
    return Semantics(
      container: true,
      sortKey: OrdinalSortKey(index.toDouble()),
      label: [
        stage.label,
        if (stage.detail.isNotEmpty) stage.detail,
        if (stage.bitPerfect case final kept?) stepMarkLabel(kept),
      ].join(', '),
      button: onTap == null ? null : true,
      onTap: onTap,
      excludeSemantics: true,
      child: onTap == null
          ? content
          : TapHighlight(
              onTap: onTap,
              focusable: true,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: kMinInteractiveDimension,
                ),
                child: Align(alignment: Alignment.topCenter, child: content),
              ),
            ),
    );
  }
}

/// Each row paints its own part of the continuous line, after its labels have
/// determined its height. Adjacent rows meet at the same outer edge.
class _TrackPainter extends CustomPainter {
  final int columns, count;
  final bool reverse, linear, incoming, outgoing;

  const _TrackPainter({
    required this.columns,
    required this.count,
    required this.reverse,
    required this.linear,
    required this.incoming,
    required this.outgoing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = _lineColor
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    const y = _rowTop + _markerSize / 2;
    if (linear) {
      const x = _markerSize / 2;
      canvas.drawLine(
        Offset(x, incoming ? 0 : y),
        Offset(x, outgoing ? size.height : y),
        pen,
      );
      return;
    }

    final slot = (size.width - 2 * _turnGutter) / columns;
    final first = reverse
        ? size.width - _turnGutter - slot / 2
        : _turnGutter + slot / 2;
    final direction = reverse ? -1.0 : 1.0;
    final last = first + direction * slot * (count - 1);
    const radius = 20.0;
    final path = Path();
    if (incoming) {
      final edge = reverse ? size.width - 2 : 2.0;
      path.moveTo(edge, 0);
      path.lineTo(edge, y - radius);
      path.arcToPoint(
        Offset(edge + direction * radius, y),
        radius: const Radius.circular(radius),
        clockwise: reverse,
      );
      path.lineTo(first, y);
    } else {
      path.moveTo(first, y);
    }
    path.lineTo(last, y);
    if (outgoing) {
      final edge = reverse ? 2.0 : size.width - 2;
      path.lineTo(edge - direction * radius, y);
      path.arcToPoint(
        Offset(edge, y + radius),
        radius: const Radius.circular(radius),
        clockwise: !reverse,
      );
      path.lineTo(edge, size.height);
    }
    for (var i = 1; i < count; i++) {
      final x = first + direction * slot * (i - .5);
      path.moveTo(x - direction * 3, y - 3);
      path.lineTo(x, y);
      path.lineTo(x - direction * 3, y + 3);
    }
    canvas.drawPath(path, pen);
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.columns != columns ||
      old.count != count ||
      old.reverse != reverse ||
      old.linear != linear ||
      old.incoming != incoming ||
      old.outgoing != outgoing;
}
