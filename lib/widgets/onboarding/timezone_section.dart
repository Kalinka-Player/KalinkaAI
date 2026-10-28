import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/timezone_provider.dart';
import '../../theme/app_theme.dart';
import '../kalinka_button.dart';
import '../settings_controls/settings_card.dart';
import '../timezone_row.dart';
import 'onboarding_step_scaffold.dart';

/// The Network step's time zone. A box on another zone than this device is
/// offered the device's, set once confirmed; the row picks any other.
class OnboardingTimezoneSection extends ConsumerWidget {
  const OnboardingTimezoneSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boxState = ref.watch(boxTimezoneProvider);
    final box = boxState.value;
    if (box == null) return const SizedBox.shrink();
    final local = box.settable ? ref.watch(localTimezoneProvider).value : null;
    final setting = ref.watch(timezoneChangeProvider);
    final boxZone = box.zone;
    // Until a change is read back, box.zone still names the old zone. A zone
    // that could not be read is most often a box that did not answer.
    final propose =
        local != null &&
        boxZone != null &&
        setting == null &&
        !boxState.isLoading &&
        !ref.read(timezoneChangeProvider.notifier).isOn(local, boxZone);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const OnboardingSectionLabel('Time zone'),
        SettingsCard(
          children: [
            TimezoneRow(box: box),
            if (propose)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'This device is on ${timezoneLabel(local)}. The '
                      'streamer shows its clock and runs its night-time '
                      'updates in its own zone.',
                      style: KalinkaTextStyles.trayRowSublabel,
                    ),
                    const SizedBox(height: 10),
                    KalinkaButton(
                      label: 'Use ${timezoneLabel(local)}',
                      size: KalinkaButtonSize.compact,
                      fullWidth: true,
                      onTap: () =>
                          setTimezoneOnceConfirmed(context, ref, local),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
