import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/server_update_provider.dart';
import '../theme/app_theme.dart';
import 'kalinka_button.dart';
import 'kalinka_dialog.dart';

/// Confirmation for the software components included in one installer run.
///
/// Returns the update it listed when the user confirms — the caller starts
/// the upgrade. Launched from the update banner in Settings; over the
/// player's pane on tablet.
/// Show via [showKalinkaDialog].
class UpgradeConfirmDialog extends ConsumerWidget {
  final ServerUpdateInfo update;

  const UpgradeConfirmDialog({super.key, required this.update});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Follows a re-check that lands while the dialog is open.
    final checked = ref.watch(serverUpdateProvider).value;
    final update = checked != null && checked.canUpgrade
        ? checked
        : this.update;
    return KalinkaDialog(
      side: KalinkaDialogSide.player,
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
          onTap: () => Navigator.pop(context),
        ),
        KalinkaButton(
          label: 'Restart & Update',
          variant: KalinkaButtonVariant.accent,
          fullWidth: true,
          onTap: () => Navigator.pop(context, update),
        ),
      ],
    );
  }
}
