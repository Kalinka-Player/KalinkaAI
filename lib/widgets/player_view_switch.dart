import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/shell_nav_provider.dart';
import '../theme/app_theme.dart';
import '../utils/click_cursor.dart';

/// The player's two views as one switch: the track, or the queue. Grey, not
/// berry: it is chrome that stays on screen.
class PlayerViewSwitch extends ConsumerWidget {
  const PlayerViewSwitch({super.key});

  static const _views = [
    (view: PlayerView.nowPlaying, label: 'PLAYING', spoken: 'Now playing'),
    (view: PlayerView.queue, label: 'QUEUE', spoken: 'Queue'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(playerViewProvider);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: KalinkaColors.surfaceInput,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: KalinkaColors.borderSubtle),
      ),
      // Equal halves as wide as the longer label, so the thumb can slide.
      child: IntrinsicWidth(
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedAlign(
                alignment: current == PlayerView.queue
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                duration: duration,
                curve: Curves.easeOutCubic,
                child: FractionallySizedBox(
                  widthFactor: 0.5,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: KalinkaColors.surfaceOverlay,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: KalinkaColors.borderDefault),
                    ),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                for (final v in _views)
                  Expanded(
                    child: _Segment(
                      label: v.label,
                      spoken: v.spoken,
                      active: v.view == current,
                      duration: duration,
                      onTap: () =>
                          ref.read(playerViewProvider.notifier).show(v.view),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final String spoken;
  final bool active;
  final Duration duration;
  final VoidCallback onTap;

  const _Segment({
    required this.label,
    required this.spoken,
    required this.active,
    required this.duration,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: spoken,
      button: true,
      selected: active,
      inMutuallyExclusiveGroup: true,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          mouseCursor: clickCursor(interactive: !active),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: AnimatedDefaultTextStyle(
              duration: duration,
              style: KalinkaFonts.mono(
                fontSize: KalinkaTypography.baseSize,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                color: active
                    ? KalinkaColors.textPrimary
                    : KalinkaColors.textSecondary,
              ),
              child: Text(label, textAlign: TextAlign.center, maxLines: 1),
            ),
          ),
        ),
      ),
    );
  }
}
