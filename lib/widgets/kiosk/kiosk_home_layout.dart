import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Lays out the local display's browsing UI in readable logical pixels.
/// The separate now-playing route already scales its own controls.
class KioskHomeLayout extends StatelessWidget {
  const KioskHomeLayout({
    super.key,
    required this.diagonalInches,
    required this.child,
  });

  final double? diagonalInches;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Without a usable EDID, infer physical size from flutter-pi's logical
    // pixels (38 per cm). At its fallback DPR of 1 this is an estimate.
    final inches =
        diagonalInches ??
        (media.size.bottomRight(Offset.zero).distance / (38 * 2.54));
    // Use the layout tested on the 65-inch 4K TV as the full-size target.
    const target = Size(1368, 769.5);
    // The 7-inch panel keeps its native layout. Below 55 inches, introduce
    // the TV zoom gradually, and only when there is room on both axes.
    final tvWeight = ((inches - 7) / (55 - 7)).clamp(0.0, 1.0);
    final tvScale = math.min(
      media.size.longestSide / target.width,
      media.size.shortestSide / target.height,
    );
    final scale = 1 + tvWeight * math.max(0.0, tvScale - 1);
    final size = media.size / scale;
    // Keep the same subtree across resizes, including transitions through
    // 1x. Layout breakpoints, hit tests and image decoding follow the zoom.
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox.fromSize(
        size: size,
        child: MediaQuery(
          data: media.copyWith(
            size: size,
            devicePixelRatio: media.devicePixelRatio * scale,
            padding: media.padding / scale,
            viewPadding: media.viewPadding / scale,
            viewInsets: media.viewInsets / scale,
            systemGestureInsets: media.systemGestureInsets / scale,
          ),
          child: child,
        ),
      ),
    );
  }
}
