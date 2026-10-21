import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Amber bar at the foot of a settings page while changes are staged but not
/// yet applied: the count of them, Discard and APPLY.
///
/// Laid out under the page, not over it, so whatever it would have covered
/// scrolls up into view above it. The amber tint + bold text already signal
/// urgency clearly; an earlier pulsing dot animation here turned out to be a
/// major CPU drain (perpetual 60Hz Opacity rebuild + saveLayer) and gave no
/// information the colour didn't already convey. Now a flat static dot.
///
/// Presentational only — the caller supplies the count and the actions, so the
/// same bar serves the server's settings and Configuration (apply = restart)
/// and a renderer's (apply = write the paths), which cost different things
/// and read from different stores.
class PendingChangesBanner extends StatelessWidget {
  final int pendingCount;

  /// Trailing clause after the count, e.g. `restart required`. Omitted when
  /// applying costs nothing worth warning about.
  final String? consequence;
  final VoidCallback onDiscard;
  final VoidCallback onApply;

  /// While true the actions are inert and the button reads APPLYING.
  final bool busy;

  /// While true applying is out of reach and the bar says why.
  final bool blocked;

  /// What stands in the way while [blocked], e.g. `check Service name`.
  final String? blockedReason;

  /// Where one is given, a blocked bar offers REVIEW in APPLY's place.
  final VoidCallback? onReview;

  const PendingChangesBanner({
    super.key,
    required this.pendingCount,
    required this.onDiscard,
    required this.onApply,
    this.consequence,
    this.busy = false,
    this.blocked = false,
    this.blockedReason,
    this.onReview,
  });

  String _trailingClause() {
    if (blocked) return ' · ${blockedReason ?? 'fix what is marked above'}';
    return consequence == null ? '' : ' · $consequence';
  }

  @override
  Widget build(BuildContext context) {
    final review = blocked && onReview != null;
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: pendingCount > 0
          ? Container(
              width: double.infinity,
              decoration: BoxDecoration(
                // Opaque: the page scrolls up out from under it.
                color: Color.alphaBlend(
                  KalinkaColors.statusPending.withValues(alpha: 0.07),
                  KalinkaColors.background,
                ),
                border: Border(
                  top: BorderSide(
                    color: KalinkaColors.statusPending.withValues(alpha: 0.18),
                  ),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final stacked =
                          constraints.maxWidth < 420 ||
                          MediaQuery.textScalerOf(context).scale(1) > 1.3;
                      final summary = Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: KalinkaColors.statusPending,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '$pendingCount change${pendingCount == 1 ? '' : 's'} '
                              'staged${_trailingClause()}',
                              style: KalinkaTextStyles.bannerText.copyWith(
                                color: blocked
                                    ? KalinkaColors.actionDeleteLight
                                    : KalinkaColors.statusPendingLight,
                              ),
                              // Stacked, it has the line to itself to wrap on.
                              maxLines: stacked ? null : 1,
                              overflow: stacked ? null : TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      );
                      final actions = Wrap(
                        spacing: 7,
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _Action(
                            key: const ValueKey('pending-changes-discard'),
                            onTap: busy ? null : onDiscard,
                            child: Text(
                              'Discard',
                              style: KalinkaTextStyles.cancelButton,
                            ),
                          ),
                          _Action(
                            key: const ValueKey('pending-changes-apply'),
                            onTap: busy
                                ? null
                                : review
                                ? onReview
                                : blocked
                                ? null
                                : onApply,
                            child: _ApplyPill(
                              label: busy
                                  ? 'APPLYING…'
                                  : review
                                  ? 'REVIEW'
                                  : 'APPLY',
                              dimmed: blocked && !review,
                            ),
                          ),
                        ],
                      );
                      return stacked
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: summary,
                                ),
                                actions,
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(child: summary),
                                const SizedBox(width: 8),
                                actions,
                              ],
                            );
                    },
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

/// One of the bar's actions: drawn small, aimed at in a 48dp target.
class _Action extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;

  const _Action({super.key, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 4),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      side: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? const BorderSide(color: KalinkaColors.textPrimary, width: 2)
            : BorderSide.none,
      ),
    ),
    child: child,
  );
}

class _ApplyPill extends StatelessWidget {
  final String label;
  final bool dimmed;

  const _ApplyPill({required this.label, required this.dimmed});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: KalinkaColors.statusPending.withValues(alpha: dimmed ? 0.04 : 0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: KalinkaColors.statusPending.withValues(
          alpha: dimmed ? 0.15 : 0.4,
        ),
      ),
    ),
    child: Text(
      label,
      style: KalinkaTextStyles.bannerText.copyWith(
        color: KalinkaColors.statusPendingLight.withValues(
          alpha: dimmed ? 0.4 : 1,
        ),
        fontWeight: FontWeight.w600,
        letterSpacing: 1.0,
      ),
    ),
  );
}
