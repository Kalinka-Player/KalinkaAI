import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/click_cursor.dart';
import '../utils/haptics.dart';

/// One earlier segment of a breadcrumb: a plain label until the pointer finds
/// it, then an outlined target. Tapping it returns to the place it names, so
/// the crumb is not merely a caption.
class BreadcrumbCrumb extends StatefulWidget {
  final String label;

  /// What a screen reader announces for a crumb that can be tapped.
  final String semanticsLabel;

  final TextStyle style;

  /// Drawn before [label].
  final IconData? icon;

  /// Null where this crumb names the page you are already on.
  final VoidCallback? onTap;

  const BreadcrumbCrumb({
    super.key,
    required this.label,
    required this.semanticsLabel,
    required this.style,
    required this.onTap,
    this.icon,
  });

  static const _padding = EdgeInsets.symmetric(horizontal: 7, vertical: 4);
  static const _iconGap = 10.0;

  static double _iconSize(TextStyle style) => (style.fontSize ?? 14) * 1.4;

  /// How wide [label] sets in [style], for a trail measuring what goes
  /// between its crumbs.
  static double labelWidth(String label, TextStyle style, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// How wide a crumb for [label] lays out when nothing narrows it, for a
  /// trail that has to choose which crumbs fit before it builds them.
  static double widthOf(
    String label,
    TextStyle style,
    TextScaler scaler, {
    bool withIcon = false,
  }) {
    final text = labelWidth(label, style, scaler);
    if (!withIcon) return _padding.horizontal + text;
    // The icon rides in the text as a widget span, so it scales with it.
    final fontSize = style.fontSize ?? 14;
    final iconScale = scaler.scale(fontSize) / fontSize;
    return _padding.horizontal +
        text +
        (_iconSize(style) + _iconGap) * iconScale;
  }

  @override
  State<BreadcrumbCrumb> createState() => _BreadcrumbCrumbState();
}

class _BreadcrumbCrumbState extends State<BreadcrumbCrumb> {
  bool _hovering = false;

  void _setHovering(bool value) {
    if (value == _hovering) return;
    setState(() => _hovering = value);
  }

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null;
    final colour = interactive
        ? KalinkaColors.textMuted
        : KalinkaColors.textPrimary;

    final crumb = AnimatedContainer(
      duration: const Duration(milliseconds: 130),
      curve: Curves.easeOut,
      padding: BreadcrumbCrumb._padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        // White alpha rather than a surface tone: the bar is transparent, so
        // on a catalog page this plate sits over blurred art, and only
        // lightening whatever is behind it reads on both.
        color: _hovering && interactive
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.transparent,
      ),
      child: Text.rich(
        TextSpan(
          children: [
            if (widget.icon case final icon?)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(
                    right: BreadcrumbCrumb._iconGap,
                  ),
                  child: Icon(
                    icon,
                    size: BreadcrumbCrumb._iconSize(widget.style),
                    color: colour,
                  ),
                ),
              ),
            TextSpan(text: widget.label),
          ],
        ),
        style: widget.style.copyWith(color: colour),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      ),
    );

    if (!interactive) return crumb;

    return Semantics(
      button: true,
      label: widget.semanticsLabel,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: clickCursor(interactive: true),
        onEnter: (_) => _setHovering(true),
        onExit: (_) => _setHovering(false),
        child: GestureDetector(
          onTap: () {
            KalinkaHaptics.lightImpact();
            widget.onTap!();
          },
          behavior: HitTestBehavior.opaque,
          child: crumb,
        ),
      ),
    );
  }
}
