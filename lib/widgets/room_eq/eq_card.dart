import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../keyboard/ink_focus_outline.dart';
import '../tap_highlight.dart';

enum RoomEqSection { bands, preamp, fir }

/// Align card headings with the centre of a 48dp switch or icon target.
class EqCard extends StatelessWidget {
  const EqCard({super.key, this.action, this.child, this.spacing = 8})
    : assert(action != null || child != null);

  final Widget? action, child;
  final double spacing;
  static const double _contentInset = 16;
  static const double _actionInset = 4;

  static Widget title(String text) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(text, style: KalinkaTextStyles.cardTitle),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Material(
    color: KalinkaColors.surfaceRaised,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: KalinkaColors.borderSubtle),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: spacing,
        children: [
          ?action,
          if (child != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _contentInset),
              child: child!,
            ),
        ],
      ),
    ),
  );
}

/// A clickable card heading with room around both the ink and its contents.
class EqCardAction extends StatelessWidget {
  const EqCardAction({
    super.key,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  final String title;
  final Widget subtitle, trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        EqCard._actionInset,
        8,
        EqCard._actionInset,
        0,
      ),
      child: MergeSemantics(
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          overlayColor: kalinkaOverlay,
          child: InkFocusOutline(
            shape: shape,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: kMinInteractiveDimension,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: EqCard._contentInset - EqCard._actionInset,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        spacing: 2,
                        children: [
                          Text(title, style: KalinkaTextStyles.cardTitle),
                          subtitle,
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    trailing,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
