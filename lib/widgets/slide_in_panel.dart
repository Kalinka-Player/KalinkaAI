import 'package:flutter/material.dart';

/// How long the panel takes to slide in, and out again.
const Duration kSlideInPanelDuration = Duration(milliseconds: 320);

/// Full-bleed panel that slides in from the right over whatever hosts it.
///
/// Hosted as a `Positioned.fill` in a Stack rather than pushed as a route, so
/// the tablet layout can put it in the left panel while the phone layout puts
/// it over the whole screen — the same flag re-homes it across the breakpoint.
///
/// [onClose] non-null means overlay mode: the system back and the panel's own
/// back control both play the slide-out and then call it. Null means the panel
/// is a route, and `Navigator.pop` handles both.
///
/// [overlays] sit above the panel and do *not* slide with it — restart and
/// upgrade progress, which must stay put while the panel moves.
class SlideInPanel extends StatefulWidget {
  final Widget child;
  final List<Widget> overlays;
  final VoidCallback? onClose;

  /// Fires `true` once the slide-in finishes (the panel now fully covers what
  /// is behind it) and `false` the moment the slide-out begins. Lets the host
  /// stop painting the occluded content without flashing mid-animation.
  final ValueChanged<bool>? onCoverageChanged;

  /// False while a panel opened over this one owns the system back: every
  /// PopScope on a route hears it, so both would close.
  final bool handlesBack;

  const SlideInPanel({
    super.key,
    required this.child,
    this.overlays = const [],
    this.onClose,
    this.onCoverageChanged,
    this.handlesBack = true,
  });

  /// Dismiss the nearest enclosing panel, playing the slide-out first.
  static void closeOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_SlideInPanelScope>();
    assert(scope != null, 'No SlideInPanel above this widget');
    scope?.close();
  }

  @override
  State<SlideInPanel> createState() => _SlideInPanelState();
}

class _SlideInPanelState extends State<SlideInPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: kSlideInPanelDuration,
    );
    _slide = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: const Cubic(0.4, 0, 0.2, 1)),
    );
    _controller.forward().whenComplete(() {
      if (mounted) widget.onCoverageChanged?.call(true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    final onClose = widget.onClose;
    if (onClose == null) {
      // Route mode — the route transition animates the exit.
      Navigator.pop(context);
      return;
    }
    // Reveal what is behind us before sliding out, then remove.
    widget.onCoverageChanged?.call(false);
    await _controller.reverse();
    onClose();
  }

  @override
  Widget build(BuildContext context) {
    final content = _SlideInPanelScope(
      close: _close,
      child: Stack(
        children: [
          SlideTransition(position: _slide, child: widget.child),
          for (final overlay in widget.overlays)
            Positioned.fill(child: overlay),
        ],
      ),
    );

    // As an overlay there is no route to pop, so intercept the system back to
    // animate out the same way the panel's own back control does.
    if (widget.onClose == null) return content;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.handlesBack) _close();
      },
      child: content,
    );
  }
}

class _SlideInPanelScope extends InheritedWidget {
  final VoidCallback close;

  const _SlideInPanelScope({required this.close, required super.child});

  // `close` is a State method, so its identity never changes — descendants
  // that only call it never need rebuilding.
  @override
  bool updateShouldNotify(_SlideInPanelScope oldWidget) => false;
}
