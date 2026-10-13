import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/box_power_off_timer_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import 'settings_controls/settings_binding.dart';
import 'settings_controls/settings_row.dart';
import 'settings_renderer.dart';

/// A persisted Core timer beside the supervisor's manual power-off action.
class BoxPowerOffTimer extends ConsumerWidget {
  const BoxPowerOffTimer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final enabledField = settings.schema?.field(boxPowerOffEnabledPath);
    final minutesField = settings.schema?.field(boxPowerOffMinutesPath);
    if (enabledField == null ||
        minutesField == null ||
        !ref.watch(boxPowerOffTimerAvailableProvider)) {
      return const SizedBox.shrink();
    }
    final binding = ServerSettingsBinding(
      settings,
      ref.read(settingsProvider.notifier),
    );
    final enabled = binding.effectiveValue(boxPowerOffEnabledPath) == true;
    return SettingsScope(
      binding: binding,
      child: Column(
        children: [
          SettingsRow(
            label: enabledField.label,
            sublabel: enabledField.help,
            isStaged: binding.isStaged(boxPowerOffEnabledPath),
            issues: binding.issuesFor(boxPowerOffEnabledPath),
            control: Semantics(
              label: enabledField.label,
              child: Switch(
                value: enabled,
                onChanged: enabledField.readonly
                    ? null
                    : (value) {
                        FocusScope.of(context).unfocus();
                        binding.stage(boxPowerOffEnabledPath, value);
                      },
                activeTrackColor: KalinkaColors.accent,
                activeThumbColor: KalinkaColors.textPrimary,
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
            ),
          ),
          if (enabled)
            Semantics(
              label: '${minutesField.label}, minutes',
              child: SchemaFieldRenderer(field: minutesField),
            ),
        ],
      ),
    );
  }
}
