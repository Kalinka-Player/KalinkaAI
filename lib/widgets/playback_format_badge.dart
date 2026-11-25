import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_state_provider.dart';
import '../providers/bit_perfect_provider.dart';
import '../theme/app_theme.dart';
import 'dsp_readout.dart';

/// Output clipping takes priority over the bit-perfect badge beside the format.
class PlaybackFormatBadge extends ConsumerWidget {
  final double scale;

  /// Room around the badge, gone with it when it hides. Defaults to 6 before
  /// it, scaled.
  final EdgeInsetsGeometry? margin;

  const PlaybackFormatBadge({super.key, this.scale = 1, this.margin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clipping = ref.watch(
      playbackEventsProvider.select((events) => clippedSamples(events) > 0),
    );
    if (!clipping && !ref.watch(bitPerfectProvider)) {
      return const SizedBox.shrink();
    }
    final color = clipping
        ? KalinkaColors.statusError
        : KalinkaColors.statusOnline;
    final label = clipping
        ? 'Output clipping detected'
        : 'Bit-perfect playback';

    // The gap belongs to the badge: without it the row keeps a hole where a
    // hidden badge would have been.
    final badge = Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        margin: margin ?? EdgeInsets.only(left: 6 * scale),
        padding: EdgeInsets.symmetric(
          horizontal: 5 * scale,
          vertical: 2 * scale,
        ),
        decoration: BoxDecoration(
          color: clipping
              ? color.withValues(alpha: 0.12)
              : KalinkaColors.statusOnlineSurface,
          border: Border.all(color: color.withValues(alpha: 0.30)),
          borderRadius: BorderRadius.circular(4 * scale),
        ),
        child: Text(
          clipping ? '!' : '1:1',
          style: KalinkaTextStyles.bitPerfectBadge.copyWith(
            color: clipping ? color : KalinkaColors.statusOnlineLight,
            fontSize: KalinkaTextStyles.bitPerfectBadge.fontSize! * scale,
          ),
        ),
      ),
    );
    return clipping
        ? Tooltip(message: label, excludeFromSemantics: true, child: badge)
        : badge;
  }
}
