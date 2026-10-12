import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/onboarding_provider.dart';
import '../../providers/server_connect.dart';
import '../../providers/soundcard_provider.dart';
import '../../theme/app_theme.dart';
import '../kalinka_button.dart';

/// Attempts at reaching the server, about three minutes: as long as a Pi
/// takes to restart.
const _attempts = 60;

/// Reconnects a setup run the app lost while a Pi restarted to the server it
/// was setting up, for as long as the restart may take, before leaving the
/// person to find another server.
class ResumeConnect extends ConsumerStatefulWidget {
  final OobeResume resume;
  final VoidCallback onConnected;
  final VoidCallback onFindAnother;

  const ResumeConnect({
    super.key,
    required this.resume,
    required this.onConnected,
    required this.onFindAnother,
  });

  @override
  ConsumerState<ResumeConnect> createState() => _ResumeConnectState();
}

class _ResumeConnectState extends ConsumerState<ResumeConnect> {
  bool _gaveUp = false;

  /// Bumped per round of attempts, so a retry outruns the round before it.
  int _round = 0;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _round++;
    super.dispose();
  }

  Future<void> _connect() async {
    final round = ++_round;
    if (_gaveUp) setState(() => _gaveUp = false);
    for (var i = 0; i < _attempts; i++) {
      if (i > 0) await Future<void>.delayed(ref.read(soundcardPollProvider));
      if (!mounted || round != _round) return;
      try {
        await connectToServer(
          ref,
          name: widget.resume.name,
          address: widget.resume.address,
          persist: false,
        );
        if (mounted && round == _round) widget.onConnected();
        return;
      } catch (_) {
        // Still restarting, most likely.
      }
    }
    if (mounted && round == _round) setState(() => _gaveUp = true);
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.resume.name;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_gaveUp)
                  const Icon(
                    Icons.cloud_off_outlined,
                    size: 32,
                    color: KalinkaColors.statusOffline,
                  )
                else
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(KalinkaColors.accent),
                    ),
                  ),
                const SizedBox(height: 20),
                Text(
                  _gaveUp ? 'Couldn’t reach $name' : 'Reconnecting to $name',
                  textAlign: TextAlign.center,
                  style: KalinkaTextStyles.dialogTitle,
                ),
                const SizedBox(height: 8),
                Text(
                  _gaveUp
                      ? 'Check that it has power and a network connection.'
                      : 'Setup was restarting it to set up its sound card, '
                            'and carries on where it was once it is back.',
                  textAlign: TextAlign.center,
                  style: KalinkaTextStyles.trayRowSublabel.copyWith(
                    fontSize: KalinkaTypography.baseSize + 1,
                  ),
                ),
                const SizedBox(height: 24),
                if (_gaveUp)
                  KalinkaButton(
                    label: 'Try again',
                    fullWidth: true,
                    onTap: _connect,
                  ),
                const SizedBox(height: 8),
                KalinkaButton(
                  label: 'Find another server',
                  variant: KalinkaButtonVariant.neutral,
                  fullWidth: true,
                  onTap: widget.onFindAnother,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
