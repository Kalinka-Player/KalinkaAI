import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'kalinka_button.dart';
import 'kalinka_dialog.dart';

/// Asks whether to upgrade the renderer named [rendererName].
///
/// Returns `true` when the user confirms — the caller posts the upgrade.
/// Raised from the output picker by both the row of a renderer that can no
/// longer play and the button on one merely behind; [blocked] tells the two
/// apart in the wording. Show via [showKalinkaDialog].
class RendererUpgradeDialog extends StatelessWidget {
  final String rendererName;

  /// The renderer cannot play at all until it is upgraded.
  final bool blocked;

  const RendererUpgradeDialog({
    super.key,
    required this.rendererName,
    required this.blocked,
  });

  @override
  Widget build(BuildContext context) {
    return KalinkaDialog(
      side: KalinkaDialogSide.player,
      icon: Icons.system_update_alt,
      iconGlyphColor: blocked
          ? KalinkaColors.statusPending
          : KalinkaColors.accentTint,
      title: 'Upgrade $rendererName?',
      message: blocked
          ? '$rendererName is running software this server can no longer talk '
                'to, so it cannot play until it is upgraded. It installs the '
                'new version itself and reconnects in a minute or two.'
          : 'A newer version is available for $rendererName. It installs the '
                'new version itself and reconnects in a minute or two; '
                'playback on it stops while it restarts.',
      actions: [
        KalinkaButton(
          label: 'Cancel',
          variant: KalinkaButtonVariant.neutral,
          fullWidth: true,
          onTap: () => Navigator.pop(context, false),
        ),
        KalinkaButton(
          label: 'Upgrade',
          variant: KalinkaButtonVariant.accent,
          fullWidth: true,
          onTap: () => Navigator.pop(context, true),
        ),
      ],
    );
  }
}
