import 'package:flutter/material.dart';

/// Fades the ends of the scrollable [child] along [axis], each as far as
/// there is more to scroll that way: a hint that the content goes on, gone
/// once there is nothing more on that side.
class ScrollEdgeFade extends StatefulWidget {
  final Widget child;
  final Axis axis;

  /// How far in from each end the fade reaches, at its fullest.
  final double extent;

  const ScrollEdgeFade({
    super.key,
    required this.child,
    this.axis = Axis.vertical,
    this.extent = 24,
  });

  @override
  State<ScrollEdgeFade> createState() => _ScrollEdgeFadeState();
}

class _ScrollEdgeFadeState extends State<ScrollEdgeFade> {
  /// How far each end fades, 0 to 1: the content left to scroll that way,
  /// up to [ScrollEdgeFade.extent].
  double _before = 0;
  double _after = 0;

  bool _onMetrics(ScrollMetrics metrics, int depth) {
    // Only the scrollable it wraps, not one nested in it.
    if (depth != 0 || metrics.axis != widget.axis) return false;
    final extent = widget.extent;
    final before = ((metrics.pixels - metrics.minScrollExtent) / extent).clamp(
      0.0,
      1.0,
    );
    final after = ((metrics.maxScrollExtent - metrics.pixels) / extent).clamp(
      0.0,
      1.0,
    );
    if (before != _before || after != _after) {
      setState(() {
        _before = before;
        _after = after;
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final vertical = widget.axis == Axis.vertical;
    // Fires on first layout too, so a list that overflows fades from the
    // start, before any scroll.
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => _onMetrics(n.metrics, n.depth),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => _onMetrics(n.metrics, n.depth),
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) {
            final length = vertical ? bounds.height : bounds.width;
            final stop = length <= 0
                ? 0.0
                : (widget.extent / length).clamp(0.0, 0.5);
            return LinearGradient(
              begin: vertical ? Alignment.topCenter : Alignment.centerLeft,
              end: vertical ? Alignment.bottomCenter : Alignment.centerRight,
              colors: [
                Colors.white.withValues(alpha: 1 - _before),
                Colors.white,
                Colors.white,
                Colors.white.withValues(alpha: 1 - _after),
              ],
              stops: [0, stop, 1 - stop, 1],
            ).createShader(bounds);
          },
          child: widget.child,
        ),
      ),
    );
  }
}
