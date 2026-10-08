import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The folded state of the search-and-filters control: one pill in the title
/// bar carrying a magnifier and a sliders glyph, badged with how many answers
/// the current filter holds.
///
/// Collapsing the controls is only safe while the *state* stays visible — the
/// badge here, and the chip row above the rows, are that guarantee.
class SearchFilterButton extends StatefulWidget {
  final int activeCount;
  final VoidCallback onTap;

  /// Drawn as engaged while the overlay it opens is up.
  final bool open;

  const SearchFilterButton({
    super.key,
    required this.activeCount,
    required this.onTap,
    this.open = false,
  });

  @override
  State<SearchFilterButton> createState() => _SearchFilterButtonState();
}

class _SearchFilterButtonState extends State<SearchFilterButton> {
  bool _hovering = false;

  void _setHovering(bool value) {
    if (value == _hovering) return;
    setState(() => _hovering = value);
  }

  @override
  Widget build(BuildContext context) {
    // The badge is what says a filter is on, and it is the only berry here:
    // the pill itself stays grey however many are applied, so crimson in the
    // bar keeps meaning one thing. Hover lightens the edge — borderDefault is
    // a very dark grey, so a mid grey reads clearly without going near-white;
    // the fill lift is only ~2% on a near-black bar. An open overlay holds
    // that same step up, the pill being engaged for as long as it is up.
    final engaged = widget.open || _hovering;
    final bg = engaged
        ? KalinkaColors.surfaceOverlay
        : KalinkaColors.surfaceElevated;
    final border = engaged
        ? KalinkaColors.textMuted
        : KalinkaColors.borderDefault;
    const fg = KalinkaColors.textPrimary;

    return Semantics(
      button: true,
      label: widget.activeCount == 0
          ? 'Search and filters'
          : 'Search and filters, ${widget.activeCount} active',
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHovering(true),
        onExit: (_) => _setHovering(false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            // Room for the badge to sit proud of the pill without clipping.
            padding: const EdgeInsets.only(top: 6, right: 6, bottom: 6),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 130),
                  curve: Curves.easeOut,
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: border, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search_rounded, size: 18, color: fg),
                      const SizedBox(width: 6),
                      Icon(Icons.tune_rounded, size: 18, color: fg),
                    ],
                  ),
                ),
                if (widget.activeCount > 0)
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Container(
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: KalinkaColors.accent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        // Two digits is the most that fits the circle; genres
                        // are counted one apiece, so the cap is reachable.
                        widget.activeCount > 9 ? '9+' : '${widget.activeCount}',
                        style: KalinkaFonts.sans(
                          fontSize: KalinkaTypography.baseSize - 1,
                          fontWeight: FontWeight.w700,
                          color: KalinkaColors.frost,
                        ),
                      ),
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
