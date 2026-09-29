import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/kiosk_provider.dart';
import '../theme/app_theme.dart';
import 'kalinka_button.dart';
import 'kalinka_dialog.dart';
import 'settings_controls/settings_card.dart';
import 'settings_controls/settings_row.dart';
import 'settings_controls/settings_toggle.dart';

/// "THIS DEVICE" on the General settings page: settings kept by this app
/// install rather than the server, applied at once rather than staged.
class ThisDeviceSection extends ConsumerWidget {
  const ThisDeviceSection({super.key});

  Future<void> _lock(BuildContext context, WidgetRef ref) async {
    final confirmed = await showKalinkaDialog<bool>(
      context: context,
      builder: (_) => const _LockToDisplayDialog(),
    );
    if (confirmed == true) {
      await ref.read(kioskProvider.notifier).lockToDevice();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locked = ref.watch(
      kioskProvider.select((s) => s.lock == KioskLock.device),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 10),
          child: Text(
            'THIS DEVICE',
            style: KalinkaTextStyles.sectionHeaderMuted,
          ),
        ),
        SettingsCard(
          children: [
            SettingsRow(
              label: 'Now-playing display',
              sublabel:
                  'Keep this device on a full-screen now-playing screen, '
                  'every time the app starts',
              control: SettingsToggle(
                value: locked,
                onChanged: (on) {
                  if (on) {
                    _lock(context, ref);
                  } else {
                    ref.read(kioskProvider.notifier).unlockDevice();
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LockToDisplayDialog extends StatelessWidget {
  const _LockToDisplayDialog();

  @override
  Widget build(BuildContext context) {
    return KalinkaDialog(
      side: KalinkaDialogSide.left,
      icon: Icons.fullscreen_rounded,
      iconGlyphColor: KalinkaColors.accentTint,
      title: 'Switch to the now-playing display?',
      message:
          'This device will show only what is playing, full screen, and '
          'open that way every time the app starts. To leave it, tap the '
          'Kalinka logo at the top of the screen five times.',
      actions: [
        KalinkaButton(
          label: 'Cancel',
          variant: KalinkaButtonVariant.neutral,
          fullWidth: true,
          onTap: () => Navigator.pop(context, false),
        ),
        KalinkaButton(
          label: 'Switch',
          variant: KalinkaButtonVariant.accent,
          fullWidth: true,
          onTap: () => Navigator.pop(context, true),
        ),
      ],
    );
  }
}
