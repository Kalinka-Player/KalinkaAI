import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../providers/connection_state_provider.dart' show ConnectionStatus;
import '../theme/app_theme.dart';

enum GradientProgressLineMode { normal, reconnecting, offline }

/// The line's mode for the connection to the server.
GradientProgressLineMode progressLineModeFor(ConnectionStatus status) =>
    switch (status) {
      ConnectionStatus.reconnecting => GradientProgressLineMode.reconnecting,
      ConnectionStatus.offline => GradientProgressLineMode.offline,
      _ => GradientProgressLineMode.normal,
    };

/// A mini-player progress line with online/reconnecting/offline visual modes.
///
/// In [GradientProgressLineMode.normal] the filled portion uses the standard
/// progress gradient. In [reconnecting] and [offline] modes the bar shows a
/// full-width shimmer sweep instead of a progress fill, so the user knows the
/// position can't be trusted. A faint echo of the last-known position is still
/// drawn underneath the shimmer.
class GradientProgressLine extends StatefulWidget {
  final double progress;
  final double height;
  final GradientProgressLineMode mode;

  const GradientProgressLine({
    super.key,
    required this.progress,
    required this.mode,
    this.height = 2,
  });

  @override
  State<GradientProgressLine> createState() => _GradientProgressLineState();
}

class _GradientProgressLineState extends State<GradientProgressLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerController;

  bool get _isDisconnected =>
      widget.mode == GradientProgressLineMode.reconnecting ||
      widget.mode == GradientProgressLineMode.offline;

  Duration get _shimmerDuration =>
      widget.mode == GradientProgressLineMode.offline
          ? const Duration(milliseconds: 1800)
          : const Duration(milliseconds: 1200);

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: _shimmerDuration,
    );
    _syncShimmerAnimation();
  }

  @override
  void didUpdateWidget(covariant GradientProgressLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode ||
        oldWidget.progress != widget.progress) {
      _syncShimmerAnimation();
    }
  }

  void _syncShimmerAnimation() {
    if (_isDisconnected) {
      _shimmerController.duration = _shimmerDuration;
      if (!_shimmerController.isAnimating) {
        _shimmerController.repeat(reverse: true);
      }
      return;
    }

    if (_shimmerController.isAnimating) {
      _shimmerController.stop();
    }
    _shimmerController.value = 0.0;
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isDisconnected) {
      return AnimatedBuilder(
        animation: _shimmerController,
        builder: (context, _) {
          return CustomPaint(
            size: Size(double.infinity, widget.height),
            painter: _GradientProgressPainter(
              progress: widget.progress,
              mode: widget.mode,
              shimmerProgress: _shimmerController.value,
            ),
          );
        },
      );
    }

    return CustomPaint(
      size: Size(double.infinity, widget.height),
      painter: _GradientProgressPainter(
        progress: widget.progress,
        mode: widget.mode,
        shimmerProgress: 0.0,
      ),
    );
  }
}

class _GradientProgressPainter extends CustomPainter {
  final double progress;
  final GradientProgressLineMode mode;
  final double shimmerProgress;

  _GradientProgressPainter({
    required this.progress,
    required this.mode,
    required this.shimmerProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background track
    final bgPaint = Paint()..color = KalinkaColors.borderSubtle;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    if (mode == GradientProgressLineMode.normal) {
      final clampedProgress = progress.clamp(0.0, 1.0).toDouble();
      final fillWidth = size.width * clampedProgress;
      if (fillWidth > 0) {
        final fillPaint = Paint()
          ..shader = KalinkaColors.progressGradient.createShader(
            Rect.fromLTWH(0, 0, size.width, size.height),
          );
        canvas.drawRect(
          Rect.fromLTWH(0, 0, fillWidth, size.height),
          fillPaint,
        );
      }
      return;
    }

    // Disconnected modes: replace progress fill with a full-width shimmer.
    final shimmerColor = mode == GradientProgressLineMode.offline
        ? KalinkaColors.statusOffline
        : KalinkaColors.statusPending;

    // Faint echo of the last-known position so users can see where it was.
    final clampedProgress = progress.clamp(0.0, 1.0).toDouble();
    final fillWidth = size.width * clampedProgress;
    if (fillWidth > 0) {
      final echoPaint = Paint()
        ..color = shimmerColor.withValues(alpha: 0.18);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, fillWidth, size.height),
        echoPaint,
      );
    }

    // Shimmer sweep — wide brush travelling left→right across the full bar.
    final shimmerWidth = (size.width * 0.45).clamp(20.0, 160.0).toDouble();
    final travelDistance = math.max(size.width - shimmerWidth, 0.0);
    final shimmerLeft = shimmerProgress * travelDistance;
    final shimmerRect = Rect.fromLTWH(shimmerLeft, 0, shimmerWidth, size.height);

    final shimmerAlpha =
        mode == GradientProgressLineMode.offline ? 0.35 : 0.50;
    final shimmerPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          shimmerColor.withValues(alpha: 0.0),
          shimmerColor.withValues(alpha: shimmerAlpha),
          shimmerColor.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(shimmerRect);
    canvas.drawRect(shimmerRect, shimmerPaint);
  }

  @override
  bool shouldRepaint(_GradientProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.mode != mode ||
        oldDelegate.shimmerProgress != shimmerProgress;
  }
}
