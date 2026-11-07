import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'kalinka_popover.dart';

/// Centered dialog chrome within the available safe area and keyboard bounds.
/// The route owns its dimmed barrier; content owns scrolling.
class KalinkaCenteredSurface extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const KalinkaCenteredSurface({
    super.key,
    required this.child,
    this.maxWidth = kKalinkaPopupMaxWidth,
  });

  static const surfaceKey = ValueKey('kalinka-centered-surface');

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        media.padding.left + 12,
        media.padding.top + 12,
        media.padding.right + 12,
        math.max(media.padding.bottom, media.viewInsets.bottom) + 12,
      ),
      child: Center(
        child: SizedBox(
          width: maxWidth,
          child: Material(
            key: surfaceKey,
            color: KalinkaColors.surfaceDialog,
            surfaceTintColor: Colors.transparent,
            elevation: 12,
            shadowColor: Colors.black,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
              side: BorderSide(color: KalinkaColors.borderDefault),
            ),
            clipBehavior: Clip.antiAlias,
            child: KalinkaPopoverContentScope(child: child),
          ),
        ),
      ),
    );
  }
}
