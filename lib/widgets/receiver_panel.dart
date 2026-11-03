import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/receiver_control.dart';
import '../providers/connection_settings_provider.dart';
import '../providers/receiver_provider.dart';
import '../theme/app_theme.dart';
import 'kalinka_bottom_sheet.dart';

IconData receiverIcon(String kind) => switch (kind) {
  'bluetooth' => Icons.bluetooth,
  'airplay' => Icons.airplay,
  _ => Icons.speaker_outlined,
};

Future<void> showReceiverPanel(BuildContext context) =>
    showKalinkaBottomSheet<void>(
      context: context,
      mayFillScreen: true,
      contentBuilder: (_) => const ReceiverPanel(),
    );

/// Uses the existing source strip's neutral, 48dp interaction target.
class ConnectSourceButton extends ConsumerWidget {
  const ConnectSourceButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(enabledReceiversProvider).isEmpty) {
      return const SizedBox.shrink();
    }
    return TextButton.icon(
      key: const ValueKey('connect-source-button'),
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        foregroundColor: KalinkaColors.textPrimary,
        textStyle: KalinkaFonts.sans(fontSize: 16, fontWeight: FontWeight.w500),
      ),
      onPressed: () => showReceiverPanel(context),
      icon: const Icon(Icons.phonelink_ring_outlined, size: 20),
      label: const Text('Connect'),
    );
  }
}

/// Native menu anchoring keeps the compact panel beside its sidebar entry.
class ReceiverPopover extends StatelessWidget {
  final String receiverId;
  final Widget Function(VoidCallback open) builder;
  const ReceiverPopover({
    super.key,
    required this.receiverId,
    required this.builder,
  });
  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final width = (viewport.width - 32).clamp(0.0, 380.0);
    return MenuAnchor(
      consumeOutsideTap: true,
      style: MenuStyle(
        alignment: AlignmentDirectional.topEnd,
        backgroundColor: const WidgetStatePropertyAll(
          KalinkaColors.surfaceRaised,
        ),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: KalinkaColors.borderDefault),
          ),
        ),
      ),
      builder: (context, controller, _) => builder(
        () => controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        Builder(
          builder: (context) => SizedBox(
            width: width,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: viewport.height - 48),
              child: ReceiverPanel(
                receiverId: receiverId,
                onClose: () => MenuController.maybeOf(context)?.close(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ReceiverPanel extends ConsumerWidget {
  final String? receiverId;
  final VoidCallback? onClose;
  const ReceiverPanel({super.key, this.receiverId, this.onClose});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inventory = ref.watch(receiversProvider);
    final connection = ref.watch(connectionSettingsProvider);
    final receivers = ref
        .watch(enabledReceiversProvider)
        .where((r) => receiverId == null || r.id == receiverId)
        .toList();
    return Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    receiverId != null && receivers.isNotEmpty
                        ? receivers.first.title
                        : 'Play from a device',
                    style: KalinkaTextStyles.settingsPageTitle,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: onClose ?? () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              primary: false,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Receive audio on ${connection.name}',
                    style: KalinkaTextStyles.trayRowSublabel,
                  ),
                  if (inventory.error != null) ...[
                    Text(
                      inventory.error!,
                      style: KalinkaTextStyles.trayRowSublabel,
                    ),
                    TextButton(
                      onPressed: () =>
                          ref.read(receiversProvider.notifier).refresh(),
                      child: const Text('Retry'),
                    ),
                  ],
                  if (receivers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'No enabled receivers. Manage plugins in Configuration.',
                      ),
                    ),
                  for (final receiver in receivers)
                    _ReceiverDetails(
                      key: ValueKey('${connection.address}:${receiver.id}'),
                      receiver: receiver,
                      available: inventory.error == null,
                      showTitle: receiverId == null,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiverDetails extends ConsumerStatefulWidget {
  final ReceiverSnapshot receiver;
  final bool available, showTitle;
  const _ReceiverDetails({
    super.key,
    required this.receiver,
    required this.available,
    required this.showTitle,
  });
  @override
  ConsumerState<_ReceiverDetails> createState() => _ReceiverDetailsState();
}

class _ReceiverDetailsState extends ConsumerState<_ReceiverDetails>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _busy = false;
  bool _expanded = false;
  String? _error, _password;
  int _secretEpoch = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.receiver.pairing != null) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant _ReceiverDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.available ||
        !widget.receiver.passwordRevealAvailable ||
        widget.receiver.state != 'ready') {
      _password = null;
      _secretEpoch++;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted) {
      setState(() {
        _password = null;
        _secretEpoch++;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _password = null;
    super.dispose();
  }

  Future<void> _run(Future<void> Function() operation) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not complete the action. Check the refreshed state and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _command(
    String command, [
    Map<String, dynamic> target = const {},
  ]) => _run(
    () => ref.read(receiversProvider.notifier).command(widget.receiver, {
      'command': command,
      ...target,
    }),
  );
  Widget _button(String label, VoidCallback? action) => OutlinedButton(
    onPressed: widget.available && !_busy ? action : null,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      foregroundColor: KalinkaColors.textPrimary,
    ),
    child: Text(label),
  );
  bool _canPair(ReceiverSnapshot receiver) =>
      receiver.can('open_pairing') &&
      (receiver.kind != 'bluetooth' || receiver.offers('answer_pairing'));

  Future<void> _reveal() async {
    if (_password != null) {
      setState(() {
        _password = null;
        _secretEpoch++;
      });
      return;
    }
    final epoch = _secretEpoch;
    await _run(() async {
      final password = await ref
          .read(receiversProvider.notifier)
          .revealPassword(widget.receiver);
      if (mounted &&
          epoch == _secretEpoch &&
          widget.available &&
          widget.receiver.passwordRevealAvailable) {
        setState(() => _password = password);
      }
    });
  }

  Widget _compact(ReceiverSnapshot r) {
    final session = r.sessions.firstOrNull;
    final status = r.state != 'ready'
        ? (r.message ?? 'Receiver ${r.state}')
        : session != null
        ? '${session.name} · Connected'
        : r.kind == 'airplay'
        ? (r.passwordRequired ? 'Password required' : 'No password required')
        : 'Not connected';
    final VoidCallback? action;
    final String? label;
    if (r.offers('open_pairing')) {
      label = session == null ? 'Pair a device' : 'Disconnect';
      action = session == null
          ? (_canPair(r)
                ? () {
                    setState(() => _expanded = true);
                    _command('open_pairing');
                  }
                : null)
          : (r.can('disconnect_audio')
                ? () => _command('disconnect_audio', {'session_id': session.id})
                : null);
    } else if (r.passwordRequired) {
      label = 'Show password';
      action = r.passwordRevealAvailable
          ? () {
              setState(() => _expanded = true);
              _reveal();
            }
          : null;
    } else {
      label = null;
      action = null;
    }
    final details = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(receiverIcon(r.kind), size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.title, style: KalinkaTextStyles.trayRowLabel),
              Text(status, style: KalinkaTextStyles.trayRowSublabel),
              Text(
                r.effectiveName ?? r.title,
                style: KalinkaTextStyles.trayRowSublabel,
              ),
            ],
          ),
        ),
      ],
    );
    final button = label == null
        ? const Icon(Icons.chevron_right)
        : TextButton(
            style: TextButton.styleFrom(
              foregroundColor: KalinkaColors.textPrimary,
              minimumSize: const Size(48, 48),
            ),
            onPressed: widget.available && !_busy ? action : null,
            child: Text(label),
          );
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = true),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final roomy =
                      constraints.maxWidth >=
                      320 * MediaQuery.textScalerOf(context).scale(1);
                  return roomy
                      ? Row(
                          children: [
                            Expanded(child: details),
                            button,
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            details,
                            Align(
                              alignment: Alignment.centerRight,
                              child: button,
                            ),
                          ],
                        );
                },
              ),
            ),
          ),
          if (_error != null)
            Text(_error!, style: KalinkaTextStyles.trayRowSublabel),
          if (_busy) const LinearProgressIndicator(),
          const Divider(color: KalinkaColors.borderSubtle),
        ],
      ),
    );
  }

  Future<void> _remove(ReceiverPeer peer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove audio access for ${peer.name}?'),
        content: const Text(
          'Disconnects Bluetooth audio and removes permission to play here. The saved pairing and provisioning access remain.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove audio access'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _command('revoke_audio', {'peer_id': peer.id});
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.receiver;
    final pairing = r.pairing;
    if (widget.showTitle && !_expanded && pairing == null) return _compact(r);
    final remaining = pairing?.remainingSeconds ?? 0;
    final pairingOpen = widget.available && pairing != null && remaining > 0;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showTitle)
            Row(
              children: [
                Icon(receiverIcon(r.kind), size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(r.title, style: KalinkaTextStyles.trayRowLabel),
                ),
              ],
            ),
          const SizedBox(height: 8),
          Text(
            r.effectiveName ?? r.title,
            style: KalinkaTextStyles.trayRowLabel,
          ),
          if (r.message != null)
            Text(r.message!, style: KalinkaTextStyles.trayRowSublabel),
          if (r.state != 'ready')
            Text(switch (r.state) {
              'starting' => 'Starting receiver…',
              'stopping' => 'Stopping receiver…',
              _ => 'Receiver unavailable',
            }, style: KalinkaTextStyles.trayRowSublabel),
          if (r.offers('open_pairing')) ...[
            if (pairingOpen) ...[
              Text(
                'Visible as ${r.effectiveName ?? r.title} · ${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}',
                style: KalinkaTextStyles.trayRowSublabel,
              ),
              const SizedBox(height: 8),
              Text(
                'Open Bluetooth settings on your device and select ${r.effectiveName ?? r.title}.',
                style: KalinkaTextStyles.trayRowSublabel,
              ),
              const SizedBox(height: 12),
              _button(
                'Stop pairing',
                r.can('close_pairing')
                    ? () => _command('close_pairing', {'window_id': pairing.id})
                    : null,
              ),
            ] else ...[
              if (r.sessions.isEmpty)
                Text('Not connected', style: KalinkaTextStyles.trayRowSublabel),
              const SizedBox(height: 8),
              _button(
                r.sessions.isEmpty ? 'Pair a device' : 'Pair another device',
                _canPair(r) ? () => _command('open_pairing') : null,
              ),
              Text(
                'Visible for 2 minutes',
                style: KalinkaTextStyles.trayRowSublabel,
              ),
              if (r.kind == 'bluetooth' && !r.offers('answer_pairing'))
                Text(
                  'Update the server to pair with device approval.',
                  style: KalinkaTextStyles.trayRowSublabel,
                ),
            ],
          ] else if (r.instructions.isNotEmpty)
            Text(r.instructions, style: KalinkaTextStyles.trayRowSublabel),
          if (r.kind == 'airplay' || r.passwordRequired) ...[
            const SizedBox(height: 8),
            Text(
              r.passwordRequired ? 'Password required' : 'No password required',
              style: KalinkaTextStyles.trayRowSublabel,
            ),
            if (_password != null)
              SelectableText(
                _password!,
                style: KalinkaFonts.mono(fontSize: 16),
              ),
            if (r.passwordRequired)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed:
                      !widget.available || _busy || !r.passwordRevealAvailable
                      ? null
                      : () {
                          _reveal();
                        },
                  style: TextButton.styleFrom(
                    foregroundColor: KalinkaColors.textPrimary,
                  ),
                  child: Text(
                    _password == null ? 'Show password' : 'Hide password',
                  ),
                ),
              ),
          ],
          for (final session in r.sessions)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(session.name, style: KalinkaTextStyles.trayRowLabel),
                  Text(
                    session.playing ? 'Connected · Playing' : 'Connected',
                    style: KalinkaTextStyles.trayRowSublabel,
                  ),
                  if (r.offers('disconnect_audio'))
                    TextButton(
                      onPressed:
                          widget.available &&
                              !_busy &&
                              r.can('disconnect_audio')
                          ? () => _command('disconnect_audio', {
                              'session_id': session.id,
                            })
                          : null,
                      child: const Text('Disconnect'),
                    ),
                ],
              ),
            ),
          if (r.peers.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                'Saved devices',
                style: KalinkaTextStyles.trayRowSublabel,
              ),
              children: [
                for (final peer in r.peers)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(peer.name, style: KalinkaTextStyles.trayRowLabel),
                        Text(
                          '${peer.paired ? 'Paired' : 'Not paired'} · ${peer.audioAllowed ? 'Audio allowed' : 'No audio permission'}',
                          style: KalinkaTextStyles.trayRowSublabel,
                        ),
                        if (peer.audioAllowed && r.can('revoke_audio'))
                          TextButton(
                            onPressed: widget.available && !_busy
                                ? () => _remove(peer)
                                : null,
                            child: const Text('Remove audio access'),
                          ),
                        if (peer.paired &&
                            !peer.audioAllowed &&
                            r.can('grant_audio'))
                          TextButton(
                            onPressed: widget.available && !_busy
                                ? () => _command('grant_audio', {
                                    'peer_id': peer.id,
                                  })
                                : null,
                            child: const Text('Allow audio'),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          if (_error != null)
            Text(_error!, style: KalinkaTextStyles.trayRowSublabel),
          if (_busy) const LinearProgressIndicator(),
          if (widget.showTitle)
            const Divider(color: KalinkaColors.borderSubtle),
        ],
      ),
    );
  }
}
