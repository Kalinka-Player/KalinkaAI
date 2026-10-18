import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/presentation_schema.dart' show OptionSpec;
import '../providers/box_control_provider.dart';
import '../providers/supervisor_api.dart';
import '../providers/timezone_provider.dart';
import '../providers/toast_provider.dart';
import '../theme/app_theme.dart';
import '../theme/field_decoration.dart';
import 'kalinka_bottom_sheet.dart';
import 'kalinka_button.dart';
import 'kalinka_dialog.dart';
import 'settings_controls/option_picker.dart';
import 'settings_controls/settings_action_row.dart';

/// "Time zone" on the connected server's box: the zone it is on, opening the
/// picker. A box that cannot set its zone shows the row disabled, saying why,
/// or offering to look again when its supervisor did not answer.
class TimezoneRow extends ConsumerStatefulWidget {
  final BoxTimezone box;
  final IconData? leading;

  /// Set when shown in a pane of the tablet layout.
  final bool inPanel;

  const TimezoneRow({
    super.key,
    required this.box,
    this.leading,
    this.inPanel = false,
  });

  @override
  ConsumerState<TimezoneRow> createState() => _TimezoneRowState();
}

class _TimezoneRowState extends ConsumerState<TimezoneRow> {
  // A second tap while the list loads would open a second picker.
  bool _choosing = false;

  Future<void> _choose() async {
    if (_choosing) return;
    _choosing = true;
    try {
      await chooseTimezone(context, ref, widget.box, inPanel: widget.inPanel);
    } finally {
      _choosing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final box = widget.box;
    final leading = widget.leading;
    if (!box.settable) {
      final retry = switch (box.probe.missing) {
        NoBoxControl.notAnswering || NoBoxControl.otherServer => true,
        _ => false,
      };
      final looking = retry && ref.watch(boxProbeProvider).isLoading;
      return SettingsActionRow(
        label: 'Time zone',
        sublabel: looking ? 'Looking for the box…' : timezoneUnavailable(box),
        leading: leading,
        trailing: retry ? Icons.refresh : null,
        onTap: retry && !looking
            ? () {
                ref.invalidate(serverIdentityProvider);
                ref.invalidate(boxProbeProvider);
              }
            : null,
      );
    }
    final setting = ref.watch(timezoneChangeProvider);
    return SettingsActionRow(
      label: 'Time zone',
      sublabel: switch ((setting, box.zone)) {
        (final zone?, _) => 'Setting ${timezoneLabel(zone)}…',
        (_, final zone?) => timezoneLabel(zone),
        _ => 'Not known',
      },
      leading: leading,
      onTap: () {
        if (setting == null) _choose();
      },
    );
  }
}

/// Why [box] cannot be set to another zone from the app.
String timezoneUnavailable(BoxTimezone box) => switch (box.probe.missing) {
  NoBoxControl.noSupervisor =>
    'No box supervisor answers on this server, so it keeps the time zone of '
        'the computer it runs on. Set it there.',
  NoBoxControl.notAnswering => 'The box did not answer. Tap to try again.',
  NoBoxControl.otherServer =>
    'A different Kalinka box answers at this address. Tap to try again.',
  NoBoxControl.incompatible =>
    'The box’s supervisor and this app do not speak the same version. '
        'Update both to set the time zone here.',
  null => 'Updating Kalinka on this box lets the app set its time zone.',
};

/// Lets the person pick one of the zones [box] offers, confirms it, and
/// sets it.
Future<void> chooseTimezone(
  BuildContext context,
  WidgetRef ref,
  BoxTimezone box, {
  bool inPanel = false,
}) async {
  // Held until read, or the zone would be dropped while nothing shows it.
  final local = ref.listenManual(localTimezoneProvider.future, (_, _) {});
  final (String?, List<String>?) found;
  try {
    found = await (
      local.read(),
      ref.read(supervisorApiProvider)?.timezones() ?? Future.value(),
    ).wait;
  } finally {
    local.close();
  }
  if (!context.mounted) return;
  final (localZone, zones) = found;
  if (zones == null) {
    ref
        .read(toastProvider.notifier)
        .show(
          'The box did not answer. Check that it is on and connected.',
          isError: true,
          inPanel: inPanel,
        );
    return;
  }
  final picked = await showKalinkaBottomSheet<String>(
    context: context,
    mayFillScreen: true,
    contentBuilder: (_) =>
        TimezonePicker(zones: zones, current: box.zone, local: localZone),
  );
  if (picked == null || picked == box.zone || !context.mounted) return;
  await setTimezoneOnceConfirmed(context, ref, picked, inPanel: inPanel);
}

/// Asks before setting the box to [zone], since its display restarts.
Future<void> setTimezoneOnceConfirmed(
  BuildContext context,
  WidgetRef ref,
  String zone, {
  bool inPanel = false,
}) async {
  // Read before the dialog: the row may be gone by the time Apply is tapped.
  final change = ref.read(timezoneChangeProvider.notifier);
  final confirmed = await showKalinkaDialog<bool>(
    context: context,
    builder: (_) => _ConfirmTimezone(zone: zone),
  );
  if (confirmed != true) return;
  await change.apply(zone, inPanel: inPanel);
}

/// The zones a box offers, searchable, with this device's own first; pops the
/// one tapped.
class TimezonePicker extends StatefulWidget {
  final List<String> zones;

  /// The zone the box is on, listed even when it is not among [zones].
  final String? current;

  /// This device's zone.
  final String? local;

  const TimezonePicker({
    super.key,
    required this.zones,
    this.current,
    this.local,
  });

  @override
  State<TimezonePicker> createState() => _TimezonePickerState();
}

class _TimezonePickerState extends State<TimezonePicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final needle = timezoneLabel(_query).trim().toLowerCase();
    bool matches(String zone) =>
        timezoneLabel(zone).toLowerCase().contains(needle);
    final current = widget.current;
    final local = widget.local;
    final all = [
      if (current != null && !widget.zones.contains(current)) current,
      ...widget.zones,
    ].where(matches).toList();
    final entries = <({String text, bool header})>[
      if (local != null && matches(local)) ...[
        (text: 'THIS DEVICE', header: true),
        (text: local, header: false),
      ],
      if (all.isNotEmpty) (text: 'ALL TIME ZONES', header: true),
      for (final zone in all) (text: zone, header: false),
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: TextField(
                key: const ValueKey('timezone-search'),
                style: KalinkaTextStyles.textFieldInput,
                decoration: kalinkaFieldDecoration(hint: 'Search time zones'),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Flexible(
              child: entries.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                      child: Text(
                        'No time zone matches “${_query.trim()}”.',
                        textAlign: TextAlign.center,
                        style: KalinkaTextStyles.trayRowSublabel,
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 12),
                      itemCount: entries.length,
                      itemBuilder: (context, i) {
                        final (:text, :header) = entries[i];
                        if (header) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                            child: Text(
                              text,
                              style: KalinkaTextStyles.sectionHeaderMuted,
                            ),
                          );
                        }
                        return OptionRow(
                          option: OptionSpec(
                            value: text,
                            label: timezoneLabel(text),
                          ),
                          selected: text == current,
                          onTap: () => Navigator.of(context).pop(text),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmTimezone extends StatelessWidget {
  final String zone;

  const _ConfirmTimezone({required this.zone});

  @override
  Widget build(BuildContext context) {
    return KalinkaDialog(
      side: KalinkaDialogSide.player,
      icon: Icons.schedule,
      iconColor: KalinkaColors.accent,
      iconGlyphColor: KalinkaColors.accentTint,
      title: 'Change the time zone?',
      message:
          'The box shows the time in ${timezoneLabel(zone)} from now on. A '
          'now-playing display on it restarts to follow; playback carries on.',
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
