import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../favorite_toggle.dart';
import '../keyboard/ink_focus_outline.dart';
import '../modifier_click.dart';
import '../tap_highlight.dart' show kalinkaOverlay;

/// A bare heart for what [mark] is of: muted at rest, bright under the
/// pointer and once marked, and never in the accent, so a page of favourites
/// is not a column of red. Its whole square takes the tap.
class RowFavoriteButton extends StatefulWidget {
  final FavoriteMark mark;

  /// Its square.
  final double size;

  const RowFavoriteButton({super.key, required this.mark, required this.size});

  static const double iconSize = 20;

  @override
  State<RowFavoriteButton> createState() => _RowFavoriteButtonState();
}

class _RowFavoriteButtonState extends State<RowFavoriteButton> {
  /// A press tints its circle; the pointer alone only lifts the glyph, so
  /// the heart stays bare.
  static final _overlay = WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.pressed)
        ? kalinkaOverlay.resolve(states)
        : Colors.transparent,
  );

  bool _hovering = false;

  void _setHover(bool value) {
    if (value == _hovering) return;
    setState(() => _hovering = value);
  }

  @override
  Widget build(BuildContext context) {
    final mark = widget.mark;
    return ClickAtOnce(
      child: Tooltip(
        message: mark.label,
        excludeFromSemantics: true,
        child: MergeSemantics(
          child: Semantics(
            button: true,
            enabled: mark.toggle != null,
            label: mark.label,
            child: SizedBox.square(
              dimension: widget.size,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  mouseCursor: WidgetStateMouseCursor.clickable,
                  customBorder: const CircleBorder(),
                  // Kept while inert, so the click is taken here and never
                  // falls through to the row, which would play it.
                  onTap: mark.toggle ?? () {},
                  onHover: _setHover,
                  overlayColor: _overlay,
                  child: InkFocusOutline(
                    shape: const CircleBorder(),
                    child: Center(
                      child: Icon(
                        mark.icon,
                        size: RowFavoriteButton.iconSize,
                        color: mark.favorite || _hovering
                            ? KalinkaColors.textPrimary
                            : KalinkaColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
