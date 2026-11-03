import 'package:flutter/material.dart';

import '../data_model/data_model.dart';
import '../theme/app_theme.dart';
import 'tap_highlight.dart';

/// An artist or album name, plain unless its source supplied a browse id.
/// A link adds a chevron and lifts under the pointer in a rounded mark, but
/// stays no taller than its line, so the names keep plain text's spacing.
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

  static const verticalPadding = 2.0;
  static const chevronWidth = 18.0;

  /// How far past the name the mark reaches on either side, so the text
  /// itself stays aligned with the lines around it.
  static const markOutset = 8.0;

  @override
  Widget build(BuildContext context) {
    final target = item;
    final text = Text(
      label,
      style: style,
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
      child: TapHighlight(
        onTap: open,
        borderRadius: BorderRadius.circular(6),
        inset: -markOutset,
        focusable: true,
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
    );
  }
}
