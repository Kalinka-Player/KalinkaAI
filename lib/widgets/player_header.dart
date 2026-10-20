import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
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
      // one, their controls on one centre line. Browsing's half, at the
      // window's start, leads with the wordmark.
      final actions = Align(
        alignment: Alignment.centerRight,
        child: showingQueue
            ? const QueueMenuButton()
            : const KioskEnterButton(),
      );
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kKalinkaTopBarHeight),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // What each end keeps clear of the centred tabs: the actions'
              // room.
              const side = 36 + 8;
              final tabs = PlayerViewSwitch.preferredWidth(context);
              // Enlarged labels that would reach either end take a row of
              // their own, as the phone's do.
              if (constraints.maxWidth < tabs + 2 * side) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    actions,
                    const SizedBox(height: 8),
                    const Center(child: PlayerViewSwitch()),
                  ],
                );
              }
              return Stack(
                alignment: Alignment.center,
                children: [
                  const Center(child: PlayerViewSwitch()),
                  actions,
                ],
              );
            },
          ),
        ),
      );
    }

    final leading = IconButton(
      tooltip: 'Minimise player',
      onPressed: onClose,
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.all(10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(
        Icons.keyboard_arrow_down,
        size: 28,
        color: KalinkaColors.textSecondary,
      ),
    );
    // Fullscreen stays on the same right edge as the docked player, even
    // when the tabs need their own row. Queue options use that same slot.
    final trailing = showingQueue
        ? const QueueMenuButton()
        : const KioskEnterButton();

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
              // Reserve the larger action's width at both ends so the tabs
              // stay centred and do not move when switching views.
              const sideSpace = 48 + 8;
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
