import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart' show DeviceVolume;
import '../../providers/app_state_provider.dart' show volumeAvailableProvider;
import '../../theme/app_theme.dart';
import '../volume_control_slider.dart' show OptimisticVolume;

/// Tall volume bar for the display's right edge, the speaker above it. It
/// comes up when the volume changes from elsewhere, and fades once left
/// alone. Absent for outputs whose volume is fixed.
class KioskVolumeControl extends ConsumerStatefulWidget {
  final double scale;
  final bool visible;

  /// The bar was used, or the volume moved: keep it up a while longer.
  final VoidCallback onActivity;

  /// A solid panel, for use over busy app screens rather than the kiosk's
  /// dimmed artwork.
  final bool opaque;

  /// Come up when the volume moves from elsewhere, not only when touched.
  final bool revealOnChange;

  const KioskVolumeControl({
    super.key,
    required this.scale,
    required this.visible,
    required this.onActivity,
    this.opaque = false,
    this.revealOnChange = true,
  });

  @override
  ConsumerState<KioskVolumeControl> createState() => _KioskVolumeControlState();
}

class _KioskVolumeControlState extends ConsumerState<KioskVolumeControl>
    with OptimisticVolume {
  double _dragLevel = 0;

  @override
  void onVolumeChanged(DeviceVolume previous, DeviceVolume next) {
    // The first reading after (re)connecting replaces the placeholder — no
    // one turned anything.
    if (widget.revealOnChange &&
        previous.supported &&
        previous.currentVolume != next.currentVolume) {
      widget.onActivity();
    }
  }

  double _levelAt(Offset local, double height) =>
      height > 0 ? (1 - local.dy / height).clamp(0.0, 1.0) : 0.0;

  void _adjust(double level) {
    _dragLevel = level;
    adjustVolume(level);
    widget.onActivity();
  }

  @override
  Widget build(BuildContext context) {
    if (!volumeAvailable) return const SizedBox.shrink();
    double s(double v) => v * widget.scale;
    final level = volumeProgress;

    return IgnorePointer(
      ignoring: !widget.visible,
      child: AnimatedOpacity(
        opacity: widget.visible ? 1 : 0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
        child: Semantics(
          label: 'Volume',
          value: '${(level * 100).round()}%',
          slider: true,
          child: Container(
            width: s(76),
            padding: EdgeInsets.symmetric(vertical: s(18)),
            decoration: widget.opaque
                ? BoxDecoration(
                    color: KalinkaColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(s(38)),
                    border: Border.all(color: KalinkaColors.borderDefault),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x80000000),
                        offset: Offset(0, 4),
                        blurRadius: 24,
                      ),
                    ],
                  )
                : BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(s(38)),
                  ),
            child: Column(
              children: [
                Icon(
                  kioskVolumeIcon(level),
                  size: s(30),
                  color: KalinkaColors.textPrimary,
                ),
                SizedBox(height: s(16)),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final height = constraints.maxHeight;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (d) {
                          final l = _levelAt(d.localPosition, height);
                          _adjust(l);
                          commitVolume(l);
                        },
                        onVerticalDragStart: (d) =>
                            _adjust(_levelAt(d.localPosition, height)),
                        onVerticalDragUpdate: (d) =>
                            _adjust(_levelAt(d.localPosition, height)),
                        onVerticalDragEnd: (_) => commitVolume(_dragLevel),
                        child: SizedBox(
                          width: s(76),
                          child: CustomPaint(
                            painter: _VolumePainter(
                              level: level,
                              thickness: s(isAdjustingVolume ? 22 : 18),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The volume as a bar across: the speaker, the bar with its knob, and the
/// level in figures. Absent for outputs whose volume is fixed.
class KioskVolumeSlider extends ConsumerStatefulWidget {
  final double scale;

  /// The bar was used, or the volume moved from elsewhere; null where
  /// nothing needs to know.
  final VoidCallback? onActivity;

  const KioskVolumeSlider({super.key, required this.scale, this.onActivity});

  @override
  ConsumerState<KioskVolumeSlider> createState() => _KioskVolumeSliderState();
}

class _KioskVolumeSliderState extends ConsumerState<KioskVolumeSlider>
    with OptimisticVolume {
  double _dragLevel = 0;

  @override
  void onVolumeChanged(DeviceVolume previous, DeviceVolume next) {
    // The first reading after (re)connecting replaces the placeholder — no
    // one turned anything.
    if (previous.supported && previous.currentVolume != next.currentVolume) {
      widget.onActivity?.call();
    }
  }

  /// The level under [local]: the painted track is inset by the knob's
  /// radius at either end, so the knob lands under the finger.
  double _levelAt(Offset local, double width) {
    final inset = widget.scale * (isAdjustingVolume ? 13 : 10);
    final track = width - 2 * inset;
    return track > 0 ? ((local.dx - inset) / track).clamp(0.0, 1.0) : 0.0;
  }

  void _adjust(double level) {
    _dragLevel = level;
    adjustVolume(level);
    widget.onActivity?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (!volumeAvailable) return const SizedBox.shrink();
    double s(double v) => v * widget.scale;
    final level = volumeProgress;

    return Semantics(
      label: 'Volume',
      value: '${(level * 100).round()}%',
      slider: true,
      child: Row(
        children: [
          Icon(
            kioskVolumeIcon(level),
            size: s(26),
            color: KalinkaColors.textPrimary,
          ),
          SizedBox(width: s(16)),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) {
                    final l = _levelAt(d.localPosition, width);
                    _adjust(l);
                    commitVolume(l);
                  },
                  onHorizontalDragStart: (d) =>
                      _adjust(_levelAt(d.localPosition, width)),
                  onHorizontalDragUpdate: (d) =>
                      _adjust(_levelAt(d.localPosition, width)),
                  onHorizontalDragEnd: (_) => commitVolume(_dragLevel),
                  child: SizedBox(
                    height: s(44),
                    child: CustomPaint(
                      painter: _SliderPainter(
                        level: level,
                        thickness: s(isAdjustingVolume ? 8 : 6),
                        knobRadius: s(isAdjustingVolume ? 13 : 10),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SizedBox(width: s(16)),
          SizedBox(
            width: s(52),
            child: Text(
              '${(level * 100).round()}%',
              textAlign: TextAlign.end,
              style: KalinkaFonts.sans(
                fontSize: s(18),
                fontWeight: FontWeight.w500,
                color: KalinkaColors.textPrimary,
              ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
        ],
      ),
    );
  }
}

/// The volume slider in a capsule, for hanging under the output pill: it
/// comes up when the volume changes from elsewhere and fades once left
/// alone. Absent for outputs whose volume is fixed.
class KioskVolumePopup extends ConsumerWidget {
  final double scale;
  final bool visible;

  /// The slider was used, or the volume moved: keep it up a while longer.
  final VoidCallback onActivity;

  const KioskVolumePopup({
    super.key,
    required this.scale,
    required this.visible,
    required this.onActivity,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(volumeAvailableProvider)) return const SizedBox.shrink();
    double s(double v) => v * scale;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
        child: Container(
          width: s(300),
          height: s(54),
          padding: EdgeInsets.symmetric(horizontal: s(20)),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(s(18)),
            border: Border.all(
              color: KalinkaColors.textPrimary.withValues(alpha: 0.16),
            ),
          ),
          // Its figures stay legible on the smallest screens.
          child: KioskVolumeSlider(
            scale: math.max(s(0.8), 0.55),
            onActivity: onActivity,
          ),
        ),
      ),
    );
  }
}

/// The speaker for a volume [level] from 0 to 1.
IconData kioskVolumeIcon(double level) => level == 0
    ? Icons.volume_off_rounded
    : (level < 0.5 ? Icons.volume_down_rounded : Icons.volume_up_rounded);

class _VolumePainter extends CustomPainter {
  final double level;
  final double thickness;

  _VolumePainter({required this.level, required this.thickness});

  @override
  void paint(Canvas canvas, Size size) {
    final track = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: thickness,
      height: size.height,
    );
    final radius = Radius.circular(thickness / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(track, radius),
      Paint()..color = Colors.white.withValues(alpha: 0.14),
    );
    if (level <= 0) return;
    final fill = Rect.fromLTRB(
      track.left,
      track.bottom - track.height * level,
      track.right,
      track.bottom,
    );
    // Spans the whole track: 70% at the foot, fully opaque at the top.
    final shader = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [Colors.white.withValues(alpha: 0.7), Colors.white],
    ).createShader(track);
    canvas.drawRRect(
      RRect.fromRectAndRadius(fill, radius),
      Paint()..shader = shader,
    );
  }

  @override
  bool shouldRepaint(_VolumePainter old) =>
      old.level != level || old.thickness != thickness;
}

/// A thin track filled in the accent up to the level, a white knob there.
class _SliderPainter extends CustomPainter {
  final double level;
  final double thickness;
  final double knobRadius;

  _SliderPainter({
    required this.level,
    required this.thickness,
    required this.knobRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    // The knob stays whole at either end.
    final left = knobRadius;
    final width = size.width - 2 * knobRadius;
    final radius = Radius.circular(thickness / 2);
    final track = Rect.fromLTWH(left, cy - thickness / 2, width, thickness);
    canvas.drawRRect(
      RRect.fromRectAndRadius(track, radius),
      Paint()..color = Colors.white.withValues(alpha: 0.24),
    );
    final head = left + width * level;
    if (level > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(left, track.top, head, track.bottom),
          radius,
        ),
        Paint()..color = KalinkaColors.accentTint,
      );
    }
    final centre = Offset(head, cy);
    canvas.drawCircle(
      centre,
      knobRadius + 2,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(centre, knobRadius, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_SliderPainter old) =>
      old.level != level ||
      old.thickness != thickness ||
      old.knobRadius != knobRadius;
}
