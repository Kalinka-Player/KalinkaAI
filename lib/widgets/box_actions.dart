import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/box_control_provider.dart';
import '../providers/connection_state_provider.dart';
import '../providers/power_off_status_provider.dart';
import '../providers/supervisor_api.dart';
import '../providers/toast_provider.dart';
import '../theme/app_theme.dart';
import 'kalinka_button.dart';
import 'kalinka_dialog.dart';

typedef _Wording = ({
  IconData icon,
  String title,
  String message,
  String confirm,
  String accepted,
  bool destructive,
});

_Wording _wording(BoxAction action) => switch (action) {
  BoxAction.restartServer => (
    icon: Icons.restart_alt,
    title: 'Restart the server?',
    message:
        "Kalinka's server is not answering. The streamer starts it again; playback "
        'stops until it is back.',
    confirm: 'Restart',
    accepted: 'Restarting the server…',
    destructive: false,
  ),
  BoxAction.reboot => (
    icon: Icons.autorenew,
    title: 'Restart streamer?',
    message:
        'The whole player restarts. Playback stops, and the streamer is back in a '
        'minute or two.',
    confirm: 'Restart',
    accepted: 'Restarting the streamer. The app reconnects when it is back.',
    destructive: false,
  ),
  BoxAction.powerOff => (
    icon: Icons.power_settings_new,
    title: 'Power off streamer?',
    message:
        'The player shuts down safely. To start it again, unplug it and plug '
        'it back in.',
    confirm: 'Power off',
    accepted: 'Powering off. Unplug the streamer once its lights stop.',
    destructive: true,
  ),
};

/// Confirmation for a box action. Returns `true` for immediate actions,
/// or a delay in minutes for sleep timers (0 for Now, -1 to cancel the timer).
/// The caller carries the action out. Show via [showKalinkaDialog].
class BoxActionDialog extends ConsumerStatefulWidget {
  final BoxAction action;
  final KalinkaDialogSide side;
  final bool canSchedule;

  const BoxActionDialog({
    super.key,
    required this.action,
    this.side = KalinkaDialogSide.player,
    this.canSchedule = false,
  });

  @override
  ConsumerState<BoxActionDialog> createState() => _BoxActionDialogState();
}

class _BoxActionDialogState extends ConsumerState<BoxActionDialog> {
  int _minutes = 0;

  @override
  Widget build(BuildContext context) {
    final wording = _wording(widget.action);
    final scheduling =
        widget.action == BoxAction.powerOff && widget.canSchedule;
    final status = scheduling ? ref.watch(currentPowerOffStatusProvider) : null;
    return KalinkaDialog(
      side: widget.side,
      icon: wording.icon,
      iconColor: wording.destructive
          ? KalinkaColors.actionDelete
          : KalinkaColors.accent,
      iconGlyphColor: wording.destructive ? null : KalinkaColors.accentTint,
      title: wording.title,
      message: wording.message,
      content: scheduling
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (status?.countdownLabel case final label?) ...[
                  Text(
                    label,
                    style: KalinkaTextStyles.dialogBody,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                ],
                DropdownButtonFormField<int>(
                  key: const ValueKey('power-off-delay'),
                  initialValue: _minutes,
                  isExpanded: true,
                  dropdownColor: KalinkaColors.surfaceElevated,
                  style: KalinkaTextStyles.trayRowLabel,
                  decoration: InputDecoration(
                    labelText: 'When',
                    filled: true,
                    fillColor: KalinkaColors.surfaceInput,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: KalinkaColors.borderDefault,
                      ),
                    ),
                  ),
                  items: [
                    for (final minutes in [0, 30, 60, 90])
                      DropdownMenuItem(
                        value: minutes,
                        child: Text(minutes == 0 ? 'Now' : '$minutes mins'),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _minutes = value);
                  },
                ),
                if (status?.remainingMinutes != null) ...[
                  const SizedBox(height: 12),
                  KalinkaButton(
                    label: 'Cancel power-off',
                    variant: KalinkaButtonVariant.neutral,
                    fullWidth: true,
                    onTap: () => Navigator.pop(context, -1),
                  ),
                ],
              ],
            )
          : null,
      actions: [
        KalinkaButton(
          label: status?.remainingMinutes == null ? 'Cancel' : 'Close',
          variant: KalinkaButtonVariant.neutral,
          fullWidth: true,
          onTap: () => Navigator.pop(context, false),
        ),
        KalinkaButton(
          label: scheduling && _minutes > 0 ? 'Set timer' : wording.confirm,
          variant: KalinkaButtonVariant.accent,
          fullWidth: true,
          onTap: () => Navigator.pop(context, scheduling ? _minutes : true),
        ),
      ],
    );
  }
}

/// Confirms [action], then asks the connected server's box to carry it out.
/// Returns whether the streamer accepted it; a refusal is reported in a toast.
///
/// Set [inPanel] when called from a pane of the tablet layout.
/// [dialogSide] keeps the confirmation over the panel that opened it.
Future<bool> runBoxAction(
  BuildContext context,
  WidgetRef ref,
  BoxAction action, {
  bool inPanel = false,
  KalinkaDialogSide dialogSide = KalinkaDialogSide.player,
}) async {
  final control = ref.read(boxControlProvider).value;
  final api = ref.read(supervisorApiProvider);
  if (control == null || api == null) return false;
  final toast = ref.read(toastProvider.notifier);
  final connection = ref.read(connectionStateProvider.notifier);
  final timer = ref.read(scheduledPowerOffProvider.notifier);
  final confirmed = await showKalinkaDialog<Object>(
    context: context,
    builder: (_) => BoxActionDialog(
      action: action,
      side: dialogSide,
      canSchedule: control.info.supportsPowerOffSchedule,
    ),
  );
  if (confirmed != true && confirmed is! int) return false;
  // Never send a dialog's choice to a newly selected server.
  if (!context.mounted ||
      ref.read(supervisorApiProvider) != api ||
      ref.read(boxControlProvider).value?.serverId != control.serverId) {
    return false;
  }
  var accepted = _wording(action).accepted;
  try {
    if (confirmed is int && confirmed > 0) {
      await api.schedulePowerOff(confirmed, serverId: control.serverId);
      timer.schedule(control.serverId, confirmed);
      accepted = 'Power off in $confirmed minutes.';
    } else if (confirmed == -1) {
      await api.cancelPowerOff(serverId: control.serverId);
      timer.cancel();
      accepted = 'Power-off timer cancelled.';
    } else {
      await api.run(action, serverId: control.serverId);
      if (action == BoxAction.powerOff) connection.poweredOff();
    }
  } on BoxActionException catch (e) {
    toast.show(e.message, isError: true, inPanel: inPanel);
    // A timer or another device got there first.
    if (e.code == 'shutting_down') {
      final status = await api.powerStatus();
      if (status?.state == 'powering_off' &&
          status?.serverId == control.serverId) {
        connection.poweredOff();
      }
    }
    return false;
  }
  if (context.mounted) ref.invalidate(powerOffStatusProvider);
  toast.show(accepted, inPanel: inPanel);
  return true;
}

/// Whether the connected server's box can restart its server, which the app
/// offers once the server stops answering.
final canRestartServerThroughBoxProvider = Provider<bool>(
  (ref) =>
      ref.watch(boxControlProvider).value?.offers(BoxAction.restartServer) ??
      false,
);

/// Restarts a server that stopped answering through its box, then retries
/// the connection with a fresh window for it to come back in.
Future<void> restartServerThroughBox(
  BuildContext context,
  WidgetRef ref, {
  bool inPanel = false,
}) async {
  final api = ref.read(supervisorApiProvider);
  final connection = ref.read(connectionStateProvider.notifier);
  final toast = ref.read(toastProvider.notifier);
  if (api == null) return;
  // A server on a Pi can take a minute to start; restarting it again then
  // would only start it over.
  if (await api.serverState() case 'activating' || 'reloading') {
    toast.show('The server is starting. Give it a moment.', inPanel: inPanel);
    connection.retryNow();
    return;
  }
  if (!context.mounted) return;
  if (await runBoxAction(
    context,
    ref,
    BoxAction.restartServer,
    inPanel: inPanel,
  )) {
    connection.retryNow();
  }
}
