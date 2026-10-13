import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/box_control_provider.dart';
import '../providers/supervisor_api.dart';
import '../providers/toast_provider.dart';
import '../theme/app_theme.dart';
import 'configuration_appearance.dart';
import 'box_actions.dart';
import 'settings_controls/settings_action_row.dart';
import 'settings_controls/settings_card.dart';

/// Management actions for the server's hardware, through its supervisor.
/// Optional server actions remain available without a matching supervisor.
class BoxSection extends ConsumerWidget {
  final String title;
  final List<Widget> leadingActions;

  const BoxSection({
    super.key,
    this.title = 'STREAMER',
    this.leadingActions = const [],
  });

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
    final hasBox = control != null && api != null;
    if (!hasBox && leadingActions.isEmpty) return const SizedBox.shrink();
    final configured = ConfigurationAppearance.active(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: ConfigurationAppearance.sectionPadding(context),
          child: Text(title, style: KalinkaTextStyles.sectionHeaderMuted),
        ),
        SettingsCard(
          children: [
            ...leadingActions,
            if (hasBox) ...[
              SettingsActionRow(
                label: 'Streamer dashboard',
                sublabel:
                    'Versions, memory and processor use, and reinstalling '
                    'Kalinka, in the browser',
                trailing: Icons.open_in_new,
                leading: configured ? Icons.dashboard_outlined : null,
                onTap: () => _openDashboard(ref, api.page),
              ),
              if (control.offers(BoxAction.reboot))
                SettingsActionRow(
                  label: 'Restart streamer',
                  sublabel:
                      'Restarts the whole player. It is back in a minute '
                      'or two',
                  leading: configured ? Icons.autorenew : null,
                  trailing: configured ? null : Icons.autorenew,
                  onTap: () => runBoxAction(
                    context,
                    ref,
                    BoxAction.reboot,
                    inPanel: true,
                  ),
                ),
              if (control.offers(BoxAction.powerOff))
                SettingsActionRow(
                  label: 'Power off streamer',
                  sublabel:
                      'Shuts the player down safely, so it can be '
                      'unplugged',
                  leading: configured ? Icons.power_settings_new : null,
                  trailing: configured ? null : Icons.power_settings_new,
                  onTap: () => runBoxAction(
                    context,
                    ref,
                    BoxAction.powerOff,
                    inPanel: true,
                  ),
                ),
            ],
          ],
        ),
      ],
    );
  }
}
