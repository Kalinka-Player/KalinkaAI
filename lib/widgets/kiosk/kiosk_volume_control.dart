import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data_model/data_model.dart' show DeviceVolume;
import '../../theme/app_theme.dart';
import '../volume_control_slider.dart' show OptimisticVolume;

/// Tall volume bar for the display's right edge, the speaker above it. It
/// comes up with a touch or when the volume changes from elsewhere, and
/// fades once left alone. Absent for outputs whose volume is fixed.
class KioskVolumeControl extends ConsumerStatefulWidget {
  final double scale;
  final bool visible;

  /// The bar was used, or the volume moved: keep it up a while longer.
  final VoidCallback onActivity;

  const KioskVolumeControl({
    super.key,
    required this.scale,
    required this.visible,
    required this.onActivity,
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
    if (previous.supported && previous.currentVolume != next.currentVolume) {
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
    if (!volume.supported) return const SizedBox.shrink();
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
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(s(38)),
            ),
            child: Column(
              children: [
                Icon(
                  level == 0
                      ? Icons.volume_off_rounded
                      : (level < 0.5
                            ? Icons.volume_down_rounded
                            : Icons.volume_up_rounded),
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
