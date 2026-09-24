import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'sheet_anchor.dart';
import 'tap_highlight.dart';

/// Shows a modal bottom sheet styled with the Kalinka visual identity.
///
/// Wraps [showModalBottomSheet] with the app's standard chrome: scrim,
/// surface container with rounded top corners, drag handle, and shadow.
/// The [contentBuilder] receives the sheet context and should return the
/// sheet body (rows, cards, etc.) — the chrome is added automatically.
/// When launched from inside a [SheetAnchor] (the tablet layout's panels),
/// the sheet slides up over that panel instead of the window centre.
Future<T?> showKalinkaBottomSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext) contentBuilder,
}) {
  final anchor = SheetAnchor.elementOf(context);
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.60),
    isScrollControlled: true,
    // Anchored sheets span the window and get padded down to the panel —
    // the M3 640px cap would re-centre them.
    constraints: anchor != null
        ? const BoxConstraints(maxWidth: double.infinity)
        : null,
    builder: (ctx) {
      final sheet = Container(
        decoration: BoxDecoration(
          color: KalinkaColors.surfaceRaised,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: const Border(
            top: BorderSide(color: KalinkaColors.borderDefault),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.7),
              blurRadius: 60,
              offset: const Offset(0, -20),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12),
                    decoration: BoxDecoration(
                      color: KalinkaColors.surfaceOverlay,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                contentBuilder(ctx),
              ],
            ),
          ),
        ),
      );
      if (anchor == null) return sheet;
      // LayoutBuilder re-runs at layout time, after the page below (and so
      // the anchor panel) has laid out for the current window size — the
      // inset tracks live resizes, and falls back to full width if the
      // anchor is gone after crossing the tablet breakpoint.
      return LayoutBuilder(
        builder: (_, constraints) {
          final padding = SheetAnchor.paddingFor(anchor, constraints.maxWidth);
          if (padding == EdgeInsets.zero) return sheet;
          // The window-wide sheet's Material claims taps in the strip
          // beside the panel, so the route's own barrier never sees them —
          // this one restores tap-outside-to-close there.
          return Stack(
            children: [
              const Positioned.fill(child: ModalBarrier(color: null)),
              Padding(padding: padding, child: sheet),
            ],
          );
        },
      );
    },
  );
}

/// The margin a sheet's rows keep: where their content starts, how far the
/// rule between them runs, and where the mark under the pointer stops. All
/// three read as one edge, so they are one number.
const double kSheetGutter = 20;

/// A sheet's title, what it is about under it, and the × that closes it.
class SheetHeader extends StatelessWidget {
  final String title;
  final String summary;

  const SheetHeader({super.key, required this.title, this.summary = ''});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(kSheetGutter, 16, 12, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: KalinkaTextStyles.sectionLabel),
                if (summary.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(summary, style: KalinkaTextStyles.trackRowSubtitle),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          TapHighlight(
            onTap: () => Navigator.of(context).pop(),
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(
                Icons.close_rounded,
                size: 22,
                color: KalinkaColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The hairline between two rows of a sheet. Every sheet's sections are ruled
/// the same way.
class SheetDivider extends StatelessWidget {
  const SheetDivider({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: kSheetGutter),
    child: Divider(color: KalinkaColors.borderSubtle, height: 1),
  );
}

/// What the rows under it have in common, over the first of them.
class SheetSectionLabel extends StatelessWidget {
  final String text;

  const SheetSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(kSheetGutter, 0, kSheetGutter, 8),
    child: Text(text, style: KalinkaTextStyles.traySectionLabel),
  );
}

/// A row in a sheet: a tinted glyph, what it does, and whatever sits at its
/// end. Its content, the rule under it and the mark under the pointer all
/// keep the same gutter, so the three read as one edge.
class SheetRow extends StatelessWidget {
  /// The tile at the row's head. Left out where the row reads as a setting
  /// rather than a destination, and then the label starts at the gutter.
  final IconData? icon;

  final Color? iconBackground;
  final Color? iconColor;
  final String label;

  /// A second line under the label. Empty leaves the row a single line.
  final String sublabel;

  /// Colours the label where the row is worth hesitating over. A row that
  /// merely goes somewhere leaves it alone.
  final Color? labelColor;

  /// What sits at the row's end — a [SheetChevron] where it opens something
  /// else, a badge, a switch.
  final Widget? trailing;

  final VoidCallback? onTap;

  const SheetRow({
    super.key,
    this.icon,
    this.iconBackground,
    this.iconColor,
    required this.label,
    this.sublabel = '',
    this.labelColor,
    this.trailing,
    this.onTap,
  }) : assert(
         icon == null || (iconBackground != null && iconColor != null),
         'an icon needs the tile it sits in',
       );

  @override
  Widget build(BuildContext context) {
    return TapHighlight(
      onTap: onTap,
      inset: kSheetGutter,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: kSheetGutter,
          vertical: 13,
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: KalinkaTextStyles.trayRowLabel.copyWith(
                      color: labelColor,
                    ),
                  ),
                  if (sublabel.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(sublabel, style: KalinkaTextStyles.trayRowSublabel),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
  }
}

/// The mark at the end of a row that opens something else.
class SheetChevron extends StatelessWidget {
  const SheetChevron({super.key});

  @override
  Widget build(BuildContext context) =>
      const Icon(Icons.chevron_right, size: 18, color: KalinkaColors.textMuted);
}
