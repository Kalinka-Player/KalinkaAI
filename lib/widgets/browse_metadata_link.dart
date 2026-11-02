import 'package:flutter/material.dart';

import '../data_model/data_model.dart';
import '../theme/app_theme.dart';

/// An artist or album name, plain unless its source supplied a browse id.
class BrowseMetadataLink extends StatelessWidget {
  final String label;
  final TextStyle style;
  final BrowseItem? item;
  final ValueChanged<BrowseItem> onOpen;
  final TextAlign textAlign;
  final int? maxLines;

  const BrowseMetadataLink({
    super.key,
    required this.label,
    required this.style,
    required this.item,
    required this.onOpen,
    this.textAlign = TextAlign.start,
    this.maxLines,
  });

  static const minHeight = 48.0;
  static const verticalPadding = 4.0;
  static const chevronWidth = 18.0;

  @override
  Widget build(BuildContext context) {
    final target = item;
    final text = Text(
      label,
      style: target == null
          ? style
          : style.copyWith(
              decoration: TextDecoration.underline,
              decorationColor: KalinkaColors.textMuted,
            ),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
    if (target == null) return text;
    void open() => onOpen(target);
    return Semantics(
      link: true,
      label: 'Open ${target.name}',
      onTap: open,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: open,
          borderRadius: BorderRadius.circular(6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: 48,
              minHeight: minHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: verticalPadding),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: text),
                  const Icon(
                    Icons.chevron_right,
                    size: chevronWidth,
                    color: KalinkaColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
