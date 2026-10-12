import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/kalinka_player_api_provider.dart';
import '../../theme/app_theme.dart';
import '../kalinka_button.dart';
import '../kalinka_dialog.dart';

enum _TestPhase { left, right, done }

/// Asks for a tone on one channel (`left` / `right`). Throwing
/// [TestToneUnsupportedException] tells the dialog the server is too old.
typedef ToneRequest = Future<void> Function(String channel);

/// Speaker test popup: lights up the left speaker for 3 seconds, then the
/// right, asking for a tone on the matching channel at the start of each
/// segment. The visual sequence runs even when the server can't play tones
/// yet (endpoint added in a newer server release) — a note explains that no
/// sound will come out in that case.
///
/// Where the tone comes from is the caller's business: onboarding routes it
/// through the server's staged output device, the renderer settings page
/// routes it to that renderer. Show via [showKalinkaDialog].
class SpeakerTestDialog extends ConsumerStatefulWidget {
  final ToneRequest playTone;

  /// Names the thing being tested, e.g. `Kitchen`. Shown in the title when
  /// there is more than one possible target.
  final String? targetName;

  const SpeakerTestDialog({super.key, required this.playTone, this.targetName});

  @override
  ConsumerState<SpeakerTestDialog> createState() => _SpeakerTestDialogState();
}

class _SpeakerTestDialogState extends ConsumerState<SpeakerTestDialog>
    with SingleTickerProviderStateMixin {
  static const _segment = Duration(seconds: 3);

  _TestPhase _phase = _TestPhase.left;
  bool _unsupported = false;
  bool _toneFailed = false;
  Timer? _timer;
  int _runId = 0;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.45, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _start() {
    final run = ++_runId;
    _timer?.cancel();
    setState(() {
      _phase = _TestPhase.left;
      _toneFailed = false;
    });
    _playTone('left');
    _timer = Timer(_segment, () {
      if (!mounted || run != _runId) return;
      setState(() => _phase = _TestPhase.right);
      _playTone('right');
      _timer = Timer(_segment, () {
        if (!mounted || run != _runId) return;
        setState(() => _phase = _TestPhase.done);
      });
    });
  }

  Future<void> _playTone(String channel) async {
    if (_unsupported) return;
    try {
      await widget.playTone(channel);
    } on TestToneUnsupportedException {
      if (mounted) setState(() => _unsupported = true);
    } catch (_) {
      if (mounted) setState(() => _toneFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return KalinkaDialog(
      side: KalinkaDialogSide.full,
      title: widget.targetName == null
          ? 'Testing output'
          : 'Testing ${widget.targetName}',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildSpeaker('LEFT', _phase == _TestPhase.left),
              const SizedBox(width: 28),
              _buildSpeaker('RIGHT', _phase == _TestPhase.right),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 40,
            child: Center(
              child: Text(
                switch (_phase) {
                  _TestPhase.left =>
                    'You should hear a tone from the left speaker.',
                  _TestPhase.right =>
                    'You should hear a tone from the right speaker.',
                  _TestPhase.done =>
                    'Heard both sides? You’re set. If not, pick a different '
                        'output device and test again.',
                },
                textAlign: TextAlign.center,
                style: KalinkaTextStyles.dialogBody,
              ),
            ),
          ),
          if (_unsupported) ...[
            const SizedBox(height: 8),
            Text(
              'This server version can’t play test tones yet — '
              'update Kalinka server to hear them.',
              textAlign: TextAlign.center,
              style: KalinkaTextStyles.trayRowSublabel.copyWith(
                color: KalinkaColors.statusPendingLight,
              ),
            ),
          ] else if (_toneFailed) ...[
            const SizedBox(height: 8),
            Text(
              'Could not reach the server to play the tone.',
              textAlign: TextAlign.center,
              style: KalinkaTextStyles.trayRowSublabel.copyWith(
                color: KalinkaColors.statusPendingLight,
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (_phase == _TestPhase.done)
          KalinkaButton(
            label: 'Play again',
            variant: KalinkaButtonVariant.neutral,
            fullWidth: true,
            onTap: _start,
          ),
        KalinkaButton(
          label: 'Close',
          variant: _phase == _TestPhase.done
              ? KalinkaButtonVariant.accent
              : KalinkaButtonVariant.neutral,
          fullWidth: true,
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildSpeaker(String label, bool active) {
    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: active
            ? KalinkaColors.accent.withValues(alpha: 0.12)
            : KalinkaColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? KalinkaColors.accent : KalinkaColors.borderDefault,
          width: active ? 1.5 : 1,
        ),
      ),
      child: Icon(
        Icons.volume_up_rounded,
        size: 30,
        color: active ? KalinkaColors.accentTint : KalinkaColors.textMuted,
      ),
    );

    return Column(
      children: [
        active ? FadeTransition(opacity: _pulseAnimation, child: tile) : tile,
        const SizedBox(height: 8),
        Text(
          label,
          style: KalinkaTextStyles.sectionHeaderMuted.copyWith(
            color: active
                ? KalinkaColors.accentTint
                : KalinkaColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
