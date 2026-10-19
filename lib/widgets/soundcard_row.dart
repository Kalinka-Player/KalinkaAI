import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/presentation_schema.dart' show OptionSpec;
import '../providers/soundcard_provider.dart';
import '../providers/supervisor_api.dart';
import '../providers/toast_provider.dart';
import '../theme/app_theme.dart';
import 'kalinka_bottom_sheet.dart';
import 'kalinka_button.dart';
import 'kalinka_dialog.dart';
import 'settings_controls/option_picker.dart';
import 'settings_controls/settings_action_row.dart';
import 'settings_controls/settings_card.dart';

/// Sets a box up for the card the person picked and confirmed.
typedef SetUpSoundcard = void Function(SoundcardBox box, SoundcardOption card);

/// A host that runs sound card changes itself, as the setup wizard does,
/// rather than leaving them to the row that was tapped.
class SoundcardHost {
  final SetUpSoundcard setUp;

  /// Ends the confirmation, saying what the host does meanwhile.
  final String? confirmNote;

  const SoundcardHost({required this.setUp, this.confirmNote});
}

/// "Sound card" on a box: the DAC it has and how it stands, opening the
/// picker. Its host shows it once [soundcardReportProvider] has a report.
class SoundcardRow extends ConsumerWidget {
  final SoundcardBox box;
  final SoundcardReport report;

  /// Set when shown in a pane of the tablet layout.
  final bool inPanel;

  /// Runs the change, when the row is hosted by one that does.
  final SoundcardHost? host;

  const SoundcardRow({
    super.key,
    required this.box,
    required this.report,
    this.inPanel = false,
    this.host,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final step = ref.watch(soundcardChangeProvider(box));
    return SettingsActionRow(
      label: 'Sound card',
      sublabel: switch (step) {
        SoundcardStep.applying => 'Setting the sound card up…',
        SoundcardStep.restarting => 'Restarting to switch the card on…',
        SoundcardStep.switching => 'Switching the output to the card…',
        SoundcardStep.idle => soundcardSummary(report),
      },
      onTap: () {
        if (step != SoundcardStep.idle) return;
        if (host case final host?) {
          chooseSoundcardFor(context, box, report, host);
        } else {
          chooseSoundcard(context, ref, box, report, inPanel: inPanel);
        }
      },
    );
  }
}

/// The DAC a box has, and whether it plays: what the row says at rest.
String soundcardSummary(SoundcardReport report) {
  final configured = report.option(report.configured);
  final suggested = report.suggested;
  if (report.activePcm != null) {
    return report.name ?? configured?.label ?? 'A sound card is up';
  }
  if (configured != null) return '${configured.label}, not detected';
  if (suggested.length == 1) {
    final found = report.name ?? report.option(suggested.first)?.label;
    return '$found found. Choose it to switch it on';
  }
  if (suggested.isNotEmpty) return 'A DAC HAT found. Choose your board';
  if (report.usb.isNotEmpty) {
    return 'No DAC HAT. USB DAC: ${report.usb.join(', ')}';
  }
  return 'No DAC HAT found';
}

/// Why the card a box found, or is set up for, does not play yet; null when
/// nothing the box can tell is wrong.
String? soundcardTrouble(SoundcardReport report) {
  if (report.activePcm != null) return null;
  if (report.option(report.configured) case final configured?) {
    return '${configured.label} is set up but did not come up. Check that '
        'the HAT sits firmly on the pins, or choose another card.';
  }
  final suggested = report.suggested;
  if (suggested.isEmpty) return null;
  final found = suggested.length == 1
      ? report.name ?? report.option(suggested.first)?.label
      : null;
  return '${found ?? 'A DAC HAT'} was found but is not set up, so nothing '
      'plays through it yet.';
}

/// Lets the person pick a card for [box], confirms it, and applies it. The
/// card already set up needs nothing; a refusal is reported in a toast.
Future<void> chooseSoundcard(
  BuildContext context,
  WidgetRef ref,
  SoundcardBox box,
  SoundcardReport report, {
  bool inPanel = false,
}) async {
  final card = await pickSoundcard(context, report);
  if (card == null) return;
  try {
    await ref.read(soundcardChangeProvider(box).notifier).apply(card);
  } on BoxActionException catch (e) {
    ref
        .read(toastProvider.notifier)
        .show(e.message, isError: true, inPanel: inPanel);
  }
}

/// Lets the person pick and confirm a card for [box], for [host] to set up.
Future<void> chooseSoundcardFor(
  BuildContext context,
  SoundcardBox box,
  SoundcardReport report,
  SoundcardHost host,
) async {
  final card = await pickSoundcard(
    context,
    report,
    afterRestart: host.confirmNote,
  );
  if (card != null) host.setUp(box, card);
}

/// The card the person picked from [report]'s and confirmed; null when they
/// backed out or picked the card already set up. [afterRestart] ends the
/// confirmation.
Future<SoundcardOption?> pickSoundcard(
  BuildContext context,
  SoundcardReport report, {
  String? afterRestart,
}) async {
  final picked = await showKalinkaBottomSheet<String>(
    context: context,
    mayFillScreen: true,
    contentBuilder: (_) => SoundcardPicker(report: report),
  );
  final card = report.option(picked);
  if (card == null || card.name == report.configured || !context.mounted) {
    return null;
  }
  return await confirmSoundcard(context, card, afterRestart: afterRestart)
      ? card
      : null;
}

/// Asks before [card] is set up, since the box may restart.
Future<bool> confirmSoundcard(
  BuildContext context,
  SoundcardOption card, {
  String? afterRestart,
}) async =>
    await showKalinkaDialog<bool>(
      context: context,
      builder: (_) => _ConfirmSoundcard(card: card, afterRestart: afterRestart),
    ) ==
    true;

/// Every card a box can be set up for, the detected ones first, then by
/// maker, the Pi's own outputs and no HAT; pops the name of the one tapped.
class SoundcardPicker extends StatelessWidget {
  final SoundcardReport report;

  const SoundcardPicker({super.key, required this.report});

  Map<String, List<SoundcardOption>> get _groups {
    final groups = <String, List<SoundcardOption>>{};
    final found = [for (final name in report.suggested) ?report.option(name)];
    if (found.isNotEmpty) groups['FOUND ON THIS BOX'] = found;
    for (final option in report.options) {
      final group = switch (option.kind) {
        'onboard' => 'THE PI’S OWN OUTPUTS',
        'none' => 'NO HAT',
        _ => option.vendor.toUpperCase(),
      };
      (groups[group] ??= []).add(option);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (final MapEntry(key: group, value: options) in _groups.entries) {
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
          child: Text(group, style: KalinkaTextStyles.sectionHeaderMuted),
        ),
      );
      for (final option in options) {
        rows.add(
          OptionRow(
            option: OptionSpec(value: option.name, label: option.label),
            selected: option.name == report.configured,
            onTap: () => Navigator.of(context).pop(option.name),
          ),
        );
      }
    }
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 12),
        children: rows,
      ),
    );
  }
}

class _ConfirmSoundcard extends StatelessWidget {
  final SoundcardOption card;
  final String? afterRestart;

  const _ConfirmSoundcard({required this.card, this.afterRestart});

  @override
  Widget build(BuildContext context) {
    return KalinkaDialog(
      side: KalinkaDialogSide.player,
      icon: Icons.speaker_outlined,
      iconColor: KalinkaColors.accent,
      iconGlyphColor: KalinkaColors.accentTint,
      title: 'Change the sound card?',
      message:
          'Sets this box up for ${card.label}. If its boot settings change, '
          'it restarts once, which takes a minute or two.'
          '${afterRestart == null ? '' : ' $afterRestart'}',
      actions: [
        KalinkaButton(
          label: 'Cancel',
          variant: KalinkaButtonVariant.neutral,
          fullWidth: true,
          onTap: () => Navigator.pop(context, false),
        ),
        KalinkaButton(
          label: 'Apply',
          variant: KalinkaButtonVariant.accent,
          fullWidth: true,
          onTap: () => Navigator.pop(context, true),
        ),
      ],
    );
  }
}

/// "SOUND CARD" on an output's settings page, for an output on a box whose
/// supervisor can set up its sound card.
class RendererSoundcardSection extends ConsumerWidget {
  final String rendererId;

  const RendererSoundcardSection({super.key, required this.rendererId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final box = ref.watch(rendererSoundcardBoxProvider(rendererId)).value;
    final report = box == null
        ? null
        : ref.watch(soundcardReportProvider(box)).value;
    if (box == null || report == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 10),
          child: Text(
            'SOUND CARD',
            style: KalinkaTextStyles.sectionHeaderMuted,
          ),
        ),
        SettingsCard(
          children: [SoundcardRow(box: box, report: report)],
        ),
      ],
    );
  }
}
