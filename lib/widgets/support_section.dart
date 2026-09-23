import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/click_cursor.dart';
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
            // Ink paints on the nearest Material, which must sit above the
            // card's fill for the press to show.
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onDownloadLogs,
                mouseCursor: clickCursor(interactive: true),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Download server logs',
                              style: KalinkaTextStyles.trayRowLabel,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'An archive of recent logs to attach to a bug '
                              'report.',
                              style: KalinkaTextStyles.trayRowSublabel,
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: KalinkaColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
