import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/soundcard_provider.dart';
import '../../providers/supervisor_api.dart';
import '../../theme/app_theme.dart';
import '../kalinka_button.dart';
import '../progress_timeline.dart';

/// Covers the wizard, or an output's settings, while the Pi the output plays
/// on restarts to switch a sound card on. The wizard also offers the way on
/// when it does not come back in time.
class SoundcardRestartOverlay extends ConsumerWidget {
  final SoundcardBox box;
  final SoundcardOption card;

  /// What happens once the Pi is back, after how long it takes.
  final String afterwards;

  /// Set once the Pi did not come back in time; then [onKeepWaiting] and
  /// [onContinue] are the ways on.
  final bool notBack;
  final VoidCallback? onKeepWaiting;
  final VoidCallback? onContinue;

  const SoundcardRestartOverlay({
    super.key,
    required this.box,
    required this.card,
    this.afterwards = 'Setup carries on afterwards.',
    this.notBack = false,
    this.onKeepWaiting,
    this.onContinue,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final step = ref.watch(soundcardChangeProvider(box));
    final switching = step == SoundcardStep.switching;
    final hat = card.kind != 'none';
    return ProgressScrim(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            notBack
                ? 'The streamer is not back yet'
                : 'Restarting the streamer',
            style: KalinkaTextStyles.dialogTitle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            notBack
                ? 'Check that it has power and a network connection. A start '
                      'after a change can take a while.'
                : 'This takes a minute or two. $afterwards',
            textAlign: TextAlign.center,
            style: KalinkaTextStyles.trayRowSublabel.copyWith(
              fontSize: KalinkaTypography.baseSize + 1,
              color: KalinkaColors.textSecondary,
            ),
          ),
          const SizedBox(height: 28),
          TimelineStep(
            label: 'Setting up ${card.label}',
            sublabel: 'The streamer’s boot settings',
            done: true,
            active: false,
          ),
          TimelineStep(
            label: 'Restarting the streamer',
            sublabel: 'Waiting for it to come back',
            done: switching,
            active: !switching && !notBack,
            last: !hat,
          ),
          if (hat)
            TimelineStep(
              label: 'Playing through ${card.label}',
              sublabel: 'Switching the output to it',
              done: false,
              active: switching,
              last: true,
            ),
          if (notBack) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: KalinkaButton(
                    label: 'Continue setup',
                    variant: KalinkaButtonVariant.neutral,
                    fullWidth: true,
                    onTap: onContinue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: KalinkaButton(
                    label: 'Keep waiting',
                    fullWidth: true,
                    onTap: onKeepWaiting,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
