import 'package:flutter/material.dart';

import '../favorite_toggle.dart';
import 'row_circle_button.dart';

/// The heart on a cover, for what [mark] is of, in the grey circle Play
/// wears beside it.
class CoverFavoriteButton extends StatelessWidget {
  final FavoriteMark mark;
  final FocusNode? focusNode;

  const CoverFavoriteButton({super.key, required this.mark, this.focusNode});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: mark.label,
    excludeFromSemantics: true,
    child: RowCircleButton(
      label: mark.label,
      icon: mark.icon,
      busy: mark.toggle == null,
      onTap: mark.toggle ?? () {},
      focusNode: focusNode,
    ),
  );
}
