import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data_model/presentation_schema.dart';
import '../../providers/renderer_host_provider.dart'
    show rendererIdentityProvider;
import '../../providers/renderer_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../renderer_switcher.dart' show rendererDisplayName;
import '../settings_controls/settings_card.dart';
import 'onboarding_fields.dart';
import 'onboarding_step_scaffold.dart';
import 'sound_widgets.dart';

/// Wizard step: amplifier or receiver control for the chosen output.
///
/// Optional throughout — the default leaves volume with the output itself.
/// Choosing a device plugin (MusicCast today) stages its enabled flag and
/// shows the questions the server tagged for it; the output is handed to
/// it right after the final restart (see the attach task in
/// `onboarding_screen.dart`), taking over volume and power while the
/// output runs fixed at full. The built-in module's enabled flag is never
/// written — disabling it would drop volume control everywhere — and it
/// carries no setup tags, so no options card renders for the default.
/// Closes with the effective setup those choices add up to.
class OnboardingAmpControlStep extends ConsumerWidget {
  const OnboardingAmpControlStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final renderers = ref.watch(rendererListProvider);
    final ownId = ref.watch(rendererIdentityProvider).value?.rendererId;

    final active = renderers.active;
    final outputName = active == null
        ? null
        : rendererDisplayName(active, isSelf: active.rendererId == ownId);

    final choices = setupDeviceModules(state.schema);
    final hasRendererModule = schemaModulesOfKind(
      state.schema,
      'device',
    ).any((m) => m.id == kRendererVolumeModuleId);

    String enabledPath(ModuleSpec m) => 'devices.${m.id}.enabled';
    ModuleSpec? selected;
    for (final m in choices) {
      if (state.getEffective(enabledPath(m)) == true) {
        selected = m;
        break;
      }
    }

    void select(ModuleSpec? device) {
      for (final m in choices) {
        notifier.stageChange(enabledPath(m), m == device);
      }
    }

    final selectedFields = selected == null
        ? const <FieldSpec>[]
        : setupModuleFields(state.schema, selected);

    final defaultTitle = hasRendererModule
        ? kDefaultVolumeControlLabel
        : 'None';
    final defaultSubtitle = hasRendererModule
        ? 'The output sets its own volume.'
        : 'Kalinka plays straight to the audio output.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsCard(
          children: [
            _ChoiceRow(
              title: defaultTitle,
              subtitle: defaultSubtitle,
              selected: selected == null,
              // With nothing else to choose, the row is informational only.
              enabled: choices.isNotEmpty,
              onTap: () => select(null),
            ),
            for (final m in choices)
              _ChoiceRow(
                title: m.title,
                // Only the plugin's own words — the help on its `enabled`
                // field, the one per-device description the schema carries.
                // A stock sentence repeated under every device said nothing
                // the deck hadn't already said, three lines at a time.
                subtitle: moduleEnabledField(m)?.help,
                selected: selected == m,
                onTap: () => select(m),
              ),
          ],
        ),
        // One line, not two paragraphs: what the list holds is evident from
        // the list, and what the choice does is spelled out by the summary
        // card below — restating it here only pushed that card off screen.
        const OnboardingNote(
          'Missing your amplifier? Install its plugin on the server later '
          '— it shows up in Settings.',
        ),
        if (selected != null && selectedFields.isNotEmpty) ...[
          OnboardingSectionLabel('${selected.title} options'),
          SettingsCard(
            children: [
              for (final f in selectedFields) OnboardingFieldRow(path: f.path),
            ],
          ),
        ],
        const OnboardingSectionLabel('Your sound setup'),
        SettingsCard(
          children: [
            _EffectiveRow(
              label: 'Audio output',
              value: outputName ?? 'None connected yet',
            ),
            _EffectiveRow(
              label: 'Volume & power',
              value: selected?.title ?? kDefaultVolumeControlLabel,
            ),
            _EffectiveRow(
              label: 'Output volume',
              value: selected == null
                  ? 'Set on the output itself'
                  : 'Fixed at full — ${selected.title} sets the level',
            ),
          ],
        ),
      ],
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  final String title;

  /// Null for a device that describes itself nowhere — the name is then the
  /// whole row, which is all most amplifiers need.
  final String? subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _ChoiceRow({
    required this.title,
    this.subtitle,
    required this.selected,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.45,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          color: selected ? KalinkaColors.surfaceElevated : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              RadioMark(selected: selected),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: KalinkaTextStyles.trayRowLabel),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: KalinkaTextStyles.trayRowSublabel),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One line of the effective sound setup — label and outcome, no control.
class _EffectiveRow extends StatelessWidget {
  final String label;
  final String value;

  const _EffectiveRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: KalinkaTextStyles.trayRowSublabel),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(value, style: KalinkaTextStyles.trayRowLabel)),
        ],
      ),
    );
  }
}
