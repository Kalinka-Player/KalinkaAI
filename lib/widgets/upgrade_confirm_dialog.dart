import 'package:flutter/material.dart';

import '../providers/server_update_provider.dart';
import '../theme/app_theme.dart';
import 'kalinka_button.dart';
import 'kalinka_dialog.dart';

/// Confirmation for the software components included in one installer run.
///
/// Returns `true` when the user confirms — the caller starts the upgrade.
/// Launched from the update banner in Settings (left panel on tablet).
/// Show via [showKalinkaDialog].
class UpgradeConfirmDialog extends StatelessWidget {
  final ServerUpdateInfo update;

  const UpgradeConfirmDialog({super.key, required this.update});

  @override
  Widget build(BuildContext context) {
    return KalinkaDialog(
      side: KalinkaDialogSide.left,
      icon: Icons.system_update_alt,
      iconGlyphColor: KalinkaColors.accentTint,
      title: 'Update player software?',
      message:
          'Updating takes a few minutes. Playback stops and the player '
          'will be unavailable until it restarts.',
      content: update.changes.isEmpty
          ? null
          : Text(
              update.changes.join('\n'),
              style: KalinkaTextStyles.trayRowSublabel,
            ),
      actions: [
        KalinkaButton(
          label: 'Cancel',
          variant: KalinkaButtonVariant.neutral,
          fullWidth: true,
          onTap: () => Navigator.pop(context, false),
        ),
        KalinkaButton(
          label: 'Restart & Update',
          variant: KalinkaButtonVariant.accent,
          fullWidth: true,
          onTap: () => Navigator.pop(context, true),
        ),
      ],
    );
  }
}
