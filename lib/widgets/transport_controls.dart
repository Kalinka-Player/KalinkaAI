import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/kalinka_ws_api.dart';
import '../providers/app_state_provider.dart';
import '../providers/kalinka_ws_api_provider.dart';
import '../providers/now_playing_provider.dart';
import '../theme/app_theme.dart';
import 'transport_button.dart';

/// Previous or next track. Faded and inert where the queue has no track that
/// way to go to.
class SkipButton extends ConsumerWidget {
  final bool next;
  final double hitDiameter;
  final double iconSize;

  const SkipButton({
    super.key,
    required this.next,
    this.hitDiameter = 52,
    this.iconSize = 36,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(
      transportStateProvider.select((t) => next ? t.canNext : t.canPrev),
    );
    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: enabled,
        label: next ? 'Next track' : 'Previous track',
        child: Opacity(
          opacity: enabled ? 1.0 : 0.4,
          child: TransportButton(
            hitDiameter: hitDiameter,
            onTap: enabled
                ? () => ref
                      .read(kalinkaWsApiProvider)
                      .sendQueueCommand(
                        next
                            ? const QueueCommand.next()
                            : const QueueCommand.prev(),
                      )
                : null,
            child: Icon(
              next ? Icons.skip_next_rounded : Icons.skip_previous_rounded,
              size: iconSize,
              color: KalinkaColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shuffle, on or off for what the queue plays next. Absent while a plugin
/// plays, which takes no playback mode.
class ShuffleButton extends ConsumerWidget {
  final double hitDiameter;
  final double iconSize;

  const ShuffleButton({super.key, this.hitDiameter = 44, this.iconSize = 22});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(transportStateProvider.select((t) => t.exclusive))) {
      return const SizedBox.shrink();
    }
    final mode = ref.watch(playbackModeProvider);
    return MergeSemantics(
      child: Semantics(
        button: true,
        toggled: mode.shuffle,
        label: 'Shuffle',
        child: TransportButton(
          hitDiameter: hitDiameter,
          onTap: () => ref
              .read(kalinkaWsApiProvider)
              .sendQueueCommand(
                QueueCommand.setPlaybackMode(
                  shuffle: !mode.shuffle,
                  repeatAll: mode.repeatAll,
                  repeatSingle: mode.repeatSingle,
                ),
              ),
          child: Icon(
            Icons.shuffle,
            size: iconSize,
            color: mode.shuffle
                ? KalinkaColors.accent
                : KalinkaColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Repeat, stepping off → all → one. Absent while a plugin plays.
class RepeatButton extends ConsumerWidget {
  final double hitDiameter;
  final double iconSize;

  const RepeatButton({super.key, this.hitDiameter = 44, this.iconSize = 22});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(transportStateProvider.select((t) => t.exclusive))) {
      return const SizedBox.shrink();
    }
    final mode = ref.watch(playbackModeProvider);
    final one = mode.repeatSingle;
    final on = mode.repeatAll || one;
    // Off → all → one → off.
    final (all, single) = one
        ? (false, false)
        : mode.repeatAll
        ? (false, true)
        : (true, false);
    return MergeSemantics(
      child: Semantics(
        button: true,
        toggled: on,
        label: one ? 'Repeat one' : 'Repeat',
        child: TransportButton(
          hitDiameter: hitDiameter,
          onTap: () => ref
              .read(kalinkaWsApiProvider)
              .sendQueueCommand(
                QueueCommand.setPlaybackMode(
                  shuffle: mode.shuffle,
                  repeatAll: all,
                  repeatSingle: single,
                ),
              ),
          child: Icon(
            one ? Icons.repeat_one : Icons.repeat,
            size: iconSize,
            color: on ? KalinkaColors.accent : KalinkaColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
