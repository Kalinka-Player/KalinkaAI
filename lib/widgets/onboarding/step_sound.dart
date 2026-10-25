import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/kalinka_player_api_provider.dart';
import '../../providers/renderer_host_provider.dart'
    show rendererIdentityProvider;
import '../../providers/renderer_provider.dart';
import '../../providers/renderer_settings_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/soundcard_provider.dart';
import '../../providers/supervisor_api.dart';
import '../../theme/app_theme.dart';
import '../kalinka_button.dart';
import '../kalinka_dialog.dart';
import '../renderer_switcher.dart' show rendererDisplayName;
import '../settings_controls/settings_card.dart';
import '../settings_controls/settings_enum_dropdown.dart';
import '../settings_controls/warning_note.dart';
import '../soundcard_row.dart';
import 'onboarding_step_scaffold.dart';
import 'sound_widgets.dart';
import 'speaker_test_dialog.dart';

/// The one card [report] found that only needs setting up; null when the
/// person has to choose.
SoundcardOption? _foundCard(SoundcardReport report) =>
    report.configured == null && report.suggested.length == 1
    ? report.option(report.suggested.first)
    : null;

/// What putting [report]'s trouble right is called.
String fixSoundcardLabel(SoundcardReport report) =>
    _foundCard(report) == null ? 'Choose a card' : 'Set it up';

/// Puts right what [soundcardTrouble] reports: sets up the one card found,
/// once the person confirms, or lets them choose.
Future<void> fixSoundcard(
  BuildContext context,
  SoundcardBox box,
  SoundcardReport report,
  SoundcardHost host,
) async {
  final found = _foundCard(report);
  if (found == null) return chooseSoundcardFor(context, box, report, host);
  if (await confirmSoundcard(
    context,
    box,
    found,
    afterRestart: host.confirmNote,
  )) {
    host.setUp(box, found);
  }
}

/// Asks before setup moves on from an output whose sound card does not play,
/// saying why it does not: true to move on, false to put it right, null when
/// dismissed.
Future<bool?> askLeavingSilentSoundcard(
  BuildContext context, {
  required String trouble,
  required String fixLabel,
}) => showKalinkaDialog<bool>(
  context: context,
  builder: (context) => KalinkaDialog(
    side: KalinkaDialogSide.player,
    icon: Icons.speaker_outlined,
    iconColor: KalinkaColors.statusPending,
    iconGlyphColor: KalinkaColors.statusPending,
    title: 'The sound card is not playing',
    message: trouble,
    actions: [
      KalinkaButton(
        label: 'Continue anyway',
        variant: KalinkaButtonVariant.neutral,
        fullWidth: true,
        onTap: () => Navigator.pop(context, true),
      ),
      KalinkaButton(
        label: fixLabel,
        fullWidth: true,
        onTap: () => Navigator.pop(context, false),
      ),
    ],
  ),
);

/// Wizard step: make the chosen output play, and hear it.
///
/// On a Raspberry Pi whose supervisor can set its sound card up, the card
/// comes first: one found but not set up is called out with the way to set
/// it up, and any other can be chosen. The output's playback device follows,
/// then the speaker test. The test is recommended, never required — the host
/// offers "Skip for now" until one ran, and [onTested] tells it one did.
class OnboardingSoundStep extends ConsumerWidget {
  /// Fired when the user starts a test, so the host can stop suggesting
  /// the step be skipped and the review can report it.
  final VoidCallback? onTested;

  /// Runs a sound card change, since the Pi may restart under the wizard.
  final SoundcardHost soundcardHost;

  const OnboardingSoundStep({
    super.key,
    required this.soundcardHost,
    this.onTested,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final renderers = ref.watch(rendererListProvider);
    final ownId = ref.watch(rendererIdentityProvider).value?.rendererId;
    final soundcard = ref.watch(outputSoundcardProvider).value;

    final active = renderers.active;
    final activeName = active == null
        ? null
        : rendererDisplayName(active, isSelf: active.rendererId == ownId);
    final canTest =
        !renderers.supported || (active != null && active.isConnected);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (soundcard != null) ...[
          const OnboardingSectionLabel('Sound card'),
          _SoundcardCard(
            box: soundcard.box,
            report: soundcard.report,
            host: soundcardHost,
          ),
        ],
        if (active != null && active.isConnected)
          OutputDeviceSection(rendererId: active.rendererId),
        const OnboardingSectionLabel('Test'),
        SettingsCard(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TestSoundButton(
                    enabled: canTest,
                    onTap: () {
                      onTested?.call();
                      showKalinkaDialog<void>(
                        context: context,
                        builder: (_) => SpeakerTestDialog(
                          targetName: activeName,
                          // Old servers read the staged ALSA device,
                          // renderer-era servers the renderer id — each
                          // ignores the parameter it doesn't know.
                          playTone: (channel) => ref
                              .read(kalinkaProxyProvider)
                              .testTone(
                                channel,
                                device: ref
                                    .read(settingsProvider)
                                    .getEffective(
                                      'base_config.output.alsa.device',
                                    )
                                    ?.toString(),
                                rendererId: active?.rendererId,
                              ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Plays a short tone down each channel'
                    '${activeName == null ? '' : ' through “$activeName”'}. '
                    'New outputs start at a safe volume.',
                    style: KalinkaTextStyles.trayRowSublabel,
                  ),
                ],
              ),
            ),
          ],
        ),
        if (!canTest)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: WarningNote(
              severity: WarningNoteSeverity.warning,
              message:
                  'No output is connected, so there is nothing to test — '
                  'continue and test from the output’s settings once one '
                  'joins.',
            ),
          )
        else
          const OnboardingNote(
            'If the tone comes out wrong, pick another playback device above '
            'and test again. The rest of the output’s settings are in the '
            'output picker once setup is done.',
          ),
      ],
    );
  }
}

/// The output's box's sound card: what plays, or, while a card it found or
/// was set up for does not, what is wrong and the way to put it right.
class _SoundcardCard extends ConsumerWidget {
  final SoundcardBox box;
  final SoundcardReport report;
  final SoundcardHost host;

  const _SoundcardCard({
    required this.box,
    required this.report,
    required this.host,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idle = ref.watch(soundcardChangeProvider(box)) == SoundcardStep.idle;
    final trouble = soundcardTrouble(report);

    if (trouble == null || !idle) {
      return SettingsCard(
        children: [SoundcardRow(box: box, report: report, host: host)],
      );
    }
    return _Callout(
      message: trouble,
      actions: [
        if (_foundCard(report) != null)
          KalinkaButton(
            label: 'Choose another',
            variant: KalinkaButtonVariant.neutral,
            size: KalinkaButtonSize.compact,
            onTap: () => chooseSoundcardFor(context, box, report, host),
          ),
        KalinkaButton(
          label: fixSoundcardLabel(report),
          size: KalinkaButtonSize.compact,
          onTap: () => fixSoundcard(context, box, report, host),
        ),
      ],
    );
  }
}

/// A warning that carries the actions which settle it.
class _Callout extends StatelessWidget {
  final String message;
  final List<Widget> actions;

  const _Callout({required this.message, required this.actions});

  @override
  Widget build(BuildContext context) {
    const tint = KalinkaColors.statusPending;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tint.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber_outlined, size: 22, color: tint),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: KalinkaTextStyles.trayRowLabel.copyWith(height: 1.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: actions,
          ),
        ],
      ),
    );
  }
}

/// An output's playback device, chosen from what its renderer offers and
/// applied on the spot. Shows nothing for a renderer that names no devices.
class OutputDeviceSection extends ConsumerStatefulWidget {
  final String rendererId;

  const OutputDeviceSection({super.key, required this.rendererId});

  @override
  ConsumerState<OutputDeviceSection> createState() =>
      _OutputDeviceSectionState();
}

class _OutputDeviceSectionState extends ConsumerState<OutputDeviceSection> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(rendererSettingsProvider(widget.rendererId).notifier).load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rendererSettingsProvider(widget.rendererId));
    final options = state.options[outputDevicePath] ?? const [];
    if (!state.loaded || options.isEmpty) return const SizedBox.shrink();
    final notifier = ref.read(
      rendererSettingsProvider(widget.rendererId).notifier,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const OnboardingSectionLabel('Playback device'),
        SettingsCard(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: SettingsEnumDropdown(
                options: options,
                selectedValue: '${state.values[outputDevicePath] ?? ''}',
                onChanged: (value) {
                  notifier.stage(outputDevicePath, value);
                  notifier.save();
                },
              ),
            ),
          ],
        ),
        if (state.error case final error?)
          WarningNote(message: error, severity: WarningNoteSeverity.warning),
      ],
    );
  }
}
