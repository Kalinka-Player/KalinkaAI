import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/box_control_provider.dart';
import '../providers/connection_state_provider.dart';
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
        "Kalinka's server is not answering. The box starts it again; playback "
        'stops until it is back.',
    confirm: 'Restart',
    accepted: 'Restarting the server…',
    destructive: false,
  ),
  BoxAction.reboot => (
    icon: Icons.autorenew,
    title: 'Restart the box?',
    message:
        'The whole player restarts. Playback stops, and the box is back in a '
        'minute or two.',
    confirm: 'Restart',
    accepted: 'Restarting the box. The app reconnects when it is back.',
    destructive: false,
  ),
  BoxAction.powerOff => (
    icon: Icons.power_settings_new,
    title: 'Power off the box?',
    message:
        'The player shuts down safely. To start it again, unplug it and plug '
        'it back in.',
    confirm: 'Power off',
    accepted: 'Powering off. Unplug the box once its lights stop.',
    destructive: true,
  ),
};

/// Confirmation for a box action. Returns `true` when confirmed; the caller
/// carries the action out. Show via [showKalinkaDialog].
class BoxActionDialog extends StatelessWidget {
  final BoxAction action;

  const BoxActionDialog({super.key, required this.action});

  @override
  Widget build(BuildContext context) {
    final wording = _wording(action);
    return KalinkaDialog(
      side: KalinkaDialogSide.left,
      icon: wording.icon,
      iconColor: wording.destructive
          ? KalinkaColors.actionDelete
          : KalinkaColors.accent,
      iconGlyphColor: wording.destructive ? null : KalinkaColors.accentTint,
      title: wording.title,
      message: wording.message,
      actions: [
        KalinkaButton(
          label: 'Cancel',
          variant: KalinkaButtonVariant.neutral,
          fullWidth: true,
          onTap: () => Navigator.pop(context, false),
        ),
        KalinkaButton(
          label: wording.confirm,
          variant: KalinkaButtonVariant.accent,
          fullWidth: true,
          onTap: () => Navigator.pop(context, true),
        ),
      ],
    );
  }
}

/// Confirms [action], then asks the connected server's box to carry it out.
/// Returns whether the box accepted it; a refusal is reported in a toast.
///
/// Set [inPanel] when called from the tablet layout's left panel.
Future<bool> runBoxAction(
  BuildContext context,
  WidgetRef ref,
  BoxAction action, {
  bool inPanel = false,
}) async {
  final control = ref.read(boxControlProvider).value;
  final api = ref.read(supervisorApiProvider);
  if (control == null || api == null) return false;
  final toast = ref.read(toastProvider.notifier);
  final confirmed = await showKalinkaDialog<bool>(
    context: context,
    builder: (_) => BoxActionDialog(action: action),
  );
  if (confirmed != true) return false;
  try {
    await api.run(action, serverId: control.serverId);
  } on BoxActionException catch (e) {
    toast.show(e.message, isError: true, inPanel: inPanel);
    return false;
  }
  toast.show(_wording(action).accepted, inPanel: inPanel);
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
