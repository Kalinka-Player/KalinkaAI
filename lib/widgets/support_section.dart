import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'settings_controls/settings_action_row.dart';
import 'settings_controls/settings_card.dart';

/// "SUPPORT" at the foot of the General settings page: what a user needs
/// when reporting a problem.
class SupportSection extends StatelessWidget {
  final VoidCallback onDownloadLogs;

  const SupportSection({super.key, required this.onDownloadLogs});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 10),
          child: Text('SUPPORT', style: KalinkaTextStyles.sectionHeaderMuted),
        ),
        SettingsCard(
          children: [
            SettingsActionRow(
              label: 'Download server logs',
              sublabel: 'An archive of recent logs to attach to a bug report.',
              onTap: onDownloadLogs,
            ),
          ],
        ),
      ],
    );
  }
}
