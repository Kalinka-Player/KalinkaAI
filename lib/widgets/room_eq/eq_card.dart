import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

enum RoomEqSection { bands, preamp, fir }

/// Align card headings with the centre of a 48dp switch or icon target.
class EqCard extends StatelessWidget {
  const EqCard({super.key, required this.child});

  final Widget child;

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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: child,
    ),
  );
}
