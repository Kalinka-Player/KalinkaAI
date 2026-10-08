import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/restart_provider.dart';
import '../theme/app_theme.dart';
import '../utils/haptics.dart';

/// Full-screen overlay showing restart progress with a 4-step timeline,
/// connector lines, progress bar, and auto-dismiss.
class RestartOverlay extends ConsumerStatefulWidget {
  final VoidCallback onDismiss;

  const RestartOverlay({super.key, required this.onDismiss});

  @override
  ConsumerState<RestartOverlay> createState() => _RestartOverlayState();
}

class _RestartOverlayState extends ConsumerState<RestartOverlay>
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

  void _scheduleAutoDismiss() {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) {
        _fadeController.reverse().then((_) {
          if (mounted) widget.onDismiss();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final restartState = ref.watch(restartProvider);

    ref.listen(restartProvider, (prev, next) {
      if (prev != null && !prev.isDone && next.isDone) KalinkaHaptics.success();
    });

    // Auto-dismiss when done
    if (restartState.isDone && _autoDismissTimer == null) {
      _spinController.stop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduleAutoDismiss();
      });
    }

    // Auto-dismiss when restart is no longer active
    if (!restartState.isRestarting && !restartState.isDone) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _fadeController.reverse().then((_) {
            if (mounted) widget.onDismiss();
          });
        }
      });
    }

    return FadeTransition(
      opacity: _fadeController,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          color: const Color(0xFF0A0A0D).withValues(alpha: 0.93),
          child: SafeArea(
            // The scrim covers everything, but the timeline shouldn't: on a
            // wide window its rows and progress bar stretched the full width
            // and the eye had to travel between the dot and its label. Same
            // 5:10:5 split the discovery screen uses, gated on our own width
            // so the panel-hosted copy in settings isn't squeezed twice.
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= kKalinkaTabletBreakpoint;
                return Row(
                  children: [
                    if (wide)
                      const Flexible(
                        flex: 5,
                        child: SizedBox(width: double.infinity),
                      ),
                    Flexible(
                      flex: 10,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Icon with crossfade
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                child: Container(
                                  key: ValueKey(restartState.isDone),
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: restartState.isDone
                                        ? KalinkaColors.statusOnline.withValues(
                                            alpha: 0.14,
                                          )
                                        : KalinkaColors.surfaceRaised,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: restartState.isDone
                                          ? KalinkaColors.statusOnline
                                                .withValues(alpha: 0.25)
                                          : KalinkaColors.borderDefault,
                                    ),
                                  ),
                                  child: restartState.isDone
                                      ? const Icon(
                                          Icons.check_rounded,
                                          size: 28,
                                          color: KalinkaColors.statusOnline,
                                        )
                                      : RotationTransition(
                                          turns: _spinController,
                                          child: const Icon(
                                            Icons.autorenew_rounded,
                                            size: 28,
                                            color: KalinkaColors.textSecondary,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              // Title
                              Text(
                                restartState.isDone
                                    ? 'Restart complete'
                                    : 'Restarting server',
                                style: KalinkaTextStyles.dialogTitle,
                              ),
                              const SizedBox(height: 6),
                              // Subtitle
                              Text(
                                restartState.isDone
                                    ? 'All changes applied.'
                                    : 'Applying staged changes\u2026',
                                style: KalinkaTextStyles.trayRowSublabel
                                    .copyWith(
                                      fontSize: KalinkaTypography.baseSize + 1,
                                      color: KalinkaColors.textSecondary,
                                    ),
                              ),
                              const SizedBox(height: 28),
                              // Progress bar
                              _buildProgressBar(restartState),
                              const SizedBox(height: 24),
                              // Timeline steps
                              ..._buildSteps(restartState),
                              if (restartState.error != null) ...[
                                const SizedBox(height: 16),
                                Text(
                                  restartState.error!,
                                  textAlign: TextAlign.center,
                                  style: KalinkaTextStyles.trayRowSublabel
                                      .copyWith(
                                        color: KalinkaColors.statusOffline,
                                      ),
                                ),
                              ],
                              const SizedBox(height: 24),
                              // Dismiss note
                              Text(
                                'You can leave this screen.',
                                style: KalinkaTextStyles.trayRowSublabel
                                    .copyWith(
                                      color: KalinkaColors.textSecondary,
                                      fontSize: KalinkaTypography.baseSize + 0,
                                    ),
                              ),
                              const SizedBox(height: 16),
                              GestureDetector(
                                onTap: () {
                                  _autoDismissTimer?.cancel();
                                  ref.read(restartProvider.notifier).dismiss();
                                  _fadeController.reverse().then((_) {
                                    if (mounted) widget.onDismiss();
                                  });
                                },
                                child: Text(
                                  'Dismiss',
                                  style: KalinkaTextStyles.trayRowSublabel
                                      .copyWith(
                                        color: KalinkaColors.textSecondary,
                                        decoration: TextDecoration.underline,
                                        decorationColor:
                                            KalinkaColors.textSecondary,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (wide)
                      const Flexible(
                        flex: 5,
                        child: SizedBox(width: double.infinity),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar(RestartState restartState) {
    final progress = restartState.completedSteps.length / 4.0;
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

  List<Widget> _buildSteps(RestartState restartState) {
    const steps = [
      (RestartStep.saving, 'Saving configuration', 'Writing changes to server'),
      (RestartStep.stopping, 'Stopping server', 'Graceful shutdown'),
      (RestartStep.starting, 'Starting server', 'Loading new configuration'),
      (RestartStep.reconnecting, 'Reconnecting', 'Waiting for server'),
    ];

    final widgets = <Widget>[];
    for (var i = 0; i < steps.length; i++) {
      final (stepEnum, label, sublabel) = steps[i];
      final isDone = restartState.completedSteps.contains(stepEnum);
      final isActive = restartState.currentStep == stepEnum;
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
            // Dot column with connector
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
                  // Connector line
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
            // Labels
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
