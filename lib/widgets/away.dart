import 'package:flutter/widgets.dart';

/// Dims playback while the server is [away], the same way in the mini-player,
/// Now Playing and the kiosk.
class AwayDim extends StatelessWidget {
  final bool away;
  final Widget child;

  const AwayDim({super.key, required this.away, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: away ? 0.45 : 1.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      child: child,
    );
  }
}

/// Keeps taps and keyboard focus off a control while the server is [away].
class AwayLock extends StatelessWidget {
  final bool away;
  final Widget child;

  const AwayLock({super.key, required this.away, required this.child});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: away,
      child: ExcludeFocus(excluding: away, child: child),
    );
  }
}
