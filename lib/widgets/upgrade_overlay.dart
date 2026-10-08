import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/upgrade_provider.dart';
import '../theme/app_theme.dart';
import '../utils/haptics.dart';

/// Full-screen overlay showing upgrade progress with a 2-step timeline.
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
  late AnimationController _spinController;
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..forward();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _spinController.dispose();
    _autoDismissTimer?.cancel();
    super.dispose();
  }

  void _close() {
    _autoDismissTimer?.cancel();
    // Fade out first: resetting the provider unmounts this overlay (the
    // settings screen shows it while isUpgrading), so it must come last.
    _fadeController.reverse().then((_) {
      if (!mounted) return;
      widget.onDismiss();
      ref.read(upgradeProvider.notifier).dismiss();
    });
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

    if (upgradeState.isDone && _autoDismissTimer == null) {
      _spinController.stop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduleAutoDismiss();
      });
    }

    final target = upgradeState.targetVersion;
    return FadeTransition(
      opacity: _fadeController,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          color: const Color(0xFF0A0A0D).withValues(alpha: 0.93),
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
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
                              ? KalinkaColors.statusOnline.withValues(
                                  alpha: 0.14,
                                )
                              : KalinkaColors.surfaceRaised,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: upgradeState.isDone
                                ? KalinkaColors.statusOnline.withValues(
                                    alpha: 0.25,
                                  )
                                : KalinkaColors.borderDefault,
                          ),
                        ),
                        child: upgradeState.isDone
                            ? const Icon(
                                Icons.check_rounded,
                                size: 28,
                                color: KalinkaColors.statusOnline,
                              )
                            : RotationTransition(
                                turns: _spinController,
                                child: const Icon(
                                  Icons.system_update_alt,
                                  size: 26,
                                  color: KalinkaColors.textSecondary,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      upgradeState.isDone
                          ? 'Upgrade complete'
                          : 'Upgrading server',
                      style: KalinkaTextStyles.dialogTitle,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      upgradeState.isDone
                          ? 'Now running version $target.'
                          : 'Installing version $target… this can '
                                'take several minutes.',
                      textAlign: TextAlign.center,
                      style: KalinkaTextStyles.trayRowSublabel.copyWith(
                        fontSize: KalinkaTypography.baseSize + 1,
                        color: KalinkaColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _buildProgressBar(upgradeState),
                    const SizedBox(height: 24),
                    ..._buildSteps(upgradeState),
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
                      GestureDetector(
                        onTap: _close,
                        child: Text(
                          'Close',
                          style: KalinkaTextStyles.trayRowSublabel.copyWith(
                            color: KalinkaColors.textSecondary,
                            decoration: TextDecoration.underline,
                            decorationColor: KalinkaColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar(UpgradeState upgradeState) {
    final progress = upgradeState.completedSteps.length / 2.0;
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
    const steps = [
      (
        UpgradeStep.installing,
        'Installing new version',
        'Downloading and installing packages',
      ),
      (UpgradeStep.reconnecting, 'Reconnecting', 'Waiting for server'),
    ];

    final widgets = <Widget>[];
    for (var i = 0; i < steps.length; i++) {
      final (stepEnum, label, sublabel) = steps[i];
      final isDone = upgradeState.completedSteps.contains(stepEnum);
      final isActive = upgradeState.currentStep == stepEnum;
      final isLast = i == steps.length - 1;

      Color dotColor;
      if (isDone) {
        dotColor = KalinkaColors.statusOnline;
      } else if (isActive) {
        dotColor = KalinkaColors.textSecondary;
      } else {
        dotColor = KalinkaColors.textMuted;
      }

      widgets.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 22,
              child: Column(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: dotColor, width: 1.5),
                      color: isDone
                          ? dotColor.withValues(alpha: 0.15)
                          : Colors.transparent,
                    ),
                    child: isDone
                        ? Icon(Icons.check, size: 12, color: dotColor)
                        : isActive
                        ? Center(
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: dotColor,
                              ),
                            ),
                          )
                        : null,
                  ),
                  if (!isLast)
                    Container(
                      width: 1,
                      height: 14,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: KalinkaColors.borderSubtle,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: KalinkaTextStyles.trayRowLabel.copyWith(
                        fontSize: KalinkaTypography.baseSize + 2,
                        color: isDone || isActive
                            ? KalinkaColors.textPrimary
                            : KalinkaColors.textSecondary,
                      ),
                    ),
                    Text(
                      sublabel,
                      style: KalinkaTextStyles.trayRowSublabel.copyWith(
                        fontSize: KalinkaTypography.baseSize + 0,
                        color: KalinkaColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    return widgets;
  }
}
