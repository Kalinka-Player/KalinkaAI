import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../utils/click_cursor.dart';
import '../kalinka_button.dart' show PillTarget;

/// Pill button for batch actions ("Play all", "Enqueue", a page's Edit) and
/// the choices beside them, 40dp tall in a 48dp target.
///
/// [accent] marks the default action with the subtle crimson idiom
/// (accentSubtle fill, accentBorder edge, berry-tint label) — never a solid
/// crimson fill; the neutral variant is a plain surface.
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

  static const _vertical = 8.0;

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
    this.selected,
    this.enabled = true,
    this.onTap,
    this.foregroundOverride,
    this.borderOverride,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final fg =
        foregroundOverride ??
        (accent ? KalinkaColors.accentTint : KalinkaColors.textPrimary);
    final bg = accent
        ? KalinkaColors.accentSubtle
        : KalinkaColors.surfaceElevated;
    final border =
        borderOverride ??
        (accent ? KalinkaColors.accentBorder : KalinkaColors.borderDefault);
    final labelStyle = KalinkaFonts.sans(
      fontSize: KalinkaTypography.baseSize + 2,
      fontWeight: FontWeight.w600,
      color: fg,
    );
    final mark = icon != null || leading != null;
    // A glyph alone sits in a circle; one ahead of a label takes some of
    // that side's room.
    final padding = label == null
        ? const EdgeInsets.symmetric(horizontal: 11, vertical: _vertical)
        : EdgeInsets.fromLTRB(mark ? 13 : 18, _vertical, 18, _vertical);
    final interactive = enabled && onTap != null;

    Widget button = PillTarget(
      onTap: interactive ? onTap : null,
      child: Material(
        color: bg,
        shape: StadiumBorder(side: BorderSide(color: border, width: 1)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          mouseCursor: clickCursor(interactive: interactive),
          child: Padding(
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
                  if (icon != null) Icon(icon, size: 18, color: fg),
                  if (mark && label != null) const SizedBox(width: 6),
                  if (label != null) Text(label!, style: labelStyle),
                ],
              ),
            ),
          ),
        ),
      ),
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
