import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/receiver_control.dart';
import '../providers/connection_settings_provider.dart';
import '../providers/receiver_provider.dart';
import '../theme/app_theme.dart';
import 'kalinka_bottom_sheet.dart';
import 'kalinka_dialog.dart';
import 'renderer_switcher.dart';

Future<void> showReceiverPanel(BuildContext context) =>
    showKalinkaBottomSheet<void>(
      context: context,
      mayFillScreen: true,
      contentBuilder: (_) => const ReceiverPanel(),
    );

/// Used independently of catalogs on Home and in both server menus.
class ConnectDeviceEntry extends ConsumerWidget {
  final VoidCallback? onTap;
  const ConnectDeviceEntry({super.key, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inventory = ref.watch(receiversProvider);
    if (inventory.receivers.isEmpty) return const SizedBox.shrink();
    return SheetRow(
      icon: Icons.devices_outlined,
      iconBackground: KalinkaColors.surfaceOverlay,
      iconColor: KalinkaColors.textSecondary,
      label: 'Connect a device',
      sublabel: inventory.error == null
          ? inventory.receivers.map((r) => r.title).join(' · ')
          : 'Receivers unavailable · retry',
      trailing: const SheetChevron(),
      onTap: onTap ?? () => showReceiverPanel(context),
    );
  }
}

class ReceiverPanel extends ConsumerWidget {
  const ReceiverPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inventory = ref.watch(receiversProvider);
    final connection = ref.watch(connectionSettingsProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        'CONNECT A DEVICE',
                        style: KalinkaTextStyles.sectionLabel,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Receive on ${connection.name}',
                      style: KalinkaTextStyles.trayRowSublabel,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Text('Play through', style: KalinkaTextStyles.trayRowSublabel),
              const Align(
                alignment: Alignment.centerLeft,
                child: RendererSwitcherDropdown(
                  maxNameWidth: 220,
                  framed: true,
                ),
              ),
              const SizedBox(height: 16),
              if (inventory.error != null) ...[
                Text(
                  inventory.error!,
                  style: KalinkaTextStyles.trayRowSublabel,
                ),
                TextButton(
                  onPressed: inventory.loading
                      ? null
                      : () => ref.read(receiversProvider.notifier).refresh(),
                  child: const Text('Retry'),
                ),
              ],
              if (inventory.loading && inventory.receivers.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (!inventory.loading &&
                  inventory.error == null &&
                  inventory.receivers.isEmpty)
                Text(
                  'No receiver plugins installed. Add one in Configuration.',
                  style: KalinkaTextStyles.trayRowSublabel,
                ),
              for (final receiver in inventory.receivers)
                _ReceiverCard(
                  key: ValueKey('${connection.address}:${receiver.id}'),
                  receiver: receiver,
                  available: inventory.error == null,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReceiverCard extends ConsumerStatefulWidget {
  final ReceiverSnapshot receiver;
  final bool available;
  const _ReceiverCard({
    super.key,
    required this.receiver,
    required this.available,
  });
  @override
  ConsumerState<_ReceiverCard> createState() => _ReceiverCardState();
}

class _ReceiverCardState extends ConsumerState<_ReceiverCard> {
  bool _busy = false;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.receiver.pairing != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showKalinkaDialog<bool>(
        context: context,
        builder: (context) => KalinkaDialog(
          side: KalinkaDialogSide.browsing,
          title: title,
          message: message,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      ) ??
      false;

  Future<void> _command(
    String name, {
    String? peer,
    String? session,
    String? window,
  }) => _run(
    () => ref.read(receiversProvider.notifier).command(widget.receiver, {
      'command': name,
      'peer_id': ?peer,
      'session_id': ?session,
      'window_id': ?window,
    }),
  );

  Future<void> _toggle() async {
    final receiver = widget.receiver;
    if (receiver.enabled &&
        !await _confirm(
          'Disable ${receiver.title}?',
          'This ends any ${receiver.title} playback. It stays disabled until you enable it again.',
        )) {
      return;
    }
    if (!mounted) return;
    await _run(
      () => ref
          .read(receiversProvider.notifier)
          .setEnabled(receiver, !receiver.enabled),
    );
  }

  Future<void> _revoke(ReceiverPeer peer) async {
    if (!await _confirm(
      'Remove audio access?',
      '${peer.name} will be disconnected from audio and cannot play here until allowed again. Its Bluetooth pairing is kept.',
    )) {
      return;
    }
    if (mounted) await _command('revoke_audio', peer: peer.id);
  }

  Widget _button(String label, VoidCallback? tap, {bool primary = false}) {
    final onPressed = _busy || !widget.available ? null : tap;
    if (primary) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 48),
            backgroundColor: KalinkaColors.accent,
            foregroundColor: KalinkaColors.textPrimary,
          ),
          onPressed: onPressed,
          child: Text(label),
        ),
      );
    }
    return TextButton(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: KalinkaColors.textPrimary,
        alignment: Alignment.centerLeft,
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final receiver = widget.receiver;
    final pairing = receiver.pairing;
    final recent = receiver.peers
        .where((p) => p.id == receiver.recentPeerId && p.audioAllowed)
        .firstOrNull;
    final status = switch (receiver.state) {
      'disabled' => 'Disabled',
      'starting' => 'Starting',
      'stopping' => 'Stopping',
      'error' => 'Unavailable',
      _ => 'Ready',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KalinkaColors.surfaceOverlay,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: KalinkaColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(receiver.title, style: KalinkaTextStyles.trayRowLabel),
          ),
          const SizedBox(height: 8),
          Text(
            receiver.effectiveName ?? receiver.title,
            style: KalinkaTextStyles.trayRowLabel,
          ),
          Text(status, style: KalinkaTextStyles.trayRowSublabel),
          if (receiver.message != null)
            Text(receiver.message!, style: KalinkaTextStyles.trayRowSublabel),
          if (receiver.enabled && receiver.instructions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              receiver.instructions,
              style: KalinkaTextStyles.trayRowSublabel,
            ),
          ],
          if (receiver.enabled && receiver.offers('open_pairing')) ...[
            if (pairing == null)
              _button(
                'Pair a device',
                receiver.can('open_pairing')
                    ? () => _command('open_pairing')
                    : null,
                primary: true,
              )
            else ...[
              const SizedBox(height: 8),
              Text(
                !widget.available
                    ? 'Pairing state unavailable'
                    : pairing.remainingSeconds > 0
                    ? 'Visible for ${pairing.remainingSeconds} seconds'
                    : 'Pairing window is closing',
                style: KalinkaTextStyles.trayRowSublabel,
              ),
              _button(
                'Stop pairing',
                receiver.can('close_pairing')
                    ? () => _command('close_pairing', window: pairing.id)
                    : null,
              ),
            ],
          ],
          if (recent != null) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                '${recent.name} can now play audio.',
                style: KalinkaTextStyles.trayRowSublabel,
              ),
            ),
            _button(
              'Not this device? Remove',
              receiver.can('revoke_audio') ? () => _revoke(recent) : null,
            ),
          ],
          for (final session in receiver.sessions) ...[
            const SizedBox(height: 8),
            Text(
              '${session.playing ? 'Receiving from' : 'Connected'} ${session.name}',
              style: KalinkaTextStyles.trayRowSublabel,
            ),
            if (receiver.offers('disconnect_audio'))
              _button(
                'Disconnect audio',
                receiver.can('disconnect_audio')
                    ? () => _command('disconnect_audio', session: session.id)
                    : null,
              ),
          ],
          for (final peer in receiver.peers) ...[
            const Divider(color: KalinkaColors.borderSubtle),
            Text(peer.name, style: KalinkaTextStyles.trayRowLabel),
            Text(
              peer.audioAllowed ? 'Audio allowed' : 'Audio not allowed',
              style: KalinkaTextStyles.trayRowSublabel,
            ),
            if (peer.audioAllowed && receiver.offers('revoke_audio'))
              _button(
                'Remove audio access',
                receiver.can('revoke_audio') ? () => _revoke(peer) : null,
              )
            else if (peer.paired && receiver.offers('grant_audio'))
              _button(
                'Allow audio',
                receiver.can('grant_audio')
                    ? () => _command('grant_audio', peer: peer.id)
                    : null,
              ),
          ],
          _button(
            '${receiver.enabled ? 'Disable' : 'Enable'} ${receiver.title}',
            _toggle,
          ),
          SizedBox(
            height: 8,
            child: _busy
                ? Semantics(
                    label: 'Applying receiver change',
                    child: const LinearProgressIndicator(),
                  )
                : null,
          ),
          if (_error != null)
            Semantics(
              liveRegion: true,
              child: Text(_error!, style: KalinkaTextStyles.trayRowSublabel),
            ),
        ],
      ),
    );
  }
}
