import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data_model/kalinka_ws_api.dart';

import '../providers/app_state_provider.dart';
import '../providers/kalinka_ws_api_provider.dart';
import '../theme/app_theme.dart';
import 'kalinka_bottom_sheet.dart';
import 'tap_highlight.dart';

/// Actions that can be returned from the queue management tray.
enum TrayAction { saveToCollection, clearPlayed, clearAll }

/// Content body for the queue management tray, shown with
/// [showKalinkaBottomSheet].
class QueueManagementTrayContent extends ConsumerWidget {
  final ValueChanged<TrayAction>? onAction;

  const QueueManagementTrayContent({super.key, this.onAction});

  void _emitAction(BuildContext context, TrayAction action) {
    if (onAction != null) {
      onAction!(action);
      return;
    }
    Navigator.pop(context, action);
  }

  void _setRepeatMode(
    WidgetRef ref, {
    required bool repeatAll,
    required bool repeatSingle,
  }) {
    final playbackMode = ref.read(playbackModeProvider);
    ref
        .read(kalinkaWsApiProvider)
        .sendQueueCommand(
          QueueCommand.setPlaybackMode(
            shuffle: playbackMode.shuffle,
            repeatAll: repeatAll,
            repeatSingle: repeatSingle,
          ),
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queued = ref.watch(playQueueProvider).length;
    final playbackMode = ref.watch(playbackModeProvider);
    final isRepeatAll = playbackMode.repeatAll;
    final isRepeatOne = playbackMode.repeatSingle;
    final isShuffle = playbackMode.shuffle;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        const SheetSectionLabel('PLAYBACK'),

        SheetRow(
          icon: Icons.shuffle,
          iconBackground: KalinkaColors.surfaceOverlay,
          iconColor: KalinkaColors.textSecondary,
          label: 'Shuffle',
          sublabel: isShuffle
              ? 'On \u2014 playing in random order'
              : 'Off \u2014 plays in order',
          trailing: _buildToggleSwitch(
            value: isShuffle,
            activeColor: KalinkaColors.accent,
            onTap: () {
              // Shuffle not yet wired to API
            },
          ),
        ),
        const SheetDivider(),
        SheetRow(
          icon: isRepeatOne ? Icons.repeat_one : Icons.repeat,
          iconBackground: KalinkaColors.surfaceOverlay,
          iconColor: KalinkaColors.textSecondary,
          label: 'Repeat',
          trailing: _RepeatSegmentedControl(
            repeatAll: isRepeatAll,
            repeatOne: isRepeatOne,
            onChanged: (repeatAll, repeatSingle) {
              _setRepeatMode(
                ref,
                repeatAll: repeatAll,
                repeatSingle: repeatSingle,
              );
            },
          ),
        ),

        const SizedBox(height: 8),
        const SheetDivider(),
        const SizedBox(height: 12),

        const SheetSectionLabel('QUEUE'),

        _SaveRow(
          queued: queued,
          onTap: queued == 0
              ? null
              : () {
                  _emitAction(context, TrayAction.saveToCollection);
                },
        ),

        const SizedBox(height: 8),
        const SheetDivider(),
        const SizedBox(height: 12),

        SheetRow(
          icon: Icons.history,
          iconBackground: KalinkaColors.surfaceOverlay,
          iconColor: KalinkaColors.textSecondary,
          label: 'Clear played',
          sublabel: 'Remove tracks from listening history',
          onTap: () {
            _emitAction(context, TrayAction.clearPlayed);
          },
        ),
        const SheetDivider(),
        SheetRow(
          icon: Icons.delete_outline,
          iconBackground: KalinkaColors.actionDelete.withValues(alpha: 0.12),
          iconColor: KalinkaColors.actionDelete,
          label: 'Clear queue',
          sublabel: 'Remove current and upcoming tracks',
          labelColor: KalinkaColors.actionDelete,
          onTap: () {
            _emitAction(context, TrayAction.clearAll);
          },
        ),
      ],
    );
  }

  Widget _buildToggleSwitch({
    required bool value,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return TapHighlight(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        width: 42,
        height: 24,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: value ? activeColor : KalinkaColors.surfaceElevated,
          border: value ? null : Border.all(color: KalinkaColors.borderDefault),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 16,
            height: 16,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value ? Colors.white : KalinkaColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// The one way forward in the tray: what is queued, kept. Drawn as a card
/// among plain rows because it is the only thing here that makes something
/// rather than unmaking it, and lettered in leaf green for the same reason —
/// the palette's own colour for a positive action, against the red below.
class _SaveRow extends StatelessWidget {
  final int queued;
  final VoidCallback? onTap;

  const _SaveRow({required this.queued, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kSheetGutter),
      child: Semantics(
        button: true,
        label: 'Save this queue to a collection',
        child: TapHighlight(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: KalinkaColors.statusOnlineSurface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.playlist_add_rounded,
                  size: 16,
                  color: KalinkaColors.statusOnlineLight,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Save this queue',
                      style: KalinkaTextStyles.trayRowLabel,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      queued == 0
                          ? 'Nothing queued to save yet'
                          : 'Choose a collection or create a new one',
                      style: KalinkaTextStyles.trayRowSublabel,
                    ),
                  ],
                ),
              ),
              if (queued > 0) ...[
                const SizedBox(width: 10),
                _QueuedBadge(queued: queued),
              ],
              const SizedBox(width: 4),
              const SheetChevron(),
            ],
          ),
        ),
      ),
    );
  }
}

/// How much would be saved, said where the decision is made.
class _QueuedBadge extends StatelessWidget {
  final int queued;

  const _QueuedBadge({required this.queued});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: KalinkaColors.surfaceOverlay,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$queued ${queued == 1 ? 'TRACK' : 'TRACKS'}',
        style: KalinkaTextStyles.traySectionLabel,
      ),
    );
  }
}

/// Three-segment pill control for repeat mode: Off / All / One.
class _RepeatSegmentedControl extends StatelessWidget {
  final bool repeatAll;
  final bool repeatOne;
  final void Function(bool repeatAll, bool repeatSingle) onChanged;

  const _RepeatSegmentedControl({
    required this.repeatAll,
    required this.repeatOne,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KalinkaColors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: KalinkaColors.borderDefault),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSegment(
            label: 'Off',
            isActive: !repeatAll && !repeatOne,
            onTap: () => onChanged(false, false),
          ),
          _buildSegment(
            label: 'All',
            isActive: repeatAll,
            onTap: () => onChanged(true, false),
          ),
          _buildSegment(
            label: 'One',
            isActive: repeatOne,
            onTap: () => onChanged(false, true),
          ),
        ],
      ),
    );
  }

  Widget _buildSegment({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return TapHighlight(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? KalinkaColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: KalinkaTextStyles.trayRowSublabel.copyWith(
            color: isActive ? Colors.white : KalinkaColors.textSecondary,
            fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
