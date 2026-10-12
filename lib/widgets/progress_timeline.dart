import 'dart:ui';

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The dark, blurred scrim a progress overlay covers the screen with, its
/// [child] centred in a column no wider than reads comfortably.
class ProgressScrim extends StatelessWidget {
  final Widget child;

  const ProgressScrim({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Container(
        color: const Color(0xFF0A0A0D).withValues(alpha: 0.93),
        child: SafeArea(
          // The scrim covers everything, but the timeline shouldn't: on a
          // wide window its rows stretched the full width and the eye had to
          // travel between the dot and its label. Same 5:10:5 split the
          // discovery screen uses, gated on our own width so a panel-hosted
          // copy isn't squeezed twice.
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
                        child: child,
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
    );
  }
}

/// One step of a progress timeline: a dot that fills while the step runs and
/// checks once it is done, its label, and what the step does.
class TimelineStep extends StatelessWidget {
  final String label;
  final String sublabel;
  final bool done;
  final bool active;

  /// The last step draws no connector below its dot.
  final bool last;

  const TimelineStep({
    super.key,
    required this.label,
    required this.sublabel,
    required this.done,
    required this.active,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    final dotColor = done
        ? KalinkaColors.statusOnline
        : active
        ? KalinkaColors.textSecondary
        : KalinkaColors.textMuted;
    return Row(
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
                  color: done
                      ? dotColor.withValues(alpha: 0.15)
                      : Colors.transparent,
                ),
                child: done
                    ? Icon(Icons.check, size: 12, color: dotColor)
                    : active
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
              if (!last)
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
                    color: done || active
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
    );
  }
}
