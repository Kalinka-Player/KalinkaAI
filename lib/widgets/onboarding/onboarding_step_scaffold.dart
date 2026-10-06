import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../kalinka_button.dart';

/// Width cap for the wizard's content column, shared by the steps and the
/// output-settings panel: half the window on a tablet — the same split the
/// discovery screen uses — 600 below the breakpoint.
double onboardingContentMaxWidth(double available) =>
    available >= kKalinkaTabletBreakpoint ? available / 2 : 600;

/// Shared chrome for wizard steps after the discovery step: progress
/// header, display-font title, scrollable body, Back/Continue footer.
///
/// Content is width-constrained and centered so the wizard reads well on
/// tablets without a separate layout.
class OnboardingStepScaffold extends StatelessWidget {
  /// 1-based step number shown in the header (includes the discovery step).
  final int stepNumber;
  final int stepCount;
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final String nextLabel;

  /// One short label per step; the current one is highlighted. Scaled down
  /// as one line on narrow screens rather than wrapped.
  final List<String> stepLabels;

  /// Gates Continue without hiding it; the step says what's missing.
  final bool nextEnabled;

  const OnboardingStepScaffold({
    super.key,
    required this.stepNumber,
    required this.stepCount,
    required this.title,
    this.subtitle,
    required this.children,
    this.onBack,
    this.onNext,
    this.nextLabel = 'Continue',
    this.stepLabels = const [],
    this.nextEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: onboardingContentMaxWidth(constraints.maxWidth),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OnboardingProgress(
                        stepNumber: stepNumber,
                        stepCount: stepCount,
                        stepLabels: stepLabels,
                      ),
                      const SizedBox(height: 20),
                      Text(title, style: KalinkaTextStyles.dialogTitle),
                      if (subtitle != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitle!,
                          // Same size as [OnboardingNote]: the deck and the
                          // body copy are one voice, and a deck that reads
                          // smaller than the paragraph under it looks demoted.
                          style: KalinkaTextStyles.trayRowSublabel.copyWith(
                            fontSize: KalinkaTypography.baseSize + 3,
                            height: 1.55,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(top: 16, bottom: 24),
                    children: children,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    children: [
                      if (onBack != null) ...[
                        KalinkaButton(
                          label: 'Back',
                          variant: KalinkaButtonVariant.neutral,
                          size: KalinkaButtonSize.normal,
                          onTap: onBack,
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: KalinkaButton(
                          label: nextLabel,
                          variant: KalinkaButtonVariant.accent,
                          size: KalinkaButtonSize.normal,
                          fullWidth: true,
                          enabled: nextEnabled && onNext != null,
                          onTap: nextEnabled ? onNext : null,
                        ),
                      ),
                    ],
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

/// Shared step count, labels, and progress for box setup and onboarding.
class OnboardingProgress extends StatelessWidget {
  final int stepNumber;
  final int stepCount;
  final List<String> stepLabels;

  const OnboardingProgress({
    super.key,
    required this.stepNumber,
    required this.stepCount,
    this.stepLabels = const [],
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'STEP $stepNumber OF $stepCount',
        style: KalinkaTextStyles.sectionHeaderMuted,
      ),
      if (stepLabels.isNotEmpty) ...[
        const SizedBox(height: 10),
        _buildStepper(),
      ],
      const SizedBox(height: 8),
      _buildProgressBar(),
    ],
  );

  /// The step names in one mono line — walked steps in accent, the current
  /// one bright, the rest muted. Scaled down as a whole when width runs out,
  /// so it never wraps or truncates a label.
  Widget _buildStepper() {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          for (var i = 0; i < stepLabels.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: Text(
                  '·',
                  style: KalinkaTextStyles.sectionHeaderMuted.copyWith(
                    color: KalinkaColors.textMuted,
                  ),
                ),
              ),
            Text(
              stepLabels[i],
              style: KalinkaTextStyles.sectionHeaderMuted.copyWith(
                color: i + 1 == stepNumber
                    ? KalinkaColors.textPrimary
                    : i + 1 < stepNumber
                    ? KalinkaColors.accentTint
                    : KalinkaColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    final progress = stepNumber / stepCount;
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: 3,
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
              height: 3,
              decoration: BoxDecoration(
                color: KalinkaColors.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Muted uppercase section label above a settings card, matching the
/// settings screen's section chrome.
class OnboardingSectionLabel extends StatelessWidget {
  final String text;

  const OnboardingSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Text(
        text.toUpperCase(),
        style: KalinkaTextStyles.sectionHeaderMuted,
      ),
    );
  }
}

/// Explanatory note for wizard steps. Larger and brighter than the
/// settings screen's [FooterNote] — first-run copy is read once and must
/// be readable at a glance, not blend into the chrome.
class OnboardingNote extends StatelessWidget {
  final String text;

  const OnboardingNote(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Bottom margin matches the section label's, so a note introducing a
      // card sits off it by the same gap a heading would.
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Text(
        text,
        style: KalinkaTextStyles.trayRowSublabel.copyWith(
          fontSize: KalinkaTypography.baseSize + 3,
          height: 1.55,
        ),
      ),
    );
  }
}
