import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import 'settings_controls/settings_toggle.dart';
import 'settings_top_bar.dart';

/// Expert view control in the secondary settings toolbar.
/// Off = the structured page, on = the flat about:config-style list.
///
/// One switch for the whole app: expert is a disposition the user is in, not a
/// per-page mode, so the server's settings and a renderer's follow each other.
///
/// One native button supplies keyboard activation, focus and a 48dp target;
/// the switch inside is its visual state, not a second interactive control.
class ExpertModeToggle extends ConsumerWidget {
  const ExpertModeToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expert = ref.watch(expertModeProvider);
    final notifier = ref.read(expertModeProvider.notifier);
    // Merged: the button is its own semantics container, so the label and
    // toggled state would otherwise sit on a node that cannot be activated.
    return MergeSemantics(
      child: Semantics(
        label: 'Expert settings',
        toggled: expert,
        child: TextButton(
          style: settingsIconButtonStyle,
          onPressed: notifier.toggle,
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'EXPERT',
                  style: KalinkaTextStyles.sectionHeaderMuted.copyWith(
                    letterSpacing: 1.0,
                    color: KalinkaColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 10),
                IgnorePointer(
                  child: SettingsToggle(
                    value: expert,
                    onChanged: (_) => notifier.toggle(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
