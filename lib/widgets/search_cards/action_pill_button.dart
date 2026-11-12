import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../utils/click_cursor.dart';
import '../kalinka_button.dart' show PillTarget;
import '../kalinka_popover.dart';

/// Pill button for batch actions ("Play all", "Enqueue", a page's Edit) and
/// the choices beside them, 40dp tall in a 48dp target.
///
/// [accent] marks the default action with the subtle crimson idiom
/// (accentSubtle fill, accentBorder edge, berry-tint label). [primary] gives
/// Play all a solid crimson fill; the neutral variant is a plain surface.
class ActionPillButton extends StatelessWidget {
  /// What the button says, or null for an icon-only one — the same chrome and
  /// height as the pills beside it, for an action its glyph already names.
  final String? label;
  final IconData? icon;

  /// A mark ahead of the label, where a glyph will not do — a source's
  /// tile. Takes the place of [icon], not a second thing beside it.
  final Widget? leading;

  /// Crimson-highlighted rather than grey: the one a set leads with, or the
  /// one being read. See the palette's outline treatment.
  final bool accent;

  /// A primary playback action, with a crimson face and warm-white label.
  final bool primary;

  /// A centered icon in a 40dp circle, inside a 48dp square touch target.
  /// Unlike a labelled pill, its face does not depend on text metrics.
  final bool circular;

  static const _vertical = 8.0;

  // A labelled pill's sides, the side ahead of a mark, and the mark's gap.
  static const _side = 18.0;
  static const _markSide = 13.0;
  static const _iconSize = 18.0;
  static const _markGap = 6.0;

  /// The accent pill's tint laid on the canvas, so the pill reads as it
  /// does there over a page's art too.
  static final accentFill = Color.alphaBlend(
    KalinkaColors.accentSubtle,
    KalinkaColors.background,
  );

  /// Reported to a screen reader for a pill that stands for a choice rather
  /// than an action. Null leaves it unsaid.
  final bool? selected;
  final bool enabled;
  final VoidCallback? onTap;

  /// Overrides for transient states (e.g. gold "Added ✓" confirmation).
  final Color? foregroundOverride;
  final Color? borderOverride;

  final String? semanticsLabel;

  const ActionPillButton({
    super.key,
    this.label,
    this.icon,
    this.leading,
    this.accent = false,
    this.primary = false,
    this.circular = false,
    this.selected,
    this.enabled = true,
    this.onTap,
    this.foregroundOverride,
    this.borderOverride,
    this.semanticsLabel,
  }) : assert(!circular || (label == null && icon != null && leading == null));

  @override
  Widget build(BuildContext context) {
    final fg =
        foregroundOverride ??
        (accent && !primary
            ? KalinkaColors.accentTint
            : KalinkaColors.textPrimary);
    final bg = primary
        ? KalinkaColors.accent
        : accent
        ? accentFill
        : KalinkaColors.surfaceElevated;
    final border =
        borderOverride ??
        (primary
            ? KalinkaColors.accent
            : accent
            ? KalinkaColors.accentBorder
            : KalinkaColors.borderDefault);
    final labelStyle = _labelStyle(fg);
    final mark = icon != null || leading != null;
    // A glyph alone sits in a circle; one ahead of a label takes some of
    // that side's room.
    final padding = label == null
        ? const EdgeInsets.symmetric(horizontal: 11, vertical: _vertical)
        : EdgeInsets.fromLTRB(
            mark ? _markSide : _side,
            _vertical,
            _side,
            _vertical,
          );
    final interactive = enabled && onTap != null;
    final activate = interactive
        ? () => KalinkaPopupOrigin.run(context, onTap!)
        : null;

    final OutlinedBorder shape = circular
        ? CircleBorder(side: BorderSide(color: border))
        : StadiumBorder(side: BorderSide(color: border));
    final face = Material(
      color: bg,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: activate,
        mouseCursor: clickCursor(interactive: interactive),
        customBorder: shape,
        child: circular
            ? SizedBox.square(
                dimension: kKalinkaPillHeight,
                child: Center(child: Icon(icon, size: 20, color: fg)),
              )
            : Padding(
                padding: padding,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: math.max(
                      kKalinkaPillHeight - 2 * _vertical,
                      _lineHeightOf(context, labelStyle),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ?leading,
                      if (icon != null) Icon(icon, size: _iconSize, color: fg),
                      if (mark && label != null)
                        const SizedBox(width: _markGap),
                      if (label != null) Text(label!, style: labelStyle),
                    ],
                  ),
                ),
              ),
      ),
    );
    Widget button = PillTarget(
      onTap: activate,
      child: circular
          ? SizedBox(
              width: kKalinkaPillTarget,
              height: kKalinkaPillHeight,
              child: Center(child: face),
            )
          : face,
    );
    if (!enabled) {
      button = Opacity(opacity: 0.6, child: button);
    }

    return Semantics(
      label: semanticsLabel ?? label,
      button: true,
      enabled: enabled,
      selected: selected,
      child: button,
    );
  }

  /// How wide a pill with an icon and no label sets.
  static const iconOnlyWidth = 2 * 11 + _iconSize;

  static TextStyle _labelStyle(Color color) => KalinkaFonts.sans(
    fontSize: KalinkaTypography.baseSize + 2,
    fontWeight: FontWeight.w600,
    color: color,
  );

  /// How far below its target's top the pill itself starts, so what stands
  /// beside one can line up with the pill rather than its target.
  static double edgeInset(BuildContext context) {
    final line = _lineHeightOf(context, _labelStyle(KalinkaColors.textPrimary));
    final height = math.max(kKalinkaPillHeight, line + 2 * _vertical);
    return math.max(0, (kKalinkaPillTarget - height) / 2);
  }

  /// The target's height, including labels enlarged by the system text size.
  static double heightOf(BuildContext context) => math.max(
    kKalinkaPillTarget,
    math.max(
      kKalinkaPillHeight,
      _lineHeightOf(context, _labelStyle(KalinkaColors.textPrimary)) +
          2 * _vertical,
    ),
  );

  /// How wide a pill with an icon ahead of [label] sets, as [build] lays it
  /// out.
  static double widthOf(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: DefaultTextStyle.of(context).style
            .merge(_labelStyle(KalinkaColors.textPrimary)),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return _markSide + _iconSize + _markGap + width.ceilToDouble() + _side;
  }

  /// How tall a line of label sets, so a pill without one is as tall as
  /// those with.
  static double _lineHeightOf(BuildContext context, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(
        text: ' ',
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      textHeightBehavior: DefaultTextHeightBehavior.maybeOf(context),
      maxLines: 1,
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }
}
