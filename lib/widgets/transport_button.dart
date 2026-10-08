import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Circular tappable wrapper for transport icons. Combines an InkWell ripple
/// with a scale-on-press animation so taps are obviously visible — important
/// for play/pause, where the white face washes out a typical ripple tint.
/// `background` paints the disc behind the icon (used by play/pause); leave
/// null for plain icon buttons that sit directly on the surface.
///
/// The press animation only scales down (0.92), so the control never grows
/// past its [hitDiameter] — safe inside tight rows like the mini player.
class TransportButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double hitDiameter;
  final Color? background;
  final Color? splashColor;
  final Color? highlightColor;

  const TransportButton({
    super.key,
    required this.child,
    required this.onTap,
    required this.hitDiameter,
    this.background,
    this.splashColor,
    this.highlightColor,
  });

  @override
  State<TransportButton> createState() => _TransportButtonState();
}

class _TransportButtonState extends State<TransportButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null;
    // Default ripple is a soft white tint that works against the dark
    // surface. Buttons with a light face override these.
    final defaultSplash = KalinkaColors.textPrimary.withValues(alpha: 0.20);
    final defaultHighlight = KalinkaColors.textPrimary.withValues(alpha: 0.10);

    return AnimatedScale(
      scale: _pressed ? 0.92 : 1.0,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: SizedBox(
        width: widget.hitDiameter,
        height: widget.hitDiameter,
        child: Material(
          color: widget.background ?? Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            // Drive the scale animation off the highlight signal so the
            // press state matches what the ripple shows.
            onHighlightChanged: (highlighted) {
              if (disabled) return;
              if (highlighted == _pressed) return;
              setState(() => _pressed = highlighted);
            },
            customBorder: const CircleBorder(),
            splashColor: widget.splashColor ?? defaultSplash,
            highlightColor: widget.highlightColor ?? defaultHighlight,
            child: Center(child: widget.child),
          ),
        ),
      ),
    );
  }
}
