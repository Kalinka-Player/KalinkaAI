import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data_model/presentation_schema.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../settings_controls/module_header_row.dart' show ModuleHeaderRow;
import '../settings_controls/settings_card.dart';
import '../settings_controls/settings_toggle.dart';
import 'onboarding_fields.dart';
import 'onboarding_step_scaffold.dart';

/// Wizard step: choose which sources feed the library — the on/off half of
/// the question. What each chosen source needs comes on the next step, so
/// this one stays a short list, straight off the schema's input modules.
class OnboardingMusicSourcesStep extends ConsumerWidget {
  const OnboardingMusicSourcesStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(settingsProvider);
    final modules = schemaModulesOfKind(state.schema, 'input_module');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsCard(
          children: [for (final m in modules) _SourceRow(module: m)],
        ),
        const OnboardingNote(
          'My Library is the music on your server, so it is always on.',
        ),
      ],
    );
  }
}

/// One input plugin: icon tile, title, enable switch. My Library renders
/// on and locked — the server's library backend is built in.
class _SourceRow extends ConsumerWidget {
  final ModuleSpec module;

  const _SourceRow({required this.module});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    final isLocalFiles = module.id == 'localfiles';
    final enabledField = moduleEnabledField(module);
    final enabled = inputModuleEnabled(state, module);
    final (icon, iconColor) = ModuleHeaderRow.iconForModule(module.id);

    final sublabel = isLocalFiles
        ? 'Your music folders on the server — always on.'
        : enabledField == null
        ? 'Set up later in Settings.'
        : 'Streaming source.';

    Widget toggle = SettingsToggle(
      value: enabled,
      onChanged: (v) {
        if (isLocalFiles || enabledField == null) return;
        notifier.stageChange(enabledField.path, v);
        // What was entered for a source switched off goes with it: the next
        // step no longer shows it, so a value the server refuses there would
        // hold up the save with nowhere to fix it.
        if (!v) {
          notifier.unstageUnder(moduleRoot(module), keep: enabledField.path);
        }
      },
    );
    if (isLocalFiles || enabledField == null) {
      toggle = IgnorePointer(child: Opacity(opacity: 0.4, child: toggle));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: KalinkaColors.surfaceOverlay,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(module.title, style: KalinkaTextStyles.trayRowLabel),
                const SizedBox(height: 2),
                Text(sublabel, style: KalinkaTextStyles.trayRowSublabel),
              ],
            ),
          ),
          const SizedBox(width: 12),
          toggle,
        ],
      ),
    );
  }
}
