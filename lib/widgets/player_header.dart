import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'kalinka_top_bar.dart' show KalinkaWordmark;
import 'kiosk/kiosk_enter_button.dart';
import 'player_view_switch.dart';
import 'queue_actions.dart';

/// Keeps the player's view labels at their requested text size. When the
/// controls and labels no longer fit together, they get separate rows.
class PlayerHeader extends StatelessWidget {
  final bool isTablet;
  final bool showingQueue;
  final VoidCallback? onClose;

  /// The output switch is the player's, under its transport, not the
  /// header's.
  const PlayerHeader({
    super.key,
    required this.isTablet,
    required this.showingQueue,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    if (isTablet) {
      // The docked player's half of the bar it shares with browsing: the
      // same height and inset as the top bar beside it, so the two read as
      // one, their controls on one centre line.
      final actions = showingQueue
          ? const QueueMenuButton()
          : const KioskEnterButton();
      const wordmark = Padding(
        padding: EdgeInsets.only(left: 4),
        child: KalinkaWordmark(),
      );
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kKalinkaTopBarHeight),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // What each end keeps clear of the centred tabs: the
              // wordmark's room, which the actions at the other end fit in.
              const side = 4 + KalinkaWordmark.width + 16;
              final tabs = PlayerViewSwitch.preferredWidth(context);
              // Enlarged labels that would reach either end take a row of
              // their own, as the phone's do.
              if (constraints.maxWidth < tabs + 2 * side) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [wordmark, actions],
                    ),
                    const SizedBox(height: 8),
                    const Center(child: PlayerViewSwitch()),
                  ],
                );
              }
              return Stack(
                alignment: Alignment.center,
                children: [
                  const Center(child: PlayerViewSwitch()),
                  const Align(alignment: Alignment.centerLeft, child: wordmark),
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              );
            },
          ),
        ),
      );
    }

    final leading = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Minimise player',
          onPressed: onClose,
          style: IconButton.styleFrom(
            minimumSize: const Size(36, 36),
            padding: const EdgeInsets.all(4),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: const Icon(
            Icons.keyboard_arrow_down,
            size: 28,
            color: KalinkaColors.textSecondary,
          ),
        ),
        if (!showingQueue) ...[
          const SizedBox(width: 4),
          const KioskEnterButton(),
        ],
      ],
    );
    final trailing = showingQueue
        ? const QueueMenuButton()
        : const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              // Reserve the same side space in both views, even when output
              // selection is hidden, so switching views cannot move the tabs.
              const sideSpace = 36 + 4 + 36 + 8;
              final fits =
                  PlayerViewSwitch.preferredWidth(context) + 2 * sideSpace <=
                  constraints.maxWidth;
              if (!fits) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [leading, trailing],
                    ),
                    const SizedBox(height: 8),
                    const Center(child: PlayerViewSwitch()),
                  ],
                );
              }
              return Stack(
                alignment: Alignment.center,
                children: [
                  const Center(child: PlayerViewSwitch()),
                  Align(alignment: Alignment.centerLeft, child: leading),
                  Align(alignment: Alignment.centerRight, child: trailing),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
