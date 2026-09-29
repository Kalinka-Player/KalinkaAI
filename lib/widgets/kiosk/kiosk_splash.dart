import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/app_theme.dart';

/// The Kalinka wordmark, full screen, for the first seconds of a display's
/// run — covering the moment the connection and the first cover are still on
/// their way. A glow rises behind it, holds, then the whole card fades into
/// the display. Never takes a touch.
class KioskSplash extends StatefulWidget {
  final VoidCallback onDone;

  const KioskSplash({super.key, required this.onDone});

  static const _rise = Duration(seconds: 2);
  static const _hold = Duration(seconds: 1);
  static const _fade = Duration(milliseconds: 700);
  static final duration = _rise + _hold + _fade;

  @override
  State<KioskSplash> createState() => _KioskSplashState();
}

/// Where the glow ends up: the canvas warmed a little towards the berry.
final _glow = Color.lerp(KalinkaColors.background, KalinkaColors.accent, 0.14)!;

class _KioskSplashState extends State<KioskSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: KioskSplash.duration,
  );

  late final Animation<double> _rise = CurvedAnimation(
    parent: _controller,
    curve: Interval(0, _at(KioskSplash._rise), curve: Curves.easeOut),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      _at(KioskSplash._rise + KioskSplash._hold),
      1,
      curve: Curves.easeInOut,
    ),
  );

  double _at(Duration d) =>
      d.inMicroseconds / KioskSplash.duration.inMicroseconds;

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logo = LayoutBuilder(
      builder: (context, constraints) => Center(
        child: SvgPicture.asset(
          'assets/images/kalinka_logo.svg',
          width: constraints.maxWidth * 0.62,
          height: constraints.maxHeight * 0.62,
          fit: BoxFit.contain,
        ),
      ),
    );

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        child: logo,
        builder: (context, logo) => Opacity(
          opacity: 1 - _fade.value,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 0.9,
                colors: [
                  Color.lerp(KalinkaColors.background, _glow, _rise.value)!,
                  KalinkaColors.background,
                ],
              ),
            ),
            child: logo,
          ),
        ),
      ),
    );
  }
}
