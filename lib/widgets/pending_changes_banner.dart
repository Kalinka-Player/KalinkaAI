import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Amber banner that appears when settings changes are staged but not yet applied.
///
/// Shows the count of pending changes, a "Discard" link, and "APPLY" button.
/// The amber tint + bold text already signal urgency clearly; an earlier
/// pulsing dot animation here turned out to be a major CPU drain (perpetual
/// 60Hz Opacity rebuild + saveLayer) and gave no information the colour
/// didn't already convey. Now a flat static dot.
///
/// Presentational only — the caller supplies the count and the actions, so the
/// same banner serves the server's settings (apply = restart) and a renderer's
/// (apply = write the paths), which cost different things and read from
/// different stores.
class PendingChangesBanner extends StatelessWidget {
  final int pendingCount;

  /// Trailing clause after the count, e.g. `restart required`. Omitted when
  /// applying costs nothing worth warning about.
  final String? consequence;
  final VoidCallback onDiscard;
  final VoidCallback onApply;

  /// While true the actions are inert and the button reads APPLYING.
  final bool busy;

  /// While true applying is out of reach and the banner says why.
  final bool blocked;

  const PendingChangesBanner({
    super.key,
    required this.pendingCount,
    required this.onDiscard,
    required this.onApply,
    this.consequence,
    this.busy = false,
    this.blocked = false,
  });

  String _trailingClause() {
    if (blocked) return ' · fix what is marked below';
    return consequence == null ? '' : ' · $consequence';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: pendingCount > 0
          ? Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: KalinkaColors.statusPending.withValues(alpha: 0.07),
                border: Border(
                  bottom: BorderSide(
                    color: KalinkaColors.statusPending.withValues(alpha: 0.18),
                  ),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: busy ? null : onDiscard,
                    child: Text(
                      'Discard',
                      style: KalinkaTextStyles.cancelButton,
                    ),
                  ),
                  const SizedBox(width: 15),
                  GestureDetector(
                    onTap: busy || blocked ? null : onApply,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: KalinkaColors.statusPending.withValues(
                          alpha: blocked ? 0.04 : 0.1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: KalinkaColors.statusPending.withValues(
                            alpha: blocked ? 0.15 : 0.4,
                          ),
                        ),
                      ),
                      child: Text(
                        busy ? 'APPLYING…' : 'APPLY',
                        style: KalinkaTextStyles.bannerText.copyWith(
                          color: KalinkaColors.statusPendingLight.withValues(
                            alpha: blocked ? 0.4 : 1,
                          ),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
