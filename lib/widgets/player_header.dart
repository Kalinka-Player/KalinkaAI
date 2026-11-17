import 'dart:math' as math;

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
  final Widget? output;

  /// Wide Now Playing places its output beside fullscreen. Other layouts
  /// keep it with the playback controls.
  const PlayerHeader({
    super.key,
    required this.isTablet,
    required this.showingQueue,
    this.onClose,
    this.output,
  });

  static double _outputWidth(BuildContext context, double width, bool tablet) =>
      math.min(
        280,
        (width -
                    (tablet ? 40 : 32) -
                    PlayerViewSwitch.preferredWidth(context)) /
                2 -
            52,
      );

  /// Leave readable device text and space between the centred tabs and the
  /// output/fullscreen group. The same budget sizes the actual header.
  static bool outputFits(
    BuildContext context,
    double width, {
    required bool tablet,
  }) => _outputWidth(context, width, tablet) >= 144;

  static double _outputRowHeight(BuildContext context) {
    double textHeight(TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: 'Output', style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final height = painter.height;
      painter.dispose();
      return height;
    }

    return math.max(
      kKalinkaTopBarHeight,
      math.max(
        textHeight(KalinkaTextStyles.sectionLabel) + 24,
        textHeight(KalinkaTextStyles.trayRowSublabel) + 20,
      ),
    );
  }

  /// Used by Now Playing to check that its artwork and controls fit below
  /// this header before moving the output out of the body.
  static double heightWithOutput(
    BuildContext context, {
    required bool tablet,
  }) => _outputRowHeight(context) + (tablet ? 0 : 22);

  Widget _withOutput(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 20 : 16,
        vertical: isTablet ? 0 : 8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isTablet) ...[_handle(), const SizedBox(height: 2)],
          SizedBox(
            height: _outputRowHeight(context),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Center(child: PlayerViewSwitch()),
                if (!isTablet)
                  Align(alignment: Alignment.centerLeft, child: _closeButton()),
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: _outputWidth(
                            context,
                            constraints.maxWidth,
                            isTablet,
                          ),
                          minHeight: 48,
                        ),
                        child: output!,
                      ),
                      const SizedBox(width: 8),
                      const KioskEnterButton(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _closeButton() => IconButton(
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

  Widget _handle() => Center(
    child: Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (output != null && !showingQueue) return _withOutput(context);
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

    final leading = _closeButton();
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
          _handle(),
          // The chevron's own padding already sets it off from the handle.
          const SizedBox(height: 2),
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
