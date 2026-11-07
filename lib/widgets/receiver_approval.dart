import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_model/receiver_control.dart';
import '../providers/connection_settings_provider.dart';
import '../providers/receiver_provider.dart';
import '../theme/app_theme.dart';

/// Mounted below the app Navigator, independently of the connection panel.
/// The backend owns the request lifetime; closing a sheet changes no BT state.
class ReceiverApprovalHost extends ConsumerStatefulWidget {
  final Widget child;
  const ReceiverApprovalHost({super.key, required this.child});
  @override
  ConsumerState<ReceiverApprovalHost> createState() =>
      _ReceiverApprovalHostState();
}

class _ReceiverApprovalHostState extends ConsumerState<ReceiverApprovalHost> {
  DialogRoute<void>? _route;
  String? _identity;
  void _sync() {
    if (!mounted) return;
    final inventory = ref.read(receiversProvider);
    final receiver = inventory.error == null
        ? inventory.receivers
              .where((r) => r.enabled && r.pairingRequest != null)
              .firstOrNull
        : null;
    final request = receiver?.pairingRequest;
    final identity = request == null
        ? null
        : '${ref.read(connectionSettingsProvider).address}:${receiver!.id}:${request.id}';
    if (_identity == identity) return;
    final old = _route;
    _route = null;
    _identity = identity;
    if (old != null && old.navigator != null) old.navigator!.removeRoute(old);
    if (receiver == null || request == null) return;
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: KalinkaColors.surfaceDialog,
          surfaceTintColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ReceiverApproval(
                receiverId: receiver.id,
                requestId: request.id,
              ),
            ),
          ),
        ),
      ),
    );
    _route = route;
    unawaited(Navigator.of(context, rootNavigator: true).push(route));
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(receiversProvider);
    ref.watch(connectionSettingsProvider.select((s) => s.address));
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    return widget.child;
  }
}

class ReceiverApproval extends ConsumerStatefulWidget {
  final String receiverId, requestId;
  const ReceiverApproval({
    super.key,
    required this.receiverId,
    required this.requestId,
  });
  @override
  ConsumerState<ReceiverApproval> createState() => _ReceiverApprovalState();
}

class _ReceiverApprovalState extends ConsumerState<ReceiverApproval> {
  final _input = TextEditingController();
  Timer? _timer;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _answer(
    ReceiverSnapshot receiver,
    ReceiverPairingRequest request,
    bool accept,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(receiversProvider.notifier).command(receiver, {
        'command': 'answer_pairing',
        'request_id': request.id,
        'accept': accept,
        if (accept && request.needsInput) 'code': _input.text,
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not answer this request. It may have expired or been answered on another client.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inventory = ref.watch(receiversProvider);
    final receiver = inventory.receivers
        .where((r) => r.id == widget.receiverId)
        .firstOrNull;
    final request = receiver?.pairingRequest;
    if (receiver == null || request == null || request.id != widget.requestId) {
      return const SizedBox.shrink();
    }
    final allowed =
        inventory.error == null &&
        !_busy &&
        receiver.can('answer_pairing') &&
        request.remainingSeconds > 0;
    final code = request.code;
    final text = switch (request.method) {
      'confirmation' => 'Check this code matches your device',
      'authorization' => 'Allow this device to pair and play audio? This pairing method has no comparison code.',
      'pin' => 'Enter the PIN shown on your device',
      'passkey' => 'Enter the six-digit code shown on your device',
      _ => 'Enter this code on your device',
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Pair with ${request.deviceName}?',
          style: KalinkaTextStyles.settingsPageTitle,
        ),
        const SizedBox(height: 12),
        Text(text, style: KalinkaTextStyles.trayRowLabel),
        if (code != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Semantics(
              label: 'Pairing code ${code.split('').join(' ')}',
              excludeSemantics: true,
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 16,
                children: [
                  for (final part
                      in code.length == 6
                          ? [code.substring(0, 3), code.substring(3)]
                          : [code])
                    Text(
                      part,
                      style: KalinkaFonts.mono(
                        fontSize: 32,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (request.needsInput)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: TextField(
              controller: _input,
              autofocus: true,
              keyboardType: request.method == 'passkey'
                  ? TextInputType.number
                  : TextInputType.text,
              maxLength: request.method == 'passkey' ? 6 : 16,
              decoration: InputDecoration(
                labelText: request.method == 'passkey' ? 'Code' : 'PIN',
              ),
            ),
          ),
        if (request.entered != null)
          Text(
            '${request.entered} of 6 digits entered',
            style: KalinkaTextStyles.trayRowSublabel,
          ),
        Text(
          'Request expires in ${request.remainingSeconds}s',
          style: KalinkaTextStyles.trayRowSublabel,
        ),
        if (_error != null)
          Text(_error!, style: KalinkaTextStyles.trayRowSublabel),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: allowed
                  ? () => _answer(receiver, request, false)
                  : null,
              child: const Text('Reject'),
            ),
            if (!request.displayOnly)
              FilledButton(
                onPressed: allowed
                    ? () => _answer(receiver, request, true)
                    : null,
                child: Text(
                  request.method == 'confirmation'
                      ? 'Codes match'
                      : request.needsInput
                      ? 'Continue'
                      : 'Allow pairing',
                ),
              ),
          ],
        ),
      ],
    );
  }
}
