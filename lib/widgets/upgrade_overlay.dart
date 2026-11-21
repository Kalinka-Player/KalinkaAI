import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/upgrade_provider.dart';
import '../theme/app_theme.dart';
import '../utils/haptics.dart';
import 'progress_timeline.dart';

/// Full-screen overlay showing upgrade progress on a timeline: installing
/// and reconnecting, or updating packages when the server keeps its version.
///
/// Unlike [RestartOverlay] there is no dismiss affordance — the upgrade
/// can't be left half-watched, since the server is being replaced under
/// the app. The only exits are success (auto-dismiss) and an error
/// (explicit Close button).
class UpgradeOverlay extends ConsumerStatefulWidget {
  final VoidCallback onDismiss;

  const UpgradeOverlay({super.key, required this.onDismiss});

  @override
  ConsumerState<UpgradeOverlay> createState() => _UpgradeOverlayState();
}

class _UpgradeOverlayState extends ConsumerState<UpgradeOverlay>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _unpackController;
  Timer? _autoDismissTimer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..forward();
    _unpackController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _unpackController.dispose();
    _autoDismissTimer?.cancel();
    super.dispose();
  }

  void _close() {
    _closing = true;
    _autoDismissTimer?.cancel();
    // Fade out first: resetting the provider unmounts this overlay (the
    // settings screen shows it while isUpgrading), so it must come last.
    _fadeController.reverse().then((_) {
      if (!mounted) return;
      widget.onDismiss();
      ref.read(upgradeProvider.notifier).dismiss();
    });
  }

  // A run started during the fade-out would be wiped by dismiss() mid-flight.
  void _retry() {
    if (!_closing) ref.read(upgradeProvider.notifier).retry();
  }

  void _scheduleAutoDismiss() {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = Timer(const Duration(milliseconds: 2600), _close);
  }

  @override
  Widget build(BuildContext context) {
    final upgradeState = ref.watch(upgradeProvider);

    ref.listen(upgradeProvider, (prev, next) {
      if (prev != null && !prev.isDone && next.isDone) KalinkaHaptics.success();
    });

    final still = MediaQuery.disableAnimationsOf(context);
    // A stopped box draws nothing new: don't keep ticking frames for it.
    if (upgradeState.isDone || still) {
      _unpackController.stop();
    } else if (!_unpackController.isAnimating) {
      _unpackController.repeat();
    }
    if (upgradeState.isDone && _autoDismissTimer == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduleAutoDismiss();
      });
    }

    return FadeTransition(
      opacity: _fadeController,
      child: ProgressScrim(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Container(
                key: ValueKey(upgradeState.isDone),
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: upgradeState.isDone
                      ? KalinkaColors.statusOnline.withValues(alpha: 0.14)
                      : KalinkaColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: upgradeState.isDone
                        ? KalinkaColors.statusOnline.withValues(alpha: 0.25)
                        : KalinkaColors.borderDefault,
                  ),
                ),
                child: upgradeState.isDone
                    ? const Icon(
                        Icons.check_rounded,
                        size: 28,
                        color: KalinkaColors.statusOnline,
                      )
                    : Center(
                        child: CustomPaint(
                          size: const Size.square(28),
                          painter: _UnpackingBoxPainter(
                            // Reduced motion: hold the open box, arrow out.
                            t: still
                                ? const AlwaysStoppedAnimation(0.35)
                                : _unpackController,
                            color: KalinkaColors.textSecondary,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              upgradeState.upToDate
                  ? 'Already up to date'
                  : upgradeState.isDone
                  ? 'Upgrade complete'
                  : 'Upgrading server',
              style: KalinkaTextStyles.dialogTitle,
            ),
            const SizedBox(height: 6),
            Text(
              _subtitle(upgradeState),
              textAlign: TextAlign.center,
              style: KalinkaTextStyles.trayRowSublabel.copyWith(
                fontSize: KalinkaTypography.baseSize + 1,
                color: KalinkaColors.textSecondary,
              ),
            ),
            if (upgradeState.note != null) ...[
              const SizedBox(height: 6),
              Text(
                upgradeState.note!,
                textAlign: TextAlign.center,
                style: KalinkaTextStyles.trayRowSublabel.copyWith(
                  color: KalinkaColors.textSecondary,
                ),
              ),
            ],
            if (!upgradeState.upToDate) ...[
              const SizedBox(height: 28),
              _buildProgressBar(upgradeState),
              const SizedBox(height: 24),
              ..._buildSteps(upgradeState),
            ],
            if (upgradeState.error != null) ...[
              const SizedBox(height: 16),
              Text(
                upgradeState.error!,
                textAlign: TextAlign.center,
                style: KalinkaTextStyles.trayRowSublabel.copyWith(
                  color: KalinkaColors.statusOffline,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 24,
                children: [
                  if (upgradeState.canRetry) _link('Retry', _retry),
                  _link('Close', _close),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _subtitle(UpgradeState upgradeState) {
    final target = upgradeState.targetVersion;
    if (upgradeState.upToDate) {
      return 'The server runs version $target, with nothing left to install.';
    }
    return switch ((upgradeState.isDone, upgradeState.packagesOnly)) {
      (true, false) => 'Now running version $target.',
      (true, true) => 'All packages are up to date.',
      (false, false) =>
        'Installing version $target… this can take several minutes.',
      (false, true) =>
        'Installing the new packages… this can take several minutes.',
    };
  }

  Widget _link(String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Text(
      label,
      style: KalinkaTextStyles.trayRowSublabel.copyWith(
        color: KalinkaColors.textSecondary,
        decoration: TextDecoration.underline,
        decorationColor: KalinkaColors.textSecondary,
      ),
    ),
  );

  List<(UpgradeStep, String, String)> _steps(UpgradeState upgradeState) =>
      upgradeState.packagesOnly
      ? const [
          (
            UpgradeStep.updatingPackages,
            'Updating packages',
            'Waiting for the installer to finish',
          ),
        ]
      : const [
          (
            UpgradeStep.installing,
            'Installing new version',
            'Downloading and installing packages',
          ),
          (UpgradeStep.reconnecting, 'Reconnecting', 'Waiting for server'),
        ];

  Widget _buildProgressBar(UpgradeState upgradeState) {
    final progress =
        upgradeState.completedSteps.length / _steps(upgradeState).length;
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: 4,
          decoration: BoxDecoration(
            color: KalinkaColors.surfaceElevated,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: const Cubic(0.4, 0, 0.2, 1),
              width: constraints.maxWidth * progress,
              height: 4,
              decoration: BoxDecoration(
                color: progress > 0 ? KalinkaColors.accent : null,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildSteps(UpgradeState upgradeState) {
    final steps = _steps(upgradeState);
    return [
      for (final (i, (step, label, sublabel)) in steps.indexed)
        TimelineStep(
          label: label,
          sublabel: sublabel,
          done: upgradeState.completedSteps.contains(step),
          active: upgradeState.currentStep == step,
          last: i == steps.length - 1,
        ),
    ];
  }
}

/// A box whose flaps swing open for an arrow to rise out and fade, then
/// close again: the new version coming out of its package. One cycle per
/// run of [t], drawn on a 28-unit grid.
class _UnpackingBoxPainter extends CustomPainter {
  final Animation<double> t;
  final Color color;

  _UnpackingBoxPainter({required this.t, required this.color})
    : super(repaint: t);

  static const _opening = Interval(0, .2, curve: Curves.easeOutBack);
  static const _rising = Interval(.15, .62, curve: Curves.easeOutCubic);
  static const _fading = Interval(.45, .62, curve: Curves.easeIn);
  static const _closing = Interval(.66, .84, curve: Curves.easeInOutCubic);

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    canvas.scale(size.width / 28);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Flaps hinge on the top corners, meet in the middle when shut and
    // swing out to 120° (a little past it on the bounce).
    final a =
        _opening.transform(v) * (1 - _closing.transform(v)) * math.pi * 2 / 3;
    final dx = 8 * math.cos(a), dy = 8 * math.sin(a);
    canvas.drawPath(
      Path()
        ..addRRect(
          RRect.fromLTRBAndCorners(
            6,
            12,
            22,
            22,
            bottomLeft: const Radius.circular(2),
            bottomRight: const Radius.circular(2),
          ),
        )
        ..moveTo(11.5, 16.5)
        ..lineTo(16.5, 16.5)
        ..moveTo(6, 12)
        ..lineTo(6 + dx, 12 - dy)
        ..moveTo(22, 12)
        ..lineTo(22 - dx, 12 - dy),
      paint,
    );

    final rise = _rising.transform(v);
    final fade = 1 - _fading.transform(v);
    if (rise == 0 || fade == 0) return;
    final tip = 15 - 14 * rise;
    canvas
      ..save()
      // Only the part out of the box shows.
      ..clipRect(const Rect.fromLTRB(-2, -2, 30, 11))
      ..drawPath(
        Path()
          ..moveTo(14, tip + 7)
          ..lineTo(14, tip)
          ..moveTo(11, tip + 3)
          ..lineTo(14, tip)
          ..lineTo(17, tip + 3),
        paint..color = color.withValues(alpha: color.a * fade),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_UnpackingBoxPainter old) =>
      old.t != t || old.color != color;
}
