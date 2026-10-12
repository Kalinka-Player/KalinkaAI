import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../utils/click_cursor.dart';

/// A settings card row that acts when tapped — opens a screen, a page or a
/// confirmation — with [trailing] hinting at which.
class SettingsActionRow extends StatelessWidget {
  final String label;
  final String? sublabel;
  final IconData? leading;
  final IconData? trailing;
  final VoidCallback onTap;

  const SettingsActionRow({
    super.key,
    required this.label,
    this.sublabel,
    this.leading,
    this.trailing = Icons.chevron_right,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Ink paints on the nearest Material, which must sit above the card's
    // fill for the press to show.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        mouseCursor: clickCursor(interactive: true),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              if (leading case final icon?) ...[
                ExcludeSemantics(
                  child: Icon(
                    icon,
                    size: 24,
                    color: KalinkaColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: KalinkaTextStyles.trayRowLabel),
                    if (sublabel != null) ...[
                      const SizedBox(height: 2),
                      Text(sublabel!, style: KalinkaTextStyles.trayRowSublabel),
                    ],
                  ],
                ),
              ),
              if (trailing case final icon?) ...[
                const SizedBox(width: 12),
                ExcludeSemantics(
                  child: Icon(
                    icon,
                    size: 20,
                    color: KalinkaColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
