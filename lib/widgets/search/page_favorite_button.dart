import 'package:flutter/material.dart';

import '../favorite_toggle.dart';
import '../home/catalog_pin_button.dart';
import '../tap_highlight.dart';

/// The heart of a page's own entity, an album, an artist or a playlist,
/// drawn as the Pin it stands beside: a neutral glyph in a 48dp target.
/// Nothing where [id] cannot be marked.
class PageFavoriteButton extends StatelessWidget {
  final String id;

  const PageFavoriteButton({super.key, required this.id});

  /// Its target.
  static const double size = 48;

  @override
  Widget build(BuildContext context) => FavoriteToggle(
    id: id,
    builder: (context, mark) => IconButton(
      tooltip: mark.label,
      iconSize: CatalogPinButton.iconSize,
      style: kalinkaIconButtonStyle,
      isSelected: mark.favorite,
      icon: const Icon(Icons.favorite_border_rounded),
      selectedIcon: const Icon(Icons.favorite_rounded),
      // Kept while inert, so the heart does not grey for the moment each tap
      // is answered.
      onPressed: mark.toggle ?? () {},
    ),
  );
}
