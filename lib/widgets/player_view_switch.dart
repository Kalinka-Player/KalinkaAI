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

  static final _labelStyle = KalinkaFonts.mono(
    fontSize: KalinkaTypography.baseSize,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.2,
  );

  /// Space for both labels at the user's text size, including their padding
  /// and the outer border. Headers can move the switch onto its own row.
  static double preferredWidth(BuildContext context) {
    var labelWidth = 0.0;
    for (final view in _views) {
      final painter = TextPainter(
        text: TextSpan(text: view.label, style: _labelStyle),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
      )..layout();
      if (painter.width > labelWidth) labelWidth = painter.width;
      painter.dispose();
    }
    return 2 * (labelWidth.ceilToDouble() + 24) + 6;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(playerViewProvider);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    final width = preferredWidth(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // At very large text sizes, stack whole labels instead of shrinking
        // them or breaking a word across lines.
        final vertical = constraints.maxWidth < width;
        return SizedBox(
          width: vertical ? constraints.maxWidth : width,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: KalinkaColors.surfaceInput,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: KalinkaColors.borderSubtle),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedAlign(
                    alignment: vertical
                        ? (current == PlayerView.queue
                              ? Alignment.bottomCenter
                              : Alignment.topCenter)
                        : (current == PlayerView.queue
                              ? AlignmentDirectional.centerEnd
                              : AlignmentDirectional.centerStart),
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    child: FractionallySizedBox(
                      widthFactor: vertical ? 1 : 0.5,
                      heightFactor: vertical ? 0.5 : 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: KalinkaColors.surfaceOverlay,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ),
                if (vertical)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final v in _views)
                        _Segment(
                          label: v.label,
                          spoken: v.spoken,
                          active: v.view == current,
                          duration: duration,
                          onTap: () => ref
                              .read(playerViewProvider.notifier)
                              .show(v.view),
                        ),
                    ],
                  )
                else
                  Row(
                    children: [
                      for (final v in _views)
                        Expanded(
                          child: _Segment(
                            label: v.label,
                            spoken: v.spoken,
                            active: v.view == current,
                            duration: duration,
                            onTap: () => ref
                                .read(playerViewProvider.notifier)
                                .show(v.view),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
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
      onTap: onTap,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          mouseCursor: clickCursor(interactive: !active),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Center(
                heightFactor: 1,
                child: AnimatedDefaultTextStyle(
                  duration: duration,
                  style: PlayerViewSwitch._labelStyle.copyWith(
                    color: active
                        ? KalinkaColors.textPrimary
                        : KalinkaColors.textSecondary,
                  ),
                  child: Text(label, textAlign: TextAlign.center),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
