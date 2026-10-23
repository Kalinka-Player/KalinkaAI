import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../providers/search_session_provider.dart';
import '../../theme/app_theme.dart';
import '../catalog_art.dart';

/// The catalog's own artwork and caption, without fetching its children.
class CatalogArtwork extends StatelessWidget {
  final CatalogPage page;
  final String? description;
  final IconData sourceIcon;
  final Color? sourceColor;
  final VoidCallback? onOpen;

  const CatalogArtwork({
    super.key,
    required this.page,
    this.description,
    this.sourceIcon = Icons.library_music_outlined,
    this.sourceColor,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final title = page.title ?? 'Catalog';
    return LayoutBuilder(
      builder: (context, constraints) {
        // A 3:1 card stops growing at about 320dp tall.
        final width = math.min(constraints.maxWidth, 320 * 3.0);
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: width,
            child: Semantics(
              button: true,
              enabled: onOpen != null,
              label: onOpen == null ? title : 'Open $title',
              value: description,
              onTap: onOpen,
              excludeSemantics: true,
              child: Material(
                color: KalinkaColors.surfaceRaised,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    CatalogCard(
                      artPath: page.artPath,
                      aspectRatio: page.artAspectRatio,
                      title: title,
                      description: page.description,
                      subtitle: description,
                      leading: (scale) => Icon(
                        sourceIcon,
                        size: 15 * scale,
                        color: sourceColor,
                      ),
                    ),
                    Positioned.fill(
                      child: Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          mouseCursor: WidgetStateMouseCursor.clickable,
                          onTap: onOpen,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
