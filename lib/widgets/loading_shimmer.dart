import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared motion for loading placeholders; reduced motion leaves them still.
class ShimmerPulse extends StatefulWidget {
  final Widget child;

  const ShimmerPulse({super.key, required this.child});

  @override
  State<ShimmerPulse> createState() => _ShimmerPulseState();
}

class _ShimmerPulseState extends State<ShimmerPulse>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final _opacity = Tween<double>(
    begin: 0.55,
    end: 1,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: MediaQuery.disableAnimationsOf(context)
          ? widget.child
          : FadeTransition(opacity: _opacity, child: widget.child),
    ),
  );
}

/// A neutral shape shared by row, card and artwork placeholders.
class ShimmerBlock extends StatelessWidget {
  final double? width;
  final double? height;
  final double radius;

  const ShimmerBlock({super.key, this.width, this.height, this.radius = 6});

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: KalinkaColors.surfaceOverlay,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}
