import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'away.dart';
import 'kiosk/kiosk_enter_button.dart';
import 'player_view_switch.dart';
import 'queue_actions.dart';
import 'renderer_switcher.dart';

/// Keeps the player's view labels at their requested text size. When the
/// controls and labels no longer fit together, they get separate rows.
class PlayerHeader extends StatelessWidget {
  final bool isTablet;
  final bool showingQueue;
  final VoidCallback? onClose;
  final Key? outputSwitcherKey;

  /// The server is away: the output switcher takes no input, as the
  /// mini-player's does. Closing and switching views still work.
  final bool away;

  const PlayerHeader({
    super.key,
    required this.isTablet,
    required this.showingQueue,
    this.onClose,
    this.outputSwitcherKey,
    this.away = false,
  });

  Widget _output(Widget switcher) => AwayDim(
    away: away,
    child: AwayLock(away: away, child: switcher),
  );

  @override
  Widget build(BuildContext context) {
    if (isTablet) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: OverflowBar(
          alignment: MainAxisAlignment.spaceBetween,
          overflowAlignment: OverflowBarAlignment.start,
          spacing: 16,
          overflowSpacing: 8,
          children: [
            const PlayerViewSwitch(),
            // In queue mode the mini-player carries the output switcher.
            if (showingQueue)
              const QueueMenuButton()
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const KioskEnterButton(),
                  const SizedBox(width: 8),
                  Flexible(
                    child: _output(
                      RendererSwitcherDropdown(key: outputSwitcherKey),
                    ),
                  ),
                ],
              ),
          ],
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
        : _output(const RendererSwitcherButton(hitDiameter: 36, iconSize: 20));

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
