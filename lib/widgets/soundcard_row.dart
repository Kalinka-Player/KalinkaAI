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

/// "Sound card" on a box: the DAC it has and how it stands, opening the
/// picker. Its host shows it once [soundcardReportProvider] has a report.
class SoundcardRow extends ConsumerWidget {
  final SoundcardBox box;
  final SoundcardReport report;

  /// Set when shown in the tablet layout's left panel.
  final bool inPanel;

  const SoundcardRow({
    super.key,
    required this.box,
    required this.report,
    this.inPanel = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final step = ref.watch(soundcardChangeProvider(box));
    return SettingsActionRow(
      label: 'Sound card',
      sublabel: switch (step) {
        SoundcardStep.applying => 'Setting the sound card up…',
        SoundcardStep.restarting => 'Restarting to switch the card on…',
        SoundcardStep.idle => soundcardSummary(report),
      },
      onTap: () {
        if (step == SoundcardStep.idle) {
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

/// Lets the person pick a card for [box], confirms it, and applies it. The
/// card already set up needs nothing; a refusal is reported in a toast.
Future<void> chooseSoundcard(
  BuildContext context,
  WidgetRef ref,
  SoundcardBox box,
  SoundcardReport report, {
  bool inPanel = false,
}) async {
  final picked = await showKalinkaBottomSheet<String>(
    context: context,
    mayFillScreen: true,
    contentBuilder: (_) => SoundcardPicker(report: report),
  );
  final card = report.option(picked);
  if (card == null || card.name == report.configured || !context.mounted) {
    return;
  }
  final confirmed = await showKalinkaDialog<bool>(
    context: context,
    builder: (_) => _ConfirmSoundcard(card: card),
  );
  if (confirmed != true) return;
  try {
    await ref.read(soundcardChangeProvider(box).notifier).apply(card);
  } on BoxActionException catch (e) {
    ref
        .read(toastProvider.notifier)
        .show(e.message, isError: true, inPanel: inPanel);
  }
}

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

  const _ConfirmSoundcard({required this.card});

  @override
  Widget build(BuildContext context) {
    return KalinkaDialog(
      side: KalinkaDialogSide.left,
      icon: Icons.speaker_outlined,
      iconColor: KalinkaColors.accent,
      iconGlyphColor: KalinkaColors.accentTint,
      title: 'Change the sound card?',
      message:
          'Sets this box up for ${card.label}. If its boot settings change, '
          'it restarts once, which takes a minute or two.',
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

/// A pointer to an output's gear while the Raspberry Pi it runs on has no
/// sound card up, not even over USB, so a DAC HAT is set up before setup
/// finishes.
class SoundcardHint extends ConsumerWidget {
  final List<String> rendererIds;

  const SoundcardHint({super.key, required this.rendererIds});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var silent = false;
    for (final id in rendererIds) {
      final box = ref.watch(rendererSoundcardBoxProvider(id)).value;
      final report = box == null
          ? null
          : ref.watch(soundcardReportProvider(box)).value;
      silent |=
          report != null && report.activePcm == null && report.usb.isEmpty;
    }
    if (!silent) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Text(
        'Using a DAC HAT? Open the output’s gear and choose it under '
        'Sound card.',
        style: KalinkaTextStyles.trayRowSublabel,
      ),
    );
  }
}
