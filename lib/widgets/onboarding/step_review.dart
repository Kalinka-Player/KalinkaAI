import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/connection_settings_provider.dart';
import '../../providers/renderer_host_provider.dart'
    show rendererIdentityProvider;
import '../../providers/renderer_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../renderer_switcher.dart' show rendererDisplayName;
import '../settings_controls/settings_card.dart';
import '../settings_controls/warning_note.dart';
import 'onboarding_fields.dart';
import 'onboarding_step_scaffold.dart';

/// Wizard step: the setup at a glance, ahead of the final apply-and-restart.
///
/// Every row is derived from the same schema state the steps stage into, so
/// the summary cannot drift from the flow; rows carry a Change link back to
/// their step via [onEdit].
class OnboardingReviewStep extends ConsumerWidget {
  /// Jumps the wizard to a step (1 = sources, 2 = source setup, 3 = output,
  /// 4 = amplifier control, 5 = sound test).
  final void Function(int step)? onEdit;

  /// Whether a sound test was run this session — the test step reports it.
  final bool soundTested;

  const OnboardingReviewStep({
    super.key,
    this.onEdit,
    this.soundTested = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(settingsProvider);
    final connection = ref.watch(connectionSettingsProvider);
    final renderers = ref.watch(rendererListProvider);
    final ownId = ref.watch(rendererIdentityProvider).value?.rendererId;

    final modules = schemaModulesOfKind(state.schema, 'input_module');
    final enabledModules = [
      for (final m in modules)
        if (inputModuleEnabled(state, m)) m,
    ];
    final notReady = [
      for (final m in enabledModules)
        if (!moduleConfigured(state, m)) m,
    ];

    final sourcesValue = enabledModules.isEmpty
        ? 'None'
        : enabledModules
              .map(
                (m) => moduleConfigured(state, m)
                    ? '${m.title} · Ready'
                    : '${m.title} · Needs setup',
              )
              .join('\n');

    final activeRenderer = renderers.active;
    String outputValue;
    if (renderers.supported) {
      outputValue = activeRenderer == null
          ? 'None connected'
          : rendererDisplayName(
              activeRenderer,
              isSelf: activeRenderer.rendererId == ownId,
            );
    } else {
      // Pre-renderer server: the ALSA option label, over the raw id.
      final deviceValue =
          state
              .getEffective('base_config.output.alsa.device')
              ?.toString()
              .trim() ??
          '';
      outputValue = deviceValue.isEmpty ? 'System default' : deviceValue;
      for (final o
          in state.optionsFor('base_config.output.alsa.device') ?? const []) {
        if (o.value == deviceValue) {
          outputValue = o.label;
          break;
        }
      }
    }

    String? volumeControlTitle;
    for (final m in setupDeviceModules(state.schema)) {
      if (state.getEffective('devices.${m.id}.enabled') == true) {
        volumeControlTitle = m.title;
        break;
      }
    }
    final hasRendererModule = schemaModulesOfKind(
      state.schema,
      'device',
    ).any((m) => m.id == kRendererVolumeModuleId);
    final volumeValue =
        volumeControlTitle ??
        (hasRendererModule ? kDefaultVolumeControlLabel : 'None');

    final serviceName = state
        .getEffective('base_config.server.service_name')
        ?.toString()
        .trim();

    void Function()? edit(int step) =>
        onEdit == null ? null : () => onEdit!(step);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const OnboardingSectionLabel('Your setup'),
        SettingsCard(
          children: [
            // No Change link: the server is the one thing the wizard can't
            // revisit — switching it would restart setup from discovery.
            _SummaryRow(
              label: 'Server',
              value:
                  '${(serviceName?.isNotEmpty ?? false) ? serviceName! : connection.name}'
                  ' · ${connection.host}:${connection.port}',
            ),
            _SummaryRow(
              label: 'Music sources',
              value: sourcesValue,
              onChange: edit(notReady.isEmpty ? 1 : 2),
            ),
            _SummaryRow(
              label: 'Audio output',
              value: outputValue,
              onChange: edit(3),
            ),
            _SummaryRow(
              label: 'Volume & power',
              value: volumeValue,
              onChange: edit(4),
            ),
            _SummaryRow(
              label: 'Sound test',
              value: soundTested ? 'Played' : 'Skipped',
              onChange: edit(5),
            ),
          ],
        ),
        if (renderers.supported && activeRenderer == null)
          const WarningNote(
            severity: WarningNoteSeverity.warning,
            message:
                'No outputs connected — nothing can play yet. Install the '
                'Kalinka renderer on the machine wired to your speakers, '
                'or open the web player in a browser.',
          ),
        for (final m in notReady)
          if (moduleMissingFields(state, m) case final missing
              when missing.isNotEmpty)
            WarningNote(
              severity: WarningNoteSeverity.warning,
              message:
                  '${m.title} still needs ${missing.join(' and ')} — it '
                  'won’t work until that is set.',
            ),
        // Why Start is out of reach: the server would refuse the whole save.
        if (refusedNotes(state) case final refused when refused.isNotEmpty)
          WarningNote(
            severity: WarningNoteSeverity.error,
            message:
                'The server won’t accept this setup yet — '
                '${refused.join('; ')}. Fix that before starting.',
          ),
        if (!soundTested && renderers.supported && activeRenderer != null)
          const WarningNote(
            severity: WarningNoteSeverity.warning,
            message:
                'Sound was never tested. If nothing plays later, open the '
                'output’s settings from the output picker and test there.',
          ),
        const OnboardingNote(
          'Starting saves these settings and restarts the server so they '
          'take effect — that takes about half a minute. Library indexing '
          'and any smart-search analysis run in the background afterwards; '
          'the app reconnects by itself and drops you on the play queue.',
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onChange;

  const _SummaryRow({required this.label, required this.value, this.onChange});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: KalinkaTextStyles.trayRowSublabel.copyWith(
                fontSize: KalinkaTypography.baseSize + 2,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: KalinkaTextStyles.trayRowLabel.copyWith(
                fontSize: KalinkaTypography.baseSize + 3,
              ),
            ),
          ),
          if (onChange != null) ...[
            const SizedBox(width: 12),
            _ChangeLink(label: label, onTap: onChange!),
          ],
        ],
      ),
    );
  }
}

/// "Change" affordance: plain accent text at rest, a tinted pill under the
/// pointer — without it the word reads as a caption rather than a control.
class _ChangeLink extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _ChangeLink({required this.label, required this.onTap});

  @override
  State<_ChangeLink> createState() => _ChangeLinkState();
}

class _ChangeLinkState extends State<_ChangeLink> {
  bool _hovered = false;

  void _setHover(bool value) {
    if (value != _hovered) setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Change ${widget.label}',
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHover(true),
        onExit: (_) => _setHover(false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _hovered ? KalinkaColors.accentSubtle : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _hovered
                    ? KalinkaColors.accentBorder
                    : Colors.transparent,
              ),
            ),
            child: Text(
              'Change',
              style: KalinkaTextStyles.trayRowSublabel.copyWith(
                fontSize: KalinkaTypography.baseSize + 2,
                color: KalinkaColors.accentTint,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
