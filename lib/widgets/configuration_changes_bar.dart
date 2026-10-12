import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'configuration_appearance.dart';

class ConfigurationChangesBar extends StatelessWidget {
  final int count;
  final bool busy;
  final String? issueLabel;
  final VoidCallback onReview;
  final VoidCallback onDiscard;
  final VoidCallback onApply;

  const ConfigurationChangesBar({
    super.key,
    required this.count,
    required this.busy,
    required this.issueLabel,
    required this.onReview,
    required this.onDiscard,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    final gutter = ConfigurationAppearance.gutter(context);
    final blocked = issueLabel != null;
    return Material(
      color: KalinkaColors.surfaceRaised,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: KalinkaColors.borderDefault)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(gutter, 10, gutter, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$count ${count == 1 ? 'change' : 'changes'} not applied',
                  style: KalinkaTextStyles.trayRowLabel,
                ),
                const SizedBox(height: 4),
                Text(
                  blocked ? 'Check $issueLabel before applying your changes.' : 'Applying them will restart your player and briefly stop music.',
                  style: KalinkaTextStyles.trayRowSublabel,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    TextButton(
                      key: const ValueKey('configuration-bar-discard'),
                      onPressed: busy ? null : onDiscard,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        foregroundColor: KalinkaColors.textSecondary,
                      ),
                      child: const Text('Discard'),
                    ),
                    FilledButton(
                      key: const ValueKey('configuration-bar-apply'),
                      onPressed: busy
                          ? null
                          : blocked
                          ? onReview
                          : onApply,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        backgroundColor: KalinkaColors.accent,
                        foregroundColor: KalinkaColors.textPrimary,
                      ),
                      child: Text(
                        busy
                            ? 'Applying…'
                            : blocked
                            ? 'Review changes'
                            : 'Apply & restart',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
