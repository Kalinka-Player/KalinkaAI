import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/box_control_provider.dart';
import '../providers/supervisor_api.dart';
import '../providers/toast_provider.dart';
import '../theme/app_theme.dart';
import 'box_actions.dart';
import 'settings_controls/settings_action_row.dart';
import 'settings_controls/settings_card.dart';

/// "BOX" on the General settings page: the player box the server runs on,
/// through its supervisor. Absent when the box has none, or one that is not
/// this server's.
class BoxSection extends ConsumerWidget {
  const BoxSection({super.key});

  Future<void> _openDashboard(WidgetRef ref, Uri page) async {
    final toast = ref.read(toastProvider.notifier);
    try {
      if (await launchUrl(page, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // Reported below, as when no browser takes the link.
    }
    toast.show(
      'Could not open a browser. Visit $page instead.',
      isError: true,
      inPanel: true,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final control = ref.watch(boxControlProvider).value;
    final api = ref.watch(supervisorApiProvider);
    if (control == null || api == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 10),
          child: Text('BOX', style: KalinkaTextStyles.sectionHeaderMuted),
        ),
        SettingsCard(
          children: [
            SettingsActionRow(
              label: 'Box dashboard',
              sublabel:
                  'Versions, memory and processor use, and reinstalling '
                  'Kalinka, in the browser',
              trailing: Icons.open_in_new,
              onTap: () => _openDashboard(ref, api.page),
            ),
            if (control.offers(BoxAction.reboot))
              SettingsActionRow(
                label: 'Restart the box',
                sublabel:
                    'Restarts the whole player. It is back in a minute '
                    'or two',
                trailing: Icons.autorenew,
                onTap: () =>
                    runBoxAction(context, ref, BoxAction.reboot, inPanel: true),
              ),
            if (control.offers(BoxAction.powerOff))
              SettingsActionRow(
                label: 'Power off',
                sublabel:
                    'Shuts the player down safely, so it can be '
                    'unplugged',
                trailing: Icons.power_settings_new,
                onTap: () => runBoxAction(
                  context,
                  ref,
                  BoxAction.powerOff,
                  inPanel: true,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
