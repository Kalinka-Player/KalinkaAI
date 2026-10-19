import 'package:flutter/material.dart';

/// How long the panel takes to slide in, and out again.
const Duration kSlideInPanelDuration = Duration(milliseconds: 320);

/// Full-bleed panel that slides in from the right over whatever hosts it.
///
/// Hosted as a `Positioned.fill` in a Stack rather than pushed as a route, so
/// the tablet layout can put it in the browsing pane while the phone layout
/// puts it over the whole screen — the same flag re-homes it across the
/// breakpoint.
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

  /// Return false to keep the panel open before its exit animation starts.
  final Future<bool> Function()? beforeClose;

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
    this.beforeClose,
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
  bool _closing = false;
  bool _allowPop = false;
  bool _started = false;

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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : kSlideInPanelDuration;
    if (!_started) {
      _started = true;
      _controller.forward().whenComplete(() {
        if (mounted) widget.onCoverageChanged?.call(true);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    var proceed = false;
    try {
      proceed = widget.beforeClose == null || await widget.beforeClose!();
    } finally {
      if (!proceed) _closing = false;
    }
    if (!proceed || !mounted) return;
    final onClose = widget.onClose;
    if (onClose == null) {
      setState(() => _allowPop = true);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
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
          // Keyed by what they hold, so one closing beneath another leaves
          // the other's state, and its animation, alone.
          for (final overlay in widget.overlays)
            Positioned.fill(key: overlay.key, child: overlay),
        ],
      ),
    );

    // As an overlay there is no route to pop, so intercept the system back to
    // animate out the same way the panel's own back control does.
    if (widget.onClose == null && widget.beforeClose == null) return content;
    return PopScope(
      canPop: widget.onClose == null && _allowPop,
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
