import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/presentation_schema.dart';
import '../providers/settings_provider.dart';
import '../providers/box_power_off_timer_provider.dart';
import 'expert_field_list.dart';

/// The server's own settings as the about:config-style flat list.
///
/// Reached via the EXPERT toggle in the settings header. All the rendering
/// lives in [ExpertFieldList]; this only points it at `/server/config`.
class ExpertSettingsScreen extends ConsumerWidget {
  final Widget? heading;
  const ExpertSettingsScreen({super.key, this.heading});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(settingsProvider);
    final fields = state.schema?.expertFields ?? const <FieldSpec>[];
    final timerAvailable =
        fields.any((f) => boxPowerOffPaths.contains(f.path)) &&
        ref.watch(boxPowerOffTimerAvailableProvider);
    return ExpertFieldList(
      heading: heading,
      fields: fields
          .where((f) => timerAvailable || !boxPowerOffPaths.contains(f.path))
          .toList(),
      binding: ServerSettingsBinding(
        state,
        ref.read(settingsProvider.notifier),
      ),
    );
  }
}
