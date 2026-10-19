import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data_model/kalinka_ws_api.dart';
import '../providers/kalinka_ws_api_provider.dart';
import '../theme/app_theme.dart';
import 'kalinka_button.dart';
import 'kalinka_dialog.dart';

/// Shown when the current track fails to play. Offers two actions:
///   - "Skip" (primary/accent): advance to the next track and close.
///   - "Dismiss" (neutral): just close.
///
/// Sits over Now Playing on tablet: it is about the current track, and both
/// its actions are transport actions. The queue/search panel stays legible —
/// this dialog is uninvited, so it shouldn't black out whatever the user was
/// actually doing. Show via [showKalinkaDialog].
class PlaybackErrorDialog extends ConsumerWidget {
  final String? message;

  const PlaybackErrorDialog({super.key, this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return KalinkaDialog(
      side: KalinkaDialogSide.player,
      // Greyscale, not accent — this reports a state, it isn't a CTA.
      icon: Icons.warning_rounded,
      iconColor: KalinkaColors.textMuted,
      title: 'Playback error',
      message: (message != null && message!.isNotEmpty)
          ? message!
          : 'This track couldn’t be played.',
      actions: [
        KalinkaButton(
          label: 'Dismiss',
          variant: KalinkaButtonVariant.neutral,
          fullWidth: true,
          onTap: () => Navigator.pop(context),
        ),
        KalinkaButton(
          label: 'Skip',
          variant: KalinkaButtonVariant.accent,
          fullWidth: true,
          onTap: () {
            ref
                .read(kalinkaWsApiProvider)
                .sendQueueCommand(const QueueCommand.next());
            Navigator.pop(context);
          },
        ),
      ],
    );
  }
}
