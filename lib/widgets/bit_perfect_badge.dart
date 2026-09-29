import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/bit_perfect_provider.dart';
import '../theme/app_theme.dart';

/// Says that playback reaches the output device untouched.
///
/// Shown only when that is certain, so its absence means "not established",
/// not "altered" — nothing here is in a position to tell the two apart.
class BitPerfectBadge extends ConsumerWidget {
  final double scale;

  const BitPerfectBadge({super.key, this.scale = 1});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(bitPerfectProvider)) return const SizedBox.shrink();

    // The gap belongs to the badge: without it the row keeps a hole where a
    // hidden badge would have been.
    return Semantics(
      label: 'Bit-perfect playback',
      excludeSemantics: true,
      child: Container(
        margin: EdgeInsets.only(left: 6 * scale),
        padding: EdgeInsets.symmetric(
          horizontal: 5 * scale,
          vertical: 2 * scale,
        ),
        decoration: BoxDecoration(
          color: KalinkaColors.statusOnlineSurface,
          border: Border.all(
            color: KalinkaColors.statusOnline.withValues(alpha: 0.30),
          ),
          borderRadius: BorderRadius.circular(4 * scale),
        ),
        child: Text(
          '1:1',
          style: KalinkaTextStyles.bitPerfectBadge.copyWith(
            color: KalinkaColors.statusOnlineLight,
            fontSize: KalinkaTextStyles.bitPerfectBadge.fontSize! * scale,
          ),
        ),
      ),
    );
  }
}
