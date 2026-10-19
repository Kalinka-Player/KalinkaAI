import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'kalinka_button.dart';
import 'kalinka_dialog.dart';

/// Confirmation dialog for restarting the server.
///
/// Returns `true` when the user confirms, `false`/`null` when cancelled —
/// the caller performs the restart. Launched from Settings; over the player's
/// pane on tablet. Show via [showKalinkaDialog].
class RestartConfirmDialog extends StatelessWidget {
  const RestartConfirmDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return KalinkaDialog(
      side: KalinkaDialogSide.player,
      icon: Icons.restart_alt,
      iconGlyphColor: KalinkaColors.accentTint,
      title: 'Restart server?',
      message:
          'Applies any pending changes and restarts the server. '
          'Playback will stop briefly.',
      actions: [
        KalinkaButton(
          label: 'Cancel',
          variant: KalinkaButtonVariant.neutral,
          fullWidth: true,
          onTap: () => Navigator.pop(context, false),
        ),
        KalinkaButton(
          label: 'Restart',
          variant: KalinkaButtonVariant.accent,
          fullWidth: true,
          onTap: () => Navigator.pop(context, true),
        ),
      ],
    );
  }
}
